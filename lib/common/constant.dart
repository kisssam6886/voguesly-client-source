// ignore_for_file: constant_identifier_names

import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:path/path.dart' show join;

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/material.dart';

const appName = '易联 voguesly';
/// ⚠️ [2026-09-23] 唔好改返 `FlClashHelperService` —— 嗰个係官方 FlClash 嘅
/// Windows 服务名,撞咗等於两个 App 抢同一个 **root 权限**服务。
/// 改呢度就要同步改 `services/helper/src/service/windows.rs` 嘅 `SERVICE_NAME`,
/// 两边唔一致会令 helper 完全揾唔到。
const appHelperService = 'VogueslyHelperService';

/// 官方 FlClash 嘅旧服务名。**只用嚟喺升级时卸载残留**,唔好攞嚟注册。
const legacyFlClashHelperService = 'FlClashHelperService';
const coreName = 'clash.meta';
const browserUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const packageName = 'com.follow.clash';
/// [2026-09-23 Sam 要求审计]「**用户如果都下载咗官方 FlClash 嘅客户端,会唔会同我哋撞?**」
///
/// 会。原本以下全部係**官方原名 / 原值**:
///   · socket `/tmp/FlClashSocket_<0-9999>.sock` —— 同名格式 + `/tmp` **全局可写**
///     + 随机空间得 10000 ⇒ ① 撞名 ② 本地任何用户可以**抢先占位**
///   · Windows pipe `\\.\pipe\FlClashCore_<0-9999>` —— 同上
///   · helperPort `47890` —— 同官方一样,而 helper 係 **root 权限**;两个 App
///     同时跑,谁先绑谁赢,另一个嘅提权请求会打落对方个进程度。
///
/// 现全部搬入 voguesly 命名空间:
///   · 目录优先用**用户私有**嘅(Linux `XDG_RUNTIME_DIR` / macOS `Directory.systemTemp`
///     = `/var/folders/<user>/T/`),唔再用人人写得嘅 `/tmp`
///   · 随机位数加大,撞名机率由 1/10⁴ 降到 ~1/10⁹
///
/// ⚠️ unix socket 路径有长度上限(macOS 104 / Linux 108 bytes),所以只落短前缀。
String _runtimeDirPath() {
  final xdg = Platform.environment['XDG_RUNTIME_DIR'];
  if (xdg != null && xdg.isNotEmpty && Directory(xdg).existsSync()) {
    return xdg;
  }
  return Directory.systemTemp.path;
}

final _ipcNonce = Random.secure().nextInt(1 << 30).toRadixString(36);
final unixSocketPath = join(_runtimeDirPath(), 'vgly-core-$_ipcNonce.sock');
final windowsPipeName = '\\\\.\\pipe\\VogueslyCore_$_ipcNonce';

/// ⚠️ 唔好改返 47890(官方值)。改呢度就要同步改
/// `services/helper/src/service/hub.rs` 嘅 `LISTEN_PORT`,两边唔一致 helper 就废。
const helperPort = 47893;
const maxTextScale = 1.4;
const minTextScale = 0.8;
final baseInfoEdgeInsets = EdgeInsets.symmetric(
  vertical: 16.mAp,
  horizontal: 16.mAp,
);
final listHeaderPadding = EdgeInsets.only(
  left: 16.mAp,
  right: 8.mAp,
  top: 24.mAp,
  bottom: 8.mAp,
);
const sheetAppBarHeight = 68.0;

const watchExecution = false;

final defaultTextScaleFactor =
    WidgetsBinding.instance.platformDispatcher.textScaleFactor;
/// 延迟测试畀 Core 嘅上限。
///
/// 5000 → 8000(2026-09-10)。点解:呢个常数就係 Sam 截图见到嗰个「5001ms」本身
/// (5000 + 1)。欧洲/香港线路由大陆过去 RTT 300-850ms,一次 HTTPS 探测要
/// TCP 1 + TLS 2 + HTTP 1 ≈ 4 个来回;850ms × 4 = 3.4s,再撞埋并发争用就爆 5 秒,
/// 于是「英国住宅 / 荷兰 / 德国 / 香港 CMI」几乎必然报超时,而美国/日本(60-180ms)冇事
/// —— 睇落就係「总係呢几个坏」。
///
/// ⚠️ 改呢个一定要一齐改 interface.dart 嗰个 RPC wrapper timeout,
///    wrapper 必须**大过**呢个值,否则 wrapper 先放弃 = 一样报假死。
const httpTimeoutDuration = Duration(milliseconds: 8000);
const moreDuration = Duration(milliseconds: 100);
const animateDuration = Duration(milliseconds: 100);
const midDuration = Duration(milliseconds: 200);
const commonDuration = Duration(milliseconds: 300);
const defaultUpdateDuration = Duration(days: 1);
const MMDB = 'GEOIP.metadb';
const ASN = 'ASN.mmdb';
const GEOIP = 'GEOIP.dat';
const GEOSITE = 'GEOSITE.dat';
final double kHeaderHeight = system.isDesktop
    ? !system.isMacOS
          ? 40
          : 28
    : 0;
const profilesDirectoryName = 'profiles';
const localhost = '127.0.0.1';
const clashConfigKey = 'clash_config';
const configKey = 'config';
const double dialogCommonWidth = 300;
// ⚠️ 呢个 fork 已经唔再检查上游 chen08209/FlClash 嘅 release(旧代码打
// api.github.com/repos/chen08209/FlClash/releases/latest,会引导用户去装返
// 原版 FlClash——完全错嘅方向,而且 api.github.com 喺国内冇 VPN 好大机会连唔到)。
// 改用自己域名(cp 面板同 host,登录/订阅都靠佢,已确认国内可达)。
// [0.9.92] 旧常量 vogueslyVersionCheckUrl 已删(冇人用,但 0.9.91 仲跟住改咗两次);地址见下面 kVogueslyVersionCheckUrls。

/// [0.9.91] 版本检查按次序逐个试,第一个 200 就用。
/// 点解:0.9.90 之前只打 cp.samseah.qzz.io 一个 —— qzz.io 係免费域名服务,2026-09-25 同类嘅 ccwu.cc
///   整个后缀被 SNI 封(09-24 cc.cd 都係)。佢一封,全部用户收唔到新版推送 = 连用发新版嚟救都救唔到。
///   四个 host 返同一份 version.json(HK /var/www/cp-downloads,md5 一致,09-25 实测)。
const List<String> kVogueslyVersionCheckUrls = [
  'https://cp.ylink.uk/downloads/version.json',   // 2026-09-26 起首位(cp.ylink.im 09-25 已封)
  'https://cp.yli.world/downloads/version.json',
  'https://cp.yilian.live/downloads/version.json', // [0.9.91] CF 橙云(唔同 IP 路径);取代免费域 cp.samseah.qzz.io(可能被收回 / 抢注)
  'https://cp.ylink.im/downloads/version.json',   // 09-25 大陆已封,只有开住代理时先通
];

/// [0.9.87] 邀请链接基址(客户端喺后面加 `?code=xxx`)。
/// 邀请链接係全站传播最广嘅 URL(用户为佣金到处发),所以用**专门、可弃**嘅域名,
/// 唔放喺 ylink.im / ylink.uk / ylink.live 之下(ylink.im 主域就係死喺「畀人当入口公开传播」)。
/// 服务端 join.hazu.world 橙云,`/` 同 `/go/register` 都 302 去面板注册页并带码。
const kVogueslyInviteBase = 'https://join.hazu.world/';

/// [0.9.92] 订阅识别改用 voguesly_device_id.dart 嘅 isVogueslyProfileUrl(唯一根域表,按 host 后缀匹配)。

/// 实际用嘅邀请基址:version.json 有合法 `invite_base` 就用佢(换域唔使发版),冇就用上面常量。
String vogueslyInviteBase = kVogueslyInviteBase;
// ⚠️ 保持 9090 唔改:呢个係「外部控制器」开关(ExternalControllerStatus 默认
// close,要用户主动开先监听),撞端口嘅机会远低过 mixed-port;而佢嘅
// @JsonValue 就係 '127.0.0.1:9090',改咗会令旧配置反序列化唔返 —— 风险大过收益。
const defaultExternalController = '127.0.0.1:9090';
const maxMobileWidth = 600;
const maxLaptopWidth = 840;
/// 节点延迟测速 / DIRECT 延迟嘅默认目标。
///
/// ⚠️ **唔好换返 gstatic**(2026-08-10 三点实测,数据见下),旧值 `https://www.gstatic.com/generate_204`
/// 同时坏咗两件事:
///  ① **国内直连唔通** → 测 DIRECT 必然 timeout,界面上「直连」永远显示红,用户以为直连坏咗。
///     实测(Sam 家网,去代理真直连):gstatic 6s 超时;google/generate_204 一样超时。
///  ② **单个 IP,遇到烂路由就虚高** → 界面上节点延迟数字唔可信。实测同一个 gstatic:
///     HK 出口 **627ms**、SG 出口 49ms(相差 12 倍),而 cp.cloudflare 喺两边都係 6-10ms。
///     `voguesly_detection.dart` 早就为咗同一原因唔用 gstatic(嗰度实测过 1055ms ≈ 4× 基线)。
///
/// 拣 `cp.cloudflare.com` 嘅理由:唯一**两边都满足**嘅候选 —— 国内直连通(实测 385ms,
/// 令 DIRECT 有真数字),境外出口又快又稳(HK 6ms / SG 10ms,anycast 多 IP,唔会撞单点烂路由)。
/// 用 http 唔用 https:免 TLS 握手噪音,量到更接近纯 RTT(mihomo 上游默认都係 http 204)。
// [2026-09-18 0.9.79] http → https:mihomo 源码明写 unified-delay 第二次 HEAD 用 HTTP 会被劫持/唔兼容而失败
//   (adapter.go URLTest 嘅 log.Warnln),HTTPS 先稳。cp.cloudflare.com 係 anycast,每个出口都近。
const defaultTestUrl = 'https://cp.cloudflare.com/generate_204';
const legacyHttpCloudflareTestUrl = 'http://cp.cloudflare.com/generate_204';

/// 旧默认值,只畀迁移逻辑认「呢个係我哋以前钉嘅默认」用,唔好再攞去测速。
const legacyGstaticTestUrl = 'https://www.gstatic.com/generate_204';
final commonFilter = ImageFilter.blur(
  sigmaX: 5,
  sigmaY: 5,
  tileMode: TileMode.clamp,
);

const listEquality = ListEquality();
const navigationItemListEquality = ListEquality<NavigationItem>();
const trackerInfoListEquality = ListEquality<TrackerInfo>();
const stringListEquality = ListEquality<String>();
const intListEquality = ListEquality<int>();
const logListEquality = ListEquality<Log>();
const groupListEquality = ListEquality<Group>();
const ruleListEquality = ListEquality<Rule>();
const scriptListEquality = ListEquality<Script>();
const externalProviderListEquality = ListEquality<ExternalProvider>();
const packageListEquality = ListEquality<Package>();
const profileListEquality = ListEquality<Profile>();
const proxyGroupsEquality = ListEquality<ProxyGroup>();
const hotKeyActionListEquality = ListEquality<HotKeyAction>();
const stringAndStringMapEquality = MapEquality<String, String>();
const stringAndStringMapEntryListEquality =
    ListEquality<MapEntry<String, String>>();
const stringAndStringMapEntryIterableEquality =
    IterableEquality<MapEntry<String, String>>();
const stringAndObjectMapEntryIterableEquality =
    IterableEquality<MapEntry<String, Object?>>();
const delayMapEquality = MapEquality<String, Map<String, int?>>();
const stringSetEquality = SetEquality<String>();
const keyboardModifierListEquality = SetEquality<KeyboardModifier>();

const viewModeColumnsMap = {
  ViewMode.mobile: [2, 1],
  ViewMode.laptop: [3, 2],
  ViewMode.desktop: [4, 3],
};

const proxiesListStoreKey = PageStorageKey<String>('proxies_list');
const toolsStoreKey = PageStorageKey<String>('tools');
const profilesStoreKey = PageStorageKey<String>('profiles');

// 易联品牌主色:voguesly D-v 霓虹紫(#7C5CF6,对齐 D-v icon 同 Ninja 参考风格)。
// Material ColorScheme.fromSeed 会据此铺全局色调。
const defaultPrimaryColor = 0XFF7C5CF6;

double getWidgetHeight(num lines) {
  final space = 14.mAp;
  return max(lines * (80.ap + space) - space, 0);
}

const maxLength = 1000;

const mainIsolate = 'FlClashMainIsolate';

const serviceIsolate = 'FlClashServiceIsolate';

const defaultPrimaryColors = [
  0xFF795548,
  0xFF03A9F4,
  0xFFFFFF00,
  0XFFBBC9CC,
  0XFFABD397,
  defaultPrimaryColor,
  0XFF665390,
];

const scriptTemplate = '''
const main = (config) => {
  return config;
}''';

const backupDatabaseName = 'database.sqlite';
const configJsonName = 'config.json';
