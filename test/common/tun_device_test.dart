import 'package:fl_clash/common/task.dart';
import 'package:test/test.dart';

// [0.9.86] Linux TUN 设备名(B-P1-LINUXTUN-0923):
// 默认名「易联 voguesly」带空格 ⇒ 内核 dev_valid_name() 的 isspace() 一票否决
// (Fedora 44 / Debian 12 都实测过:`ip tuntap add dev "易联 voguesly"` → not a valid ifname,exit=255;
//  同一条命令去掉空格 → exit=0)⇒ 核心报 configure tun interface: invalid argument,TUN 永远起不来。
// macOS(utun*)/ Windows(Wintun 适配器名)用原名正常,平台判断在 tunDeviceNameFor 里。

void main() {
  group('isValidLinuxIfname(照内核 dev_valid_name)', () {
    test('带空格 / 带冒号 / 带斜杠 一律唔收', () {
      expect(isValidLinuxIfname('易联 voguesly'), isFalse);
      expect(isValidLinuxIfname('vg tun'), isFalse);
      expect(isValidLinuxIfname('vg:tun'), isFalse);
      expect(isValidLinuxIfname('vg/tun'), isFalse);
      expect(isValidLinuxIfname('vg\ttun'), isFalse);
    });
    test('空 / 太长 / . / .. 唔收', () {
      expect(isValidLinuxIfname(''), isFalse);
      expect(isValidLinuxIfname('a' * 16), isFalse);
      expect(isValidLinuxIfname('.'), isFalse);
      expect(isValidLinuxIfname('..'), isFalse);
    });
    test('正常名收', () {
      expect(isValidLinuxIfname('voguesly-tun'), isTrue);
      expect(isValidLinuxIfname('utun0'), isTrue);
      expect(isValidLinuxIfname('a' * 15), isTrue);
      expect(isValidLinuxIfname('易联voguesly'), isTrue); // 冇空格就算带中文都收(Fedora 实测)
    });
  });

  group('sanitizeLinuxTunDevice', () {
    test('默认品牌名「易联 voguesly」换成 voguesly-tun', () {
      expect(sanitizeLinuxTunDevice('易联 voguesly'), 'voguesly-tun');
      expect(kLinuxTunDevice, 'voguesly-tun');
    });
    test('用户自己改过、本身合法嘅名保持唔变', () {
      expect(sanitizeLinuxTunDevice('utun0'), 'utun0');
      expect(sanitizeLinuxTunDevice('vg_tun-0'), 'vg_tun-0');
    });
    test('空 / 超长 / 净係符号 → 兜底名', () {
      expect(sanitizeLinuxTunDevice(''), 'voguesly-tun');
      expect(sanitizeLinuxTunDevice('a' * 40), 'voguesly-tun');
      expect(sanitizeLinuxTunDevice('   '), 'voguesly-tun');
    });
    test('出嚟嘅名一定係内核收嘅', () {
      for (final input in ['易联 voguesly', '易联', 'a' * 40, 'my tun:0/1', 'utun0', '']) {
        expect(isValidLinuxIfname(sanitizeLinuxTunDevice(input)), isTrue,
            reason: 'input=$input');
      }
    });
  });
}
