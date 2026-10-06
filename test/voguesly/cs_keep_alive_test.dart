import 'package:fl_clash/voguesly/voguesly_cs.dart';
import 'package:flutter_test/flutter_test.dart';

// [0.9.98 Sam] 客服 tab 切走再返嚟唔可以重新加载:WebView 保唔保,只睇「而家睇紧」或「保活中」,
// 唔再分手机 / 桌面(0.9.84 手机切走即销毁,Sam 反馈切去「我的」再返客服成页重新加载)。
void main() {
  test('睇紧客服:一定保住', () {
    expect(csKeepPanel(visible: true, alive: true), isTrue);
  });

  test('切去其他 tab 但仲喺保活期(15 分钟内):保住,唔重新加载', () {
    expect(csKeepPanel(visible: false, alive: true), isTrue);
  });

  test('隐藏满 15 分钟 / 登出 / 明确关闭(alive=false)而且唔喺眼前:销毁', () {
    expect(csKeepPanel(visible: false, alive: false), isFalse);
  });
}
