// [0.9.91] 高级功能「添加单独节点」页面(设置首页入口,只喺开发者模式开住时显示)。
// 逻辑见 voguesly_custom_nodes.dart;改完即刻 reapplyRulesSoon() 令配置重新生效。
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/voguesly/voguesly_custom_nodes.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VogueslyCustomNodesView extends ConsumerStatefulWidget {
  const VogueslyCustomNodesView({super.key});

  @override
  ConsumerState<VogueslyCustomNodesView> createState() =>
      _VogueslyCustomNodesViewState();
}

class _VogueslyCustomNodesViewState
    extends ConsumerState<VogueslyCustomNodesView> {
  final _input = TextEditingController();
  List<Map<String, dynamic>> _nodes = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final nodes = await loadVogueslyCustomNodes();
    if (mounted) setState(() => _nodes = nodes);
  }

  void _apply() {
    ref.read(setupActionProvider.notifier).reapplyRulesSoon();
  }

  Future<void> _add() async {
    if (_busy) return;
    final l = currentAppLocalizations;
    final r = parseVogueslyNodeInput(_input.text);
    if (r.nodes.isEmpty) {
      globalState.showNotifier(
        l.vgCustomNodesFailed(r.failed == 0 ? 1 : r.failed),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final byName = {for (final n in _nodes) n['name'] as String: n};
      for (final n in r.nodes) {
        byName[n['name'] as String] = n; // 同名当更新
      }
      final next = byName.values.toList();
      await saveVogueslyCustomNodes(next);
      _input.clear();
      setState(() => _nodes = next);
      _apply();
      globalState.showNotifier(
        l.vgCustomNodesAdded(r.nodes.length) +
            (r.failed > 0 ? '\n${l.vgCustomNodesFailed(r.failed)}' : ''),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String name) async {
    final next = _nodes.where((n) => n['name'] != name).toList();
    await saveVogueslyCustomNodes(next);
    setState(() => _nodes = next);
    _apply();
    globalState.showNotifier(currentAppLocalizations.vgCustomNodesDeleted);
  }

  @override
  Widget build(BuildContext context) {
    final l = currentAppLocalizations;
    final cs = context.colorScheme;
    return CommonScaffold(
      title: l.vgCustomNodesTitle,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l.vgCustomNodesNote,
            style: context.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: l.vgCustomNodesHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add),
              label: Text(l.vgCustomNodesAdd),
            ),
          ),
          const SizedBox(height: 16),
          if (_nodes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  l.vgCustomNodesEmpty,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            for (final n in _nodes)
              Card(
                child: ListTile(
                  title: EmojiText(
                    n['name'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${n['type']} · ${n['server']}:${n['port']}'),
                  trailing: IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).deleteButtonTooltip,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(n['name'] as String),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
