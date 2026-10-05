import 'package:fl_clash/common/constant.dart' show vogueslyInviteBase;
import 'package:flutter/material.dart';
import 'package:fl_clash/common/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'voguesly_api.dart';
import 'voguesly_auth.dart';
import 'voguesly_ui.dart';

/// 易联 · 原生邀请返利页(照商城做法,直调 XBoard /user/invite/*,唔用 webview)。
class VogueslyInvitePage extends ConsumerStatefulWidget {
  const VogueslyInvitePage({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VogueslyInvitePage()),
    );
  }

  @override
  ConsumerState<VogueslyInvitePage> createState() => _VogueslyInvitePageState();
}

class _VogueslyInvitePageState extends ConsumerState<VogueslyInvitePage> {
  bool _loading = true;
  String? _error;
  VogueslyInviteData? _data;
  // [0.9.84] 提现方式 / 门槛 / 结算比例全部跟后端(/user/comm/config),唔再写死「支付宝 / 微信 / USDT」。
  VogueslyCommConfig? _comm;

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
        _error = currentAppLocalizations.vgNotSignedIn;
      });
      return;
    }
    final api = ref.read(vogueslyApiProvider);
    var data = await api.fetchInviteData(token);
    // 未有邀请码 → 生成一个再拉。
    if (data != null && (data.firstCode == null)) {
      final ok = await api.generateInviteCode(token);
      if (ok) data = await api.fetchInviteData(token);
    }
    // 可用佣金以 /user/info 嘅 commission_balance 为准(同面板);攞唔到就用 invite stat[4]。
    final extra = await Future.wait([
      api.fetchCommissionBalanceCents(token),
      api.fetchCommConfig(token),
    ]);
    data = data?.withAvailable(extra[0] as int?);
    if (!mounted) return;
    setState(() {
      _data = data;
      _comm = extra[1] as VogueslyCommConfig?;
      _loading = false;
      _error = data == null ? currentAppLocalizations.vgLoadFailedPullToRetry : null;
    });
  }

  String get _inviteLink {
    final code = _data?.firstCode;
    // [0.9.87] 唔再直写面板域名:邀请链接会畀用户公开转发(ylink.im 主域就係咁被封)。
    //   用专门可弃域 join.hazu.world(橙云,302 去面板注册页带码,跟 panel-target.conf 走);
    //   基址可由 version.json 嘅 invite_base 覆盖 ⇒ 邀请域出事换域唔使发版。
    //   ⚠️ 注册页由 hash 读邀请码:服务端 302 去 `#/register?code=`,唔好「统一格式」改成 ?code=…#/register。
    if (code == null) return '';
    // 基址由 version.json 下发(见 vogueslyInviteBase),读唔到用常量 join.hazu.world;统一喺后面加 ?code=。
    final base = Uri.parse(vogueslyInviteBase);
    return base.replace(queryParameters: {...base.queryParameters, 'code': code}).toString();
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(currentAppLocalizations.vgCopiedSuffix(label)), behavior: SnackBarBehavior.floating),
    );
  }

  String _yuan(int cents) => '¥${(cents / 100).toStringAsFixed(2)}';

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  // 佣金划转到余额(默认全部)。
  Future<void> _transfer() async {
    final avail = _data?.commissionCents ?? 0;
    final ctrl = TextEditingController(text: (avail / 100).toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(currentAppLocalizations.vgTransferToBalance),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(currentAppLocalizations.vgAvailableCommissionWith(_yuan(avail))),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: currentAppLocalizations.vgTransferAmountYuan, prefixText: '¥'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(currentAppLocalizations.vgCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(currentAppLocalizations.vgTransfer)),
        ],
      ),
    );
    if (ok != true) return;
    final cents = ((double.tryParse(ctrl.text) ?? 0) * 100).round();
    if (cents <= 0 || cents > avail) {
      _toast(currentAppLocalizations.vgInvalidAmount);
      return;
    }
    final token = ref.read(vogueslyAuthProvider).token;
    if (token == null) return;
    final res =
        await ref.read(vogueslyApiProvider).transferCommission(token, cents);
    _toast(res.message);
    if (res.ok) _load();
  }

  // 提现:选方式 + 填收款账号(建工单,客服处理)。
  // 方式只可以揀后端 withdraw_methods 入面嘅(后端会校验,之前默认填「支付宝」而后端只收 USDT 就会失败);
  // 未满门槛 / 暂停提现就唔开弹窗,直接讲原因。
  Future<void> _withdraw() async {
    final comm = _comm;
    final avail = _data?.commissionCents ?? 0;
    if (comm != null && comm.withdrawClosed) {
      _toast(currentAppLocalizations.vgWithdrawClosed);
      return;
    }
    final minCents = comm?.minWithdrawCents;
    if (minCents != null && avail < minCents) {
      _toast(currentAppLocalizations.vgBelowMinWithdrawWith(_yuan(minCents)));
      return;
    }
    final methods = comm?.withdrawMethods ?? const <String>[];
    var method = methods.isEmpty ? '' : methods.first;
    final methodC = TextEditingController();
    final accountC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(currentAppLocalizations.vgWithdrawRequest),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(currentAppLocalizations.vgAvailableCommissionWith(_yuan(avail))),
            if (_settleText != null) ...[
              const SizedBox(height: 6),
              Text(_settleText!, style: Theme.of(dctx).textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            // 后端有列方式就只畀揀(冇得乱填);攞唔到设定先退返手填。
            if (methods.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: InputDecoration(
                    labelText: currentAppLocalizations.vgWithdrawMethod),
                items: [
                  for (final m in methods)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) => method = v ?? method,
              )
            else
              TextField(
                  controller: methodC,
                  decoration: InputDecoration(
                      labelText: currentAppLocalizations.vgWithdrawMethod)),
            TextField(
                controller: accountC,
                decoration: InputDecoration(labelText: currentAppLocalizations.vgPayoutAccount)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(currentAppLocalizations.vgCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(currentAppLocalizations.vgSubmit)),
        ],
      ),
    );
    if (ok != true) return;
    if (accountC.text.trim().isEmpty) {
      _toast(currentAppLocalizations.vgEnterPayoutAccount);
      return;
    }
    final token = ref.read(vogueslyAuthProvider).token;
    if (token == null) return;
    final chosen = methods.isNotEmpty ? method : methodC.text.trim();
    if (chosen.isEmpty) {
      _toast(currentAppLocalizations.vgWithdrawMethod);
      return;
    }
    final res = await ref.read(vogueslyApiProvider).withdraw(token,
        method: chosen, account: accountC.text.trim());
    _toast(res.message);
    if (res.ok) _load();
  }

  /// 「划转全额;提现按订单实付 x% 结算」—— 比例同手续费都由后端返(佣金比例 stat[3] + commission_withdraw_fee)。
  String? get _settleText {
    final pct = _comm?.settlePercent(_data?.commissionRate ?? 0);
    return pct == null ? null : currentAppLocalizations.vgWithdrawSettleWith(pct);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final code = _data?.firstCode;
    return Scaffold(
      appBar: vogAppBar(
        context,
        title: currentAppLocalizations.vgReferralRewards,
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
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_error != null && _data == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: Text(_error!)),
                    )
                  else ...[
                    // 佣金 + 邀请人数 两卡并排
                    Row(
                      children: [
                        Expanded(
                          child: _statCard(
                            icon: Icons.savings_outlined,
                            label: currentAppLocalizations.vgAvailableCommission,
                            value: _yuan(_data?.commissionCents ?? 0),
                            color: cs.primary,
                            // 确认中(未过结算期)嘅佣金分开显示,唔再当可用
                            note: (_data?.pendingCents ?? 0) > 0
                                ? currentAppLocalizations.vgPendingCommissionWith(
                                    _yuan(_data!.pendingCents))
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _statCard(
                            icon: Icons.group_outlined,
                            label: currentAppLocalizations.vgInvited,
                            value: currentAppLocalizations.vgNPeople(_data?.inviteCount ?? 0),
                            color: cs.tertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 佣金操作:划转到余额(原生)/ 提现(原生工单)。从 ylink.im/#/invite 移入。
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: (_data?.commissionCents ?? 0) > 0
                                ? _transfer
                                : null,
                            icon: const Icon(Icons.swap_horiz, size: 18),
                            label: Text(currentAppLocalizations.vgTransferToBalance),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: (_data?.commissionCents ?? 0) > 0
                                ? _withdraw
                                : null,
                            icon: const Icon(Icons.account_balance, size: 18),
                            label: Text(currentAppLocalizations.vgWithdraw),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(currentAppLocalizations.vgMyReferralCode,
                        style: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    // 邀请码大字 + 复制
                    Card(
                      color: cs.primary.withValues(alpha: 0.08),
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                code ?? '—',
                                style: tt.headlineSmall?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2),
                              ),
                            ),
                            if (code != null)
                              TextButton.icon(
                                onPressed: () => _copy(code, currentAppLocalizations.vgReferralCode),
                                icon: const Icon(Icons.copy, size: 18),
                                label: Text(currentAppLocalizations.vgCopy),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(currentAppLocalizations.vgReferralLink,
                        style: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              _inviteLink.isEmpty ? '—' : _inviteLink,
                              maxLines: 2,
                              style: tt.bodyMedium,
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _inviteLink.isEmpty
                                    ? null
                                    : () => _copy(_inviteLink, currentAppLocalizations.vgReferralLink),
                                icon: const Icon(Icons.link, size: 18),
                                label: Text(currentAppLocalizations.vgCopyReferralLink),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      [
                        (_data?.commissionRate ?? 0) > 0
                            ? currentAppLocalizations
                                .vgCommissionRateWith(_data!.commissionRate)
                            : currentAppLocalizations.vgReferralExplain,
                        ?_settleText,
                        if (_comm?.minWithdrawCents != null)
                          currentAppLocalizations
                              .vgMinWithdrawWith(_yuan(_comm!.minWithdrawCents!)),
                        if (_comm?.withdrawClosed == true)
                          currentAppLocalizations.vgWithdrawClosed,
                      ].join('\n'),
                      style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    String? note,
  }) {
    final tt = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 10),
            Text(value,
                style: tt.headlineSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: tt.bodySmall),
            if (note != null) ...[
              const SizedBox(height: 2),
              Text(note,
                  style: tt.labelSmall
                      ?.copyWith(color: color.withValues(alpha: 0.8))),
            ],
          ],
        ),
      ),
    );
  }
}
