import 'package:fl_clash/common/system.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-09-29:客户关咗 Clash Verge 窗口,verge-mihomo.exe 仲喺后台 ⇒ 要认得出;易联自己嘅进程唔可以误报。
void main() {
  test('Windows:认出 verge-mihomo / v2rayN,唔误报易联自己', () {
    const out = '"System Idle Process","0","Services","0","8 K"\r\n'
        '"verge-mihomo.exe","4120","Services","0","42,000 K"\r\n'
        '"Voguesly.exe","5000","Console","1","120,000 K"\r\n'
        '"FlClashCore.exe","5001","Console","1","60,000 K"\r\n'
        '"VogueslyHelperService.exe","900","Services","0","9,000 K"\r\n'
        '"v2rayN.exe","7000","Console","1","50,000 K"\r\n';
    final hits = matchOtherProxyProcesses(out, windows: true);
    expect(hits, containsAll(['Clash Verge', 'v2rayN']));
    expect(hits.length, 2);
  });

  test('macOS:认出 ClashX Meta / Shadowrocket,唔误报 FlClashCore', () {
    const out = '/Applications/ClashX Meta.app/Contents/MacOS/ClashX Meta\n'
        '/Applications/Shadowrocket.app/Contents/MacOS/Shadowrocket\n'
        '/Users/x/Library/Application Support/com.voguesly.app/FlClashCore\n'
        '/Applications/Voguesly.app/Contents/MacOS/Voguesly\n';
    final hits = matchOtherProxyProcesses(out, windows: false);
    expect(hits, containsAll(['ClashX Meta', 'Shadowrocket']));
    expect(hits.length, 2);
  });

  test('macOS:Verge 已退出、只剩常驻 clash-verge-service ⇒ 唔报 Clash Verge(09-30 Air 实测)', () {
    const out = '/Library/PrivilegedHelperTools/io.github.clash-verge-rev.clash-verge-rev.service.bundle/Contents/MacOS/clash-verge-service\n'
        'Contents/MacOS/com.follow.clash.tunhelper\n'
        '/Applications/Shadowrocket.app/Contents/MacOS/Shadowrocket\n';
    expect(matchOtherProxyProcesses(out, windows: false), ['Shadowrocket']);
    const running = '$out/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo\n';
    expect(matchOtherProxyProcesses(running, windows: false), containsAll(['Clash Verge', 'Shadowrocket']));
  });

  test('冇其他代理 ⇒ 空', () {
    expect(matchOtherProxyProcesses('"explorer.exe","1","Console","1","1 K"', windows: true), isEmpty);
  });
}
