import 'package:fl_clash/voguesly/voguesly_api.dart';
import 'package:fl_clash/voguesly/voguesly_noplan.dart';
import 'package:flutter_test/flutter_test.dart';

// [0.9.98] 验证包到期 / 用完 / 快用完 ⇒ 引导升级正式套餐(唔引导再买 ¥3.9)。
void main() {
  const gb = 1073741824;
  final now = DateTime.utc(2026, 10, 6, 12);
  int sec(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
  VogueslyUser user({int? planId = 18, String? name, int used = 0, int total = 3 * gb, DateTime? exp}) =>
      VogueslyUser(upload: 0, download: used, transferEnable: total,
          expiredAt: exp == null ? null : sec(exp), planId: planId, planName: name);

  test('正式套餐唔当验证包', () {
    expect(vogueslyTrialStageAt(user(planId: 11, name: 'Pro', used: 3 * gb), now), VogueslyTrialStage.none);
  });
  test('认名(换咗 id 都认得)', () {
    expect(vogueslyIsTrialPlan(user(planId: 99, name: 'AI 稳定性验证包')), isTrue);
  });
  test('刚买:唔提示', () {
    expect(vogueslyTrialStageAt(user(used: gb ~/ 2, exp: now.add(const Duration(days: 6))), now), VogueslyTrialStage.none);
  });
  test('用咗 ≥80%:快用完', () {
    expect(vogueslyTrialStageAt(user(used: (2.5 * gb).toInt(), exp: now.add(const Duration(days: 6))), now), VogueslyTrialStage.low);
  });
  test('剩 ≤1 日:快用完', () {
    expect(vogueslyTrialStageAt(user(used: gb ~/ 10, exp: now.add(const Duration(hours: 20))), now), VogueslyTrialStage.low);
  });
  test('流量剩 ≤50MB(未到期):已用完', () {
    expect(vogueslyTrialStageAt(user(used: 3 * gb - 10 * 1024 * 1024, exp: now.add(const Duration(days: 3))), now), VogueslyTrialStage.used);
  });
  test('超用(负数剩余)亦算用完', () {
    expect(vogueslyTrialStageAt(user(used: 3 * gb + gb ~/ 10, exp: now.add(const Duration(days: 3))), now), VogueslyTrialStage.used);
  });
  test('到期优先', () {
    expect(vogueslyTrialStageAt(user(used: 0, exp: now.subtract(const Duration(minutes: 1))), now), VogueslyTrialStage.expired);
  });
}
