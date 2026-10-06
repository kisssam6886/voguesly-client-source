import 'package:fl_clash/voguesly/voguesly_conn_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// [0.9.98] 连接方式两个开关:唔准两个都关;用户亲手开嘅系统代理,TUN 接管后唔再自动关(工单 #29)。
void main() {
  group('至少一条通路', () {
    test('两个都关 ⇒ 拦', () => expect(vogueslyHasTransport(enhanced: false, systemProxy: false), isFalse));
    test('只开增强', () => expect(vogueslyHasTransport(enhanced: true, systemProxy: false), isTrue));
    test('只开系统代理', () => expect(vogueslyHasTransport(enhanced: false, systemProxy: true), isTrue));
  });

  group('TUN 接管后自动关系统代理', () {
    bool decide({bool done = false, bool fallback = false, bool user = false}) =>
        vogueslyShouldAutoOffSystemProxy(autoOffDone: done, enabledByFallback: fallback, userWants: user);

    test('旧版遗留 / 未表态:每次连接关一次', () {
      expect(decide(), isTrue);
      expect(decide(done: true), isFalse);
    });
    test('用户亲手开:唔关(新连接都唔关)', () => expect(decide(user: true), isFalse));
    test('兜底开嘅:TUN 好返就收返(就算已经关过一次)', () {
      expect(decide(fallback: true, done: true), isTrue);
    });
  });

  test('用户选择落盘 + 读返', () async {
    SharedPreferences.setMockInitialValues({});
    await vogueslyRememberUserSystemProxy(true);
    expect(await vogueslyUserWantsSystemProxy(), isTrue);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool(kVgUserSystemProxyKey), isTrue);
    await vogueslyRememberUserSystemProxy(false);
    expect(await vogueslyUserWantsSystemProxy(), isFalse);
    expect(p.getBool(kVgUserSystemProxyKey), isFalse);
  });
}
