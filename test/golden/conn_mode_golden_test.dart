import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/voguesly/voguesly_quick_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_env.dart';

// [0.9.98] 快捷设置「连接方式」两个开关:默认 / 两个都开 / TUN 失败退咗系统代理。
void main() {
  setUpAll(() async {
    if (goldenEnabled) await loadGoldenFonts();
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });
  final cases = {
    'default': (tun: true, sp: false, start: false, real: false),
    'both': (tun: true, sp: true, start: true, real: true),
    'fellback': (tun: true, sp: true, start: true, real: false),
  };
  cases.forEach((name, c) {
    testWidgets('conn mode $name', (t) async {
      await pumpGolden(
        t,
        RepaintBoundary(key: const ValueKey('picker'), child: vogueslyConnModePickerPreview()),
        surface: const Size(420, 300),
        overrides: [
          patchClashConfigProvider.overrideWithBuild((_, _) => defaultClashConfig.copyWith.tun(enable: c.tun)),
          networkSettingProvider.overrideWithBuild((_, _) => NetworkProps(systemProxy: c.sp)),
          isStartProvider.overrideWithValue(c.start),
          realTunEnableProvider.overrideWithBuild((_, _) => c.real),
        ],
      );
      await expectLater(find.byKey(const ValueKey('picker')), matchesGoldenFile('goldens/conn_mode_$name.png'));
    }, skip: !goldenEnabled);
  });
}
