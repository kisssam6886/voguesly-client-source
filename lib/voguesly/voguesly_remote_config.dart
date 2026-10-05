import 'dart:convert';

import 'package:fl_clash/common/constant.dart' as constant;
import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:intl/intl.dart' show Intl;
import 'package:shared_preferences/shared_preferences.dart';

import 'voguesly_update_download.dart' show kVogueslyDownloadPageUrl;
import 'voguesly_api.dart'
    show applyVogueslyRemotePanelHosts, isVogueslyTrustedRemoteHost, sanitizeRemoteBaseUrl;

/// [0.9.92] 服务端下发配置(version.json 嘅 `app_config`)—— 「少发版」框架。
///
/// Sam 09-26:「客户端嘅设置能挂上服务端嘅尽量挂上去,改少少嘢唔使发版。」审计(0.9.70 起 19 个版本):
/// 12 个版本改过自家域名字面量;客服入口 / 下载镜像 / 邀请基址 / 文案 / 横幅全部写死。
///
/// 规则(同 0.9.91 panel_hosts 一脉相承):
/// - **逐项校验**:某项唔合格 ⇒ 用上次合格嘅值(唔会因为一项错而成份作废);服务端删走某项 ⇒ 返内置值。
/// - 地址类只收 https + 自家**现役付费**根域(`isVogueslyTrustedRemoteHost`,排除免费域);冇 port / userinfo。
/// - 文案只收白名单 key、纯文本、唔可以有 `{}` 占位符、≤300 字;横幅 ≤200 字、action 只可以係固定几种。
/// - `seq` 只准加大(防旧镜像回滚);`{"reset": true}` = 清走远端配置返内置。成份 JSON ≤64KB。
/// - 冷启动(main)先读上次存低嘅;checkForUpdate 攞到 version.json 后更新。
/// - **安装包来源唔下发**:一键更新只认内置 `kVogueslyDownloadMirrorHosts`(荷兰下载站)。远端可以加镜像 = HK 被入侵
///   就可以喺自家根域开个子域推安装包(sha256 都係同一份 version.json 畀,挡唔住)⇒ 同签名公钥一样留喺 App。
///   下载**页**(浏览器打开、用户自己揀)可以下发。
/// - 未做:Ed25519 签名(0.9.92 决定唔做)。
const _kPref = 'yl_app_config_v1';
const _kMaxBytes = 64 * 1024;

/// 远端可以覆盖嘅文案 key(都係冇占位符、写死咗业务数字嘅句子)。
const kVogueslyRemoteTextKeys = {
  'vgTrialSpecs',
  'vgAlreadyClaimedBuyStarter',
  'vgBuyStarterPack',
  'vgStarterPackSpecs',
  'vgAboutTagline',
};

const kVogueslyBannerActions = {'none', 'open_cs', 'update_app', 'update_sub'};

class VogueslyBanner {
  const VogueslyBanner({
    required this.id,
    required this.level,
    required this.text,
    required this.action,
    this.until,
  });

  final String id;
  final String level; // info | warn
  final String text;
  final String action; // kVogueslyBannerActions
  final int? until; // epoch 秒;过咗就唔显示

  bool activeAt(DateTime now) => until == null || now.millisecondsSinceEpoch ~/ 1000 < until!;

  Map<String, Object?> toJson() => {'id': id, 'level': level, 'text': text, 'action': action, 'until': until};

  static VogueslyBanner? parse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], text = raw['text'];
    if (id is! String || !RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(id)) return null;
    if (text is! String || text.trim().isEmpty || text.length > 200) return null;
    final level = raw['level'] == 'warn' ? 'warn' : 'info';
    final action = kVogueslyBannerActions.contains(raw['action']) ? raw['action'] as String : 'none';
    final until = raw['until'];
    if (until != null && until is! int) return null;
    return VogueslyBanner(id: id, level: level, text: text.trim(), action: action, until: until as int?);
  }
}

class VogueslyAppConfig {
  const VogueslyAppConfig({
    this.seq = 0,
    this.csHosts = const [],
    this.downloadPage,
    this.inviteBase,
    this.telegram,
    this.officialSite,
    this.texts = const {},
    this.banner,
  });

  final int seq;
  final List<String> csHosts; // 完整 https://host/cs.html
  final String? downloadPage;
  final String? inviteBase;
  final String? telegram;
  final String? officialSite;
  final Map<String, Map<String, String>> texts; // locale → key → 文本
  final VogueslyBanner? banner;

  static const empty = VogueslyAppConfig();

  Map<String, Object?> toJson() => {
        'seq': seq,
        'hosts': {
          'cs': csHosts,
          'download_page': downloadPage,
          'invite_base': inviteBase,
        },
        'links': {'telegram': telegram, 'official_site': officialSite},
        'texts': texts,
        'banner': banner?.toJson(),
      };
}

// ---------- 逐项校验 ----------

List<String> sanitizeCsHosts(Object? raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final item in raw) {
    if (item is! String) continue;
    final u = Uri.tryParse(item.trim());
    if (u == null || u.scheme != 'https' || u.host.isEmpty) continue;
    if (u.hasPort || u.userInfo.isNotEmpty || u.hasQuery || u.hasFragment) continue;
    if (u.path != '/cs.html' || !isVogueslyTrustedRemoteHost(u.host)) continue;
    final v = 'https://${u.host.toLowerCase()}/cs.html';
    if (!out.contains(v)) out.add(v);
    if (out.length >= 5) break;
  }
  return out;
}

String? sanitizeTelegramUrl(Object? raw) {
  if (raw is! String) return null;
  final v = raw.trim();
  return RegExp(r'^https://t\.me/[A-Za-z0-9_]{5,32}/?$').hasMatch(v) ? v : null;
}

Map<String, Map<String, String>> sanitizeTexts(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, Map<String, String>>{};
  raw.forEach((loc, m) {
    if (loc is! String || !const {'zh_CN', 'zh_Hant', 'en', 'ja', 'ru'}.contains(loc) || m is! Map) return;
    final inner = <String, String>{};
    m.forEach((k, v) {
      if (k is! String || !kVogueslyRemoteTextKeys.contains(k) || v is! String) return;
      final t = v.trim();
      if (t.isEmpty || t.length > 300 || t.contains('{') || t.contains('}')) return;
      inner[k] = t;
    });
    if (inner.isNotEmpty) out[loc] = inner;
  });
  return out;
}

Map? _sub(Map raw, String k) => raw[k] is Map ? raw[k] as Map : null;
bool _has(Map? m, String k) => m != null && m.containsKey(k);

/// 用新下发嘅 [raw] 更新 [prev]:逐项「合格用新、唔合格留旧、冇呢项返内置」。
/// seq 细过 [prev.seq] ⇒ 成份唔要(返 null);`reset: true` ⇒ 返 [VogueslyAppConfig.empty]。
VogueslyAppConfig? mergeVogueslyAppConfig(VogueslyAppConfig prev, Object? raw) {
  if (raw is! Map) return null;
  if (raw['reset'] == true) return VogueslyAppConfig.empty;
  final seq = raw['seq'];
  if (seq is! int || seq < 0 || seq < prev.seq) return null;
  final hosts = _sub(raw, 'hosts'), links = _sub(raw, 'links');

  List<String> list(bool present, List<String> fresh, List<String> old) =>
      !present ? const [] : (fresh.isNotEmpty ? fresh : old);
  String? one(bool present, String? fresh, String? old) => !present ? null : (fresh ?? old);

  final texts = raw.containsKey('texts') ? sanitizeTexts(raw['texts']) : const <String, Map<String, String>>{};
  return VogueslyAppConfig(
    seq: seq,
    csHosts: list(_has(hosts, 'cs'), sanitizeCsHosts(hosts?['cs']), prev.csHosts),
    downloadPage: one(_has(hosts, 'download_page'), sanitizeRemoteBaseUrl(hosts?['download_page']), prev.downloadPage),
    inviteBase: one(_has(hosts, 'invite_base'), sanitizeRemoteBaseUrl(hosts?['invite_base']), prev.inviteBase),
    telegram: one(_has(links, 'telegram'), sanitizeTelegramUrl(links?['telegram']), prev.telegram),
    officialSite: one(_has(links, 'official_site'), sanitizeRemoteBaseUrl(links?['official_site']), prev.officialSite),
    texts: !raw.containsKey('texts') ? const {} : (texts.isNotEmpty ? texts : prev.texts),
    // 横幅冇「留旧」:下发唔合格 / 删走 = 唔显示(宁愿唔出,唔好出错嘅)。
    banner: raw.containsKey('banner') ? VogueslyBanner.parse(raw['banner']) : null,
  );
}

// ---------- 运行时状态 ----------

VogueslyAppConfig _cfg = VogueslyAppConfig.empty;

/// 配置有变就 +1:横幅等 UI 用 ValueListenableBuilder 跟住刷新。
final vogueslyAppConfigRevision = ValueNotifier<int>(0);

VogueslyAppConfig get vogueslyAppConfig => _cfg;

void _setCfg(VogueslyAppConfig c) {
  _cfg = c;
  // 只喺 app_config 有值先覆盖:冇嘅话保留 0.9.91 顶层 invite_base(checkForUpdate 已设)或者内置常量。
  if (c.inviteBase != null) constant.vogueslyInviteBase = c.inviteBase!;
  vogueslyAppConfigRevision.value++;
}

VogueslyAppConfig _fromStored(Map raw) =>
    mergeVogueslyAppConfig(VogueslyAppConfig.empty, raw) ?? VogueslyAppConfig.empty;

/// App 启动时调一次(main):读返上次存低嘅配置。读唔到 / 坏咗就用内置。
Future<void> loadVogueslyAppConfig() async {
  try {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kPref);
    if (s == null || s.isEmpty || s.length > _kMaxBytes) return;
    final raw = jsonDecode(s);
    if (raw is Map) _setCfg(_fromStored(raw));
  } catch (_) {}
}

/// checkForUpdate 攞到 version.json 后调。`hosts.panel` 交畀 0.9.91 嘅 panel_hosts 机制(同一套校验 / 存储)。
Future<void> applyVogueslyAppConfig(Object? raw) async {
  if (raw is! Map) return;
  try {
    if (utf8.encode(jsonEncode(raw)).length > _kMaxBytes) return;
  } catch (_) {
    return;
  }
  final hosts = _sub(raw, 'hosts');
  if (hosts != null && hosts.containsKey('panel')) {
    await applyVogueslyRemotePanelHosts(hosts['panel']);
  }
  final next = mergeVogueslyAppConfig(_cfg, raw);
  if (next == null) return;
  final encoded = jsonEncode(next.toJson());
  if (encoded == jsonEncode(_cfg.toJson())) return;
  _setCfg(next);
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPref, encoded);
  } catch (_) {}
}

@visibleForTesting
void debugResetVogueslyAppConfig() {
  _setCfg(VogueslyAppConfig.empty);
  constant.vogueslyInviteBase = constant.kVogueslyInviteBase;
}

// ---------- 读取(全部有内置兜底)----------

List<String> _dedupe(Iterable<String> xs) {
  final seen = <String>{};
  return [for (final x in xs) if (seen.add(x)) x];
}

/// 客服入口:远端排先,再接内置。
List<String> vogueslyCsHosts(List<String> builtin) => _dedupe([..._cfg.csHosts, ...builtin]);

/// 下载页(浏览器打开):version.json app_config.hosts.download_page 优先,冇就用内置。
String vogueslyDownloadPageUrl() => _cfg.downloadPage ?? kVogueslyDownloadPageUrl;

String vogueslyTelegramUrl(String builtin) => _cfg.telegram ?? builtin;

String vogueslyOfficialSiteUrl(String builtin) => _cfg.officialSite ?? builtin;

/// App 语言 → 文案 key:同 arb 一样得五种(zh_CN / zh_Hant / en / ja / ru)。
/// 中文按字形分:繁体(Hant / TW / HK / MO)永远唔会拎到简体文案,反之亦然。
String vogueslyTextLocale(String loc) {
  final l = loc.replaceAll('-', '_');
  if (l == 'zh' || l.startsWith('zh_')) {
    return (l.contains('Hant') || RegExp(r'_(TW|HK|MO)$').hasMatch(l)) ? 'zh_Hant' : 'zh_CN';
  }
  return l.split('_').first;
}

/// 文案:远端有当前语言嘅版本就用,冇就用内置 [fallback](唔会跨语言 / 跨简繁借用)。
String vogueslyText(String key, String fallback, {String? locale}) {
  final loc = locale ?? Intl.defaultLocale ?? Intl.getCurrentLocale();
  return _cfg.texts[vogueslyTextLocale(loc)]?[key] ?? fallback;
}

/// 而家应该显示嘅紧急横幅(冇 / 过期 = null)。
VogueslyBanner? vogueslyActiveBanner([DateTime? now]) {
  final b = _cfg.banner;
  return (b != null && b.activeAt(now ?? DateTime.now())) ? b : null;
}
