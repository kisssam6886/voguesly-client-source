import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/voguesly/voguesly_api.dart' show applyVogueslyRemotePanelHosts, sanitizeRemoteBaseUrl, vogueslyRemotePanelHosts;
import 'package:fl_clash/voguesly/voguesly_update_download.dart' show vetUpdateDownload;
import 'package:fl_clash/voguesly/voguesly_device.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:fl_clash/voguesly/voguesly_remote_config.dart' show applyVogueslyAppConfig;

/// 拉订阅嘅出路。次序 = 可靠度,见 [Request._subFetchRoutes]。
enum _SubFetchRoute {
  /// 直连 —— 订阅域名本身大陆通,而且唔受核心状态影响。
  direct,

  /// 用户自己嘅系统 / 环境变量代理(佢可能揸紧第三方梯子)。
  system,

  /// 我哋核心嘅 mixedPort —— 只有核心健康先有用。
  core,
}

class Request {
  late final Dio dio;
  late final Dio _clashDio;
  String? userAgent;

  Request() {
    dio = Dio(BaseOptions(headers: {'User-Agent': browserUa}));
    _clashDio = Dio();
    _clashDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (Uri uri) {
          client.userAgent = globalState.ua;
          return FlClashHttpOverrides.handleFindProxy(uri);
        };
        return client;
      },
    );
  }

  /// 拉订阅嘅出路(按顺序试)。
  ///
  /// 🔴 [2026-09-23 Sam 拍板]「**肯定要佢先拉直连,直连拉唔到先至代理拉。
  /// 而且代理都唔好净係我哋代理,佢自己有代理嘅都要拉得到。
  /// 反正要保证一切可能令佢拉得到订阅。**」
  ///
  /// 点解要改:原本订阅**只行一条路** —— `FlClashHttpOverrides.handleFindProxy`,
  /// 佢喺 `isStart == true` 嗰阵一律掟去 `PROXY localhost:<mixedPort>`。
  /// 核心一有事就连订阅都更新唔到 ⇒ **用户冇得自救**,只能重装。
  /// 2026-09-23 实锤过呢条链(IPC completer 竞态:核心进程活住、係 root、socket 连咗,
  /// 但零监听埠零 config;而 isStart 已经 true)⇒ Sam 部机更新订阅一直失败。
  /// 而订阅域名本身大陆直连係通嘅(同日实测 https://ylink.im 200 / 0.4s)。
  static const List<_SubFetchRoute> _subFetchRoutes = [
    _SubFetchRoute.direct,
    _SubFetchRoute.system,
    _SubFetchRoute.core,
  ];

  /// 按出路砌一个独立 HttpClient。唔共用 `_clashDio`,因为佢钉死咗核心代理。
  Dio _dioForRoute(_SubFetchRoute route) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 25),
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.userAgent = globalState.ua;
        switch (route) {
          case _SubFetchRoute.direct:
            client.findProxy = (_) => 'DIRECT';
            break;
          case _SubFetchRoute.system:
            // 用户自己揸紧第三方梯子 / 公司代理嗰阵,呢条路先拉得到。
            client.findProxy = (uri) =>
                HttpClient.findProxyFromEnvironment(uri, environment: null);
            break;
          case _SubFetchRoute.core:
            client.findProxy = (uri) =>
                FlClashHttpOverrides.handleFindProxy(uri);
            break;
        }
        return client;
      },
    );
    return dio;
  }

  Future<Response<Uint8List>> getFileResponseForUrl(String url) async {
    // 易联自家订阅(经呢度嘅:订阅页「全部更新」/ 手动贴 ylink 链接 等)都带设备标识;
    // 第三方订阅返空 map,唔会把设备 ID 发去人哋服务器。
    final deviceHeaders = await vogueslyDeviceHeadersFor(url);
    final options = Options(
      responseType: ResponseType.bytes,
      // ⚠️ 必须 clash UA:否则 XBoard 面板返 base64 通用格式而非 Clash YAML,
      // validateConfig 失败 → profile 刷新后无节点组,只剩 GLOBAL 兜底
      // (桌面用户见到「只有 FlClash 一个」)。同 fetchSubscribeBytes 一致。
      headers: {
        'User-Agent': 'clash-verge/2.0.0 FlClash',
        'Cache-Control': 'no-cache',
        ...deviceHeaders,
      },
    );

    Object? lastError;
    final tried = <String>[];
    for (final route in _subFetchRoutes) {
      final dio = _dioForRoute(route);
      try {
        final response = await dio.get<Uint8List>(url, options: options);
        final bytes = response.data?.length ?? 0;
        // 空 body 当失败 —— 试下一条路,好过把空档写落去整烂 profile。
        if (bytes <= 0) {
          tried.add('${route.name}:empty');
          continue;
        }
        commonPrint.log('subscribe fetched via ${route.name} ($bytes bytes)'
            '${tried.isEmpty ? "" : " after ${tried.join(",")}"}');
        return response;
      } catch (e) {
        lastError = e;
        tried.add('${route.name}:${e.runtimeType}');
      } finally {
        dio.close(force: true);
      }
    }

    commonPrint.log(
      'subscribe fetch failed on all routes: ${tried.join(" | ")}',
      logLevel: LogLevel.error,
    );
    try {
      throw lastError ?? currentAppLocalizations.unknownNetworkError;
    } catch (e) {
      commonPrint.log('getFileResponseForUrl error ${e.toString()}');
      if (e is DioException) {
        if (e.type == DioExceptionType.unknown) {
          throw currentAppLocalizations.unknownNetworkError;
        } else if (e.type == DioExceptionType.badResponse) {
          throw currentAppLocalizations.networkException;
        }
        rethrow;
      }
      throw currentAppLocalizations.unknownNetworkError;
    }
  }

  Future<Response<String>> getTextResponseForUrl(String url) async {
    final response = await _clashDio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return response;
  }

  Future<MemoryImage?> getImage(String url) async {
    if (url.isEmpty) return null;
    final response = await dio.get<Uint8List>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null) return null;
    return MemoryImage(data);
  }

  // 用自己域名嘅 version.json(唔再打 api.github.com/chen08209 上游 repo——
  // 嗰个会引导用户装返原版 FlClash,而且国内冇 VPN 好大机会连唔到)。
  // 返回形状保持同旧代码一致(tag_name/body/download_url),方便 checkUpdateResultHandle 唔使大改。
  /// 本机对应嘅 manifest 平台键(Mac 分 arm64/intel,各平台各自安装包)。
  String? _updatePlatformKey() {
    if (Platform.isAndroid) {
      // [0.9.83] 32 位 / x86 安卓以前一律收到 arm64 APK ⇒ 一键更新后「解析包出错」装唔到。
      // manifest 冇对应键就退返 'android'(见 checkForUpdate)。
      return switch (Abi.current()) {
        Abi.androidArm => 'android_arm32',
        Abi.androidX64 => 'android_x86_64',
        _ => 'android',
      };
    }
    if (Platform.isMacOS) {
      return Abi.current() == Abi.macosArm64 ? 'macos_arm64' : 'macos_x64';
    }
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return null;
  }

  Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      // [0.9.91] 逐个 host 试(见 kVogueslyVersionCheckUrls),唔再单押一个免费域名。
      Response? response;
      // [0.9.91] 远端下发嘅面板入口排先(切域后唔使等内置名单逐个超时),再接内置名单。
      final urls = <String>{
        for (final h in vogueslyRemotePanelHosts()) '$h/downloads/version.json',
        ...kVogueslyVersionCheckUrls,
      };
      for (final url in urls) {
        try {
          final r = await dio.get(url, options: Options(responseType: ResponseType.json));
          if (r.statusCode == 200 && r.data is Map) {
            response = r;
            break;
          }
        } catch (e) {
          commonPrint.log('checkForUpdate $url failed', logLevel: LogLevel.warning);
        }
      }
      // 全部失败 = 服务器/网络异常,唔可以当「已最新」(会误报),返错误标记畀调用方区分。
      if (response == null) return {'__net_error__': true};
      final data = (response.data as Map).cast<String, dynamic>();
      // [0.9.87] 顺手读邀请基址(同版本无关,所以喺比较版本之前读)。只认 https + 有域名,其它一律当冇。
      // [0.9.91] 加 host 白名单:只收自家付费根域(免费域可能被抢注)。
      final inviteBase = sanitizeRemoteBaseUrl(data['invite_base']);
      if (inviteBase != null) vogueslyInviteBase = inviteBase;
      // [0.9.91] 面板入口服务端下发(见 voguesly_api.dart applyVogueslyRemotePanelHosts),同版本无关。
      await applyVogueslyRemotePanelHosts(data['panel_hosts']);
      // [0.9.92] 通用服务端配置(客服入口 / 下载镜像 / 邀请 / 链接 / 文案 / 横幅;hosts.panel 会覆盖上面嘅 panel_hosts)
      await applyVogueslyAppConfig(data['app_config']);
      // ⚠️ 按平台+架构选对应条目。旧代码只读扁平 latest_version/download_url(=Android),
      // 令 Mac/Win 显示咗 Android 版本号 + 下错 APK。改成认返自己平台先。
      final key = _updatePlatformKey();
      final platforms = data['platforms'];
      Map<String, dynamic>? entry;
      if (key != null && platforms is Map && platforms[key] is Map) {
        entry = (platforms[key] as Map).cast<String, dynamic>();
      } else if (key != null && key.startsWith('android_') && platforms is Map && platforms['android'] is Map) {
        entry = (platforms['android'] as Map).cast<String, dynamic>(); // 旧 manifest 未分架构
      } else if (key == 'android') {
        // 向后兼容:旧 manifest 只有扁平键(即 Android)。
        entry = data;
      } else {
        // 桌面/其它平台喺 manifest 冇对应安装包 → 唔提示(唔好显示别平台版本+下错包)。
        return null;
      }
      final remoteVersion = entry['latest_version'] as String?;
      if (remoteVersion == null || remoteVersion.isEmpty) return null;
      final version = globalState.packageInfo.version;
      final hasUpdate = utils.compareVersions(remoteVersion, version) > 0;
      if (!hasUpdate) return null;
      // [0.9.91] 安装包只可以嚟自家下载站 + 必须有 sha256,先会自动下载安装;否则 download_url 留空
      //   ⇒ 更新框只打开下载页(之前任何 https 地址 + 冇 sha 都照装,version.json 任何一个来源被接管就可以推恶意安装包)。
      final vetted = vetUpdateDownload(entry['download_url'], entry['sha256']);
      return {
        'tag_name': 'v$remoteVersion',
        'body': entry['changelog'],
        'download_url': vetted?.url,
        'sha256': vetted?.sha256,
      };
    } catch (e) {
      // 网络异常(断网/超时/DNS)唔可以当「已最新」误报,返错误标记畀调用方区分。
      commonPrint.log('checkForUpdate failed', logLevel: LogLevel.warning);
      return {'__net_error__': true};
    }
  }

  final Map<String, IpInfo Function(Map<String, dynamic>)> _ipInfoSources = {
    'https://ipwho.is': IpInfo.fromIpWhoIsJson,
    'https://api.myip.com': IpInfo.fromMyIpJson,
    'https://ipapi.co/json': IpInfo.fromIpApiCoJson,
    'https://ident.me/json': IpInfo.fromIdentMeJson,
    'http://ip-api.com/json': IpInfo.fromIpAPIJson,
    'https://api.ip.sb/geoip': IpInfo.fromIpSbJson,
    'https://ipinfo.io/json': IpInfo.fromIpInfoIoJson,
  };

  Future<Result<IpInfo?>> checkIp({CancelToken? cancelToken}) async {
    var failureCount = 0;
    final token = cancelToken ?? CancelToken();
    final futures = _ipInfoSources.entries.map((source) async {
      final Completer<Result<IpInfo?>> completer = Completer();
      void handleFailRes() {
        if (!completer.isCompleted && failureCount == _ipInfoSources.length) {
          completer.complete(Result.success(null));
        }
      }

      final future = dio
          .get<Map<String, dynamic>>(
        source.key,
        cancelToken: token,
        options: Options(responseType: ResponseType.json),
      )
          .timeout(const Duration(seconds: 10));
      future
          .then((res) {
        if (res.statusCode == HttpStatus.ok && res.data != null) {
          completer.complete(Result.success(source.value(res.data!)));
          return;
        }
        commonPrint.log('checkIp data empty', logLevel: LogLevel.info);
        failureCount++;
        handleFailRes();
      })
          .catchError((e) {
        failureCount++;
        if (e is DioException && e.type == DioExceptionType.cancel) {
          completer.complete(Result.error('cancelled'));
          return;
        }
        commonPrint.log('checkIp error $e', logLevel: LogLevel.warning);
        handleFailRes();
      });
      return completer.future;
    });
    final res = await Future.any(futures);
    token.cancel();
    return res;
  }

  Future<bool> pingHelper() async {
    if (kDebugMode) return true;
    try {
      // [2026-09-23] 由 GET 改 POST:原本 helper 直接吐返预期嘅核心 SHA256,
      // 任何本机进程 GET 一下就攞到(信息泄露 + TOCTOU 助攻)。
      // 而家由我哋**证明**知道个 hash,helper 只答 ok / mismatch。
      final response = await dio
          .post(
        'http://$localhost:$helperPort/ping',
        data: json.encode({'core_sha256': globalState.coreSHA256}),
        options: Options(responseType: ResponseType.plain),
      )
          .timeout(const Duration(milliseconds: 2000));
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      return (response.data as String).trim() == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<bool> startCoreByHelper(String arg) async {
    try {
      final response = await dio
          .post(
        'http://$localhost:$helperPort/start',
        data: json.encode({'path': appPath.corePath, 'arg': arg}),
        options: Options(responseType: ResponseType.plain),
      )
          .timeout(const Duration(milliseconds: 2000));
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      // [2026-09-23] helper 成功时由「返空字符串」改成返 `ok:<session_id>`。
      // 留住个 id —— `/stop` 而家要凭佢先做得(原本无参数无校验,本机任一进程
      // POST 一下就杀到核心 ⇒ VPN 静默掉线)。
      final data = (response.data as String).trim();
      if (!data.startsWith('ok:')) {
        return false;
      }
      _helperSessionId = data.substring(3);
      return _helperSessionId!.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// `startCoreByHelper` 攞返嚟嘅 session id;`/stop` 要带住佢。
  String? _helperSessionId;

  Future<bool> stopCoreByHelper() async {
    final sid = _helperSessionId;
    if (sid == null || sid.isEmpty) {
      // 从来冇经 helper 起过核心 ⇒ 冇嘢好停,亦唔应该乱 POST。
      return true;
    }
    try {
      final response = await dio
          .post(
        'http://$localhost:$helperPort/stop',
        data: json.encode({'session_id': sid}),
        options: Options(responseType: ResponseType.plain),
      )
          .timeout(const Duration(milliseconds: 2000));
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      final data = response.data as String;
      return data.isEmpty;
    } catch (_) {
      return false;
    }
  }
}

final request = Request();
