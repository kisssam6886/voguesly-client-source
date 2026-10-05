// [0.9.89] 上传日志增强 —— 客服 / 运维靠呢份日志判断用户问题(Sam 09-24:「越详细越好」)。
//
// 09-24 审计(voguesly-ops/审计-客户端上传日志-2026-09-24.md)揾到嘅核心问题:
//   ① 内核日志等级实际係 info,每条连接一行,500 条缓冲只覆盖约 2 分钟 ⇒ 几分钟前嘅超时早被挤走,App 重启更加全冇;
//   ② 只列「手动点过嘅组」,自动组冇 ⇒ 判断唔到「全部瘫痪」系咪真;冇失败原因;
//   ③ 分唔出「节点坏」定「用户本地网络坏」。
// 呢个文件补:
//   · VogueslyIssueLog —— warning / error 独立缓冲 + 写落磁盘(重启唔丢,保留 48 小时)
//   · buildGroupStatusReport —— 由内核读**全部**组:当前节点、最终节点、可用与否、最后测速同距今
//   · buildFailureSummary —— 失败连接按「域名 × 组 × 错误类型 × 入口」汇总(唔带来源 IP / 进程名)
//   · runLiveChecks —— 上传时现场补测关键组节点 + 直连国内站 / 面板
//   · 订阅拉取记录(每个镜像域名成功 / 失败)
// 全部唔含订阅 token / 密码:写入前一律过 redactSecrets。

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/models/models.dart';

import 'voguesly_api.dart' show vogueslyHosts;

String _ts(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

String _ago(Duration d) {
  if (d.inSeconds < 90) return '${max(0, d.inSeconds)} 秒前';
  if (d.inMinutes < 90) return '${d.inMinutes} 分钟前';
  if (d.inHours < 48) return '${d.inHours} 小时前';
  return '${d.inDays} 天前';
}

// ───────────────────────── 问题日志(warning / error)持久化 ─────────────────────────

class VogueslyIssueLog {
  VogueslyIssueLog._();

  static final instance = VogueslyIssueLog._();

  static const _maxLines = 800;
  static const _maxFileBytes = 1024 * 1024;
  static const _keep = Duration(hours: 48);

  final List<String> _lines = [];
  final List<String> _pending = [];
  File? _file;
  bool _loadStarted = false;
  Timer? _flushTimer;

  /// App 启动时调用一次:读返磁盘入面最近 48 小时嘅记录(排喺内存已有记录之前)。
  Future<void> load() async {
    if (_loadStarted) return;
    _loadStarted = true;
    try {
      final dir = await appPath.homeDirPath;
      final f = File('$dir/voguesly-issues.log');
      _file = f;
      if (!await f.exists()) return;
      final raw = await f.readAsLines();
      final cutoff = DateTime.now().subtract(_keep);
      final old = <String>[];
      for (final l in raw.skip(max(0, raw.length - _maxLines))) {
        final t = l.length >= 19 ? DateTime.tryParse(l.substring(0, 19)) : null;
        if (t != null && t.isAfter(cutoff)) old.add(l);
      }
      _lines.insertAll(0, old);
      _trim();
    } catch (_) {}
  }

  void add(Log log) {
    final line =
        '${_ts(DateTime.now())} [${log.logLevel.name}] ${redactSecrets(log.payload)}';
    _lines.add(line);
    _trim();
    _pending.add(line);
    _flushTimer ??= Timer(const Duration(seconds: 5), _flush);
  }

  void _trim() {
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
  }

  Future<void> _flush() async {
    _flushTimer = null;
    final f = _file;
    if (f == null || _pending.isEmpty) return;
    final chunk = '${_pending.join('\n')}\n';
    _pending.clear();
    try {
      await f.writeAsString(chunk, mode: FileMode.append, flush: true);
      if (await f.length() > _maxFileBytes) {
        // 超 1MB:用内存入面最近嘅 _maxLines 条重写,档案唔会无限大。
        await f.writeAsString('${_lines.join('\n')}\n', flush: true);
      }
    } catch (_) {}
  }

  /// 最近 [window] 内嘅记录(旧 → 新)。
  List<String> recent({Duration window = _keep}) {
    final cutoff = DateTime.now().subtract(window);
    return _lines.where((l) {
      final t = l.length >= 19 ? DateTime.tryParse(l.substring(0, 19)) : null;
      return t == null || t.isAfter(cutoff);
    }).toList();
  }
}

// ───────────────────────── 订阅拉取记录 ─────────────────────────

final List<String> _subFetchLog = [];

/// 每个镜像域名拉订阅嘅结果(成功 / 失败原因)。只记域名,唔记路径同 token。
void vogueslyRecordSubscriptionFetch(String host, bool ok, [String detail = '']) {
  _subFetchLog.add(
    '${_ts(DateTime.now())} $host ${ok ? '成功' : '失败'}${detail.isEmpty ? '' : ' · $detail'}',
  );
  if (_subFetchLog.length > 30) {
    _subFetchLog.removeRange(0, _subFetchLog.length - 30);
  }
}

List<String> vogueslySubscriptionFetchLog() => List.unmodifiable(_subFetchLog);

// ───────────────────────── 全部组状态(由内核读) ─────────────────────────

const _groupTypes = {'Selector', 'Fallback', 'URLTest', 'LoadBalance', 'Relay'};

class GroupStatusReport {
  final String text;
  final int total;
  final int bad;

  /// 关键组(总开关 / AI / 快线 / TG / YouTube / 住宅池)最终落到嘅节点,畀现场补测用。
  final List<String> keyLeaves;

  /// 用户喺边啲组手动揀咗「🛠 …手动」(钉死咗唔会自动换)。
  final List<String> pinnedManual;

  const GroupStatusReport(this.text, this.total, this.bad, this.keyLeaves, this.pinnedManual);
}

const _keyGroupMarkers = ['总开关', 'AI', '快线·通用', 'Telegram', 'YouTube', '住宅池'];

Future<GroupStatusReport> buildGroupStatusReport() async {
  final data = await coreController.getProxiesRaw();
  final proxies = data.proxies;
  final names = data.all.isNotEmpty ? data.all : proxies.keys.toList();
  final now = DateTime.now();
  final sb = StringBuffer();
  var total = 0, bad = 0;
  final keyLeaves = <String>[];
  final pinned = <String>[];

  Map? node(String n) {
    final v = proxies[n];
    return v is Map ? v : null;
  }

  for (final name in names) {
    final p = node(name);
    if (p == null || !_groupTypes.contains(p['type'])) continue;
    if (name == 'GLOBAL' || p['hidden'] == true) continue;
    total++;
    final chain = <String>[name];
    var cur = name;
    for (var i = 0; i < 8; i++) {
      final q = node(cur);
      final next = q?['now'];
      if (q == null || !_groupTypes.contains(q['type']) || next is! String || next.isEmpty) break;
      cur = next;
      chain.add(cur);
    }
    final leaf = chain.last;
    final lp = node(leaf);
    final alive = lp?['alive'];
    String last = '未测过';
    final hist = lp?['history'];
    if (hist is List && hist.isNotEmpty && hist.last is Map) {
      final h = hist.last as Map;
      final d = h['delay'];
      final t = DateTime.tryParse('${h['time']}');
      final ds = (d is num && d > 0) ? '${d.toInt()}ms' : '超时';
      last = t == null ? ds : '$ds（${_ago(now.difference(t.toLocal()))}）';
    }
    final dead = alive == false;
    if (dead) bad++;
    if (chain.length > 1 && chain[1].contains('手动')) pinned.add(name);
    if (_keyGroupMarkers.any(name.contains) && !keyLeaves.contains(leaf)) keyLeaves.add(leaf);
    sb.writeln(
      '  ${dead ? '❌' : '✅'} $name [${p['type']}] → ${chain.skip(1).join(' → ')} · 最后测速 $last',
    );
  }
  final head = StringBuffer()
    ..writeln('--- 全部分组状态(内核实时;❌ = 当前节点不可用) · 共 $total 组,异常 $bad 组 ---');
  if (pinned.isNotEmpty) {
    head.writeln('  ⚠️ 这些组手动钉在「全部节点·手动」(节点坏了不会自动换):${pinned.join('、')}');
  }
  return GroupStatusReport('$head$sb', total, bad, keyLeaves.take(5).toList(), pinned);
}

// ───────────────────────── 失败连接汇总 ─────────────────────────

// [0.9.90] 「(match …)」可有可无:内核自己发起嘅连接(例如 DNS,来源写「mihomo」)冇呢段(0.9.89 模拟器实测漏计)。
final _dialFail = RegExp(r'\[(TCP|UDP)\] dial (.+?)(?: \(match (.+?)\))? (\S+) --> (\S+?):(\d+) error: (.+)$');
final _entry = RegExp(r'^([A-Za-z0-9.\-]+:\d+) ');

const _kCanceled = '被取消';

String _classify(String err) {
  final e = err.toLowerCase();
  if (e.contains('context canceled')) return _kCanceled;
  if (e.contains('timeout') || e.contains('deadline exceeded')) return '超时';
  if (e.contains('reset by peer')) return '被重置';
  if (e.contains('refused')) return '被拒绝';
  if (e.contains('no such host') || e.contains('dns')) return 'DNS 失败';
  if (e.contains('tls') || e.contains('handshake') || e.contains('reality')) return '握手失败';
  if (e.contains('eof')) return '连接中断(EOF)';
  if (e.contains('no route') || e.contains('unreachable')) return '网络不可达';
  return '其他';
}

class FailureSummary {
  final String text;
  final int total;
  final String? top;

  const FailureSummary(this.text, this.total, this.top);
}

FailureSummary buildFailureSummary(List<String> lines) {
  final counts = <String, int>{};
  final lastAt = <String, String>{};
  var total = 0, canceled = 0;
  for (final l in lines) {
    final m = _dialFail.firstMatch(l);
    if (m == null) continue;
    total++;
    final err = m.group(7) ?? '';
    final entry = _entry.firstMatch(err)?.group(1) ?? '-';
    final type = _classify(err);
    if (type == _kCanceled) {
      canceled++; // 切换线路 / 并发测速时被主动取消,多数唔係故障:单独计数,唔入「失败最多」
      continue;
    }
    final key = '${m.group(5)}\u0000${m.group(2)}\u0000$type\u0000$entry';
    counts[key] = (counts[key] ?? 0) + 1;
    lastAt[key] = l.length >= 16 ? l.substring(5, 16) : '';
  }
  final sb = StringBuffer()
    ..writeln('--- 失败连接汇总(近 48 小时,共 $total 次;域名 ← 分组 · 原因 × 次数 · 节点入口 · 最后一次) ---');
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  String? top;
  for (final e in sorted.take(20)) {
    final k = e.key.split('\u0000');
    top ??= '${k[0]} ${k[2]}';
    sb.writeln('  ${k[0]} ← ${k[1]} · ${k[2]} ×${e.value} · 入口 ${k[3]} · ${lastAt[e.key]}');
  }
  if (sorted.length > 20) sb.writeln('  …另有 ${sorted.length - 20} 种组合');
  if (total == canceled) sb.writeln('  (无)');
  if (canceled > 0) sb.writeln('  另有 $canceled 次「被取消」(切换线路 / 测速时主动取消,一般不是故障)');
  return FailureSummary(sb.toString(), total - canceled, top);
}

// ───────────────────────── 现场检测 ─────────────────────────

class LiveCheckResult {
  final String text;
  final bool domesticOk;
  final bool panelOk;
  final int nodesOk;
  final int nodesTested;

  const LiveCheckResult(this.text, this.domesticOk, this.panelOk, this.nodesOk, this.nodesTested);
}

Future<(int?, String)> _httpProbe(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  final sw = Stopwatch()..start();
  try {
    final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
    final resp = await req.close().timeout(const Duration(seconds: 8));
    await resp.drain<void>().timeout(const Duration(seconds: 4), onTimeout: () {});
    return (sw.elapsedMilliseconds, 'HTTP ${resp.statusCode}');
  } catch (e) {
    final s = e.toString();
    return (null, s.length > 80 ? s.substring(0, 80) : s);
  } finally {
    client.close(force: true);
  }
}

/// 上传时现场补测:关键组当前节点(经内核)+ 直连国内站 + 面板。
/// 目的:分清「节点坏」定「用户本地网络坏」。
Future<LiveCheckResult> runLiveChecks(List<String> leaves, {required bool started}) async {
  final sb = StringBuffer()..writeln('--- 现场检测(上传时实测) ---');
  var ok = 0;
  final nodeFutures = leaves.map((leaf) async {
    try {
      final d = await coreController
          .getDelay(defaultTestUrl, leaf)
          .timeout(const Duration(seconds: 15));
      final v = d.value;
      return (leaf, (v != null && v > 0) ? v : null);
    } catch (_) {
      return (leaf, null);
    }
  }).toList();
  for (final r in await Future.wait(nodeFutures)) {
    if (r.$2 != null) ok++;
    sb.writeln('  节点 ${r.$1}: ${r.$2 != null ? '${r.$2}ms ✅' : '超时 / 失败 ❌'}');
  }
  // App 自己嘅 HTTP 请求喺已连接时一律经本地混合端口(FlClashHttpOverrides.handleFindProxy)⇒ 按内核规则走(国内站直连)。
  final via = started ? '(已连接,经内核规则;国内站走直连)' : '(未连接,直连)';
  final probes = await Future.wait([
    _httpProbe('https://www.baidu.com/'),
    _httpProbe('https://www.qq.com/'),
    _httpProbe('${vogueslyHosts().first}/api/v1/guest/comm/config'), // [0.9.91] 之前写死 cp.ylink.im(09-25 已封)⇒ 诊断永远报失败
  ]);
  final domesticOk = probes[0].$1 != null || probes[1].$1 != null;
  final panelOk = probes[2].$1 != null;
  sb.writeln('  国内网站$via: 百度 ${probes[0].$1 != null ? '${probes[0].$1}ms' : '失败(${probes[0].$2})'}'
      ' · QQ ${probes[1].$1 != null ? '${probes[1].$1}ms' : '失败(${probes[1].$2})'}');
  sb.writeln('  易联面板$via: ${panelOk ? '${probes[2].$1}ms ${probes[2].$2}' : '失败(${probes[2].$2})'}');
  if (!domesticOk) {
    sb.writeln('  ⚠️ 连国内网站都打不开 ⇒ 多半是用户本地网络 / 其他 VPN 的问题,不是节点问题');
  }
  return LiveCheckResult(sb.toString(), domesticOk, panelOk, ok, leaves.length);
}
