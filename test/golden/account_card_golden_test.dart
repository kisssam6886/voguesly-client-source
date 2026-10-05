import 'package:fl_clash/views/dashboard/widgets/voguesly_account.dart';
import 'package:fl_clash/voguesly/voguesly_api.dart';
import 'package:fl_clash/voguesly/voguesly_auth.dart';
import 'package:fl_clash/voguesly/voguesly_avatar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_env.dart';

class _FakeAuth extends VogueslyAuthNotifier {
  _FakeAuth(this.s);
  final VogueslyAuthState s;
  @override
  VogueslyAuthState build() => s;
}

class _FakeAvatar extends VogueslyAvatarNotifier {
  @override
  String build() => 'anime_04';
}

VogueslyAuthState _state({int? alive = 2, int limit = 5, int usedGb = 150}) => VogueslyAuthState(
      status: VogueslyAuthStatus.loggedIn,
      token: 't',
      user: VogueslyUser(
        upload: 0,
        download: usedGb * 1073741824,
        transferEnable: 465 * 1073741824,
        expiredAt: DateTime.now().add(const Duration(days: 12)).millisecondsSinceEpoch ~/ 1000,
        planId: 11,
        planName: 'Pro',
        email: 'user@example.com',
        deviceLimit: limit,
        aliveIp: alive,
      ),
    );

void main() {
  setUpAll(() async {
    if (goldenEnabled) await loadGoldenFonts();
  });
  testWidgets('account card', (t) async {
    await pumpGolden(t, const VogueslyAccount(), overrides: [
      vogueslyAuthProvider.overrideWith(() => _FakeAuth(_state())),
      vogueslyAvatarProvider.overrideWith(_FakeAvatar.new),
    ]);
    await expectLater(find.byType(VogueslyAccount), matchesGoldenFile('goldens/account_card.png'));
  }, skip: !goldenEnabled);
  testWidgets('account card · 设备满', (t) async {
    await pumpGolden(t, const VogueslyAccount(), overrides: [
      vogueslyAuthProvider.overrideWith(() => _FakeAuth(_state(alive: 5, limit: 5, usedGb: 440))),
      vogueslyAvatarProvider.overrideWith(_FakeAvatar.new),
    ]);
    await expectLater(find.byType(VogueslyAccount), matchesGoldenFile('goldens/account_card_full.png'));
  }, skip: !goldenEnabled);
}
