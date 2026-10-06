import 'package:shared_preferences/shared_preferences.dart';

/// [0.9.98] 连接方式两个开关(增强模式 / 系统代理)嘅共用判据同「用户亲手开咗系统代理」记录。
///
/// 点解要另外记:每次连接 TUN 确认接管后会自动关一次系统代理(0.9.97 定案,收走旧版遗留 / 兜底开嘅)。
/// 但 0.9.98 起系统代理係一个正式开关,可以同增强模式同时开 —— 用户自己开咗,下次连接就唔可以再被关
/// (工单 #29「打开了也是自动关」)。`networkProps.systemProxy` 分唔出「用户开」定「旧版 / 兜底开」,
/// 所以另外记一个。
const kVgUserSystemProxyKey = 'vg_user_system_proxy_on';

bool? _userSystemProxyCache;

Future<void> vogueslyRememberUserSystemProxy(bool on) async {
  _userSystemProxyCache = on;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kVgUserSystemProxyKey, on);
  } catch (_) {}
}

Future<bool> vogueslyUserWantsSystemProxy() async {
  final cached = _userSystemProxyCache;
  if (cached != null) return cached;
  var v = false;
  try {
    final p = await SharedPreferences.getInstance();
    v = p.getBool(kVgUserSystemProxyKey) ?? false;
  } catch (_) {}
  _userSystemProxyCache = v;
  return v;
}

/// 改完之后仲有冇至少一条通路。`enhanced` 要传**实际**状态:已连接时 TUN 失败退咗系统代理,
/// 设定值仍然係 true 但其实冇接管 —— 用设定值判就会放行「两个都关」,用户即刻断网。
bool vogueslyHasTransport({required bool enhanced, required bool systemProxy}) =>
    enhanced || systemProxy;

/// TUN 确认接管后要唔要自动关系统代理。
/// - 兜底开嘅(TUN 失败时程序自己开)⇒ TUN 好返就收返。
/// - 用户亲手开 ⇒ 尊重,唔关。
/// - 其余(旧版遗留 / 未表态)⇒ 每次连接关一次(0.9.97 行为)。
bool vogueslyShouldAutoOffSystemProxy({
  required bool autoOffDone,
  required bool enabledByFallback,
  required bool userWants,
}) {
  if (enabledByFallback) return true;
  if (userWants) return false;
  return !autoOffDone;
}
