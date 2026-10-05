import 'dart:io';
import 'dart:math';

/// 易联订阅设备标识(纯 Dart 部分:格式 / 校验 / 域名判定,唔掂 Flutter 插件,方便单独测)。
///
/// 点解要:服务端按 IP 数设备,同一局域网 3–4 部机出口 IP 一样,只算 1 部(Sam 发现)。
/// 所以拉订阅时带一个请求头,服务端(`/api/v1/client/subscribe`、`/s/<token>`)按
/// user_id + 安装ID 记一行;冇呢个头服务端就乜都唔做(旧版照常)。
///
/// 格式(服务端严格校验,唔好改):`X-YL-Device: v1;<安装ID>;<平台>;<型号>[;<版本>]`
/// - 安装ID:32 位小写 hex(随机 128 bit),首次需要时生成,永久存本机;
/// - 平台:android / ios / macos / windows / linux;
/// - 型号:最多 64 字符,只准字母、数字、空格同 `_.,()+-`(冇 `;`,唔会同分段撞);
/// - 版本(第 5 段,可选):`^[0-9][0-9.]{0,15}$`,例如 `0.9.81`。点解要:订阅请求 UA 写死咗
///   `clash-verge/2.0.0 FlClash`(面板要 clash UA 先返 YAML,唔可以改),服务端喺 UA 攞唔到版本。
///   攞唔到版本就退返 4 段,服务端两种都认。
const String kVogueslyDeviceHeader = 'X-YL-Device';

/// [0.9.92] **自家根域唯一清单**(之前四张表各自维护:设备标识白名单 / 订阅识别标记(子串匹配)/ 订阅闸 / DoH,
/// 0.9.87、0.9.88 都出过「加咗入口漏咗一张表」⇒ 登出删唔到旧订阅、换账号串号)。一律按 host 后缀匹配,唔用 contains。
/// - 现役:订阅闸认呢啲先算「已导入现役订阅」;远端下发(app_config / panel_hosts)亦只信呢啲(再排除免费域)。
///   **预埋**:mola.lol / rdp.lat / rdp.autos 已买未用 —— 将来喺佢哋下面开入口唔使发版。
/// - 旧:只用嚟认返旧安装嘅订阅(登出 / 防串号清理),唔算现役。
/// ⚠️ qzz.io / ccwu.cc / cc.cd 係公共免费子域服务,只可以认自家二级(samseah.qzz.io 等),唔可以认成个后缀。
const List<String> kVogueslyCurrentRootDomains = [
  'ylink.im', // 09-23 apex 被封,子域仍用;订阅 URL 可能仲喺度
  'ylink.uk', // 面板主入口 cp.ylink.uk、逃生口 esc.ylink.uk
  'ylink.live', // 官网 / 客服
  'yli.world', // 面板备用 cp.yli.world
  'yilian.live', // 第二根域:cp. 橙云腿 / dl. 下载镜像 / cs. 客服
  'nira.ink', // 订阅域 n5
  'hazu.world', // 订阅域 n6、邀请 join.
  'kiwa.lol', // 订阅域 n7
  'samseah.qzz.io', // 旧订阅域 n4 / 旧橙云腿(免费域:只认,远端下发唔信)
  'mola.lol', // 预埋(防失联页根域)
  'rdp.lat', // 预埋
  'rdp.autos', // 预埋
];
const List<String> kVogueslyLegacyRootDomains = [
  'voguesly.com', // 旧面板 cp.voguesly.com
  'samzi.ccwu.cc', // 旧订阅域 n1(ccwu.cc 09-25 整个后缀被封)
  'samgezi.ccwu.cc', // 旧订阅域 n3
  'samge.ccwu.cc',
  'syk.ccwu.cc',
  'samseah.cc.cd', // 09-24 整根域被封
  'corelane.xyz', // 节点入口域(旧订阅可能用过)
  'octolink.xyz',
];
const List<String> kVogueslyOwnRootDomains = [
  ...kVogueslyCurrentRootDomains,
  ...kVogueslyLegacyRootDomains,
];

/// 兼容旧名:设备标识白名单 = 全部自家根域。
const List<String> kVogueslyOwnSubscriptionDomains = kVogueslyOwnRootDomains;

bool _vgHostUnder(String host, List<String> roots) {
  final h = host.toLowerCase();
  if (h.isEmpty) return false;
  return roots.any((d) => h == d || h.endsWith('.$d'));
}

String _vgHostOf(String url) => Uri.tryParse(url.trim())?.host ?? '';

/// host 係咪自家(现役 + 旧)根域或其子域。
bool isVogueslyOwnHost(String host) => _vgHostUnder(host, kVogueslyOwnRootDomains);

/// host 係咪自家**现役**根域或其子域。
bool isVogueslyCurrentHost(String host) => _vgHostUnder(host, kVogueslyCurrentRootDomains);

/// 呢个订阅 URL 係咪易联(包括旧域名)—— 登出清理 / 防串号 / 后台更新用。
bool isVogueslyProfileUrl(String url) => isVogueslyOwnHost(_vgHostOf(url));

/// 呢个订阅 URL 係咪易联**现役**域名 —— 订阅闸用(旧域名订阅要强制重导)。
bool isVogueslyCurrentProfileUrl(String url) => isVogueslyCurrentHost(_vgHostOf(url));

final RegExp _installIdRe = RegExp(r'^[0-9a-f]{32}$');
final RegExp _modelDisallowedRe = RegExp(r'[^A-Za-z0-9 _.,()+\-]');
final RegExp _appVersionRe = RegExp(r'^[0-9][0-9.]{0,15}');

/// 型号最长字符数(服务端上限)。
const int kVogueslyDeviceModelMaxLength = 64;

/// 生成新安装ID:128 bit 安全随机数 → 32 位小写 hex(等同 uuid v4 去横线,但唔使加依赖)。
String newVogueslyInstallId([Random? random]) {
  final rng = random ?? Random.secure();
  final sb = StringBuffer();
  for (var i = 0; i < 16; i++) {
    sb.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

bool isValidVogueslyInstallId(String? s) => s != null && _installIdRe.hasMatch(s);

/// 读返已存嘅安装ID;冇 / 格式唔啱就生成新嘅再写落去。
/// [read] / [write] 由调用方注入(App 用 SharedPreferences,测试用内存)。
/// 写失败都照返新 ID(今次请求照带;下次启动可能再生成一个,可接受)。
Future<String> loadOrCreateVogueslyInstallId({
  required Future<String?> Function() read,
  required Future<void> Function(String id) write,
}) async {
  final saved = await read();
  if (isValidVogueslyInstallId(saved)) return saved!;
  final id = newVogueslyInstallId();
  try {
    await write(id);
  } catch (_) {}
  return id;
}

/// 当前平台名(服务端只认呢五个);其他平台返 null = 唔带头。
String? vogueslyPlatformName() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  return null;
}

/// 型号清洗:删走唔准嘅字符(中文 / emoji / 引号等)、合并空格、截到 64 字符。
String sanitizeVogueslyDeviceModel(String raw) {
  var s = raw
      .replaceAll(_modelDisallowedRe, '')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
  if (s.length > kVogueslyDeviceModelMaxLength) {
    s = s.substring(0, kVogueslyDeviceModelMaxLength).trim();
  }
  return s;
}

/// App 版本清洗:只留开头 `^[0-9][0-9.]{0,15}` 嗰截(去走 `+2026081301` build 号之类),
/// 顺手去走开头 `v` 同结尾多余嘅 `.`。完全唔啱(空 / 唔系数字开头)返 null = 唔带第 5 段。
String? sanitizeVogueslyAppVersion(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  final m = _appVersionRe.firstMatch(s)?.group(0);
  if (m == null) return null;
  var v = m;
  while (v.endsWith('.')) {
    v = v.substring(0, v.length - 1);
  }
  return v.isEmpty ? null : v;
}

/// 喺候选型号入面揀第一个清洗后唔系空嘅(例如 Windows 电脑名全中文 → 洗完系空 → 用下一个)。
String pickVogueslyDeviceModel(Iterable<String?> candidates) {
  for (final c in candidates) {
    if (c == null) continue;
    final s = sanitizeVogueslyDeviceModel(c);
    if (s.isNotEmpty) return s;
  }
  return '';
}

/// 砌请求头值。[model] / [appVersion] 会再清洗一次,保证一定过到服务端校验;
/// 版本清洗后系空就唔带第 5 段(旧 4 段格式,服务端照认)。
String formatVogueslyDeviceHeader({
  required String installId,
  required String platform,
  required String model,
  String? appVersion,
}) {
  final base = 'v1;$installId;$platform;${sanitizeVogueslyDeviceModel(model)}';
  final ver = sanitizeVogueslyAppVersion(appVersion);
  return ver == null ? base : '$base;$ver';
}

/// 呢个 URL 系咪易联自家订阅(https + host 系自家域名或其子域名,或者 [trustedHosts] 其中一个)。
bool isVogueslyOwnSubscriptionUrl(
  String url, {
  Iterable<String> trustedHosts = const [],
}) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return false;
  if (trustedHosts.any((h) => h.toLowerCase() == host)) return true;
  return kVogueslyOwnSubscriptionDomains
      .any((d) => host == d || host.endsWith('.$d'));
}
