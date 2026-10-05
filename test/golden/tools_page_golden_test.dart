import 'package:fl_clash/views/tools.dart';
import 'package:fl_clash/voguesly/voguesly_api.dart';
import 'package:fl_clash/voguesly/voguesly_auth.dart';
import 'package:fl_clash/voguesly/voguesly_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_env.dart';

class _FakeAuth extends VogueslyAuthNotifier {
  @override
  VogueslyAuthState build() => VogueslyAuthState(
        status: VogueslyAuthStatus.loggedIn,
        token: 't',
        user: VogueslyUser(
          upload: 0, download: 150 * 1073741824, transferEnable: 465 * 1073741824,
          expiredAt: DateTime.now().add(const Duration(days: 12)).millisecondsSinceEpoch ~/ 1000,
          planId: 11, planName: 'Pro', email: 'user@example.com', deviceLimit: 5, aliveIp: 2,
        ),
      );
}

class _FakeAvatar extends VogueslyAvatarNotifier {
  @override
  String build() => 'anime_04';
}

void main() {
  setUpAll(() async {
    if (goldenEnabled) await loadGoldenFonts();
  });
  testWidgets('tools page', (t) async {
    await pumpGolden(t, const SizedBox(height: 1500, child: ToolsView()),
        surface: const Size(420, 1540),
        overrides: [vogueslyAuthProvider.overrideWith(_FakeAuth.new), vogueslyAvatarProvider.overrideWith(_FakeAvatar.new)]);
    await expectLater(find.byType(ToolsView), matchesGoldenFile('goldens/tools_page.png'));
    await t.pumpWidget(const SizedBox()); // 拆走页面,等 provider 嘅定时器取消
    await t.pump(const Duration(minutes: 31));
  }, skip: !goldenEnabled);
}
