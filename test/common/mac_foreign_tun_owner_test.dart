import 'package:fl_clash/common/system.dart';
import 'package:flutter_test/flutter_test.dart';

/// [0.9.96 Mac] 认「边个软件占住网络」。样本全部係 09-30 MacBook Air 实机输出。
void main() {
  const ncShadowrocketOn = '''
Available network connection services in the current set (*=enabled):
* (Connected)      DC85D24B-1BD7-4344-A42A-DAD911A91108 VPN (com.liguangming.Shadowrocket) "Shadowrocket"                   [VPN:com.liguangming.Shadowrocket]
* (Connected)      393D34C8-A653-49B7-8947-D77D17CE6981 VPN (io.tailscale.ipn.macos) "Tailscale"                      [VPN:io.tailscale.ipn.macos]
* (Disconnected)   AAAC0D09-52BC-483D-8036-D228C5E7A299 VPN (io.nekohasekai.sfavt.standalone) "SFM"                            [VPN:io.nekohasekai.sfavt.standalone]
''';
  const ncOnlyTailscale = '''
Available network connection services in the current set (*=enabled):
* (Disconnected)   DC85D24B-1BD7-4344-A42A-DAD911A91108 VPN (com.liguangming.Shadowrocket) "Shadowrocket"                   [VPN:com.liguangming.Shadowrocket]
* (Connected)      393D34C8-A653-49B7-8947-D77D17CE6981 VPN (io.tailscale.ipn.macos) "Tailscale"                      [VPN:io.tailscale.ipn.macos]
''';
  // Clash Verge 已经彻底退出,只剩常驻服务;旧 FlClash 留低嘅 tunhelper;易联自己嘅核心同 helper。
  const psIdleServices = '''
/Library/PrivilegedHelperTools/io.github.clash-verge-rev.clash-verge-rev.service.bundle/Contents/MacOS/clash-verge-service
/Applications/Shadowrocket.app/Contents/MacOS/Shadowrocket
Contents/MacOS/com.follow.clash.tunhelper
Contents/MacOS/com.voguesly.tunhelper
/Applications/Voguesly.app/Contents/MacOS/Voguesly
/Users/sam/Library/Application Support/com.voguesly.app/FlClashCore
/Applications/Tailscale.app/Contents/PlugIns/IPNExtension.appex/Contents/MacOS/IPNExtension
''';
  const psOfficialFlClash = '''
$psIdleServices
/Applications/FlClash.app/Contents/MacOS/FlClash
/Applications/FlClash.app/Contents/MacOS/FlClashCore
''';
  const psVergeRunning = '''
$psIdleServices
/Applications/Clash Verge.app/Contents/MacOS/clash-verge
/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo
''';

  group('macConnectedVpnNames', () {
    test('Shadowrocket VPN 连住 ⇒ 认得出;Tailscale 唔算', () {
      expect(macConnectedVpnNames(ncShadowrocketOn), ['Shadowrocket']);
    });
    test('淨係 Tailscale 连住 ⇒ 冇冲突', () {
      expect(macConnectedVpnNames(ncOnlyTailscale), isEmpty);
    });
  });

  group('macTunCoreOwners', () {
    test('Verge 退出后只剩常驻服务 / tunhelper / 易联自己 ⇒ 唔可以再报 Clash Verge(09-30 死循环)', () {
      expect(macTunCoreOwners(psIdleServices), isEmpty);
    });
    test('官方 FlClash 内核 ⇒ FlClash(官方版),唔会同易联自己个 FlClashCore 混淆', () {
      expect(macTunCoreOwners(psOfficialFlClash), ['FlClash(官方版)']);
    });
    test('Verge 内核喺度:虚拟网卡模式开 ⇒ 报;关 ⇒ 唔报;读唔到设置 ⇒ 报', () {
      expect(macTunCoreOwners(psVergeRunning, vergeTunOn: true), ['Clash Verge']);
      expect(macTunCoreOwners(psVergeRunning, vergeTunOn: false), isEmpty);
      expect(macTunCoreOwners(psVergeRunning), ['Clash Verge']);
    });
    test('其他内核', () {
      expect(macTunCoreOwners('/Applications/Clash Party.app/Contents/Resources/sidecar/mihomo'), ['Clash Party']);
      expect(macTunCoreOwners('/usr/local/bin/sing-box'), ['sing-box']);
      expect(macTunCoreOwners('/opt/homebrew/bin/mihomo'), ['Clash 类代理软件']);
    });
  });

  test('显示名去走 vpn: 前缀', () {
    expect(system.thirdPartyProxyDisplayName('vpn:Shadowrocket'), 'Shadowrocket');
    expect(system.thirdPartyProxyDisplayName('clash verge'), 'Clash Verge');
    expect(system.thirdPartyProxyDisplayName('FlClash(官方版)'), 'FlClash(官方版)');
  });
}
