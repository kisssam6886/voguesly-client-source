import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../voguesly/voguesly_auth.dart';
import '../../../voguesly/voguesly_avatar.dart';
import '../../../voguesly/voguesly_overlay.dart';
import '../../../voguesly/voguesly_noplan.dart';
import '../../../voguesly/voguesly_shop.dart';
import '../../../voguesly/voguesly_subscription.dart';
import '../../../voguesly/voguesly_user_center.dart';

/// 仪表盘「易聯 账号」大卡：可选头像 + 用户名(email) + 剩余/总流量(进度条) + 到期 + 已用。
/// 数据来自 vogueslyAuthProvider(登录后 getUserInfo 缓存)，头像来自 vogueslyAvatarProvider。
class VogueslyAccount extends StatelessWidget {
  const VogueslyAccount({super.key});

  // <1GB 显 MB(免费测试 500MB 用户唔会见到「0.49 GB」咁掉价);≥1GB 显 1 位小数 GB。
  String _gb(int bytes) {
    if (bytes < 1073741824) {
      return '${(bytes / 1048576).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }

  void _showAvatarPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  ctx.appLocalizations.vogChooseAvatar,
                  style: ctx.textTheme.titleMedium,
                ),
              ),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: vogueslyAvatars.map((id) {
                  // [0.9.83] 当前揀紧嗰个加主色圈,一眼知道揀咗边个
                  final selected = ref.read(vogueslyAvatarProvider) == id;
                  return GestureDetector(
                    onTap: () {
                      ref.read(vogueslyAvatarProvider.notifier).select(id);
                      Navigator.of(ctx).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? ctx.colorScheme.primary
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: LayoutBuilder(
                        builder: (_, c) =>
                            VogueslyAvatarImage(id, size: c.maxWidth),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subColor = context.colorScheme.onSurfaceVariant.opacity80;
    return SizedBox(
      height: getWidgetHeight(2),
      child: RepaintBoundary(
        child: CommonCard(
          // 轻触账号卡 → 「用户中心」(账号中枢:余额/套餐/订单/邀请/重置订阅/改密码)。
          // 桌面用半框 overlay;手机无 overlay 宿主,改用全页 push。
          onPressed: () {
            final w = MediaQuery.maybeOf(context)?.size.width ?? 0;
            if (w > 0 && w < 640) {
              VogueslyUserCenterPage.open(context);
            } else {
              ProviderScope.containerOf(context, listen: false)
                  .read(contentOverlayProvider.notifier)
                  .set(ContentOverlay.userCenter);
            }
          },
          child: Consumer(
            builder: (_, ref, _) {
              final user = ref.watch(
                vogueslyAuthProvider.select((s) => s.user),
              );
              // 登录态(经登录门后基本恒 true);user==null 时区分「载入中」vs「未登录」。
              final loggedIn = ref.watch(
                vogueslyAuthProvider.select((s) => s.isLoggedIn),
              );
              final avatar = ref.watch(vogueslyAvatarProvider);
              final l = context.appLocalizations;
              // 套餐到期 / 流量耗尽:红色警示,免「假连接」用户唔知自己冇得用。
              const warnColor = Color(0xFFEF4444);
              final nowMs = DateTime.now().millisecondsSinceEpoch;
              final expired =
                  user?.expiredAt != null &&
                  user!.expiredAt! > 0 &&
                  user.expiredAt! * 1000 < nowMs;
              final exhausted =
                  user != null && user.transferEnable > 0 && user.remain <= 0;
              final warn = expired || exhausted;
              // [0.9.83 门面改版] 头像(紫色渐变圈)+ 邮箱加粗 + 套餐胶囊 + 剩余日数;
              //   剩余流量用 Gelasio 衬线大数字(同面板 Georgia 风格);渐变进度条;底行 在线设备 · 已用 / 共。
              final cs = context.colorScheme;
              final accent = warn ? warnColor : cs.primary;
              final sub = context.textTheme.bodySmall?.copyWith(
                color: subColor,
              );
              String status = l.vogPermanent;
              if (user != null && expired) {
                status = currentAppLocalizations.vgExpiredRenew;
              } else if (user != null && (user.expiredAt ?? 0) > 0) {
                final days = ((user.expiredAt! * 1000 - nowMs) / 86400000)
                    .ceil();
                status = currentAppLocalizations.vgDaysLeftWith(days);
              }
              final remain = user == null
                  ? const ['', '']
                  : _gb(user.remain).split(' ');
              return Padding(
                padding: baseInfoEdgeInsets,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // [0.9.84]「购买/续费」+「更新订阅」:够阔并排;手机(~390 宽)放唔落就上下排,
                    // 唔好同左边邮箱 / 套餐抢位挤爆。门槛跟字体缩放放大。
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final actionsInRow =
                            constraints.maxWidth >=
                            MediaQuery.textScalerOf(context).scale(420);
                        return Row(
                          children: [
                            GestureDetector(
                              onTap: () => _showAvatarPicker(context, ref),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [Color(0xFF7C3AED), Color(0xFFC4B5FD)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: VogueslyAvatarImage(avatar, size: 44),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    user?.email ??
                                        (loggedIn
                                            ? currentAppLocalizations
                                                  .vgLoadingAccount
                                            : l.vogMyAccount),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      if ((user?.planName ?? '').isNotEmpty) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: accent.withValues(alpha: 0.16),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            user!.planName!,
                                            style: context.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: accent,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Flexible(
                                        child: Text(
                                          user == null
                                              ? (loggedIn
                                                    ? currentAppLocalizations
                                                          .vgLoadingEllipsis
                                                    : '—')
                                              : status,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: sub?.copyWith(
                                            color: expired ? warnColor : subColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            _HeroActions(
                              inRow: actionsInRow,
                              buy: _HeroPill(
                                color: accent,
                                label: currentAppLocalizations.vgBuyRenewShort,
                                // 原生商城(webview 唔共享登录会弹登录页;照 Ninja 全原生)。
                                onTap: () => VogueslyShopPage.open(context),
                              ),
                              update: const _UpdateSubscriptionPill(),
                            ),
                          ],
                        );
                      },
                    ),
                    if (user != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            remain.first,
                            style: TextStyle(
                              fontFamily: 'Gelasio',
                              fontSize: 34,
                              height: 1.0,
                              fontWeight: FontWeight.w600,
                              color: accent,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            remain.length > 1 ? remain[1] : '',
                            style: TextStyle(
                              fontFamily: 'Gelasio',
                              fontSize: 15,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              expired
                                  ? currentAppLocalizations.vgExpiredRenew
                                  : exhausted
                                  ? currentAppLocalizations.vgDataExhaustedRenew
                                  : currentAppLocalizations.vgRemainLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sub?.copyWith(
                                color: warn ? warnColor : subColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      _GradientBar(value: user.remainRatio, warn: warn),
                      Row(
                        children: [
                          // 设备数占用「已用 / 共」以外全部位置(之前 Flexible + Spacer 平分,满咗嗰阵「· 已满」被切走)
                          Expanded(
                            child: Row(
                              children: [
                                if (user.aliveIp != null) ...[
                                  Icon(
                                    Icons.devices_outlined,
                                    size: 13,
                                    color: user.devicesFull
                                        ? warnColor
                                        : subColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      ((user.deviceLimit ?? 0) > 0
                                              ? currentAppLocalizations
                                                    .vgOnlineDevicesWith(
                                                      user.aliveIp!,
                                                      user.deviceLimit!,
                                                    )
                                              : currentAppLocalizations
                                                    .vgOnlineDevicesNoLimitWith(
                                                      user.aliveIp!,
                                                    )) +
                                          (user.devicesFull
                                              ? currentAppLocalizations
                                                    .vgOnlineDevicesFullShort
                                              : ''),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: sub?.copyWith(
                                        color: user.devicesFull
                                            ? warnColor
                                            : subColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            currentAppLocalizations.vgUsedOfWith(
                              _gb(user.used),
                              _gb(user.transferEnable),
                            ),
                            style: sub?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else
                      Text(
                        loggedIn
                            ? currentAppLocalizations.vgLoadingPlan
                            : l.vogNotLoggedIn,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: subColor,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// [0.9.83] 紫色渐变进度条(同面板订阅卡);流量尽 / 到期转红。
class _GradientBar extends StatelessWidget {
  const _GradientBar({required this.value, required this.warn});

  final double value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      // ⚠️ 外层 Column 係 crossAxisAlignment.start(宽度唔紧),一定要自己撑满宽度,否则成条 bar 会缩到 0。
      child: SizedBox(
        width: double.infinity,
        height: 8,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: context.colorScheme.surfaceContainerHighest,
              ),
            ),
            FractionallySizedBox(
              widthFactor: v,
              heightFactor: 1,
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: warn
                        ? const [Color(0xFFDC2626), Color(0xFFF87171)]
                        : const [Color(0xFF7C3AED), Color(0xFFA78BFA)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// hero 卡右上嘅动作按钮组:够阔并排,唔够阔上下排(同阔,睇落整齐)。
class _HeroActions extends StatelessWidget {
  final bool inRow;
  final Widget buy;
  final Widget update;
  const _HeroActions({
    required this.inRow,
    required this.buy,
    required this.update,
  });

  @override
  Widget build(BuildContext context) {
    if (inRow) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [buy, const SizedBox(width: 6), update],
      );
    }
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [buy, const SizedBox(height: 4), update],
      ),
    );
  }
}

/// hero 卡嘅胶囊按钮(同原本「购买/续费」一样嘅样式)。[onTap] 为 null = 禁用(更新中)。
class _HeroPill extends StatelessWidget {
  final Color color;
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  const _HeroPill({
    required this.color,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = context.textTheme.labelSmall?.copyWith(
      color: color,
      fontWeight: FontWeight.w600,
    );
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy) ...[
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: color,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              // ⚠️ 唔可以用 Flexible:并排时成组系外层 Row 嘅非 flex 子,宽度无界,Flexible 会报 unbounded。
              Text(
                label,
                maxLines: 1,
                style: style,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 首页 hero「更新订阅」(Sam:安卓之前要入「我的」页先更新得)。
/// 同侧栏「更新订阅」同一套逻辑:有本账号订阅 → refreshVogueslyProfile(镜像 fallback + 重载核心);
/// 冇订阅 → 一键导入。更新中(isUpdating / importing)禁用,防连撳重复拉。
class _UpdateSubscriptionPill extends ConsumerWidget {
  const _UpdateSubscriptionPill();

  Future<void> _update(WidgetRef ref, Profile? profile) async {
    // ⚠️ await 之前攞定 notifier:拉订阅要十几秒,期间卡片可能已经 rebuild / 离开页面。
    final action = ref.read(profilesActionProvider.notifier);
    final ok = profile == null
        ? await importVogueslySubscription()
        : await action.refreshVogueslyProfile(profile, showLoading: true);
    // [0.9.80] 未有套餐 / 已到期唔系「更新失败」:同侧栏一样改弹开通引导。
    if (!ok && vogueslyGuideIfNoPlan()) return;
    globalState.showNotifier(
      ok
          ? currentAppLocalizations.vgSubscriptionUpdated
          : currentAppLocalizations.vgUpdateFailedRetry,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vog = ref.watch(profilesProvider).where(isVogueslyProfile);
    final profile = vog.isEmpty ? null : vog.first;
    final importing = ref.watch(vogueslyImportingProvider);
    final updating =
        profile != null && ref.watch(isUpdatingProvider(profile.updatingKey));
    final busy = importing || updating;
    return _HeroPill(
      color: context.colorScheme.primary,
      label: busy
          ? currentAppLocalizations.vgUpdating
          : currentAppLocalizations.vgUpdateSubShort,
      busy: busy,
      onTap: busy ? null : () => _update(ref, profile),
    );
  }
}
