import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// [0.9.85] 一键更新下载校验(B-P1-UPDATE-VERIFY-0922)。
///
/// 以前三端(Mac DMG / Windows setup.exe / 安卓 APK)下载完都不核对完整性:
/// Mac 只看「>= 1MB」,半截 DMG 被当成完整去 `hdiutil attach` ⇒「磁盘映像已损坏」(Sam 09-22 实际遇到)。
///
/// 现在下载完依次核对:
///   ① 文件大小 = 服务器给的完整长度(Content-Length / Content-Range,有的话);
///   ② sha256 = version.json 对应平台条目的 `sha256`(有的话;旧 manifest 没有就只核长度)。
/// 不对就重下,最多 [maxAttempts] 次:长度不足 / 网络中断 ⇒ 保留已下载部分,用 HTTP Range 续传;
/// sha256 不对 ⇒ 文件内容已坏,删掉从头下。
///
/// 纯 Dart(不依赖 Flutter),单元测试见 test/voguesly/update_download_test.dart。
enum UpdateVerifyStatus { ok, lengthMismatch, sha256Mismatch, tooSmall }

/// 最终失败时「打开下载页」按钮的目标(下载页 = dl.ylink.im 首页,与一键更新同一个下载站)。
const kVogueslyDownloadPageUrl = 'https://dl.ylink.im/';

class UpdateVerifyResult {
  final UpdateVerifyStatus status;
  final int actualLength;
  final String? actualSha256;

  const UpdateVerifyResult(
    this.status, {
    required this.actualLength,
    this.actualSha256,
  });

  bool get isOk => status == UpdateVerifyStatus.ok;
}

/// version.json 里的 sha256:只认 64 位十六进制(大小写 / 前后空格都容忍),其它一律当「没有」。
String? normalizeSha256(Object? value) {
  if (value is! String) return null;
  final s = value.trim().toLowerCase();
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(s) ? s : null;
}

Future<String> sha256OfFile(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

/// 核对已下载文件。[expectedLength] <= 0 或 null = 不核长度;[expectedSha256] 无效或 null = 不核 sha。
Future<UpdateVerifyResult> verifyUpdateFile(
  File file, {
  int? expectedLength,
  String? expectedSha256,
  int? minLength,
}) async {
  final length = await file.length();
  if (expectedLength != null &&
      expectedLength > 0 &&
      length != expectedLength) {
    return UpdateVerifyResult(
      UpdateVerifyStatus.lengthMismatch,
      actualLength: length,
    );
  }
  if (minLength != null && length < minLength) {
    return UpdateVerifyResult(
      UpdateVerifyStatus.tooSmall,
      actualLength: length,
    );
  }
  final want = normalizeSha256(expectedSha256);
  if (want != null) {
    final got = await sha256OfFile(file);
    if (got != want) {
      return UpdateVerifyResult(
        UpdateVerifyStatus.sha256Mismatch,
        actualLength: length,
        actualSha256: got,
      );
    }
    return UpdateVerifyResult(
      UpdateVerifyStatus.ok,
      actualLength: length,
      actualSha256: got,
    );
  }
  return UpdateVerifyResult(UpdateVerifyStatus.ok, actualLength: length);
}

/// 重试 [attempts] 次仍然不完整。[lastFailure] 为 null 表示最后一次是网络错误(连不上 / 中途断开)。
class UpdateDownloadException implements Exception {
  final int attempts;
  final UpdateVerifyStatus? lastFailure;
  final Object? lastError;

  const UpdateDownloadException({
    required this.attempts,
    this.lastFailure,
    this.lastError,
  });

  @override
  String toString() =>
      'UpdateDownloadException(attempts: $attempts, lastFailure: $lastFailure, lastError: $lastError)';
}

class _ContentRange {
  final int? start;
  final int? total;

  const _ContentRange(this.start, this.total);
}

/// 解析 `Content-Range: bytes 100-999/1000` 或 `bytes */1000`。
_ContentRange? _parseContentRange(String? value) {
  if (value == null) return null;
  final m = RegExp(
    r'^\s*bytes\s+(?:(\d+)-\d+|\*)/(\d+|\*)\s*$',
  ).firstMatch(value);
  if (m == null) return null;
  return _ContentRange(
    m.group(1) == null ? null : int.parse(m.group(1)!),
    m.group(2) == '*' ? null : int.parse(m.group(2)!),
  );
}

bool _isIdentityEncoding(String? encoding) =>
    encoding == null ||
    encoding.isEmpty ||
    encoding.toLowerCase() == 'identity';

/// [0.9.91] 下载站镜像:同一台荷兰机,两个唔同根域(dl.yilian.live 经 CF 橙云)。
/// dl.ylink.im 下载失败(被封 / 断线)就用同一路径改去下一个;最后照样 sha256 校验,换镜像唔会装错档。
const kVogueslyDownloadMirrorHosts = ['dl.ylink.im', 'dl.yilian.live'];

/// [0.9.91] version.json 嘅安装包地址可唔可以自动下载安装:https + host 喺 [kVogueslyDownloadMirrorHosts] + 有合格 sha256。
/// 任何一样唔啱就返回 null ⇒ 调用方只打开下载页畀用户手动下载,**唔会自动运行来历唔明嘅安装包**。
({String url, String sha256})? vetUpdateDownload(Object? url, Object? sha256) {
  final sha = normalizeSha256(sha256);
  if (url is! String || sha == null) return null;
  final u = Uri.tryParse(url.trim());
  if (u == null || u.scheme != 'https' || u.userInfo.isNotEmpty || u.hasPort) return null;
  if (!kVogueslyDownloadMirrorHosts.contains(u.host.toLowerCase())) return null;
  return (url: url.trim(), sha256: sha);
}

/// [url] 喺镜像名单入面 ⇒ 返回「原址 + 其他镜像同路径」;否则只返回原址。
List<String> updateDownloadCandidates(String url) {
  final u = Uri.tryParse(url);
  if (u == null || !kVogueslyDownloadMirrorHosts.contains(u.host)) return [url];
  return [
    url,
    for (final h in kVogueslyDownloadMirrorHosts)
      if (h != u.host) u.replace(host: h).toString(),
  ];
}

/// 按 [updateDownloadCandidates] 逐个镜像试 [_downloadVerifiedUpdateOnce];全部失败先抛最后一个错误。
/// 取消([cancelToken])唔会再试下一个镜像。
Future<File> downloadVerifiedUpdate({
  required Dio dio,
  required String url,
  required String savePath,
  String? expectedSha256,
  int? minLength,
  int maxAttempts = 3,
  void Function(int received, int total)? onProgress,
  CancelToken? cancelToken,
  Duration retryDelay = const Duration(seconds: 1),
  void Function(String message)? log,
}) async {
  final candidates = updateDownloadCandidates(url);
  for (var i = 0; i < candidates.length; i++) {
    try {
      return await _downloadVerifiedUpdateOnce(
        dio: dio,
        url: candidates[i],
        savePath: savePath,
        expectedSha256: expectedSha256,
        minLength: minLength,
        maxAttempts: maxAttempts,
        onProgress: onProgress,
        cancelToken: cancelToken,
        retryDelay: retryDelay,
        log: log,
      );
    } on UpdateDownloadException catch (e) {
      if (i == candidates.length - 1 || (cancelToken?.isCancelled ?? false)) rethrow;
      log?.call('[update] ${Uri.tryParse(candidates[i])?.host} failed ($e), try mirror ${Uri.tryParse(candidates[i + 1])?.host}');
    }
  }
  throw StateError('unreachable');
}

/// 下载 [url] 到 [savePath] 并校验;成功返回最终文件,失败抛 [UpdateDownloadException]。
/// 取消([cancelToken])时原样抛出 dio 的取消异常。
///
/// - 下载过程写到 `savePath.part`,校验通过才改名成 [savePath] ⇒ 安装步骤永远拿不到半截文件。
/// - 请求带 `Accept-Encoding: identity`:避免压缩传输令 Content-Length 与文件大小对不上。
/// - 续传带 `If-Range: <ETag>`:服务器上的文件中途换了会整份重给(200),不会拼出「新旧各半」的文件。
Future<File> _downloadVerifiedUpdateOnce({
  required Dio dio,
  required String url,
  required String savePath,
  String? expectedSha256,
  int? minLength,
  int maxAttempts = 3,
  void Function(int received, int total)? onProgress,
  CancelToken? cancelToken,
  Duration retryDelay = const Duration(seconds: 1),
  void Function(String message)? log,
}) async {
  final target = File(savePath);
  final part = File('$savePath.part');
  // 上一次会话留下的档可能是别的版本:不续传,从头下。
  for (final f in [target, part]) {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
  final wantSha = normalizeSha256(expectedSha256);
  String? etag;
  int? total;
  UpdateVerifyStatus? lastFailure;
  Object? lastError;

  Future<void> deletePart() async {
    try {
      if (await part.exists()) await part.delete();
    } catch (_) {}
  }

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    if (attempt > 1 && retryDelay > Duration.zero) {
      await Future<void>.delayed(retryDelay * (attempt - 1));
    }
    if (cancelToken?.isCancelled == true) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: url),
        reason: cancelToken?.cancelError?.error,
      );
    }
    var have = await part.exists() ? await part.length() : 0;
    var skipDownload = false;
    try {
      final headers = <String, dynamic>{'Accept-Encoding': 'identity'};
      if (have > 0) {
        headers['Range'] = 'bytes=$have-';
        if (etag != null) headers['If-Range'] = etag;
      }
      final response = await dio.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: headers,
          followRedirects: true,
          validateStatus: (s) => s == 200 || s == 206 || s == 416,
        ),
      );
      final status = response.statusCode;
      final body = response.data;
      etag = response.headers.value('etag') ?? etag;
      IOSink? sink;
      if (status == 416) {
        // 已下载部分 >= 服务器文件:若刚好等于完整长度就直接进校验,否则作废重下。
        final cr = _parseContentRange(response.headers.value('content-range'));
        await body?.stream.drain<void>();
        if (cr?.total != null && cr!.total == have) {
          total = cr.total;
          skipDownload = true;
        } else {
          log?.call('[update] attempt $attempt: 416 with have=$have, restart');
          await deletePart();
          lastFailure = UpdateVerifyStatus.lengthMismatch;
          continue;
        }
      } else if (status == 206) {
        final cr = _parseContentRange(response.headers.value('content-range'));
        if (cr == null || cr.start != have) {
          // 服务器给的片段起点不对:不敢拼接,作废重下。
          await body?.stream.drain<void>();
          log?.call(
            '[update] attempt $attempt: bad content-range ${response.headers.value('content-range')}',
          );
          await deletePart();
          lastFailure = UpdateVerifyStatus.lengthMismatch;
          continue;
        }
        total = cr.total ?? total;
        sink = part.openWrite(mode: FileMode.writeOnlyAppend);
      } else {
        // 200:整份(首次,或服务器不支持 / 拒绝续传)。
        have = 0;
        final cl = int.tryParse(response.headers.value('content-length') ?? '');
        final identity = _isIdentityEncoding(
          response.headers.value('content-encoding'),
        );
        total = identity && cl != null && cl > 0 ? cl : null;
        sink = part.openWrite(mode: FileMode.writeOnly);
      }
      if (!skipDownload && sink != null && body != null) {
        var received = have;
        try {
          await for (final chunk in body.stream) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(received, total ?? -1);
          }
        } finally {
          await sink.flush();
          await sink.close();
        }
      } else if (sink != null) {
        await sink.close();
      }
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) rethrow;
      if (cancelToken?.isCancelled == true) rethrow;
      // 网络错误 / 中途断开:保留已下载部分,下一次用 Range 续传。
      lastError = e;
      lastFailure = null;
      final got = await part.exists() ? await part.length() : 0;
      log?.call(
        '[update] attempt $attempt/$maxAttempts network error after $got bytes: $e',
      );
      continue;
    }

    if (!await part.exists()) {
      lastFailure = UpdateVerifyStatus.lengthMismatch;
      continue;
    }
    final result = await verifyUpdateFile(
      part,
      expectedLength: total,
      expectedSha256: wantSha,
      minLength: minLength,
    );
    if (result.isOk) {
      if (await target.exists()) await target.delete();
      await part.rename(savePath);
      log?.call(
        '[update] verified ok: ${result.actualLength} bytes'
        '${wantSha == null ? ' (no sha256 in manifest, length only)' : ', sha256 ok'}'
        ' after $attempt attempt(s)',
      );
      return File(savePath);
    }
    lastFailure = result.status;
    lastError = null;
    log?.call(
      '[update] attempt $attempt/$maxAttempts verify failed: ${result.status.name}'
      ' length=${result.actualLength} expected=${total ?? '?'}'
      '${result.actualSha256 != null ? ' sha256=${result.actualSha256}' : ''}',
    );
    final resumable =
        result.status == UpdateVerifyStatus.lengthMismatch &&
        total != null &&
        result.actualLength < total;
    if (!resumable) {
      // sha256 不对 / 比完整长度还长 / 太小:内容不可信,删掉从头下。
      await deletePart();
    }
  }
  await deletePart();
  throw UpdateDownloadException(
    attempts: maxAttempts,
    lastFailure: lastFailure,
    lastError: lastError,
  );
}
