import 'package:fl_clash/common/constant.dart' as constant;
import 'package:fl_clash/voguesly/voguesly_remote_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// [0.9.92] version.json app_config:逐项校验、唔合格留旧、删走返内置、seq 防回滚、reset 清走。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugResetVogueslyAppConfig();
  });

  group('逐项校验', () {
    test('客服入口:只收 https + 现役付费根域 + 路径 /cs.html', () {
      expect(
        sanitizeCsHosts([
          'https://cs.ylink.live/cs.html',
          'https://CS.YILIAN.LIVE/cs.html',
          'https://cs.ylink.live/cs.html',
          'http://cs.ylink.live/cs.html',
          'https://cs.ylink.live/other.html',
          'https://cs.ylink.live/cs.html?x=1',
          'https://cs.ylink.live:8443/cs.html',
          'https://evil.example/cs.html',
          'https://cs.samseah.qzz.io/cs.html', // 免费域
          42,
        ]),
        ['https://cs.ylink.live/cs.html', 'https://cs.yilian.live/cs.html'],
      );
    });
    test('TG 链接只收 t.me', () {
      expect(sanitizeTelegramUrl('https://t.me/easysvpn'), 'https://t.me/easysvpn');
      expect(sanitizeTelegramUrl('https://t.me.evil.example/x'), isNull);
      expect(sanitizeTelegramUrl('tg://resolve?domain=x'), isNull);
    });
    test('文案:白名单 key、五种语言、冇占位符、≤300 字', () {
      final t = sanitizeTexts({
        'zh_CN': {'vgTrialSpecs': ' 试用 1 天 ', 'vgNotAllowed': 'x', 'vgBuyStarterPack': '含 {n} 占位'},
        'zh_Hant': {'vgTrialSpecs': '試用 1 天'},
        'fr': {'vgTrialSpecs': 'essai'},
        'en': {'vgTrialSpecs': 'x' * 301},
      });
      expect(t, {
        'zh_CN': {'vgTrialSpecs': '试用 1 天'},
        'zh_Hant': {'vgTrialSpecs': '試用 1 天'},
      });
    });
    test('横幅:id 格式、文字长度、action 枚举、until 类型', () {
      expect(VogueslyBanner.parse({'id': 'a1', 'text': 'hi', 'action': 'rm -rf'})?.action, 'none');
      expect(VogueslyBanner.parse({'id': 'a1', 'text': 'hi', 'level': 'warn'})?.level, 'warn');
      expect(VogueslyBanner.parse({'id': 'bad id', 'text': 'hi'}), isNull);
      expect(VogueslyBanner.parse({'id': 'a1', 'text': 'x' * 201}), isNull);
      expect(VogueslyBanner.parse({'id': 'a1', 'text': 'hi', 'until': '123'}), isNull);
    });
  });

  group('merge', () {
    test('唔合格留旧、冇呢项返内置', () {
      final a = mergeVogueslyAppConfig(VogueslyAppConfig.empty, {
        'seq': 1,
        'hosts': {'cs': ['https://cs.ylink.live/cs.html'], 'download_page': 'https://dl.yilian.live/'},
        'links': {'telegram': 'https://t.me/easysvpn'},
      })!;
      expect(a.csHosts, ['https://cs.ylink.live/cs.html']);
      expect(a.downloadPage, 'https://dl.yilian.live/');
      final b = mergeVogueslyAppConfig(a, {
        'seq': 2,
        'hosts': {'cs': ['https://evil.example/cs.html']}, // 唔合格 ⇒ 留旧
        'links': {'telegram': 'https://t.me/easysvpn'},
      })!;
      expect(b.csHosts, ['https://cs.ylink.live/cs.html']);
      expect(b.downloadPage, isNull); // 删走 ⇒ 返内置
    });
    test('seq 倒退成份唔要;reset 清走', () {
      final a = mergeVogueslyAppConfig(VogueslyAppConfig.empty, {'seq': 5, 'links': {'telegram': 'https://t.me/easysvpn'}})!;
      expect(mergeVogueslyAppConfig(a, {'seq': 4}), isNull);
      expect(mergeVogueslyAppConfig(a, {'seq': 'x'}), isNull);
      expect(mergeVogueslyAppConfig(a, {'reset': true})!.seq, 0);
    });
  });

  group('运行时', () {
    test('apply 之后各入口用远端值,邀请基址跟住变;reset 返内置', () async {
      await applyVogueslyAppConfig({
        'seq': 1,
        'hosts': {'cs': ['https://cs.yilian.live/cs.html'], 'invite_base': 'https://join2.hazu.world/'},
        'links': {'official_site': 'https://www.ylink.uk/'},
        'texts': {'zh_CN': {'vgTrialSpecs': '远端试用文案'}},
        'banner': {'id': 'switch-0927', 'level': 'warn', 'text': '请更新订阅', 'action': 'update_sub'},
      });
      expect(vogueslyCsHosts(['https://cs.ylink.im/cs.html']),
          ['https://cs.yilian.live/cs.html', 'https://cs.ylink.im/cs.html']);
      expect(constant.vogueslyInviteBase, 'https://join2.hazu.world/');
      expect(vogueslyOfficialSiteUrl('https://ylink.live'), 'https://www.ylink.uk/');
      expect(vogueslyTelegramUrl('https://t.me/easysvpn'), 'https://t.me/easysvpn');
      expect(vogueslyActiveBanner()?.id, 'switch-0927');
      expect(vogueslyText('vgTrialSpecs', '内置', locale: 'zh_CN'), '远端试用文案');
      await applyVogueslyAppConfig({'reset': true});
      expect(vogueslyCsHosts(['https://cs.ylink.im/cs.html']), ['https://cs.ylink.im/cs.html']);
      expect(vogueslyActiveBanner(), isNull);
    });
    test('存低之后冷启动读得返', () async {
      await applyVogueslyAppConfig({'seq': 3, 'links': {'telegram': 'https://t.me/easysvpn_new'}});
      debugResetVogueslyAppConfig();
      expect(vogueslyTelegramUrl('https://t.me/easysvpn'), 'https://t.me/easysvpn');
      await loadVogueslyAppConfig();
      expect(vogueslyTelegramUrl('https://t.me/easysvpn'), 'https://t.me/easysvpn_new');
    });
    test('过期横幅唔显示', () async {
      await applyVogueslyAppConfig({
        'seq': 1,
        'banner': {'id': 'old', 'text': 'x', 'until': 1000},
      });
      expect(vogueslyActiveBanner(), isNull);
    });
  });

  group('文案语言', () {
    test('简繁唔会互相借用,其他语言按语种', () {
      expect(vogueslyTextLocale('zh_CN'), 'zh_CN');
      expect(vogueslyTextLocale('zh'), 'zh_CN');
      expect(vogueslyTextLocale('zh_Hant'), 'zh_Hant');
      expect(vogueslyTextLocale('zh_Hant_HK'), 'zh_Hant');
      expect(vogueslyTextLocale('zh_TW'), 'zh_Hant');
      expect(vogueslyTextLocale('en_US'), 'en');
    });
    test('繁体用户冇繁体文案 ⇒ 用内置,唔会见到简体', () async {
      await applyVogueslyAppConfig({'seq': 1, 'texts': {'zh_CN': {'vgTrialSpecs': '简体'}}});
      expect(vogueslyText('vgTrialSpecs', '內置繁體', locale: 'zh_Hant'), '內置繁體');
    });
  });
}
