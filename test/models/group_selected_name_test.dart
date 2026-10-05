import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-09-29:订阅改名后,本地记住嘅旧选择唔可以再当「当前」(否则测速永远转圈)。
void main() {
  const members = [
    Proxy(name: '🇺🇸 🏠 易联住宅·4837 大带宽', type: 'Selector'),
    Proxy(name: '【3x】🇺🇸 🏠 易联住宅·4837 高速', type: 'Vless'),
  ];
  const manual = Group(
    type: GroupType.Selector,
    name: '🛠 全部节点·手动',
    all: members,
    now: '🇺🇸 🏠 易联住宅·4837 大带宽',
  );

  test('旧名(已唔喺组入面)⇒ 用核心 now', () {
    expect(
      manual.getCurrentSelectedName('🇺🇸 🏠 美国住宅·4837 II ⑧A'),
      '🇺🇸 🏠 易联住宅·4837 大带宽',
    );
  });

  test('正常选择 ⇒ 照用本地选择', () {
    expect(
      manual.getCurrentSelectedName('【3x】🇺🇸 🏠 易联住宅·4837 高速'),
      '【3x】🇺🇸 🏠 易联住宅·4837 高速',
    );
  });

  test('冇本地选择 ⇒ 用核心 now', () {
    expect(manual.getCurrentSelectedName(''), '🇺🇸 🏠 易联住宅·4837 大带宽');
  });

  test('组成员未载入(all 为空)⇒ 唔误判,照用本地选择', () {
    const loading = Group(type: GroupType.Selector, name: 'x', now: 'a');
    expect(loading.getCurrentSelectedName('b'), 'b');
  });

  test('url-test / fallback 行为不变', () {
    const auto = Group(type: GroupType.Fallback, name: 'auto', all: members, now: '【3x】🇺🇸 🏠 易联住宅·4837 高速');
    expect(auto.getCurrentSelectedName('旧名'), '【3x】🇺🇸 🏠 易联住宅·4837 高速');
  });
}
