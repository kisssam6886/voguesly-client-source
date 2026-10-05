// [0.9.90] 「反馈问题 / 上传日志」网络抖动自动重试。
// 背景:09-24 Sam Mac 22:16 报「连不上服务器」、22:18 再撳即成功;客户 Windows 讲「上传完了」但面板 0 请求。
// 用本机 HttpServer 模拟「连接喺回应前被掐断」(= 晚高峰中转抖动),验证:
//   ① 请求未落地嘅错误会隔 3 秒重试,最多 3 次;② 服务器有回应(4xx)唔重试;③ 全部失败会放弃并如实报错。
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/voguesly/voguesly_api.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 前 [dropFirst] 个请求直接掐断连接,之后返 [status] + [body]。
Future<(HttpServer, List<int>)> _server({
  required int dropFirst,
  int status = 200,
  String body = '{"data":true}',
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final hits = <int>[0];
  server.listen((req) async {
    hits[0]++;
    await req.drain<void>();
    if (hits[0] <= dropFirst) {
      final socket = await req.response.detachSocket(writeHeaders: false);
      socket.destroy();
      return;
    }
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(body);
    await req.response.close();
  });
  return (server, hits);
}

void main() {
  setUpAll(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });

  test('只有请求未落地嘅错误先重试', () {
    for (final t in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.connectionError,
      DioExceptionType.sendTimeout,
      DioExceptionType.unknown,
    ]) {
      expect(VogueslyApi.isRetryableSubmitError(t), isTrue, reason: '$t');
    }
    for (final t in [
      DioExceptionType.receiveTimeout, // 可能已到服务器,重试会开重复工单
      DioExceptionType.badResponse,
      DioExceptionType.cancel,
      DioExceptionType.badCertificate,
    ]) {
      expect(VogueslyApi.isRetryableSubmitError(t), isFalse, reason: '$t');
    }
  });

  test('前两次断线、第三次成功 ⇒ 成功,服务器收到 3 次,按钮显示 2/3、3/3', () async {
    final (server, hits) = await _server(dropFirst: 2);
    addTearDown(() => server.close(force: true));
    final api = VogueslyApi(hosts: ['http://127.0.0.1:${server.port}']);
    final retries = <String>[];
    final res = await api.submitFeedback('tok',
        message: 'm', subject: 's', onRetry: (n, t) => retries.add('$n/$t'));
    expect(res.ok, isTrue);
    expect(hits[0], 3);
    expect(retries, ['2/3', '3/3']);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('服务器有回应(403 带 message)⇒ 唔重试,照实显示服务器讲嘅嘢', () async {
    final (server, hits) = await _server(
        dropFirst: 0, status: 403, body: '{"message":"未登录或登陆已过期"}');
    addTearDown(() => server.close(force: true));
    final api = VogueslyApi(hosts: ['http://127.0.0.1:${server.port}']);
    final res = await api.submitFeedback('tok', message: 'm', subject: 's');
    expect(res.ok, isFalse);
    expect(res.maybeSent, isFalse);
    expect(res.message, '未登录或登陆已过期');
    expect(hits[0], 1);
  });

  test('三次都断线 ⇒ 放弃,maybeSent=false,报网络异常', () async {
    final (server, hits) = await _server(dropFirst: 99);
    addTearDown(() => server.close(force: true));
    final api = VogueslyApi(hosts: ['http://127.0.0.1:${server.port}']);
    final res = await api.submitFeedback('tok', message: 'm', subject: 's');
    expect(res.ok, isFalse);
    expect(res.maybeSent, isFalse);
    expect(res.message, startsWith('网络异常'));
    expect(hits[0], 3);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
