import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/common/task.dart' show kLinuxTunDevice;
import 'package:flutter_test/flutter_test.dart';

/// [0.9.96] Windows 按虚拟网卡名认「边个软件占住网络」(09-30 测试机实测名)。
void main() {
  test('易联自己张网卡同普通网卡唔算冲突', () {
    expect(foreignTunOwnerFromNames(['以太网', 'WLAN', appName]), isNull);
  });
  test('官方 FlClash 张网卡叫 FlClash', () {
    expect(foreignTunOwnerFromNames(['以太网', 'FlClash']), 'FlClash(官方版)');
  });
  test('Clash Verge / mihomo 张网卡叫 Meta ⇒ 通用名,由调用方按进程细分', () {
    expect(foreignTunOwnerFromNames(['以太网', 'Meta']), 'Clash 类代理软件');
    expect(foreignTunOwnerFromNames(['Mihomo']), 'Clash 类代理软件');
  });
  test('其他代理软件', () {
    expect(foreignTunOwnerFromNames(['sing-box']), 'sing-box');
    expect(foreignTunOwnerFromNames(['HiddifyTunnel']), 'Hiddify');
  });
  test('公司 VPN / WireGuard 等唔当冲突', () {
    expect(foreignTunOwnerFromNames(['公司VPN', 'WireGuard Tunnel', 'OpenVPN TAP-Windows6']), isNull);
  });
  test('唔会将 Metadata / 名入面有 meta 嘅网卡当成 mihomo', () {
    expect(foreignTunOwnerFromNames(['Metadata Adapter']), isNull);
  });
  test('Linux:易联自己张 voguesly-tun 唔算;官方 FlClash / Verge 张网卡认得出', () {
    expect(foreignTunOwnerFromNames(['lo', 'ens3', kLinuxTunDevice]), isNull);
    expect(foreignTunOwnerFromNames(['ens3', 'FlClash']), 'FlClash(官方版)');
    expect(foreignTunOwnerFromNames(['ens3', 'Mihomo']), 'Clash 类代理软件');
  });
  test('畀用户睇嘅名去走「(服务模式)」', () {
    expect(userFacingProxyName('Clash Verge(服务模式)'), 'Clash Verge');
    expect(userFacingProxyName('Clash Verge（服务模式）'), 'Clash Verge');
    expect(userFacingProxyName('FlClash(官方版)'), 'FlClash(官方版)');
  });
}
