import 'dart:io';

import 'package:fl_clash/voguesly/voguesly_detection.dart';
import 'package:flutter_test/flutter_test.dart';

// [0.9.98] 实网测试:平时 skip;设 VG_WARM_PROXY_PORT=<本机 mixed 端口> 先跑。
// 证明「同一条连接往返」明显低于旧做法嘅冷握手(东京中转→纽约实测 ~255ms vs ~1070ms)。
void main() {
  final port = int.tryParse(Platform.environment['VG_WARM_PROXY_PORT'] ?? '');
  test('经本地代理量暖连接往返', () async {
    for (final url in [
      'https://cloudflare.com/cdn-cgi/trace',
      'https://www.google.com/generate_204',
      'https://i.ytimg.com/generate_204',
      'https://cdn.jsdelivr.net/npm/latency-test@1.0.0/generate_200',
    ]) {
      final ms = await vogueslyWarmRtt(port!, url);
      // ignore: avoid_print
      print('$url => $ms ms');
      expect(ms, isNotNull);
      expect(ms!, lessThan(800));
    }
  }, skip: port == null ? '未设 VG_WARM_PROXY_PORT' : false, timeout: const Timeout(Duration(minutes: 2)));
}
