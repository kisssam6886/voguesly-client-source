import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/voguesly/voguesly_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../voguesly/voguesly_onboarding_sheet.dart';
import '../../../voguesly/voguesly_quick_settings.dart';
import '../../../voguesly/voguesly_subscription.dart';
import '../../../voguesly/voguesly_tips.dart';

/// 仪表盘大圆圈连接掣(消费者向):
/// 未连=白底醒目圈「开启易联」+ 脉冲动效;撳后 3-2-1 倒计时;已连=绿圈「已连接·轻触断开」。
/// 连接逻辑复用 setupActionProvider.updateStatus(同原 StartButton)。
class ConnectButton extends ConsumerStatefulWidget {
  const ConnectButton({super.key});

  @override
  ConsumerState<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends ConsumerState<ConnectButton>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF22C55E);
  static const _amber = Color(0xFFF59E0B); // 已连但被排除SSID旁路(suspend):唔显绿,警示直连
  bool isStart = false;
  bool _connecting = false; // 仅控制 3-2-1 倒计时显示(只活 ~1.8s)
  bool _attempting = false; // 本次连接尝试仍在进行(未连上/未取消):供 15s 超时判定
  int _count = 0;
  Timer? _timer;
  late final AnimationController _pulse;
  bool _showConnectTip = false; // 首次进入嘅「点一下圆圈就能连上」气泡(只出一次)

  Future<void> _loadTipFlag() async {
    final seen = await vogueslyTipSeen(kVogueslyTipConnectSeen);
    if (mounted && !seen) setState(() => _showConnectTip = true);
  }

  void _dismissConnectTip() {
    if (_showConnectTip) setState(() => _showConnectTip = false);
    markVogueslyTipSeen(kVogueslyTipConnectSeen);
  }

  @override
  void initState() {
    super.initState();
    // [2026-09-23] ⚠️ 唔好喺度 `..repeat()` —— 由 build 按「而家睇唔睇得见脉冲」
    // 决定(见 _syncPulse)。原本无条件 repeat,即使脉冲根本冇渲染(已连接 / 载入中 /
    // 载入失败),Ticker 照 tick ⇒ 每个 vsync 都 scheduleFrame() ⇒ 光栅线程每帧重绘。
    //
    // 实测(2026-09-23,已连接状态、脉冲根本唔喺画面):App 稳定 ~48% CPU、
    // 24 分钟挂机烧咗 12 分 08 秒 CPU(≈ 持续半颗核),而 Go 核心係 **0.0%** —— 即係
    // 成份开销全部喺 Flutter 侧,而且主要就係「有冇帧要出」呢个开关。
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    isStart = ref.read(isStartProvider);
    ref.listenManual(isStartProvider, (prev, next) {
      if (!mounted) return;
      // 只同步真实状态;「正在开启」中间态(3-2-1)由倒计时管,唔畀连接太快冲走个倒计时。
      if (next) _attempting = false; // 已连上 → 本次尝试结束
      setState(() => isStart = next);
      if (next) {
        // 第一次连上:收起气泡,再出一次聚光灯新手引导(0.9.83 取代旧「小贴士」弹窗)。
        _dismissConnectTip();
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) maybeStartVogueslyTour(context);
        });
      }
    }, fireImmediately: true);
    _loadTipFlag();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _onTap(bool hasProfile) {
    if (!hasProfile) {
      // 正在载入订阅时唔好弹引导(避免有套餐用户启动期误开引导)。
      if (ref.read(vogueslyImportingProvider)) return;
      // 网络导入失败(≠未开通)→ 点圆圈重试导入,唔好当未开通弹引导。
      if (ref.read(vogueslyImportFailedProvider)) {
        importVogueslySubscription();
        return;
      }
      // 未有套餐/订阅:弹引导卡(免费测试一键开通 / 购买验证包),唔好净系冷冰冰禁用。
      showVogueslyOnboarding(context);
      return;
    }
    if (isStart) {
      // 断开:先 cancel 倒计时 + 清中间态,免倒计时未行完就断开令圆圈卡喺「正在开启」。
      _timer?.cancel();
      _attempting = false;
      if (_connecting) {
        setState(() {
          _connecting = false;
          _count = 0;
        });
      }
      _toggleCore(false);
      return;
    }
    // 开启:3-2-1 倒计时 + 真连接
    _attempting = true;
    setState(() {
      _connecting = true;
      _count = 3;
    });
    _toggleCore(true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 600), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_count <= 1) {
        // 倒计时 3-2-1 行足,先退出中间态显示真实状态(已连接/失败)。
        t.cancel();
        setState(() => _connecting = false);
      } else {
        setState(() => _count--);
      }
    });
    // 连接超时保护:15s 仍未连上(本次尝试仍在进行 + isStart 冇变 true)→ 明确提示。
    // ⚠️ 用 _attempting(活到连上/断开/超时)而非 _connecting(倒计时 ~1.8s 就清),否则永远唔触发。
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _attempting && !isStart) {
        _attempting = false;
        if (_connecting) setState(() => _connecting = false);
        // [0.9.96] 今次係被「请先退出其他代理软件」拦低 ⇒ 唔好再叫人「检查网络 / 换线路」
        final blockedAt = globalState.connectBlockedAt;
        if (blockedAt != null && DateTime.now().difference(blockedAt) < const Duration(seconds: 20)) return;
        globalState.showNotifier(currentAppLocalizations.vgConnectTimeoutTryAnotherRoute);
      }
    });
  }

  void _toggleCore(bool start) {
    if (start && system.isDesktop) {
      final tun = ref.read(patchClashConfigProvider).tun;
      final systemProxy = ref.read(networkSettingProvider).systemProxy;
      // The consumer-facing circle is the TUN-first entry point. If an
      // advanced user previously disabled both transport switches, restore
      // TUN for this explicit click instead of starting a core that cannot
      // take over any traffic.
      if (!tun.enable && !systemProxy) {
        ref
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith.tun(enable: true));
      }
      // [2026-09-23 Sam 拍板「只开 TUN」] ⚠️ 关系统代理嘅动作**唔喺呢度做**。
      //
      // 最初写咗喺呢度(撳落去即刻关)—— 错。TUN 起唔起得到要等
      // 20 秒启动宽限 + 连续 5 次探测失败,最快都三十几秒先回退到兼容模式;
      // 撳完就关系统代理 = **唔识嘅用户会「显示已连接但上唔到网」成半分钟**。
      // ⇒ 已经搬咗去 `action.dart` 嘅 `_verifyDesktopTunConnected()`,
      //   **TUN 确认接管到(ok == true)先关**。TUN 唔掂就由头到尾唔郁系统代理。
    }
    // 唔做乐观更新:isStart 由 isStartProvider 监听器做唯一真相源,确保 UI 同实际连接状态一致。
    debouncer.call(FunctionTag.updateStatus, () {
      globalState.container
          .read(setupActionProvider.notifier)
          .updateStatus(start, isInit: !ref.read(initProvider));
    }, duration: commonDuration);
  }

  /// 把脉冲 controller 嘅运行状态同「而家睇唔睇得见佢」绑实。
  ///
  /// 喺 post-frame 先郁 controller:build 期间 start/stop 会喺同一帧再请求帧,
  /// Flutter 会警告「setState / markNeedsBuild called during build」。
  void _syncPulse(bool shouldPulse) {
    if (shouldPulse == _pulse.isAnimating) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (shouldPulse == _pulse.isAnimating) return;
      if (shouldPulse) {
        // from: 0 —— stop() 会停喺中间值,唔重置会跳一下。
        _pulse.repeat();
      } else {
        _pulse.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasProfile = ref.watch(
      profilesProvider.select((state) => state.isNotEmpty),
    );
    // China→HK 拉订阅通常十几秒;载入期显示「正在载入订阅」而非误显示「点我开通」。
    final importing = ref.watch(vogueslyImportingProvider) && !hasProfile;
    // 网络导入失败(≠未开通套餐):空 profile 态显「载入失败·点我重试」而非「点我开通」。
    final importFailed =
        ref.watch(vogueslyImportFailedProvider) && !hasProfile && !importing;
    final suspend = ref.watch(suspendProvider);
    final realTunEnable = ref.watch(realTunEnableProvider);
    // 已连接但被排除SSID旁路(suspend)→ 流量实际走直连,圆圈唔可以显示「已连接·绿色」。
    final bypassed = isStart && suspend;
    final cs = context.colorScheme;
    // 倒计时期间(_connecting)就显示「正在开启 3-2-1」,唔好因为连接太快(isStart变true)
    // 而提早绕过倒计时;倒计时行足由 timer 清 _connecting 先显示真实状态。
    final connecting = _connecting;

    // [2026-09-23] 脉冲只喺「未连 + 空闲」先显示(下面嗰个 if 一样嘅判据)。
    // 呢度把 controller 嘅运行状态同「睇唔睇得见」绑实:睇唔见就 stop(),
    // 唔好净係唔画但照 tick。判据只写一次,由 _syncPulse 同渲染共用,
    // 避免将来改一边漏另一边。
    _syncPulse(!isStart && !connecting && !importing && !importFailed);

    // 配色
    final Color fill;
    final Color fg;
    if (bypassed) {
      fill = _amber;
      fg = Colors.white;
    } else if (isStart) {
      fill = _green;
      fg = Colors.white;
    } else if (connecting) {
      fill = cs.primary;
      fg = cs.onPrimary;
    } else {
      fill = Colors.white;
      fg = cs.primary;
    }
    final title = !hasProfile
        ? (importing
              ? currentAppLocalizations.vgLoadingSubscription
              : importFailed
              ? currentAppLocalizations.vgLoadFailedTapRetry
              : currentAppLocalizations.vgTapToActivate)
        : bypassed
        ? currentAppLocalizations.vgAccelerationSkipped // 唔用 l10n「挂起中...」(OS黑话),同副标题「已跳过加速」口径一致
        : isStart
        ? currentAppLocalizations.vgConnected
        : connecting
        ? currentAppLocalizations.vgStarting
        : currentAppLocalizations.vgTurnOnVoguesly;

    // 桌面已连接时,承载方式(TUN / 系统代理)拆做圆内第二行小字。
    // 旧实现塞成一行「已连接 · TUN + 系统代理」,喺 150 直径嘅圆入面必然溢出圆外
    // (Sam 2026-08-05 实测截图)。拆两行 + 下面 _CircleLabel 限宽 scaleDown,
    // 长短文案都唔会冲出圆边。
    // [0.9.98] 两个开关可以同时开 ⇒「增强模式」/「增强模式 + 系统代理」/「系统代理」三种。
    final systemProxyOn = ref.watch(networkSettingProvider.select((s) => s.systemProxy));
    final modeLabel = (isStart && !bypassed && system.isDesktop)
        // [0.9.83] 唔再显示「TUN」工程字:TUN 接管全机 =「增强模式」
        ? (realTunEnable
              ? (systemProxyOn
                    ? currentAppLocalizations.vgConnModeBoth
                    : currentAppLocalizations.vgConnModeEnhanced)
              : currentAppLocalizations.vgConnModeCompat)
        : null;

    return Column(
      children: [
        const SizedBox(height: 8),
        if (_showConnectTip && hasProfile && !isStart && !connecting)
          VogueslyConnectTipBubble(onDismiss: _dismissConnectTip),
        GestureDetector(
          onTap: () => _onTap(hasProfile),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            key: vogueslyTourConnectKey, // [0.9.83] 新手引导第 1 步框住呢个圆
            width: 200,
            height: 188,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 脉冲动效(只喺未连+空闲时;载入/载入失败时唔脉冲,改显示 spinner/重试图标)
                if (!isStart && !connecting && !importing && !importFailed)
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, _) {
                      final v = _pulse.value;
                      return Container(
                        width: 150 + 56 * v,
                        height: 150 + 56 * v,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.primary.withValues(alpha: 0.18 * (1 - v)),
                        ),
                      );
                    },
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fill,
                    border: Border.all(
                      color:
                          (bypassed
                                  ? _amber
                                  : isStart
                                  ? _green
                                  : cs.primary)
                              .withValues(alpha: 0.5),
                      width: 3,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (connecting && _count > 0)
                        Text(
                          '$_count',
                          style: context.textTheme.displaySmall?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else if (connecting || importing)
                        SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: fg,
                          ),
                        )
                      else if (importFailed)
                        Icon(Icons.refresh_rounded, size: 52, color: fg)
                      else
                        Icon(
                          Icons.power_settings_new_rounded,
                          size: 52,
                          color: fg,
                        ),
                      SizedBox(height: modeLabel == null ? 6 : 4),
                      // ⚠️ 圆形容器:越靠近上下边缘可用宽度越窄。文字喺图标下方,
                      // 实际可用弦长只得 ~130px,所以限宽 116 + scaleDown 兜底。
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 116),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                title,
                                maxLines: 1,
                                softWrap: false,
                                style: context.textTheme.titleMedium?.copyWith(
                                  color: fg,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (modeLabel != null) ...[
                              const SizedBox(height: 1),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  modeLabel,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: context.textTheme.labelSmall?.copyWith(
                                    color: fg.withValues(alpha: 0.88),
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // [0.9.87 Sam 09-23 定] 圆圈右下角齿轮 → 连接设置(连接方式 + 附加规则)。
                //   默认画面仍然只得一个大圆圈;要改嘅人一撳就到,唔要改嘅人唔会被工程开关吓亲。
                //   IconButton 自己食咗点击,唔会触发外层 GestureDetector 嘅连接 / 断开。
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: IconButton.filledTonal(
                    tooltip: currentAppLocalizations.vgQuickSettingsTitle,
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    onPressed: () => showVogueslyQuickSettings(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 已连接:轻触断开提示 + 实时速度;未连:留白
        SizedBox(
          height: 20,
          child: !isStart
              ? null
              : bypassed
              ? Text(
                  currentAppLocalizations.vgNetworkSkippedDirect,
                  style: context.textTheme.bodySmall?.copyWith(color: _amber),
                )
              : Consumer(
                  builder: (_, ref, _) {
                    final t = ref.watch(
                      trafficsProvider.select(
                        (s) => s.list.safeLast(const Traffic()),
                      ),
                    );
                    return Text(
                      currentAppLocalizations.vgTapToDisconnectWith(t.speedText),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
