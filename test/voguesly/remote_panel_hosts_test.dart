import 'package:fl_clash/voguesly/voguesly_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// [0.9.91] 面板入口服务端下发(version.json panel_hosts):切域唔使发版,但唔可以被引去第三方。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugSetRemotePanelHosts(const []);
  });

  group('sanitizeRemotePanelHosts', () {
    test('只收自家根域嘅 https 根地址,统一小写、去斜杠、去重', () {
      expect(
        sanitizeRemotePanelHosts([
          'https://cp.ylink.uk',
          'https://CP.YLI.WORLD/',
          'https://cp.ylink.uk',
          ' https://cp.yilian.live ',
        ]),
        ['https://cp.ylink.uk', 'https://cp.yli.world', 'https://cp.yilian.live'],
      );
    });
    test('第三方 / http / 带路径端口参数 / 冒充后缀 一律丢弃', () {
      expect(
        sanitizeRemotePanelHosts([
          'https://evil.example',
          'http://cp.ylink.uk',
          'https://cp.ylink.uk/api',
          'https://cp.ylink.uk:8443',
          'https://cp.ylink.uk/?x=1',
          'https://user@cp.ylink.uk',
          'https://ylink.uk.evil.example',
          'https://notylink.uk',
          42,
          null,
        ]),
        isEmpty,
      );
    });
    test('免费域名后缀一律唔信(可能被收回 / 抢注)', () {
      expect(sanitizeRemotePanelHosts(['https://cp.samseah.qzz.io', 'https://n1.samzi.ccwu.cc', 'https://cp.ylink.uk']),
          ['https://cp.ylink.uk']);
      expect(isVogueslyTrustedRemoteHost('cp.yilian.live'), isTrue);
      expect(isVogueslyTrustedRemoteHost('samseah.qzz.io'), isFalse);
    });
    test('sanitizeRemoteBaseUrl:邀请基址只收可信 https,保留 path', () {
      expect(sanitizeRemoteBaseUrl('https://join.hazu.world/'), 'https://join.hazu.world/');
      expect(sanitizeRemoteBaseUrl('https://JOIN.hazu.world/go/register'), 'https://join.hazu.world/go/register');
      expect(sanitizeRemoteBaseUrl('https://evil.example/'), isNull);
      expect(sanitizeRemoteBaseUrl('http://join.hazu.world/'), isNull);
      expect(sanitizeRemoteBaseUrl('https://x.samseah.qzz.io/'), isNull);
      expect(sanitizeRemoteBaseUrl('https://join.hazu.world/?a=1'), isNull);
      expect(sanitizeRemoteBaseUrl(42), isNull);
    });
    test('唔係 List 当冇;最多 8 个', () {
      expect(sanitizeRemotePanelHosts('https://cp.ylink.uk'), isEmpty);
      expect(sanitizeRemotePanelHosts(null), isEmpty);
      final many = [for (var i = 0; i < 12; i++) 'https://p$i.ylink.uk'];
      expect(sanitizeRemotePanelHosts(many).length, 8);
    });
  });

  group('vogueslyHosts', () {
    test('冇远端 = 内置名单', () {
      expect(vogueslyHosts(), kVogueslyHosts);
    });
    test('远端排先,再接内置,去重', () async {
      await applyVogueslyRemotePanelHosts(['https://cp2.ylink.uk', 'https://cp.yli.world']);
      final h = vogueslyHosts();
      expect(h.take(2), ['https://cp2.ylink.uk', 'https://cp.yli.world']);
      expect(h.where((x) => x == 'https://cp.yli.world').length, 1);
      expect(h.toSet().containsAll(kVogueslyHosts), isTrue);
    });
    test('下发唔合格 / 空 ⇒ 保留上次,唔会清空', () async {
      await applyVogueslyRemotePanelHosts(['https://cp2.ylink.uk']);
      await applyVogueslyRemotePanelHosts(['https://evil.example']);
      await applyVogueslyRemotePanelHosts(null);
      expect(vogueslyHosts().first, 'https://cp2.ylink.uk');
    });
    test('存低之后冷启动读得返', () async {
      await applyVogueslyRemotePanelHosts(['https://cp2.ylink.uk']);
      debugSetRemotePanelHosts(const []);
      expect(vogueslyHosts().first, kVogueslyHosts.first);
      await loadVogueslyRemotePanelHosts();
      expect(vogueslyHosts().first, 'https://cp2.ylink.uk');
    });
  });
}
