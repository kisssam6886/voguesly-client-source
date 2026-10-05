import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_clash/common/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'voguesly_api.dart';
import 'voguesly_auth.dart';
import 'voguesly_ui.dart';

const String _kNoticeSeenKey = 'voguesly_notice_seen_id';

/// [0.9.82] 公告未读红点:登录后拉一次公告(之后每 30 分钟),最新公告 id > 本机「已读到」id 就亮。
/// 撳入公告页即记为已读。第一次(本机未有记录):只当最近 7 日嘅公告未读,免得一装就亮一粒旧公告红点。
class VogueslyNoticeUnreadNotifier extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    final token = ref.watch(
      vogueslyAuthProvider.select((s) => s.isLoggedIn ? s.token : null),
    );
    _timer?.cancel();
    ref.onDispose(() => _timer?.cancel());
    if (token == null || token.isEmpty) return false;
    Future.microtask(() => _check(token));
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => _check(token));
    return false;
  }

  static int _maxId(Iterable<VogueslyNotice> l) =>
      l.fold<int>(0, (m, n) => n.id > m ? n.id : m);

  Future<void> _check(String token) async {
    try {
      final list = await ref.read(vogueslyApiProvider).fetchNotices(token);
      if (list.isEmpty) return;
      final p = await SharedPreferences.getInstance();
      var seen = p.getInt(_kNoticeSeenKey);
      if (seen == null) {
        final cutoff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 7 * 86400;
        seen = _maxId(list.where((n) => (n.createdAt ?? 0) < cutoff));
        await p.setInt(_kNoticeSeenKey, seen);
      }
      state = _maxId(list) > seen;
    } catch (_) {}
  }

  /// 公告页载入完 = 全部睇过。
  Future<void> markSeen(List<VogueslyNotice> list) async {
    state = false;
    if (list.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final latest = _maxId(list);
      if (latest > (p.getInt(_kNoticeSeenKey) ?? 0)) {
        await p.setInt(_kNoticeSeenKey, latest);
      }
    } catch (_) {}
  }
}

final vogueslyNoticeUnreadProvider =
    NotifierProvider<VogueslyNoticeUnreadNotifier, bool>(
  VogueslyNoticeUnreadNotifier.new,
);

/// 易联 · 原生公告中心(直调 XBoard /user/notice/fetch,唔用 webview)。
class VogueslyNoticePage extends ConsumerStatefulWidget {
  const VogueslyNoticePage({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VogueslyNoticePage()),
    );
  }

  @override
  ConsumerState<VogueslyNoticePage> createState() => _VogueslyNoticePageState();
}

class _VogueslyNoticePageState extends ConsumerState<VogueslyNoticePage> {
  bool _loading = true;
  String? _error;
  List<VogueslyNotice> _notices = const [];
  final Set<int> _expanded = {};

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
    final notices = await ref.read(vogueslyApiProvider).fetchNotices(token);
    if (!mounted) return;
    setState(() {
      _notices = notices;
      _loading = false;
    });
    unawaited(ref.read(vogueslyNoticeUnreadProvider.notifier).markSeen(notices));
  }

  String _date(int? sec) {
    if (sec == null || sec == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  // 无 flutter_html 依赖:把公告 HTML 简易转纯文本(块级标签换行 + 去标签 + 解基础实体)。
  static String _htmlToText(String html) {
    var s = html;
    s = s.replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n');
    s = s.replaceAll(
        RegExp(r'</\s*(p|div|li|h[1-6]|tr)\s*>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<\s*li[^>]*>', caseSensitive: false), '• ');
    s = s.replaceAll(RegExp(r'<[^>]+>'), ''); // 去剩余标签
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    // 收敛连续空行,去首尾空白。
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s.trim();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: vogAppBar(
        context,
        title: currentAppLocalizations.vgAnnouncements,
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
            : (_error != null && _notices.isEmpty)
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      const Icon(Icons.campaign_outlined, size: 44),
                      const SizedBox(height: 12),
                      Center(child: Text(_error!)),
                    ],
                  )
                : _notices.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 120),
                          const Icon(Icons.campaign_outlined, size: 44),
                          const SizedBox(height: 12),
                          Center(child: Text(currentAppLocalizations.vgNoAnnouncements)),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _notices.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final n = _notices[i];
                          final expanded = _expanded.contains(n.id);
                          final body = _htmlToText(n.content);
                          return Card(
                            elevation: 0,
                            color: cs.surfaceContainerHighest,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.campaign_outlined,
                                          size: 20, color: cs.primary),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          n.title,
                                          style: tt.titleSmall?.copyWith(
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_date(n.createdAt).isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      _date(n.createdAt),
                                      style: tt.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant
                                              .withValues(alpha: 0.7)),
                                    ),
                                  ],
                                  if (n.tags.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final t in n.tags)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: cs.primary
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(t,
                                                style: tt.labelSmall?.copyWith(
                                                    color: cs.primary,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ),
                                      ],
                                    ),
                                  ],
                                  if (body.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      body,
                                      maxLines: expanded ? null : 4,
                                      overflow: expanded
                                          ? TextOverflow.visible
                                          : TextOverflow.ellipsis,
                                      style: tt.bodyMedium?.copyWith(
                                          color: cs.onSurfaceVariant, height: 1.5),
                                    ),
                                    // 长文提供展开/收起。
                                    if (body.length > 120)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton(
                                          style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              minimumSize: const Size(0, 32),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap),
                                          onPressed: () => setState(() {
                                            if (expanded) {
                                              _expanded.remove(n.id);
                                            } else {
                                              _expanded.add(n.id);
                                            }
                                          }),
                                          child: Text(expanded ? currentAppLocalizations.vgCollapse : currentAppLocalizations.vgExpandFullText),
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
