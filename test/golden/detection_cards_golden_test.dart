import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/voguesly/voguesly_detection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_env.dart';

// [0.9.98] 检测页三款卡(官方图标 + 紧凑解锁卡 + B站港澳台「不适用」)出图。
void main() {
  setUpAll(() async {
    if (goldenEnabled) await loadGoldenFonts();
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });
  for (final w in [360.0, 900.0]) {
    testWidgets('detection cards $w', (t) async {
      final l = currentAppLocalizations;
      Widget build() => vogueslyDetectionCardsPreview(
            cols: w > 600 ? 3 : 2,
            unlock: [
              const UnlockResult('YouTube Premium', status: UnlockStatus.yes, region: 'US'),
              const UnlockResult('Netflix', status: UnlockStatus.yes, region: 'US'),
              const UnlockResult('Disney+', status: UnlockStatus.yes, region: 'US'),
              const UnlockResult('ChatGPT', status: UnlockStatus.yes, region: 'US'),
              const UnlockResult('Claude', status: UnlockStatus.yes, region: 'US'),
              const UnlockResult('Spotify', status: UnlockStatus.yes, region: 'US'),
              const UnlockResult('TikTok', status: UnlockStatus.no, note: '地区限制'),
              UnlockResult(l.vgBiliMainland, status: UnlockStatus.yes),
              UnlockResult(l.vgBiliHkMoTw, status: UnlockStatus.na, note: l.vgBiliHkNaNote),
            ],
            domestic: [
              LatencyResult(l.vgBaidu, 32), LatencyResult(l.vgTaobao, 41), LatencyResult(l.vgBilibili, 38),
              LatencyResult(l.vgWeChat, 29), LatencyResult(l.vgDouyin, 45),
            ],
            intl: const [
              LatencyResult('Cloudflare', 254), LatencyResult('Google', 259),
              LatencyResult('YouTube', 262), LatencyResult('jsDelivr', 270),
            ],
            split: [
              SplitRouteResult(name: l.vgSplitGeneralSites, domestic: false, countryCode: 'US', ok: true),
              const SplitRouteResult(name: 'ChatGPT', domestic: false, countryCode: 'US', ok: true),
              const SplitRouteResult(name: 'Claude', domestic: false, countryCode: 'US', ok: true),
              SplitRouteResult(name: l.vgBilibili, domestic: true, countryCode: 'CN', ok: true),
            ],
          );
      await pumpGolden(t, RepaintBoundary(key: const ValueKey('cards'), child: build()), surface: Size(w + 40, w > 600 ? 1000 : 1400));
      await expectLater(find.byKey(const ValueKey('cards')), matchesGoldenFile('goldens/detection_cards_${w.toInt()}.png'));
    }, skip: !goldenEnabled);
  }
}
