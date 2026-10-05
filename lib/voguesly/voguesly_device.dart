import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'voguesly_device_id.dart';

export 'voguesly_device_id.dart'
    show kVogueslyDeviceHeader, isVogueslyOwnSubscriptionUrl, isVogueslyOwnHost, isVogueslyCurrentHost,
        isVogueslyProfileUrl, isVogueslyCurrentProfileUrl, kVogueslyOwnRootDomains, kVogueslyCurrentRootDomains;

/// 安装ID 喺 SharedPreferences 嘅 key(同登录 token 一样嘅持久化方式)。卸载重装会变新 ID,可接受。
const String _kInstallIdPrefKey = 'voguesly_install_id';

/// 同一个进程只读 / 生成一次:并发几条拉订阅都攞同一个 Future,唔会各自生成唔同 ID。
Future<String>? _installIdFuture;
Future<String>? _modelFuture;
Future<String?>? _appVersionFuture;

/// App 版本(第 5 段):同「关于」页 / 检查更新一样用 package_info_plus 嘅 `version`(例如 `0.9.81`,
/// 唔含 `+build`)。直接 `PackageInfo.fromPlatform()` 而唔读 globalState.packageInfo ——
/// 后者系 late final,未初始化就读会抛,呢度唔想依赖启动次序。攞唔到返 null = 退返 4 段格式。
Future<String?> _loadAppVersion() async {
  try {
    final info =
        await PackageInfo.fromPlatform().timeout(const Duration(seconds: 3));
    return sanitizeVogueslyAppVersion(info.version);
  } catch (_) {
    return null;
  }
}

Future<String> _loadInstallId() async {
  final prefs = await SharedPreferences.getInstance();
  // 先 reload:万一其他 isolate 啱啱写咗 ID,本 isolate 嘅缓存未见到,唔好再生成多个。
  try {
    await prefs.reload();
  } catch (_) {}
  return loadOrCreateVogueslyInstallId(
    read: () async => prefs.getString(_kInstallIdPrefKey),
    write: (id) async {
      await prefs.setString(_kInstallIdPrefKey, id);
    },
  );
}

/// 型号:用现成 device_info_plus(唔加新包)。攞唔到就用 `Platform.operatingSystemVersion` 截短。
/// - Android:厂商 + 型号(例如 `Xiaomi 23049RAD8C`);
/// - iOS:商用名(`iPhone 16 Pro`),冇就 machine(`iPhone17,1`);
/// - macOS:型号名(`MacBook Pro (16-inch, 2021)`),冇就型号 ID(`MacBookPro18,3`)。
///   ⚠️ 刻意唔用 computerName:macOS 默认系「<用户全名>的 MacBook Pro」,等于上报真名;
/// - Windows:电脑名(默认 `DESKTOP-XXXXXXX`),冇就系统版本名;
/// - Linux:发行版名(`Ubuntu 24.04 LTS`)。
Future<String> _loadModel() async {
  final fallback = Platform.operatingSystemVersion;
  try {
    final plugin = DeviceInfoPlugin();
    const timeout = Duration(seconds: 3);
    if (Platform.isAndroid) {
      final d = await plugin.androidInfo.timeout(timeout);
      final model = d.model.trim();
      final maker = d.manufacturer.trim();
      final full = model.toLowerCase().startsWith(maker.toLowerCase())
          ? model
          : '$maker $model';
      return pickVogueslyDeviceModel([full, fallback]);
    }
    if (Platform.isIOS) {
      final d = await plugin.iosInfo.timeout(timeout);
      return pickVogueslyDeviceModel([d.modelName, d.utsname.machine, fallback]);
    }
    if (Platform.isMacOS) {
      final d = await plugin.macOsInfo.timeout(timeout);
      return pickVogueslyDeviceModel([d.modelName, d.model, fallback]);
    }
    if (Platform.isWindows) {
      final d = await plugin.windowsInfo.timeout(timeout);
      return pickVogueslyDeviceModel([d.computerName, d.productName, fallback]);
    }
    if (Platform.isLinux) {
      final d = await plugin.linuxInfo.timeout(timeout);
      return pickVogueslyDeviceModel([d.prettyName, d.name, fallback]);
    }
  } catch (_) {}
  return pickVogueslyDeviceModel([fallback]);
}

/// `X-YL-Device` 嘅值;任何异常返 null(唔带头 = 服务端当旧版,**绝对唔可以因为呢个令拉订阅失败**)。
Future<String?> vogueslyDeviceHeaderValue() async {
  final platform = vogueslyPlatformName();
  if (platform == null) return null;
  try {
    final id = await (_installIdFuture ??= _loadInstallId());
    final model = await (_modelFuture ??= _loadModel());
    final appVersion = await (_appVersionFuture ??= _loadAppVersion());
    return formatVogueslyDeviceHeader(
      installId: id,
      platform: platform,
      model: model,
      appVersion: appVersion,
    );
  } catch (_) {
    // 读写 prefs 出错:清走缓存,下次拉订阅再试,唔好一次失败就永久唔带。
    _installIdFuture = null;
    _modelFuture = null;
    _appVersionFuture = null;
    return null;
  }
}

/// 拉订阅用:[url] 系易联自家订阅先返 `{X-YL-Device: ...}`,第三方订阅 / 出错一律返空 map。
/// [trustedHosts]:调用方明确知道系自家后端嘅 host(例如 VogueslyApi 嘅镜像列表)。
Future<Map<String, String>> vogueslyDeviceHeadersFor(
  String url, {
  Iterable<String> trustedHosts = const [],
}) async {
  if (!isVogueslyOwnSubscriptionUrl(url, trustedHosts: trustedHosts)) {
    return const {};
  }
  final value = await vogueslyDeviceHeaderValue();
  return value == null ? const {} : {kVogueslyDeviceHeader: value};
}
