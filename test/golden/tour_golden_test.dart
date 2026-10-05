import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/voguesly/voguesly_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_env.dart';

Widget _mockPhone() => Builder(builder: (context) {
      Widget nav(IconData i, String t, PageLabel? l) => Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              KeyedSubtree(key: l == null ? null : vogueslyTourMobileNavKeys[l], child: Icon(i)),
              const SizedBox(height: 4),
              Text(t, style: const TextStyle(fontSize: 12)),
            ]),
          );
      return SizedBox(
        width: 390,
        height: 800,
        child: Column(children: [
          const SizedBox(height: 60),
          Container(height: 150, margin: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(16))),
          SizedBox(
            key: vogueslyTourConnectKey,
            width: 200,
            height: 188,
            child: Center(
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF7C5CF6), width: 3)),
                child: const Center(child: Text('开启易联')),
              ),
            ),
          ),
          const Spacer(),
          Container(
            color: Colors.white10,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              nav(Icons.home_rounded, '首页', null),
              nav(Icons.workspace_premium_rounded, '套餐', null),
              nav(Icons.radar_rounded, '检测', PageLabel.detection),
              nav(Icons.alt_route_rounded, '线路', PageLabel.proxies),
              nav(Icons.support_agent_rounded, '客服', PageLabel.support),
              nav(Icons.manage_accounts_rounded, '我的', PageLabel.tools),
            ]),
          ),
        ]),
      );
    });

void main() {
  setUpAll(() async {
    if (goldenEnabled) await loadGoldenFonts();
  });
  testWidgets('tour steps', (t) async {
    t.view.physicalSize = const Size(390, 800) * 2;
    t.view.devicePixelRatio = 2;
    await t.pumpWidget(goldenApp(_mockPhone(), size: const Size(390, 800)));
    await t.pumpAndSettle();
    startVogueslyTour(t.element(find.byType(Scaffold)));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/tour_step1.png'));
    await t.tap(find.text('下一步'));
    await t.pumpAndSettle();
    await t.tap(find.text('下一步'));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/tour_step3.png'));
    await t.tap(find.text('下一步'));
    await t.pumpAndSettle();
    await t.tap(find.text('下一步'));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/tour_step5.png'));
    await t.tap(find.text('开始使用'));
    await t.pumpAndSettle();
    expect(find.text('开始使用'), findsNothing);
  }, skip: !goldenEnabled);
}
