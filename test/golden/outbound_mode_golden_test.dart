import 'package:fl_clash/views/dashboard/widgets/outbound_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_env.dart';

void main() {
  setUpAll(() async {
    if (goldenEnabled) await loadGoldenFonts();
  });
  for (final w in [160.0, 260.0]) {
    testWidgets('outbound mode $w', (t) async {
      await pumpGolden(t, SizedBox(width: w, child: const OutboundMode()), surface: Size(w + 40, 240));
      await expectLater(find.byType(OutboundMode), matchesGoldenFile('goldens/outbound_mode_${w.toInt()}.png'));
    }, skip: !goldenEnabled);
  }
}
