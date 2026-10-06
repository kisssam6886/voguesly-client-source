import 'package:flutter/material.dart';
import 'package:fl_clash/common/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'voguesly_api.dart';
import 'voguesly_auth.dart';
import 'voguesly_payment.dart';
import 'voguesly_subscription.dart';
import 'voguesly_ui.dart';
import 'voguesly_user_center.dart'; // VogueslyOrdersPage(我的订单入口)

enum _PendingChoice { none, payOld, cancelledOld }

/// 套餐卖点副标题:后端 plan.content 去 HTML + 去 Markdown 符号,留前两行(信任锚 + 卖点)。
/// [0.9.98 Sam「真系够丑」] content 係 Markdown 原文(`>` 引用、`**` 粗体、`##` 标题),之前只剥 HTML ⇒ 符号原样显示。
@visibleForTesting
String? vogueslyPlanSubtitle(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  // 块级/换行标签 → 换行,再剥其余标签,解常见实体。
  final text = raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
  String md(String l) => l
      .replaceAll(RegExp(r'^\s*(>\s*)+'), '') // 引用
      .replaceAll(RegExp(r'^\s*#{1,6}\s+'), '') // 标题
      .replaceAll(RegExp(r'^\s*([-*+]|\d+[.)])\s+'), '') // 列表
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '') // 图片
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!) // 链接留文字
      .replaceAllMapped(RegExp(r'(\*\*|__|~~)(.+?)\1'), (m) => m[2]!) // 粗体 / 删除线
      .replaceAllMapped(RegExp(r'(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])'), (m) => m[1]!) // 斜体
      .replaceAll('`', '')
      .replaceAll('**', '') // 唔配对嘅残留
      .trim();
  final lines = text
      .split('\n')
      .map(md)
      .where((e) => e.isNotEmpty && !RegExp(r'^[-*_]{3,}$').hasMatch(e))
      .toList();
  if (lines.isEmpty) return null;
  // 最多两行(信任锚 + 卖点),避免卡片过长。
  return lines.take(2).join('\n');
}

/// [0.9.98] 服务端拒单原因识别(XBoard 只返文案、冇错误码)。
/// 「你当前有生效中的订阅」= 易联 override 嘅替换确认(两种情况都以呢句开头,见 OrderController::save)。
@visibleForTesting
bool vogueslyIsReplaceConfirm(String message) =>
    message.trimLeft().startsWith('你当前有生效中的订阅');

/// XBoard 原生「You have an unpaid or pending order…」,按请求语言可能返中 / 繁 / 英。
@visibleForTesting
bool vogueslyIsPendingOrder(String message) =>
    message.contains('未付款或开通中') ||
    message.contains('未付款或開通中') ||
    message.toLowerCase().contains('unpaid or pending order');

/// 易联 · 原生商城页(照 NinjaDesktop 做法:全原生直调 XBoard API,唔用 webview)。
///
/// 流程:plan/fetch 列套餐 → 点套餐弹「选周期」原生弹窗 → 点周期立即购买 →
///      order/save 下单 → 弹「选支付方式」原生弹窗 → order/checkout
///      (余额直扣 / 跳外部支付宝-微信 + 后台 order/check 轮询到账)。
/// 只有最后真支付先跳外部浏览器,前面全部内嵌原生。
class VogueslyShopPage extends ConsumerStatefulWidget {
  const VogueslyShopPage({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VogueslyShopPage()),
    );
  }

  @override
  ConsumerState<VogueslyShopPage> createState() => _VogueslyShopPageState();
}

class _VogueslyShopPageState extends ConsumerState<VogueslyShopPage> {
  bool _loading = true;
  String? _error;
  List<VogueslyPlan> _plans = const [];
  int _balanceCents = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = ref.read(vogueslyAuthProvider).token;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _error = currentAppLocalizations.vgNotSignedInPleaseSignIn;
      });
      return;
    }
    final api = ref.read(vogueslyApiProvider);
    try {
      final results = await Future.wait([
        api.fetchPlans(token),
        api.fetchBalanceCents(token),
      ]);
      if (!mounted) return;
      final plans = results[0] as List<VogueslyPlan>;
      final bal = results[1] as int?;
      setState(() {
        _plans = plans;
        _balanceCents = bal ?? 0;
        _loading = false;
        _error = plans.isEmpty ? currentAppLocalizations.vgNoPlansAvailable : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = currentAppLocalizations.vgLoadFailedWith(e);
      });
    }
  }

  String get _balanceText => '¥${(_balanceCents / 100).toStringAsFixed(2)}';

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: vogAppBar(
        context,
        title: currentAppLocalizations.vgStore,
        actions: [
          IconButton(
            tooltip: currentAppLocalizations.vgRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // 余额卡
            Card(
              color: cs.primary.withValues(alpha: 0.08),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        color: cs.primary),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(currentAppLocalizations.vgAccountBalance,
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 2),
                        Text(_balanceText,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Spacer(),
                    Text(currentAppLocalizations.vgManageBalanceAndPlan,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 我的订单入口(Sam:支付唔成功唔使去 设置→用户中心 咁远揾,商城顶直接入,继续付)。
            Card(
              elevation: 0,
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              child: ListTile(
                leading: Icon(Icons.receipt_long_outlined, color: cs.primary),
                title: Text(currentAppLocalizations.vgMyOrders),
                subtitle: Text(currentAppLocalizations.vgViewOrdersResumePayment),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => VogueslyOrdersPage.open(context),
              ),
            ),
            const SizedBox(height: 18),
            Text(currentAppLocalizations.vgPlan,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _plans.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.inbox_outlined, size: 40),
                      const SizedBox(height: 10),
                      Text(_error!, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              )
            else
              // 响应式:窄屏一列,宽屏两列自适应(桌面窗口够宽时并排)。
              LayoutBuilder(
                builder: (ctx, c) {
                  final cols = c.maxWidth >= 760 ? 2 : 1;
                  const gap = 14.0;
                  final w = (c.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: _plans
                        .map((p) => SizedBox(width: w, child: _planCard(p)))
                        .toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 套餐卖点副标题:取后端 plan.content(信任锚 + 一句卖点)去 HTML 标签后,
  /// 保留前几行做简洁副标题。空则返 null(唔占位)。
  String? _planSubtitle(VogueslyPlan p) => vogueslyPlanSubtitle(p.content);

  Widget _planBadge(String text, {required bool highlight}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: highlight ? cs.primary : cs.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: highlight ? cs.onPrimary : cs.onSecondaryContainer,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _tag(String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }

  Widget _planCard(VogueslyPlan p) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openPlanSheet(p),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(p.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  // [0.9.98] 后台标签(「推荐」用主色高亮,其他用淡色)
                  for (final t in p.tags) _planBadge(t, highlight: t == '推荐' || t == '推薦'),
                ],
              ),
              // 卖点副标题(后端 plan.content:🏠 住宅IP · 🧠 直连 · 🔒 纯净 + 卖点)。
              if (_planSubtitle(p) case final sub?) ...[
                const SizedBox(height: 6),
                Text(sub,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant, height: 1.35)),
              ],
              const SizedBox(height: 6),
              Text(currentAppLocalizations.vgNBillingCycles(p.periods.length),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _tag(currentAppLocalizations.vgTrafficNGb(p.transferEnableGb)),
                  if (p.speedLimit != null && p.speedLimit! > 0)
                    _tag(currentAppLocalizations.vgSpeedLimitNMbps(p.speedLimit ?? 0)),
                  _tag(p.periods.first.durationText == currentAppLocalizations.vgOneTime
                      ? currentAppLocalizations.vgOneTime
                      : currentAppLocalizations.vgDurationWith(p.periods.first.durationText)),
                ],
              ),
              const SizedBox(height: 14),
              Text(p.priceRangeText,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: cs.primary, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openPlanSheet(p),
                  icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                  label: Text(currentAppLocalizations.vgBuyNow),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 弹窗 1:选周期 ----
  void _openPlanSheet(VogueslyPlan p) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(currentAppLocalizations.vgChooseBillingCycle,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: p.periods
                        .map((period) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _periodCard(p, period),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _periodCard(VogueslyPlan p, VogueslyPlanPeriod period) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(period.label,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(period.priceText,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: cs.primary, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _tag(currentAppLocalizations.vgTrafficNGb(p.transferEnableGb)),
                if (period.days > 0) _tag(currentAppLocalizations.vgDurationWith(period.durationText)),
                if (p.speedLimit != null && p.speedLimit! > 0)
                  _tag(currentAppLocalizations.vgSpeedLimitNMbps(p.speedLimit ?? 0)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _placeOrder(p, period),
                child: Text(currentAppLocalizations.vgBuyNowWith(period.priceText)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 下单 → 弹窗 2:选支付方式 ----
  Future<void> _placeOrder(VogueslyPlan p, VogueslyPlanPeriod period) async {
    final token = ref.read(vogueslyAuthProvider).token;
    if (token == null || token.isEmpty) {
      _toast(currentAppLocalizations.vgNotSignedIn);
      return;
    }
    Navigator.of(context).pop(); // 关周期弹窗
    final tradeNo = await _createOrderWithRecovery(token, p, period);
    if (tradeNo == null || !mounted) return;
    // 共享支付流程(同「我的订单·继续支付」一套)。
    await VogueslyPayment.present(
      context: context,
      ref: ref,
      tradeNo: tradeNo,
      priceCents: period.priceCents,
      title: '${p.name} · ${period.label}  ${period.priceText}',
      onPaid: _afterPaid,
    );
  }

  /// [0.9.98] 下单 + 两种「被拒」嘅补救,唔再只 toast 就死路:
  ///   ① 有生效订阅买一次性套餐 ⇒ 服务端要确认替换 ⇒ 原文弹确认框,确认后带 confirm_replace 重下;
  ///   ② 已有未付款订单 ⇒ 列出嗰张单,畀「继续支付」或「取消它,下新单」;开通中嘅单只能等。
  /// 返回新单 trade_no;用户改为继续付旧单 / 取消 / 失败都返 null(调用方唔再继续)。
  Future<String?> _createOrderWithRecovery(
      String token, VogueslyPlan p, VogueslyPlanPeriod period) async {
    final api = ref.read(vogueslyApiProvider);
    final l = currentAppLocalizations;
    var confirmReplace = false;
    var cancelledOld = false;
    for (var attempt = 0; attempt < 3; attempt++) {
      _showBlockingProgress(l.vgPlacingOrder);
      final order = await api.createOrder(token,
          planId: p.id, period: period.key, confirmReplace: confirmReplace);
      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // 关进度
      if (!mounted) return null;
      if (order.tradeNo != null) return order.tradeNo;
      final err = order.error ?? l.vgOrderFailed;
      if (!confirmReplace && vogueslyIsReplaceConfirm(err)) {
        if (!await _confirmReplace(err)) return null;
        confirmReplace = true;
        continue;
      }
      if (!cancelledOld && vogueslyIsPendingOrder(err)) {
        final resolved = await _resolvePendingOrder(token);
        if (resolved != _PendingChoice.cancelledOld) return null;
        cancelledOld = true;
        continue;
      }
      _toast(err);
      return null;
    }
    return null;
  }

  Future<bool> _confirmReplace(String serverMessage) async {
    final l = currentAppLocalizations;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.vgReplaceConfirmTitle),
        // 服务端原文:讲清楚会替换 / 剩余价值点计,唔喺客户端重写一套(两边口径一致)
        content: SingleChildScrollView(child: Text(serverMessage)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.vgCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.vgReplaceConfirmAction)),
        ],
      ),
    );
    return ok == true;
  }

  Future<_PendingChoice> _resolvePendingOrder(String token) async {
    final api = ref.read(vogueslyApiProvider);
    final l = currentAppLocalizations;
    _showBlockingProgress(l.vgPlacingOrder);
    final orders = await api.fetchOrders(token);
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!mounted) return _PendingChoice.none;
    final pending = orders.where((o) => o.status == 0).toList();
    if (pending.isEmpty) {
      // 冇待付款但服务端仍拒 ⇒ 多数係「开通中」,只能等
      _toast(orders.any((o) => o.status == 1) ? l.vgOrderActivatingWait : l.vgOrderFailed);
      return _PendingChoice.none;
    }
    final o = pending.first;
    final choice = await showDialog<_PendingChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.vgPendingOrderTitle),
        content: Text(l.vgPendingOrderBody(o.planName, o.amountText)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, _PendingChoice.none), child: Text(l.vgCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, _PendingChoice.cancelledOld), child: Text(l.vgPendingCancelAndNew)),
          FilledButton(onPressed: () => Navigator.pop(ctx, _PendingChoice.payOld), child: Text(l.vgPendingContinuePay)),
        ],
      ),
    );
    if (!mounted) return _PendingChoice.none;
    if (choice == _PendingChoice.payOld) {
      await VogueslyPayment.present(
        context: context,
        ref: ref,
        tradeNo: o.tradeNo,
        priceCents: o.totalCents,
        title: '${o.planName}  ${o.amountText}',
        onPaid: _afterPaid,
      );
      return _PendingChoice.payOld;
    }
    if (choice == _PendingChoice.cancelledOld) {
      _showBlockingProgress(l.vgPlacingOrder);
      final ok = await api.cancelOrder(token, o.tradeNo);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!ok) {
        _toast(l.vgCancelOldOrderFailed);
        return _PendingChoice.none;
      }
      return _PendingChoice.cancelledOld;
    }
    return _PendingChoice.none;
  }

  // 支付成功后:刷新账号套餐 + 重导订阅(拉最新节点)+ 刷新商城余额,然后返回主页。
  Future<void> _afterPaid() async {
    try {
      await ref.read(vogueslyAuthProvider.notifier).refreshUser();
    } catch (_) {}
    try {
      // 新套餐/续费后订阅节点会变,重导一次(内部并发互斥,安全)。
      await importVogueslySubscription();
    } catch (_) {}
    if (!mounted) return;
    await _load();
    if (mounted) Navigator.of(context).maybePop();
  }

  void _showBlockingProgress(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 18),
            Expanded(child: Text(msg)),
          ],
        ),
      ),
    );
  }
}
