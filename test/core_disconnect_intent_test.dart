import 'package:fl_clash/core/service.dart';
import 'package:flutter_test/flutter_test.dart';

// [0.9.89] 「core done」英文提示回归测试:主动停核心(启动接管旧核心、切增强 / 兼容、断开)
// 引起嘅断线唔可以当崩溃;冇标记或者标记过咗 10 秒嘅断线先当意外。
void main() {
  final now = DateTime(2026, 9, 24, 19, 0, 0);
  test('冇主动停过 ⇒ 意外断线', () {
    expect(isIntentionalCoreDisconnect(null, now), isFalse);
  });
  test('主动停后 3 秒内断线 ⇒ 主动,唔报', () {
    expect(isIntentionalCoreDisconnect(now.subtract(const Duration(seconds: 3)), now), isTrue);
  });
  test('主动停后 11 秒先断 ⇒ 当意外(标记唔可以永远吞咗真崩溃)', () {
    expect(isIntentionalCoreDisconnect(now.subtract(const Duration(seconds: 11)), now), isFalse);
  });
}
