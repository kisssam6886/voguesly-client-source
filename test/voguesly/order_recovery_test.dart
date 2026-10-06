import 'package:fl_clash/voguesly/voguesly_shop.dart';
import 'package:flutter_test/flutter_test.dart';

// [0.9.98] 下单被拒嘅两种补救要认得出服务端原文(XBoard 冇错误码,只返文案)。
void main() {
  group('替换确认(易联 override OrderController::save)', () {
    test('周期订阅生效中买一次性套餐', () {
      expect(vogueslyIsReplaceConfirm('你当前有生效中的订阅（Pro，还剩 20 天）。「AI 稳定性验证包」是独立的一次性套餐…'), isTrue);
    });
    test('一次性套餐仲有流量再买', () {
      expect(vogueslyIsReplaceConfirm('你当前有生效中的订阅（AI 稳定性验证包，还剩 1.2 GB 流量）。再买…确认要继续购买吗？'), isTrue);
    });
    test('其他错误唔当替换确认', () {
      expect(vogueslyIsReplaceConfirm('该订阅已售罄，请更换其他订阅'), isFalse);
      expect(vogueslyIsReplaceConfirm('您有未付款或开通中的订单，请稍后再试或将其取消'), isFalse);
    });
  });

  group('已有未付款订单(XBoard 原生)', () {
    test('简体', () => expect(vogueslyIsPendingOrder('您有未付款或开通中的订单，请稍后再试或将其取消'), isTrue));
    test('繁体', () => expect(vogueslyIsPendingOrder('您有未付款或開通中的訂單，請稍後再試或將其取消'), isTrue));
    test('英文', () => expect(vogueslyIsPendingOrder('You have an unpaid or pending order, please try again later or cancel it'), isTrue));
    test('其他错误', () => expect(vogueslyIsPendingOrder('下单失败: Network error'), isFalse));
  });
}
