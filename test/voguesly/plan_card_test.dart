import 'package:fl_clash/voguesly/voguesly_api.dart';
import 'package:fl_clash/voguesly/voguesly_shop.dart';
import 'package:flutter_test/flutter_test.dart';

// [0.9.98] 套餐卡:plan.content 係 Markdown 原文,副标题唔可以露出 `>` `**` `##`;后台 tags 要解析出嚟。
void main() {
  group('副标题去 Markdown(用 10-06 生产 content 头几行做样本)', () {
    test('Pro', () {
      const raw = '> 🏠 Verizon / AT&T 原生住宅IP · 🧠 国内直连不绕路 · 🔒 风控养号级纯净\n\n'
          '**⭐ 最热 · AI 全家桶 + 4K 流媒体一条龙**，个人主力推荐。\n\n## 主推套餐（个人首选）\n\n- **月付** ¥69';
      expect(vogueslyPlanSubtitle(raw),
          '🏠 Verizon / AT&T 原生住宅IP · 🧠 国内直连不绕路 · 🔒 风控养号级纯净\n⭐ 最热 · AI 全家桶 + 4K 流媒体一条龙，个人主力推荐。');
    });
    test('验证包', () {
      const raw = '> 🏠 Verizon / AT&T 原生住宅IP · 🧠 国内直连不绕路 · 🔒 风控养号级纯净\n\n'
          '**¥3.9 先验货** —— 用真住宅IP实测 ChatGPT / 银行登录稳不稳，再决定要不要长期用。';
      final s = vogueslyPlanSubtitle(raw)!;
      expect(s, isNot(contains('**')));
      expect(s, isNot(startsWith('>')));
      expect(s, contains('¥3.9 先验货 —— 用真住宅IP'));
    });
    test('链接留文字、标题 / 列表符号去走', () {
      const raw = '## 标题\n- **出口**:美国 AT&T 原生家庭宽带 IP,可在 [cleanip.io](https://cleanip.io/?utm_source=x) 自查';
      expect(vogueslyPlanSubtitle(raw), '标题\n出口:美国 AT&T 原生家庭宽带 IP,可在 cleanip.io 自查');
    });
    test('HTML 照旧处理', () {
      expect(vogueslyPlanSubtitle('<p>第一行</p><p>第二&nbsp;行</p><p>第三行</p>'), '第一行\n第二 行');
    });
    test('乘号唔当斜体', () {
      expect(vogueslyPlanSubtitle('7*24 客服'), '7*24 客服');
    });
    test('空', () => expect(vogueslyPlanSubtitle('  '), isNull));
  });

  group('tags 解析', () {
    test('数组', () => expect(VogueslyPlan.parseTags(['推荐', ' 新 ', '']), ['推荐', '新']));
    test('JSON 字串(含 \\u 转义)', () => expect(VogueslyPlan.parseTags('["\\u63a8\\u8350"]'), ['推荐']));
    test('null / 坏数据', () {
      expect(VogueslyPlan.parseTags(null), isEmpty);
      expect(VogueslyPlan.parseTags('[坏'), isEmpty);
    });
    test('最多 4 个', () => expect(VogueslyPlan.parseTags(['a', 'b', 'c', 'd', 'e']).length, 4));
  });
}
