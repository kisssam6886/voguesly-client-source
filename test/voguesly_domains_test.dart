// [0.9.88] 防「加新入口域名漏同步」:0.9.87 把 cp.yli.world 加入 kVogueslyHosts,
// 但 isVogueslyProfile / 后台更新判断冇认佢 ⇒ 订阅切去 cp.yli.world 后客户端唔认得自己嘅订阅。
// [0.9.92] 四张表合一(voguesly_device_id.dart 唯一根域表),呢度逐个入口核对仲认唔认得。
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/voguesly/voguesly_api.dart';
import 'package:fl_clash/voguesly/voguesly_device_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('每个内置入口(面板 / 版本检查 / 邀请)都係现役根域', () {
    final urls = [...kVogueslyHosts, ...kVogueslyVersionCheckUrls, kVogueslyInviteBase];
    for (final u in urls) {
      expect(isVogueslyCurrentProfileUrl(u), isTrue, reason: '$u 唔喺 kVogueslyCurrentRootDomains');
      expect(isVogueslyProfileUrl('$u/api/v1/client/subscribe?token=x'), isTrue, reason: u);
    }
  });

  test('服务端而家下发嘅订阅域都认得(现役)', () {
    for (final h in ['n5.nira.ink', 'n6.hazu.world', 'n7.kiwa.lol', 'cp.ylink.uk', 'cp.yli.world', 'cp.yilian.live']) {
      expect(isVogueslyCurrentProfileUrl('https://$h/api/v1/client/subscribe?token=x'), isTrue, reason: h);
    }
  });

  test('旧域订阅:认得(登出清理防串号)但唔算现役(订阅闸要重导)', () {
    for (final h in ['cp.voguesly.com', 'n1.samzi.ccwu.cc', 'n3.samgezi.ccwu.cc', 'x.samseah.cc.cd']) {
      final u = 'https://$h/api/v1/client/subscribe?token=x';
      expect(isVogueslyProfileUrl(u), isTrue, reason: h);
      expect(isVogueslyCurrentProfileUrl(u), isFalse, reason: h);
    }
  });

  test('第三方订阅唔会被当成易联(按 host 后缀,唔按子串)', () {
    for (final u in [
      'https://sub.example.com/ylink/samseah?x=qzz.io',
      'https://other.qzz.io/sub', // 免费域:只认自家二级
      'https://other.ccwu.cc/sub',
      'https://ylink.uk.evil.example/sub',
      'https://notylink.uk/sub',
    ]) {
      expect(isVogueslyProfileUrl(u), isFalse, reason: u);
      expect(isVogueslyOwnSubscriptionUrl(u), isFalse, reason: u);
    }
  });

  test('远端下发只信现役付费根域(免费域 / 旧域都唔信)', () {
    expect(isVogueslyTrustedRemoteHost('cp.ylink.uk'), isTrue);
    expect(isVogueslyTrustedRemoteHost('go.mola.lol'), isTrue); // 预埋根域
    expect(isVogueslyTrustedRemoteHost('cp.samseah.qzz.io'), isFalse);
    expect(isVogueslyTrustedRemoteHost('cp.voguesly.com'), isFalse);
    expect(isVogueslyTrustedRemoteHost('n1.samzi.ccwu.cc'), isFalse);
  });
}
