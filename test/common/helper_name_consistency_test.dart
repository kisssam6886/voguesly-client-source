// [0.9.90] Windows 后台服务 exe 名一致性闸。
// 09-23(0.9.86)把服务改名 VogueslyHelperService:Dart / Rust / 安装器都改咗,
// 但打包侧(build_tool 嘅 helper_name、plugins/setup/windows/CMakeLists.txt)仲输出 FlClashHelperService.exe。
// 客户端 `sc create binPath= <安装目录>\VogueslyHelperService.exe` 指向一个唔存在嘅档 ⇒ sc start 必败 ⇒
// 0.9.86–0.9.89 Windows 增强模式全部起唔到(09-24 客户 yydsorz 日志:删了又建 20 几次)。
// 呢个测试直接读打包配置,任何一边再改名而漏咗另一边 ⇒ 即刻红。
import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('build_tool 输出嘅 helper exe 名 == 客户端注册服务用嘅名', () {
    final yaml = File('plugins/setup/buildkit/build_tool/build_config.yaml').readAsStringSync();
    final m = RegExp(r'^helper_name:\s*(\S+)', multiLine: true).firstMatch(yaml);
    expect(m, isNotNull, reason: 'build_config.yaml 冇 helper_name');
    expect(m!.group(1), appHelperService);

    final opts = File('plugins/setup/buildkit/build_tool/lib/src/options.dart').readAsStringSync();
    expect(opts, contains("helperName: '$appHelperService'"), reason: 'options.dart 默认值要一致');
  });

  test('Windows 安装包会把同名 helper exe 放入安装目录', () {
    final cmake = File('plugins/setup/windows/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('libclash/windows/$appHelperService.exe'));
    expect(cmake, isNot(contains('libclash/windows/$legacyFlClashHelperService.exe')));
  });
}
