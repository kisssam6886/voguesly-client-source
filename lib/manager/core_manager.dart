import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/common.dart' show onCoreDelayEvent;
import 'package:fl_clash/voguesly/voguesly_diag_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 节点测速 / 健康检查失败嘅核心 log(只入日志,唔弹通知)。
/// 按内容判:核心 log 冇「来源」字段可以分,但 mihomo 呢句格式固定;再加测速地址兜底
///(generate_204 / cp.cloudflare.com 只会喺测速 / 健康检查出现,唔会系导入、登录、连接失败)。
const List<String> _kDelayTestNoiseMarkers = [
  'failed to get the second response from',
  'generate_204',
  'cp.cloudflare.com',
];

/// [0.9.87] 加路由时撞到已存在嘅路由(另一个 VPN 占咗)。macOS / Linux 係「file exists」,Windows 係「already exists」。
bool isRouteAlreadyExistsLog(String payload) {
  final p = payload.toLowerCase();
  return p.contains('route') && (p.contains('file exists') || p.contains('already exists'));
}

bool _otherVpnNoticeShown = false;

/// [0.9.89] 内核 Error 级日志嘅中文提示节流(5 分钟最多一次;原文照入日志)。
DateTime? _lastCoreErrorNoticeAt;

bool isDelayTestNoiseLog(String payload) =>
    _kDelayTestNoiseMarkers.any(payload.contains);

class CoreManager extends ConsumerStatefulWidget {
  final Widget child;

  const CoreManager({super.key, required this.child});

  @override
  ConsumerState<CoreManager> createState() => _CoreContainerState();
}

class _CoreContainerState extends ConsumerState<CoreManager>
    with CoreEventListener {
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void initState() {
    super.initState();
    unawaited(VogueslyIssueLog.instance.load()); // [0.9.89] 读返磁盘入面最近 48 小时嘅警告 / 错误
    coreEventManager.addListener(this);
    ref.listenManual(currentProfileIdProvider, (prev, next) {
      if (prev != next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(setupActionProvider.notifier).fullSetup();
        });
      }
    });
    ref.listenManual(updateParamsProvider, (prev, next) {
      if (prev != next) {
        // [0.9.94] 模式变咗:记低,等新配置落到核心之后先断旧连接(见 SetupAction.noteModeChanged)
        if (prev != null && prev.mode != next.mode) {
          ref.read(setupActionProvider.notifier).noteModeChanged(prev.mode);
        }
        ref.read(setupActionProvider.notifier).updateConfigDebounce();
      }
    });
    // [2026-09-21] 核心日志一律订阅。之前要 openLogs 开先收,但消费者见唔到呢个开关(默认 false)
    // ⇒ 用户喺「反馈问题 / 上传日志」交上嚟嘅日志只有 App 自己嘅记录,永远冇核心嘅连接错误。
    // openLogs 而家只控制调试日志页显唔显示;缓冲仍然係 FixedList(500),唔会无限增长。
    ref.listenManual(appSettingProvider.select((state) => state.openLogs), (
      prev,
      next,
    ) {
      coreController.startLog();
    }, fireImmediately: true);
  }

  @override
  Future<void> dispose() async {
    coreEventManager.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onDelay(Delay delay) async {
    super.onDelay(delay);
    final proxiesAction = ref.read(proxiesActionProvider.notifier);
    // [0.9.87] 唔再直接 setDelay 原始值:手动测速嘅事件要忽略、后台失败唔标红,见 onCoreDelayEvent。
    onCoreDelayEvent(delay);
    debouncer.call(FunctionTag.updateDelay, () async {
      proxiesAction.updateGroupsDebounce();
    }, duration: const Duration(milliseconds: 5000));
  }

  @override
  void onLog(Log log) {
    // [0.9.87] 核心日志入缓冲(上传日志先有「连唔上 / 超时」呢类核心错误,09-21 订阅嘅原意)。
    //   ⚠️ [0.9.89 更正] 实际内核日志等级係 info(clash_config.dart 默认),每条连接一行,
    //   500 条缓冲只覆盖约 2 分钟 ⇒ warning / error 另存喺 VogueslyIssueLog(见 providers/app.dart Logs.add)。
    //   测速噪音唔入(同下面唔弹通知同一个判据)。print.dart 会喺上传前去凭证。
    if (!isDelayTestNoiseLog(log.payload)) {
      ref.read(logsProvider.notifier).add(log);
    }
    // ⚠️ 测速 / 健康检查失败唔弹:节点列表本身已经显示 Timeout / 红色,再弹提示条只系噪音。
    // 根因:mihomo adapter.go URLTest 嘅 unified-delay 第二次 HEAD 失败会用 **Error 级** 写 log
    //(「<节点名> failed to get the second response from http://…/generate_204: …」),
    // 而呢度原本「所有 Error 级 log 一律弹 showNotifier」→ url-test / fallback 组每轮探测、
    // 或者用户撳测速,一次过弹 5–6 条(Sam 安卓首页截图)。只滤呢类,其他 Error log 照弹。
    if (log.logLevel == LogLevel.error && isRouteAlreadyExistsLog(log.payload)) {
      // [0.9.87] 另一个 VPN(例如小火箭)已经占咗某条路由 ⇒ 我哋加嗰条返「file exists」。
      //   09-23 实测:47 条路由只有第一条(1.0.0.0/8)撞,其余 46 条照加,功能正常 ⇒ 唔係错误,
      //   唔好再弹原始报错;改为每次运行最多一次、讲人话、唔自动消失嘅提示。
      if (!_otherVpnNoticeShown) {
        _otherVpnNoticeShown = true;
        unawaited(globalState.showMessage(
          title: currentAppLocalizations.vgOtherVpnActiveTitle,
          message: TextSpan(text: currentAppLocalizations.vgOtherVpnActiveBody),
          confirmText: currentAppLocalizations.vgGotIt,
          cancelable: false,
        ));
      }
    } else if (log.logLevel == LogLevel.error && !isDelayTestNoiseLog(log.payload)) {
      // [0.9.89] 唔再弹内核原文(英文技术句,用户睇唔明;Sam 09-24:「如果要的话也是中文」)。
      //   原文已经喺上面入咗日志缓冲(上传日志睇得到);呢度只提一句中文,5 分钟最多一次。
      final now = DateTime.now();
      if (_lastCoreErrorNoticeAt == null ||
          now.difference(_lastCoreErrorNoticeAt!) > const Duration(minutes: 5)) {
        _lastCoreErrorNoticeAt = now;
        globalState.showNotifier(currentAppLocalizations.vgCoreErrorNotice);
      }
    }
    super.onLog(log);
  }

  @override
  void onRequest(TrackerInfo trackerInfo) async {
    ref.read(requestsProvider.notifier).addRequest(trackerInfo);
    super.onRequest(trackerInfo);
  }

  @override
  Future<void> onLoaded(String providerName) async {
    final ref = globalState.container;
    ref
        .read(providersProvider.notifier)
        .setProvider(await coreController.getExternalProvider(providerName));
    debouncer.call(FunctionTag.loadedProvider, () async {
      ref.read(proxiesActionProvider.notifier).updateGroupsDebounce();
    }, duration: const Duration(milliseconds: 5000));
    super.onLoaded(providerName);
  }

  @override
  Future<void> onCrash(String message) async {
    // 🔴 [2026-09-23] 原本第一句係
    //     `if (coreStatus != CoreStatus.connected) return;`
    // ⇒ 核心**从来未连上过**(启动就失败)嗰阵,coreStatus 係 disconnected,
    //   成个处理直接早退:唔通知、唔 shutdown、唔清理。
    //   用户只见到个大圆圈着一下就自己熄,**一个字嘅提示都冇**,唔知发生咩事。
    //   (2026-09-23 Sam 部 Mac 实锤咗呢个体验;而且令 `_startImpl` 嗰个新加嘅
    //    「逾时当启动失败 → 报 crash event」白做,event 喺呢度被食咗。)
    //
    // 而家分两种:
    //   · 运行中掉线(connected → 断)     :原有流程,要 shutdown
    //   · 一开始就起唔到(从未 connected):唔使 shutdown(冇嘢好收),但**一定要话畀用户知**
    final wasConnected = ref.read(coreStatusProvider) == CoreStatus.connected;
    ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
    // core 层传上嚟嘅係技术标识,唔係畀用户睇嘅 —— 喺呢层转文案。
    // [0.9.89] 以前未识别嘅标识(例如 'core done')会原文弹出;而家一律转中文,原文只入日志。
    commonPrint.log(
      'Core crash event: $message (wasConnected=$wasConnected)',
      logLevel: LogLevel.warning,
    );
    final userMessage = switch (message) {
      kCoreStartTimeoutReason => currentAppLocalizations.vgCoreFailedToBindPort,
      kCoreProcessStartFailedReason => currentAppLocalizations.vgCoreStartFailed,
      _ => currentAppLocalizations.vgCoreStoppedUnexpectedly,
    };
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      context.showNotifier(userMessage);
    }
    if (wasConnected) {
      await coreController.shutdown(false);
      _maybeAutoRecover();
    }
    super.onCrash(message);
  }

  /// [0.9.96] 核心喺「用户仲连住」嘅时候被外部杀咗 ⇒ 自动重启,唔好留低一个假绿灯。
  /// 实测(09-30 Windows):装 / 升级官方 FlClash 会按名 `taskkill FlClashCore.exe`(两边核心同名),
  ///   易联即刻收到断线(15:12:46),但之前只弹提示唔重启,界面继续「已连接」,
  ///   要等 TUN 自检连错 5 次(~2 分 12 秒)先恢复,期间全部流量直出国内。
  /// 防死循环:5 分钟内最多自动重启 3 次;超过就老实断开(界面显示未连接)。
  final List<DateTime> _autoRecoverAt = [];

  void _maybeAutoRecover() {
    if (ref.read(runTimeProvider) == null) return; // 用户已经主动断开
    final now = DateTime.now();
    _autoRecoverAt.removeWhere((t) => now.difference(t) > const Duration(minutes: 5));
    if (_autoRecoverAt.length >= 3) {
      commonPrint.log('[CORE-RECOVER] 5 分钟内已自动重启 3 次,唔再试;断开', logLevel: LogLevel.warning);
      unawaited(ref.read(setupActionProvider.notifier).updateStatus(false));
      return;
    }
    _autoRecoverAt.add(now);
    commonPrint.log('[CORE-RECOVER] 核心意外退出(用户仍连接中)⇒ 2 秒后自动重启(第 ${_autoRecoverAt.length} 次)', logLevel: LogLevel.warning);
    unawaited(Future.delayed(const Duration(seconds: 2), () async {
      if (ref.read(runTimeProvider) == null) return; // 呢 2 秒内用户自己断开咗
      await ref.read(setupActionProvider.notifier).recoverAfterCoreCrash();
    }));
  }
}
