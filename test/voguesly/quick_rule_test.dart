import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/voguesly/voguesly_quick_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? n(RuleAction a, String s) => normalizeQuickRuleContent(a, s);

  test('域名:容忍 URL / 大写 / *. 前缀', () {
    expect(n(RuleAction.DOMAIN_SUFFIX, 'example.com'), 'example.com');
    expect(n(RuleAction.DOMAIN_SUFFIX, 'https://WWW.Example.com/path?q=1'), 'www.example.com');
    expect(n(RuleAction.DOMAIN_SUFFIX, '*.example.com'), 'example.com');
    expect(n(RuleAction.DOMAIN_SUFFIX, '.example.com'), 'example.com');
    expect(n(RuleAction.DOMAIN, 'api.openai.com:443'), 'api.openai.com');
  });
  test('域名:拒绝错格式', () {
    expect(n(RuleAction.DOMAIN_SUFFIX, ''), isNull);
    expect(n(RuleAction.DOMAIN_SUFFIX, 'example'), isNull);
    expect(n(RuleAction.DOMAIN_SUFFIX, 'exa mple.com'), isNull);
    expect(n(RuleAction.DOMAIN_SUFFIX, 'a.com,DIRECT'), isNull);
    expect(n(RuleAction.DOMAIN_SUFFIX, 'DOMAIN-SUFFIX,a.com'), isNull);
  });
  test('关键词', () {
    expect(n(RuleAction.DOMAIN_KEYWORD, 'Google'), 'google');
    expect(n(RuleAction.DOMAIN_KEYWORD, 'g'), isNull);
    expect(n(RuleAction.DOMAIN_KEYWORD, 'goo gle'), isNull);
  });
  test('IP 段', () {
    expect(n(RuleAction.IP_CIDR, '1.2.3.4'), '1.2.3.4/32');
    expect(n(RuleAction.IP_CIDR, '10.0.0.0/8'), '10.0.0.0/8');
    expect(n(RuleAction.IP_CIDR, '10.0.0.0/33'), isNull);
    expect(n(RuleAction.IP_CIDR, '300.1.1.1'), isNull);
    expect(n(RuleAction.IP_CIDR, 'example.com'), isNull);
  });
}
