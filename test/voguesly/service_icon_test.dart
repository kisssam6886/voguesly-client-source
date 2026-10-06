import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/voguesly/voguesly_detection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// [0.9.98] 检测页每个服务都要认得到官方图标,而且图标档真係打包咗(pubspec 有登记目录)。
void main() {
  setUpAll(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });

  test('解锁 / 延迟 / 分流用到嘅名全部有图标,档案存在', () {
    final l = currentAppLocalizations;
    final names = [
      'YouTube Premium', 'Netflix', 'Disney+', 'ChatGPT', 'Claude', 'Spotify', 'TikTok',
      l.vgBiliMainland, l.vgBiliHkMoTw, l.vgBaidu, l.vgTaobao, l.vgBilibili, l.vgWeChat, l.vgDouyin,
      'Cloudflare', 'Google', 'YouTube', 'jsDelivr',
    ];
    for (final n in names) {
      final a = vogueslyServiceIconAsset(n);
      expect(a, isNotNull, reason: n);
      expect(File(a!).existsSync(), isTrue, reason: a);
    }
  });

  test('「普通网站」用通用地球图标(返 null)', () {
    expect(vogueslyServiceIconAsset(currentAppLocalizations.vgSplitGeneralSites), isNull);
  });

  test('pubspec 有登记 services 目录', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/images/services/'));
  });
}
