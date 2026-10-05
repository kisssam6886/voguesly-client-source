import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/window_manager.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/voguesly/voguesly_auth.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:fl_clash/voguesly/voguesly_noplan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/voguesly/voguesly_cs.dart';
import 'package:fl_clash/voguesly/voguesly_invite.dart';
import 'package:fl_clash/voguesly/voguesly_notice.dart';
import 'package:fl_clash/voguesly/voguesly_overlay.dart';
import 'package:fl_clash/voguesly/voguesly_shop.dart';
import 'package:fl_clash/voguesly/voguesly_stat.dart';
import 'package:fl_clash/voguesly/voguesly_subscription.dart';
import 'package:fl_clash/voguesly/voguesly_tour.dart';
import 'package:fl_clash/voguesly/voguesly_user_center.dart';

/// 侧栏「有新版本」入口用嘅版本号(null = 已係最新 / 未检查到)。
///
/// 独立于 appSetting.autoCheckUpdate 嗰个开关:嗰个开关嘅语义係「唔好弹窗打扰我」,
/// 唔应该顺带令用户**连边度睇更新都揾唔到**。所以呢度做一次静默检查,只喺侧栏亮一个
/// 入口,唔弹任何嘢;用户想更新先撳。呢样先至係 Sam 要嘅「唔使入设置→关于」。
/// ⚠️ riverpod 3 已经移除 StateProvider,手写 Notifier(唔使跑 build_runner,
/// 网络断嗰阵一样改得郁)。
class VogueslyUpdateVersion extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

final vogueslyUpdateVersionProvider =
    NotifierProvider<VogueslyUpdateVersion, String?>(
      VogueslyUpdateVersion.new,
    );

class AppStateManager extends ConsumerStatefulWidget {
  final Widget child;

  const AppStateManager({super.key, required this.child});

  @override
  ConsumerState<AppStateManager> createState() => _AppStateManagerState();
}

class _AppStateManagerState extends ConsumerState<AppStateManager>
    with WidgetsBindingObserver {
  /// 上次真正查过更新嘅时间。用嚟节流,避免回前台好频繁时不停打后端。
  DateTime? _lastUpdateCheckAt;

  /// 静默检查新版本,只写 provider 畀侧栏亮入口,**唔弹任何窗**。
  /// 失败一律静默(唔可以因为检查更新失败就打扰用户)。
  ///
  /// ⚠️ 之前净係喺 initState 调一次 —— 桌面用户 app 长开唔重启,就永远唔会再查,
  /// 出咗新版都要自己去撳「检查更新」先见到。所以回前台(resumed)亦要查一次。
  /// [delay] 启动时等几秒避开其他启动请求;回前台唔使等。
  Future<void> _silentCheckUpdate({
    Duration delay = const Duration(seconds: 5),
  }) async {
    final now = DateTime.now();
    if (_lastUpdateCheckAt != null &&
        // [0.9.83] 1 小时 → 15 分钟:Sam 09-22 发版后 Android 未见到 banner(回前台时仍喺上次检查嘅 1 小时内)
        now.difference(_lastUpdateCheckAt!) < const Duration(minutes: 15)) {
      return; // 15 分钟内查过就唔再查
    }
    _lastUpdateCheckAt = now; // 先占位,避免并发重入
    if (delay > Duration.zero) await Future.delayed(delay);
    if (!mounted) return;
    try {
      final res = await request.checkForUpdate();
      if (!mounted || res == null) return;
      // checkForUpdate 内部已经做咗版本比较,有返回 = 真係有新版;
      // __net_error__ 係网络异常标记,唔当有更新。
      if (res['__net_error__'] == true) {
        _lastUpdateCheckAt = null; // 网络问题唔算查过,下次回前台再试
        return;
      }
      final tag = res['tag_name'] as String?;
      if (tag == null || tag.isEmpty) return;
      ref.read(vogueslyUpdateVersionProvider.notifier).set(tag);
    } catch (_) {
      _lastUpdateCheckAt = null; // 同上:异常唔算查过
      // 静默:侧栏唔亮入口就算,唔好因为呢个 feature 影响正常使用。
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _silentCheckUpdate();
    ref.listenManual(checkIpProvider, (prev, next) {
      if (prev != next && next.a && next.c) {
        ref.read(networkDetectionProvider.notifier).startCheck();
      }
    });
    ref.listenManual(configProvider, (prev, next) {
      if (prev != next) {
        globalState.container
            .read(storeActionProvider.notifier)
            .savePreferencesDebounce();
      }
    });
    ref.listenManual(needUpdateGroupsProvider, (prev, next) {
      if (prev != next) {
        globalState.container
            .read(proxiesActionProvider.notifier)
            .updateGroupsDebounce();
      }
    });
    ref.listenManual(suspendProvider, (prev, next) {
      final isStart = ref.read(isStartProvider);
      if (prev != next && isStart) {
        debouncer.call(FunctionTag.suspend, () async {
          if (next == true) {
            await coreController.stopListener();
          } else {
            await coreController.startListener();
          }
          ref.read(checkIpNumProvider.notifier).add();
        });
      }
    });
    if (system.isMacOS) {
      ref.listenManual(autoSetSystemDnsStateProvider, (prev, next) async {
        if (prev == next) {
          return;
        }
        if (next.a == true && next.b == true) {
          macOS?.updateDns(false);
        } else {
          macOS?.updateDns(true);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    commonPrint.log('$state');
    if (state == AppLifecycleState.resumed) {
      permissions.check();
      render?.resume();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ref = globalState.container;
        ref.read(setupActionProvider.notifier).tryCheckIp();
        // 回前台刷新套餐/流量(连接中配额被消耗,账号卡数字会冻结);未登录时 refreshUser 自身 no-op。
        ref.read(vogueslyAuthProvider.notifier).refreshUser();
        // 回前台顺手查下有冇新版(内部 1 小时节流)。桌面用户长开唔重启,
        // 冇呢句就只有启动嗰次会查,新版本推唔到佢哋手上。
        _silentCheckUpdate(delay: Duration.zero);
        if (system.isAndroid) {
          ref.read(coreActionProvider.notifier).tryStartCore();
        }
      });
      return;
    }
    // [2026-09-23] 原本净係有 `resumed → resume()` 一个分支,**冇任何 pause 分支**
    // (只有最小化 / 收托盘先会经 window_manager 停帧)。
    //
    // ⚠️ 刻意**唔处理 `inactive`** —— macOS 窗口净係失焦(畀第二个 App 盖住 /
    //    用户去咗第二个 Space)都会係 inactive,但窗口可能仲睇得见。
    //    嗰阵停帧会令用户见到一个**唔郁嘅窗口 = 当咗你死机**,呢个係体验事故,
    //    比多食几个百分点 CPU 差得多。
    // 只有 `hidden` / `paused` 先係真系统级唔可见。
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      render?.pause();
    }
  }

  @override
  void didChangePlatformBrightness() {
    globalState.container.read(themeActionProvider.notifier).updateBrightness();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerHover: (_) {
        render?.resume();
      },
      child: widget.child,
    );
  }
}

class AppEnvManager extends StatelessWidget {
  final Widget child;

  const AppEnvManager({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      if (globalState.isPre) {
        return Banner(
          message: 'DEBUG',
          location: BannerLocation.topEnd,
          child: child,
        );
      }
    }
    // PRE 预发布角标已去除(上架前品牌化,唔畀用户见到工程化标记)。
    return child;
  }
}

class AppSidebarContainer extends ConsumerWidget {
  final Widget child;

  const AppSidebarContainer({super.key, required this.child});

  // Widget _buildLoading() {
  //   return Consumer(
  //     builder: (_, ref, _) {
  //       final loading = ref.watch(loadingProvider);
  //       final isMobileView = ref.watch(isMobileViewProvider);
  //       return loading && !isMobileView
  //           ? RotatedBox(
  //               quarterTurns: 1,
  //               child: const LinearProgressIndicator(),
  //             )
  //           : Container();
  //     },
  //   );
  // }

  Widget _buildBackground({
    required BuildContext context,
    required Widget child,
  }) {
    return Material(color: context.colorScheme.surfaceContainer, child: child);
    // if (!system.isMacOS) {
    //   return Material(
    //     color: context.colorScheme.surfaceContainer,
    //     child: child,
    //   );
    // }
    // return child;
    // return TransparentMacOSSidebar(
    //   child: Material(color: Colors.transparent, child: child),
    // );
  }

  void _updateSideBarWidth(WidgetRef ref, double contentWidth) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sideWidthProvider.notifier).value =
          ref.read(viewSizeProvider.select((state) => state.width)) -
          contentWidth;
    });
  }

  void _handleToPage(PageLabel pageLabel) {
    final container = globalState.container;
    // [0.9.84] 客服已经喺眼前再撳「在线客服」= 重新载入(同 0.9.83 半框入口一致,白屏时用得);
    // 客服隐藏中(保活)再撳 = 直接显示,唔重载(见 csAliveProvider)。
    final csShowing = pageLabel == PageLabel.support &&
        container.read(currentPageLabelProvider) == PageLabel.support &&
        container.read(contentOverlayProvider) == ContentOverlay.none;
    // 切换主菜单时关闭半框 overlay(否则 overlay 仲盖住新页,用户点咗但见唔到)。
    // ⚠️ 只改页面 / overlay,唔郁 csAliveProvider:在线客服系收埋保活,切返嚟唔会重新加载。
    globalState.container.read(contentOverlayProvider.notifier).close();
    // 点 nav 跳返该页第一级(设置深入几级后再点「设置」直接返顶,唔使逐级返回)。
    final ctx = GlobalObjectKey(pageLabel).currentContext;
    final nav = ctx == null ? null : Navigator.maybeOf(ctx);
    nav?.popUntil((r) => r.isFirst);
    globalState.container
        .read(currentPageLabelProvider.notifier)
        .toPage(pageLabel);
    if (csShowing) vogueslyCsReloadTick.value++;
  }

  /// 侧栏「更新订阅」:拉最新节点+规则。有本账号订阅就 in-place 刷新(同「我的」页一致,
  /// 保留选中);无订阅则走一键导入。结果弹 toast。
  Future<void> _updateSubscription(WidgetRef ref) async {
    final vog = ref.read(profilesProvider).where(isVogueslyProfile);
    final ok = vog.isEmpty
        ? await importVogueslySubscription()
        : await ref
            .read(profilesActionProvider.notifier)
            .refreshVogueslyProfile(vog.first, showLoading: true);
    // [0.9.80] 未有套餐唔係「更新失败」:改弹开通引导
    if (!ok && vogueslyGuideIfNoPlan()) return;
    globalState.showNotifier(ok ? currentAppLocalizations.vgSubscriptionUpdated : currentAppLocalizations.vgUpdateFailedRetry);
  }

  /// 侧栏「登出」:确认后关半框 overlay → 先删本账号订阅(防换账号串号)→ 清登录态。
  /// 与 tools.dart / profiles.dart 登出共用同一清理逻辑,杜绝匹配器漂移。
  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(currentAppLocalizations.vgSignOut),
        content: Text(currentAppLocalizations.vgSignOutConfirmShort),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(currentAppLocalizations.vgCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(currentAppLocalizations.vgExit),
          ),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(contentOverlayProvider.notifier).close();
    // 连保活中嘅客服一齐销毁(cs 页 URL 带 email,唔可以留到下个账号)。
    // csAliveProvider 本身亦会听 token 变化兜底其他登出路径;呢度先即刻拆,唔使等清订阅。
    ref.read(csAliveProvider.notifier).destroy();
    await clearVogueslyProfiles();
    ref.read(vogueslyAuthProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigationState = ref.watch(navigationStateProvider);
    final navigationItems = navigationState.navigationItems;
    final isMobileView = navigationState.viewMode == ViewMode.mobile;
    if (isMobileView) {
      return child;
    }
    final currentIndex = navigationState.currentIndex;
    final overlay = ref.watch(contentOverlayProvider);
    final updateVersion = ref.watch(vogueslyUpdateVersionProvider);
    // 侧栏常显文字(Sam 要求:图标一定加文字,唔好净图标)。
    const showLabel = true;
    return Row(
      children: [
        _buildBackground(
          context: context,
          child: SafeArea(
            child: Column(
              // ⚠️ 必须 center:呢个 Column 系 content-sized(宽度由最阔子=NavigationRail 决定),
              // 用 stretch/SizedBox(infinity) 会喺宽度未定阶段畀子 unbounded 宽 → invalid matrix 黑屏。
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (system.isMacOS) const SizedBox(height: 22),
                const SizedBox(height: 10),
                // 品牌:D-v 图标 +(展开时)Voguesly 易联
                const ClipRect(child: AppIcon()),
                if (showLabel) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Voguesly',
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: context.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    '易联',
                    style: context.textTheme.labelSmall?.copyWith(
                      color: context.colorScheme.primary,
                      letterSpacing: 2,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // ⚠️ 顶部导航 + 底部菜单(购买/邀请/用户中心/客服)合并成**单一可滚动列表**:
                // 拉窄窗口时整条一齐滚,唔会两组重叠割裂(Sam 反馈)。
                Expanded(
                  child: ScrollConfiguration(
                    behavior: HiddenBarScrollBehavior(),
                    child: SingleChildScrollView(
                      // ⚠️ 固定宽度锚定:侧栏 Column 系 content-sized,冇呢个 stretch 会畀子 unbounded 宽→黑屏。
                      child: SizedBox(
                        width: 196,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                          for (var i = 0; i < navigationItems.length; i++)
                            _SidebarNavRow(
                              // [0.9.83] 新手引导用嘅定位 key(桌面一套)
                              key: vogueslyTourDesktopNavKeys[navigationItems[i].label],
                              icon: navigationItems[i].icon,
                              label: vogueslyNavLabel(navigationItems[i].label, desktop: true),
                              selected: i == currentIndex,
                              showLabel: showLabel,
                              accent: navigationItems[i].label == PageLabel.support,
                              onTap: () =>
                                  _handleToPage(navigationItems[i].label),
                            ),
                          const SizedBox(height: 8),
                          const Divider(height: 1, indent: 12, endIndent: 12),
                          const SizedBox(height: 8),
                          // 底部快捷:全部**半框**(只覆盖右边内容区,左侧栏保留可点)。
                          // 「购买套餐」已升为顶层 nav tab(上方),此处不再重复。
                          // 「更新订阅」升一级入口(Sam 要求常驻好找):复用「我的」页同一
                          // refreshVogueslyProfile / importVogueslySubscription 逻辑,拉最新节点+规则。
                          _SidebarLink(
                            icon: Icons.cloud_sync_outlined,
                            label: currentAppLocalizations.vgUpdateSubscription,
                            showLabel: showLabel,
                            onTap: () => _updateSubscription(ref),
                          ),
                          _SidebarLink(
                            icon: Icons.card_giftcard_outlined,
                            label: currentAppLocalizations.vgReferralRewards,
                            showLabel: showLabel,
                            selected: overlay == ContentOverlay.invite,
                            onTap: () => ref
                                .read(contentOverlayProvider.notifier)
                                .set(ContentOverlay.invite),
                          ),
                          // [0.9.83] 删「用户中心」:同「账户与设置」重复,撳首页账号卡一样入到(ContentOverlay.userCenter 保留)
                          _SidebarLink(
                            icon: Icons.campaign_outlined,
                            label: currentAppLocalizations.vgAnnouncements,
                            showLabel: showLabel,
                            dot: ref.watch(vogueslyNoticeUnreadProvider),
                            selected: overlay == ContentOverlay.notice,
                            onTap: () => ref
                                .read(contentOverlayProvider.notifier)
                                .set(ContentOverlay.notice),
                          ),
                          // [2026-09-18 减法] 「流量明细」快捷删走(仪表盘账号卡已有用量,ContentOverlay.stat 仍可由用户中心入);
                          // 「在线客服」由快捷升做上方一级 nav(PageLabel.support),呢度唔再重复。
                          // 「检查更新」**常驻**。
                          // ⚠️ 2026-08-05 初版写成 `if (updateVersion != null)` 先出现,
                          // 结果係:已经喺最新版嘅用户(即大多数)**永远见唔到呢个入口**,
                          // 连「想手动查一次」都做唔到,亦无从知道功能有冇喺度行 —— Sam 第一时间
                          // 就问「点解冇」。呢个係错嘅设计:入口应该常驻,状态先至变。
                          // 平时 = 「检查更新」普通样式;静默检查到新版 = 高亮 +「有新版本 x.x.x」。
                          // 两种状态撳落去都係行现成嘅 manualCheckUpdate(有新版弹版本说明+下载,
                          // 冇新版弹「已是最新」),唔另开一套更新流程免得行为唔一致。
                          _SidebarLink(
                            icon: Icons.system_update_alt_rounded,
                            label: updateVersion != null
                                ? currentAppLocalizations.vgNewVersionAvailable(updateVersion)
                                : currentAppLocalizations.vgCheckForUpdate,
                            showLabel: showLabel,
                            highlight: updateVersion != null,
                            // [0.9.83 Sam] 下面细字显示当前版本号,用户同客服一眼对得上版本
                            sublabel: currentAppLocalizations.vgCurrentVersionWith(
                                globalState.packageInfo.version),
                            onTap: () => ref
                                .read(commonActionProvider.notifier)
                                .manualCheckUpdate(),
                          ),
                          const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // 登出:钉喺侧栏最底(scroll 之外常显),红色次要样式,同功能项用分隔线分开。
                // 多账号用户唔使深入「设置」揾退出。复用 tools/profiles 同一清理(防串号)。
                // 宽度 196 同上方 nav 列对齐(showLabel 恒真,唔用三元免 dead_code)。
                SizedBox(
                  width: 196,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Divider(height: 1, indent: 12, endIndent: 12),
                      const SizedBox(height: 4),
                      _SidebarLink(
                        icon: Icons.logout,
                        label: currentAppLocalizations.vgLogOut,
                        showLabel: showLabel,
                        danger: true,
                        onTap: () => _confirmLogout(context, ref),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: ClipRect(
            // 半框:购买套餐/邀请/用户中心/客服 都只覆盖右边内容区,左侧栏保留可点(Sam 要求)。
            child: Stack(
              children: [
                LayoutBuilder(
                  builder: (_, constraints) {
                    _updateSideBarWidth(ref, constraints.maxWidth);
                    return child;
                  },
                ),
                if (overlay != ContentOverlay.none)
                  Positioned.fill(
                    child: ContentOverlayScope(
                      close: () =>
                          ref.read(contentOverlayProvider.notifier).close(),
                      child: switch (overlay) {
                        ContentOverlay.shop => const VogueslyShopPage(),
                        ContentOverlay.invite => const VogueslyInvitePage(),
                        ContentOverlay.userCenter =>
                          const VogueslyUserCenterPage(),
                        ContentOverlay.cs => const VogueslyCsPanel(),
                        ContentOverlay.notice => const VogueslyNoticePage(),
                        ContentOverlay.stat => const VogueslyStatPage(),
                        ContentOverlay.none => const SizedBox.shrink(),
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool showLabel;
  final bool selected; // 半框 overlay 打开时高亮对应项
  final bool danger; // 危险/次要样式(登出):红色文字图标,同功能项区分
  final bool highlight; // 主动引导样式(有新版本):主色 + 加粗,平时唔用
  final bool dot; // [0.9.82] 未读红点(公告)
  final String? sublabel; // [0.9.83] 第二行细字(检查更新 → 当前版本号)
  final VoidCallback onTap;
  const _SidebarLink({
    required this.icon,
    required this.label,
    required this.showLabel,
    required this.onTap,
    this.selected = false,
    this.danger = false,
    this.highlight = false,
    this.dot = false,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final color = danger
        ? cs.error
        : highlight
        ? cs.primary
        : (selected ? cs.onSecondaryContainer : cs.onSurfaceVariant);
    void open() => onTap();
    if (showLabel) {
      // 左对齐(对齐顶部 NavigationRail 图标 ~22px):Align(centerLeft) 撑满宽再靠左,
      // 内容 Row 用 mainAxisSize.min。⚠️ 唔用 Expanded/SizedBox(infinity)(会 unbounded 宽黑屏)。
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: selected
                ? cs.secondaryContainer
                : highlight
                // 有新版本:淡主色底,喺一列灰字入面一眼睇到,但唔会抢过大圆圈。
                ? cs.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: open,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Badge(
                      isLabelVisible: dot,
                      smallSize: 8,
                      child: Icon(icon, size: 22, color: color),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: context.textTheme.labelLarge?.copyWith(
                                color: color,
                                fontWeight: (selected || highlight)
                                    ? FontWeight.w700
                                    : FontWeight.w500)),
                        if (sublabel != null)
                          Text(sublabel!,
                              style: context.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                                  fontFeatures: const [FontFeature.tabularFigures()])),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: label,
      onPressed: open,
      icon: Badge(
        isLabelVisible: dot,
        smallSize: 8,
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }
}

/// 侧栏顶部导航行(带选中态)。同底部 _SidebarLink 一齐放喺单一滚动列表,防拉窄重叠。
class _SidebarNavRow extends StatelessWidget {
  final Widget icon; // navigationItems 的 icon 系 Widget
  final String label;
  final bool selected;
  final bool showLabel;
  final bool accent; // [0.9.83] 在线客服:未选中都用主色 + 淡紫底,一眼揾到
  final VoidCallback onTap;
  const _SidebarNavRow({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.showLabel,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final fg = selected
        ? cs.onSecondaryContainer
        : (accent ? cs.primary : cs.onSurfaceVariant);
    final content = Padding(
      padding: EdgeInsets.symmetric(
          horizontal: 14, vertical: showLabel ? 11 : 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme.merge(
            data: IconThemeData(size: 22, color: fg),
            child: accent
                ? Badge(smallSize: 7, backgroundColor: const Color(0xFF22C55E), child: icon)
                : icon,
          ),
          if (showLabel) ...[
            const SizedBox(width: 14),
            Text(label,
                style: context.textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: (selected || accent) ? FontWeight.w700 : FontWeight.w500)),
          ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected
            ? cs.secondaryContainer
            : (accent ? cs.primary.withValues(alpha: 0.10) : Colors.transparent),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: showLabel
              ? Align(alignment: Alignment.centerLeft, child: content)
              : Center(child: content),
        ),
      ),
    );
  }
}
