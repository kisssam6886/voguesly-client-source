// [0.9.91] 全局模式横条嘅倍率解析:节点名格式喺 Clash / sing-box 同小火箭 v3 唔同,两种都要认。
import 'package:fl_clash/views/dashboard/widgets/current_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Clash / sing-box 名:【3x】/【5x】', () {
    expect(vogueslyRouteRate('【5x】中转·🇺🇸 🏠 美国住宅·4837 双ISP ⑨D'), 5);
    expect(vogueslyRouteRate('【3x】中转·🇯🇵 🏠 日本住宅·NTT ⑧A'), 3);
  });
  test('小火箭 v3 名:5x中转E·…', () {
    expect(vogueslyRouteRate('5x中转E·快线·德国 ④ 🚀🇩🇪'), 5);
    expect(vogueslyRouteRate('3x中转A·美国住宅·4837 ⑧ 🏠🇺🇸'), 3);
  });
  test('冇倍率标 = 1x(直连 / CF / 组名)', () {
    expect(vogueslyRouteRate('🇺🇸 🏠 美国住宅·4837 双ISP 直连'), 1);
    expect(vogueslyRouteRate('🇯🇵 🏠 日本住宅·NTT CF'), 1);
    expect(vogueslyRouteRate(''), 1);
  });
}
