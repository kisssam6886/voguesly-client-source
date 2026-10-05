import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [0.9.87 Sam 09-23 定] 大圆圈右下角齿轮 → 连接设置面板(桌面右侧滑出 / 手机底部弹起)。
///
/// 点解:「连接方式」同「附加规则」原本收喺「我的 → 进阶」好深,要改嘅人揾唔到;
/// 摆返仪表盘做开关卡又变返 0.9.83 移走嘅「工程卡」。齿轮 = 默认干净,要改嘅人一撳就到。
/// - 连接方式(只限桌面):增强(TUN)/ 兼容(系统代理)二选一。安卓行系统 VPN,冇呢个分别。
/// - 附加规则:全局附加规则(唔跟订阅,重新登录重导订阅都唔会冇),插喺订阅规则之前。
///   ⚠️ 09-23 Sam 手输一条 DOMAIN-SUFFIX 令成个客户端瘫咗一日 ⇒ 呢度一律**下拉 + 校验**,
///   打唔出格式错嘅规则;目标只可以喺现有线路入面揀(task.dart 另外会跳过目标唔存在嘅规则)。
Future<void> showVogueslyQuickSettings(BuildContext context) {
  return showSheet(
    context: context,
    props: const SheetProps(isScrollControlled: true),
    builder: (_) => AdaptiveSheetScaffold(
      title: currentAppLocalizations.vgQuickSettingsTitle,
      body: const _QuickSettingsBody(),
    ),
  );
}

class _QuickSettingsBody extends StatelessWidget {
  const _QuickSettingsBody();

  @override
  Widget build(BuildContext context) {
    final l = currentAppLocalizations;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (system.isDesktop) ...[
            _SectionTitle(l.vgConnModeTitle),
            const _ConnModePicker(),
            const SizedBox(height: 20),
          ],
          _SectionTitle(l.vgExtraRulesTitle),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l.vgExtraRulesDesc,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const _ExtraRulesList(),
          const SizedBox(height: 16),
          Text(
            l.vgQuickSettingsTip,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant.opacity60,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: context.textTheme.titleSmall),
    );
  }
}

// ───────────────────────── 连接方式 ─────────────────────────

class _ConnModePicker extends ConsumerWidget {
  const _ConnModePicker();

  void _select(WidgetRef ref, bool enhanced) {
    if (enhanced) {
      // 系统代理唔喺呢度关:0.9.86 定案 —— TUN 确认接管到先由 _verifyDesktopTunConnected 关,
      // 否则 TUN 起唔到嗰三十几秒用户会「显示已连接但上唔到网」。
      final setup = ref.read(setupActionProvider.notifier);
      setup.resetTunSessionFlags();
      final already = ref.read(patchClashConfigProvider).tun.enable;
      ref
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith.tun(enable: true));
      // [0.9.88] 设定值本来已经係 true(TUN 失败后自动用紧兼容)⇒ 上面嘅 update 冇变化、唔会重新下发,手动重试一次。
      if (already) setup.updateConfigDebounce();
    } else {
      ref
          .read(networkSettingProvider.notifier)
          .update((state) => state.copyWith(systemProxy: true));
      ref
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith.tun(enable: false));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = currentAppLocalizations;
    final tun = ref.watch(patchClashConfigProvider.select((s) => s.tun.enable));
    // [0.9.88] 已连接时显示「实际」状态:TUN 失败会自动退到兼容(tun 设定值仍然係 true),
    //   之前面板照样显示「增强」而且撳唔到,用户想重试都冇办法。两者唔一致时两个都可以撳。
    final isStart = ref.watch(isStartProvider);
    final realTun = ref.watch(realTunEnableProvider);
    final enhancedNow = isStart ? realTun : tun;
    final mismatch = enhancedNow != tun;
    return Column(
      children: [
        _ModeTile(
          selected: enhancedNow,
          tappable: !enhancedNow || mismatch,
          icon: Icons.shield_outlined,
          title: l.vgConnModeEnhanced,
          desc: l.vgConnModeEnhancedDesc,
          onTap: () => _select(ref, true),
        ),
        const SizedBox(height: 8),
        _ModeTile(
          selected: !enhancedNow,
          tappable: enhancedNow || mismatch,
          icon: Icons.language,
          title: l.vgConnModeCompat,
          desc: l.vgConnModeCompatDesc,
          onTap: () => _select(ref, false),
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  final bool selected;
  final bool tappable;
  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;

  const _ModeTile({
    required this.selected,
    required this.tappable,
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return Material(
      color: selected ? cs.primaryContainer.withValues(alpha: 0.5) : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: tappable ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 16, color: cs.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Flexible(child: Text(title, style: context.textTheme.titleSmall)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      style: context.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── 附加规则 ─────────────────────────

/// 面板提供嘅四种匹配方式(其他类型喺「进阶 → 规则」完整编辑器先有)。
const List<RuleAction> kQuickRuleActions = [
  RuleAction.DOMAIN_SUFFIX,
  RuleAction.DOMAIN,
  RuleAction.DOMAIN_KEYWORD,
  RuleAction.IP_CIDR,
];

String quickRuleActionLabel(RuleAction a) {
  final l = currentAppLocalizations;
  return switch (a) {
    RuleAction.DOMAIN_SUFFIX => l.vgRuleTypeDomainSuffix,
    RuleAction.DOMAIN => l.vgRuleTypeDomain,
    RuleAction.DOMAIN_KEYWORD => l.vgRuleTypeKeyword,
    RuleAction.IP_CIDR => l.vgRuleTypeIpCidr,
    _ => a.value,
  };
}

String quickRuleTargetLabel(String target) {
  final l = currentAppLocalizations;
  return switch (target) {
    'DIRECT' => l.vgRuleTargetDirect,
    'REJECT' => l.vgRuleTargetReject,
    _ => target,
  };
}

final _domainRe = RegExp(r'^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$');
final _ipv4Re = RegExp(r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$');

/// 用户输入 → 规则内容;格式唔啱返 null。纯函数,单测见 test/voguesly/quick_rule_test.dart。
/// - 域名类:容忍用户贴成 URL(https://www.example.com/path)、大写、前面嘅 `*.` / `.`。
/// - 关键词:唔准有空白 / 逗号(逗号会整坏规则语法)。
/// - IP 段:纯 IP 自动补 /32;只收 IPv4。
String? normalizeQuickRuleContent(RuleAction action, String input) {
  var v = input.trim().toLowerCase();
  if (v.isEmpty || v.contains(',')) return null;
  switch (action) {
    case RuleAction.DOMAIN:
    case RuleAction.DOMAIN_SUFFIX:
      if (v.contains('://')) v = v.split('://')[1];
      v = v.split('/').first.split('?').first.split('#').first.split(':').first;
      if (v.startsWith('*.')) v = v.substring(2);
      if (v.startsWith('.')) v = v.substring(1);
      return _domainRe.hasMatch(v) ? v : null;
    case RuleAction.DOMAIN_KEYWORD:
      return (v.length >= 2 && v.length <= 64 && !RegExp(r'\s').hasMatch(v)) ? v : null;
    case RuleAction.IP_CIDR:
      final parts = v.split('/');
      if (parts.length > 2 || !_ipv4Re.hasMatch(parts[0])) return null;
      if (parts.length == 1) return '${parts[0]}/32';
      final bits = int.tryParse(parts[1]);
      return (bits != null && bits >= 0 && bits <= 32) ? '${parts[0]}/$bits' : null;
    default:
      return null;
  }
}

class _ExtraRulesList extends ConsumerWidget {
  const _ExtraRulesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = currentAppLocalizations;
    final rules = ref.watch(globalRulesProvider).value ?? const <Rule>[];
    final cs = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rules.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l.vgExtraRulesEmpty,
              style: context.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant.opacity60),
            ),
          ),
        for (final r in rules)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            color: cs.surfaceContainerLow,
            elevation: 0,
            child: ListTile(
              dense: true,
              title: Text(r.content ?? r.ruleProvider ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${quickRuleActionLabel(r.ruleAction)} → ${quickRuleTargetLabel(r.ruleTarget ?? '')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: context.appLocalizations.delete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  ref.read(globalRulesProvider.notifier).delAll([r.id]);
                  ref.read(setupActionProvider.notifier).reapplyRulesSoon();
                },
              ),
            ),
          ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.add),
            label: Text(context.appLocalizations.addRule),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _AddQuickRuleDialog(),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddQuickRuleDialog extends ConsumerStatefulWidget {
  const _AddQuickRuleDialog();

  @override
  ConsumerState<_AddQuickRuleDialog> createState() => _AddQuickRuleDialogState();
}

class _AddQuickRuleDialogState extends ConsumerState<_AddQuickRuleDialog> {
  RuleAction _action = RuleAction.DOMAIN_SUFFIX;
  String? _target;
  final _content = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  String get _hint => switch (_action) {
        RuleAction.DOMAIN_KEYWORD => currentAppLocalizations.vgRuleHintKeyword,
        RuleAction.IP_CIDR => currentAppLocalizations.vgRuleHintIp,
        _ => currentAppLocalizations.vgRuleHintDomain,
      };

  void _submit() {
    final l = currentAppLocalizations;
    final content = normalizeQuickRuleContent(_action, _content.text);
    if (content == null) {
      setState(() => _error = l.vgRuleInvalidContent);
      return;
    }
    if (_target == null) {
      setState(() => _error = l.vgRuleNoTarget);
      return;
    }
    ref.read(globalRulesProvider.notifier).put(
          Rule(
            // [0.9.88] 新规则一定要攞新 id:Rule 默认 id=-1,GlobalRules.put 按 id 覆盖、DB 主键又唔係自增
            //   ⇒ 之前第二条会覆盖第一条,仲会覆盖用户原有嘅 -1 号规则(09-24 模拟器实测复现)。
            id: snowflake.id,
            ruleAction: _action,
            content: content,
            ruleTarget: _target,
            // IP 段规则唔加 no-resolve 会令前面每个域名连接都要先解析一次 DNS 嚟比对。
            noResolve: _action == RuleAction.IP_CIDR,
          ),
        );
    ref.read(setupActionProvider.notifier).reapplyRulesSoon();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = currentAppLocalizations;
    // [0.9.88] 排除内核内置 GLOBAL:rule 模式下 GLOBAL.now 多数係 DIRECT,用户以为「全局代理」揀咗其实係直连。
    final groups = ref
        .watch(groupsProvider)
        .where((g) => g.hidden != true && g.name != GroupName.GLOBAL.name)
        .map((g) => g.name);
    final targets = <String>['DIRECT', ...groups, 'REJECT'];
    return AlertDialog(
      title: Text(context.appLocalizations.addRule),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<RuleAction>(
              initialValue: _action,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.vgRuleMatchLabel),
              items: [
                for (final a in kQuickRuleActions)
                  DropdownMenuItem(value: a, child: Text(quickRuleActionLabel(a), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (a) => setState(() {
                _action = a ?? _action;
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _content,
              autofocus: true,
              decoration: InputDecoration(labelText: l.vgRuleContentLabel, hintText: _hint),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _target,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.vgRuleTargetLabel),
              items: [
                for (final t in targets)
                  DropdownMenuItem(value: t, child: Text(quickRuleTargetLabel(t), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (t) => setState(() {
                _target = t;
                _error = null;
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: context.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.appLocalizations.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(context.appLocalizations.save)),
      ],
    );
  }
}
