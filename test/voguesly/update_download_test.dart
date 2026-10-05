import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/voguesly/voguesly_update_download.dart';
import 'package:test/test.dart';

// [0.9.85] 一键更新下载校验(B-P1-UPDATE-VERIFY-0922)。
// 用本机 ServerSocket 手写 HTTP 响应,模拟「半截下载」「服务器文件被换」「旧 manifest 没有 sha256」等情况,
// 不依赖 Flutter、不连外网。

/// 每个请求怎样回应:由测试按请求序号决定。
typedef _Responder = FutureOr<void> Function(_Req req, Socket socket);

class _Req {
  final int index;
  final String? range;
  final String? ifRange;
  final String? acceptEncoding;

  _Req(this.index, this.range, this.ifRange, this.acceptEncoding);
}

class _FakeServer {
  _FakeServer._(this._server, this.responder);

  final ServerSocket _server;
  _Responder responder;
  final List<_Req> requests = [];

  static Future<_FakeServer> start(_Responder responder) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeServer._(server, responder);
    server.listen(fake._handle);
    return fake;
  }

  String get url => 'http://127.0.0.1:${_server.port}/voguesly-update.bin';

  Future<void> _handle(Socket socket) async {
    final buf = BytesBuilder();
    late StreamSubscription<Uint8List> sub;
    final headerDone = Completer<String>();
    sub = socket.listen(
      (data) {
        buf.add(data);
        final text = latin1.decode(buf.toBytes());
        final end = text.indexOf('\r\n\r\n');
        if (end >= 0 && !headerDone.isCompleted) {
          headerDone.complete(text.substring(0, end));
        }
      },
      onError: (_) {},
      onDone: () {},
    );
    final head = await headerDone.future;
    // 不取消读端订阅(取消会关闭 socket 读方向),后续数据直接忽略。
    unawaited(sub.asFuture<void>().catchError((_) {}));
    String? header(String name) {
      for (final line in head.split('\r\n').skip(1)) {
        final i = line.indexOf(':');
        if (i > 0 && line.substring(0, i).trim().toLowerCase() == name) {
          return line.substring(i + 1).trim();
        }
      }
      return null;
    }

    final req = _Req(
      requests.length,
      header('range'),
      header('if-range'),
      header('accept-encoding'),
    );
    requests.add(req);
    try {
      await responder(req, socket);
    } catch (_) {}
    try {
      await socket.flush();
    } catch (_) {}
    socket.destroy();
  }

  Future<void> close() => _server.close();
}

Uint8List _payload(int size, {int seed = 7}) {
  final b = Uint8List(size);
  var x = seed;
  for (var i = 0; i < size; i++) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    b[i] = x & 0xff;
  }
  return b;
}

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

void _writeHead(Socket s, String statusLine, Map<String, String> headers) {
  final sb = StringBuffer('HTTP/1.1 $statusLine\r\n');
  headers.forEach((k, v) => sb.write('$k: $v\r\n'));
  sb.write('Connection: close\r\n\r\n');
  s.add(latin1.encode(sb.toString()));
}

/// 正常服务器:支持 Range(206)。[truncateAt] 非 null 时只发这么多字节就断开(Content-Length 仍报完整长度)。
Future<void> _serve(
  _Req req,
  Socket s,
  Uint8List data, {
  int? truncateAt,
  bool sendLength = true,
  bool honorRange = true,
  String etag = '"v1"',
}) async {
  var start = 0;
  final range = req.range;
  if (honorRange &&
      range != null &&
      (req.ifRange == null || req.ifRange == etag)) {
    start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
  }
  if (start >= data.length && start > 0) {
    _writeHead(s, '416 Range Not Satisfiable', {
      'Content-Range': 'bytes */${data.length}',
    });
    return;
  }
  final body = data.sublist(start);
  final headers = <String, String>{'ETag': etag, 'Accept-Ranges': 'bytes'};
  if (sendLength) headers['Content-Length'] = '${body.length}';
  if (start > 0) {
    headers['Content-Range'] = 'bytes $start-${data.length - 1}/${data.length}';
    _writeHead(s, '206 Partial Content', headers);
  } else {
    _writeHead(s, '200 OK', headers);
  }
  final send = truncateAt == null
      ? body
      : body.sublist(0, truncateAt.clamp(0, body.length));
  s.add(send);
}

void main() {
  late Directory tmp;
  late Dio dio;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('vg_update_test_');
    dio = Dio();
  });

  tearDown(() async {
    dio.close(force: true);
    await tmp.delete(recursive: true);
  });

  // [0.9.91] 下载镜像回退:只对自家下载站生效,其他网址原样只试一次。
  // [0.9.91] 只有自家下载站 + 有 sha256 先自动安装。
  group('vetUpdateDownload', () {
    const sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    test('自家下载站 + sha256 ⇒ 通过', () {
      final v = vetUpdateDownload('https://dl.ylink.im/voguesly-0.9.91-setup.exe', sha.toUpperCase());
      expect(v?.url, 'https://dl.ylink.im/voguesly-0.9.91-setup.exe');
      expect(v?.sha256, sha);
      expect(vetUpdateDownload('https://dl.yilian.live/a.apk', sha), isNotNull);
    });
    test('第三方 / http / 冇 sha / 带端口 ⇒ 唔自动装', () {
      expect(vetUpdateDownload('https://evil.example/a.exe', sha), isNull);
      expect(vetUpdateDownload('http://dl.ylink.im/a.exe', sha), isNull);
      expect(vetUpdateDownload('https://dl.ylink.im/a.exe', null), isNull);
      expect(vetUpdateDownload('https://dl.ylink.im/a.exe', 'abc'), isNull);
      expect(vetUpdateDownload('https://dl.ylink.im:8443/a.exe', sha), isNull);
      expect(vetUpdateDownload('https://dl.ylink.im.evil.example/a.exe', sha), isNull);
    });
  });

  group('updateDownloadCandidates', () {
    test('dl.ylink.im 后面补 dl.yilian.live,路径 / query 不变', () {
      expect(updateDownloadCandidates('https://dl.ylink.im/voguesly-0.9.91-setup.exe?x=1'), [
        'https://dl.ylink.im/voguesly-0.9.91-setup.exe?x=1',
        'https://dl.yilian.live/voguesly-0.9.91-setup.exe?x=1',
      ]);
    });
    test('由镜像开始时补回主站', () {
      expect(updateDownloadCandidates('https://dl.yilian.live/a.apk'),
          ['https://dl.yilian.live/a.apk', 'https://dl.ylink.im/a.apk']);
    });
    test('非自家下载站不加镜像', () {
      expect(updateDownloadCandidates('http://127.0.0.1:8080/a.dmg'), ['http://127.0.0.1:8080/a.dmg']);
      expect(updateDownloadCandidates('https://evil.example/dl.ylink.im/a.exe'), ['https://evil.example/dl.ylink.im/a.exe']);
    });
  });

  group('normalizeSha256', () {
    test('64 位十六进制(大小写 / 空格都认)', () {
      final h = 'A' * 64;
      expect(normalizeSha256(h), 'a' * 64);
      expect(normalizeSha256('  ${'b' * 64}\n'), 'b' * 64);
    });
    test('空 / 太短 / 非十六进制 / 非字符串 = 当作没有', () {
      expect(normalizeSha256(null), isNull);
      expect(normalizeSha256(''), isNull);
      expect(normalizeSha256('abc'), isNull);
      expect(normalizeSha256('g' * 64), isNull);
      expect(normalizeSha256(123), isNull);
    });
  });

  group('verifyUpdateFile', () {
    late File f;
    final data = _payload(4096);
    setUp(() async {
      f = File('${tmp.path}/x.bin');
      await f.writeAsBytes(data);
    });

    test('sha 对 + 长度对 = ok', () async {
      final r = await verifyUpdateFile(
        f,
        expectedLength: data.length,
        expectedSha256: _sha(data),
      );
      expect(r.status, UpdateVerifyStatus.ok);
    });
    test('sha 错 = sha256Mismatch', () async {
      final r = await verifyUpdateFile(
        f,
        expectedSha256: _sha(_payload(4096, seed: 9)),
      );
      expect(r.status, UpdateVerifyStatus.sha256Mismatch);
      expect(r.actualSha256, _sha(data));
    });
    test('长度不足 = lengthMismatch(先于 sha 判断)', () async {
      final r = await verifyUpdateFile(
        f,
        expectedLength: data.length + 1,
        expectedSha256: _sha(data),
      );
      expect(r.status, UpdateVerifyStatus.lengthMismatch);
    });
    test('无 sha 字段(旧 manifest)只核长度', () async {
      expect(
        (await verifyUpdateFile(f, expectedLength: data.length)).status,
        UpdateVerifyStatus.ok,
      );
      expect(
        (await verifyUpdateFile(f, expectedLength: data.length - 1)).status,
        UpdateVerifyStatus.lengthMismatch,
      );
      expect((await verifyUpdateFile(f)).status, UpdateVerifyStatus.ok);
    });
    test('小于 minLength = tooSmall(保留 Mac 原来的 1MB 下限)', () async {
      final r = await verifyUpdateFile(f, minLength: 1024 * 1024);
      expect(r.status, UpdateVerifyStatus.tooSmall);
    });
  });

  group('downloadVerifiedUpdate', () {
    final data = _payload(256 * 1024);
    String savePath() => '${tmp.path}/voguesly-update.dmg';

    Future<File> run(_FakeServer server, {String? sha, int maxAttempts = 3}) =>
        downloadVerifiedUpdate(
          dio: dio,
          url: server.url,
          savePath: savePath(),
          expectedSha256: sha,
          maxAttempts: maxAttempts,
          retryDelay: Duration.zero,
        );

    test('sha 对:一次下完,文件内容一致,不留 .part', () async {
      final server = await _FakeServer.start((req, s) => _serve(req, s, data));
      addTearDown(server.close);
      final f = await run(server, sha: _sha(data));
      expect(await f.readAsBytes(), data);
      expect(server.requests, hasLength(1));
      expect(server.requests.first.acceptEncoding, 'identity');
      expect(File('${savePath()}.part').existsSync(), isFalse);
    });

    test('sha 错:删掉重下,3 次后放弃,不留任何文件', () async {
      final server = await _FakeServer.start((req, s) => _serve(req, s, data));
      addTearDown(server.close);
      await expectLater(
        run(server, sha: _sha(_payload(256 * 1024, seed: 99))),
        throwsA(
          isA<UpdateDownloadException>()
              .having(
                (e) => e.lastFailure,
                'lastFailure',
                UpdateVerifyStatus.sha256Mismatch,
              )
              .having((e) => e.attempts, 'attempts', 3),
        ),
      );
      expect(server.requests, hasLength(3));
      // sha 错 = 内容不可信,每次都从头下,不续传
      expect(server.requests.every((r) => r.range == null), isTrue);
      expect(File(savePath()).existsSync(), isFalse);
      expect(File('${savePath()}.part').existsSync(), isFalse);
    });

    test('长度不足(中途断开):第二次用 Range 续传补齐,sha 通过', () async {
      const cut = 100 * 1024;
      final server = await _FakeServer.start(
        (req, s) =>
            _serve(req, s, data, truncateAt: req.index == 0 ? cut : null),
      );
      addTearDown(server.close);
      final f = await run(server, sha: _sha(data));
      expect(await f.readAsBytes(), data);
      expect(server.requests, hasLength(2));
      expect(server.requests[1].range, 'bytes=$cut-');
      expect(server.requests[1].ifRange, '"v1"');
    });

    test('长度不足且一直断:3 次后放弃,最后不留半截文件', () async {
      final server = await _FakeServer.start(
        (req, s) => _serve(req, s, data, truncateAt: 10 * 1024),
      );
      addTearDown(server.close);
      await expectLater(
        run(server, sha: _sha(data)),
        throwsA(isA<UpdateDownloadException>()),
      );
      expect(server.requests, hasLength(3));
      expect(File(savePath()).existsSync(), isFalse);
      expect(File('${savePath()}.part').existsSync(), isFalse);
    });

    test('服务器不带 Content-Length 且悄悄截断(09-22 Mac 现场的形状):sha 抓到,重下成功', () async {
      final server = await _FakeServer.start(
        (req, s) => _serve(
          req,
          s,
          data,
          sendLength: false,
          truncateAt: req.index == 0 ? 50 * 1024 : null,
        ),
      );
      addTearDown(server.close);
      final f = await run(server, sha: _sha(data));
      expect(await f.readAsBytes(), data);
      expect(server.requests, hasLength(2));
    });

    test('续传时服务器不认 Range(回 200 整份):覆盖重写,不会拼接', () async {
      final server = await _FakeServer.start(
        (req, s) => _serve(
          req,
          s,
          data,
          honorRange: false,
          truncateAt: req.index == 0 ? 30 * 1024 : null,
        ),
      );
      addTearDown(server.close);
      final f = await run(server, sha: _sha(data));
      expect(await f.readAsBytes(), data);
      expect(await f.length(), data.length);
    });

    test('续传途中服务器文件被换(ETag 变):If-Range 令服务器回整份新文件', () async {
      final newData = _payload(256 * 1024, seed: 42);
      final server = await _FakeServer.start(
        (req, s) => req.index == 0
            ? _serve(req, s, data, truncateAt: 20 * 1024, etag: '"v1"')
            : _serve(req, s, newData, etag: '"v2"'),
      );
      addTearDown(server.close);
      final f = await run(server, sha: _sha(newData));
      expect(await f.readAsBytes(), newData);
    });

    test('无 sha 字段(旧 manifest 兼容):只核长度,完整就通过', () async {
      final server = await _FakeServer.start((req, s) => _serve(req, s, data));
      addTearDown(server.close);
      final f = await run(server);
      expect(await f.readAsBytes(), data);
    });

    test('无 sha 字段 + 长度不足:照样续传补齐', () async {
      final server = await _FakeServer.start(
        (req, s) =>
            _serve(req, s, data, truncateAt: req.index == 0 ? 64 * 1024 : null),
      );
      addTearDown(server.close);
      final f = await run(server);
      expect(await f.length(), data.length);
      expect(await f.readAsBytes(), data);
      expect(server.requests[1].range, 'bytes=${64 * 1024}-');
    });

    test('上次会话留下的旧 .part / 旧安装包会先清掉,不会拿来续传', () async {
      await File('${savePath()}.part').writeAsBytes(_payload(1000, seed: 5));
      await File(savePath()).writeAsBytes(_payload(1000, seed: 6));
      final server = await _FakeServer.start((req, s) => _serve(req, s, data));
      addTearDown(server.close);
      final f = await run(server, sha: _sha(data));
      expect(await f.readAsBytes(), data);
      expect(server.requests.single.range, isNull);
    });
  });
}
