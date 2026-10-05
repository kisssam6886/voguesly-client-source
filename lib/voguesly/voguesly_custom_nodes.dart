// [0.9.91] 高级功能:添加单独节点(Sam 2026-09-25)
//
// 点解:个别地区客户当地网络拦截大部分海外线路,要为佢单独开一条节点先用得。以后遇到类似情况,
// 客服可以直接发一条节点链接畀客户,客户喺 App 入面加入测试,唔使改服务器配置。
//
// 做法:
//   · 节点存喺 profiles 目录下嘅 vg_custom_nodes.json(同订阅文件放埋一齐,唔入 SharedPreferences,唔使改 freezed 模型)。
//   · 只喺「开发者模式 / 高级功能」开住时先注入(getProfile 入面调用 injectVogueslyCustomNodes);关咗就当冇。
//   · 注入位置:「🌐 全局线路·总开关」「🏦 AI·金融·住宅」「🛠 全部节点·手动」(Sam:AI 组要直接揀到先踩中 AI 规则),
//     插喺组尾「🛠 …手动」逃生口前面;唔入任何自动组(fallback / url-test),免得静静被自动揀中。
//   · 名一律加「🧪 自定义·」前缀,同订阅节点分得开,亦唔会撞名。
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:path/path.dart' show join;

const String kVogueslyCustomNodesFile = 'vg_custom_nodes.json';
const String kVogueslyCustomNodePrefix = '🧪 自定义·';
const List<String> kVogueslyCustomNodeGroups = [
  '🌐 全局线路·总开关',
  '🏦 AI·金融·住宅',
  '🛠 全部节点·手动',
];

Future<File> _customNodesFile() async =>
    File(join(await appPath.profilesPath, kVogueslyCustomNodesFile));

Future<List<Map<String, dynamic>>> loadVogueslyCustomNodes() async {
  try {
    final f = await _customNodesFile();
    if (!await f.exists()) return [];
    final data = jsonDecode(await f.readAsString());
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where(
          (e) =>
              e['name'] is String &&
              e['type'] is String &&
              e['server'] is String,
        )
        .toList();
  } catch (e) {
    commonPrint.log('custom nodes load failed: $e', logLevel: LogLevel.warning);
    return [];
  }
}

Future<void> saveVogueslyCustomNodes(List<Map<String, dynamic>> nodes) async {
  final f = await _customNodesFile();
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(nodes));
}

/// 把自定义节点合入订阅配置。`nodes` 为空就原样返回。
Map<String, dynamic> injectVogueslyCustomNodes(
  Map<String, dynamic> rawConfig,
  List<Map<String, dynamic>> nodes,
) {
  if (nodes.isEmpty) return rawConfig;
  final config = Map<String, dynamic>.from(rawConfig);
  final proxies = List<dynamic>.from((config['proxies'] as List?) ?? const []);
  final existing = proxies.whereType<Map>().map((p) => p['name']).toSet();
  final names = <String>[];
  for (final n in nodes) {
    final name = n['name'] as String;
    if (existing.contains(name)) continue;
    proxies.add(Map<String, dynamic>.from(n));
    existing.add(name);
    names.add(name);
  }
  config['proxies'] = proxies;
  if (names.isEmpty) return config;
  final groups = List<dynamic>.from(
    (config['proxy-groups'] as List?) ?? const [],
  );
  for (var i = 0; i < groups.length; i++) {
    final g = groups[i];
    if (g is! Map || !kVogueslyCustomNodeGroups.contains(g['name'])) continue;
    if (g['type'] != 'select') continue;
    final members = List<dynamic>.from((g['proxies'] as List?) ?? const []);
    // 组尾「🛠 …手动」逃生口保持最尾(全部节点·手动自己本身唔会以佢结尾)
    final tail = <dynamic>[];
    while (members.isNotEmpty &&
        members.last is String &&
        (members.last as String).contains('手动')) {
      tail.insert(0, members.removeLast());
    }
    for (final name in names) {
      if (!members.contains(name)) members.add(name);
    }
    final ng = Map<String, dynamic>.from(g);
    ng['proxies'] = [...members, ...tail];
    groups[i] = ng;
  }
  config['proxy-groups'] = groups;
  return config;
}

/// 解析用户贴入嘅节点:vless:// hysteria2:// hy2:// trojan:// ss:// vmess:// 链接,或者 Clash 节点 JSON。
/// 一行一个;返回成功解析嘅节点同失败行数。
({List<Map<String, dynamic>> nodes, int failed}) parseVogueslyNodeInput(
  String input,
) {
  final text = input.trim();
  final nodes = <Map<String, dynamic>>[];
  var failed = 0;
  if (text.isEmpty) return (nodes: nodes, failed: 0);
  if (text.startsWith('{') || text.startsWith('[')) {
    try {
      final data = jsonDecode(text);
      for (final e in (data is List ? data : [data])) {
        final m = e is Map ? _fromClashMap(Map<String, dynamic>.from(e)) : null;
        m == null ? failed++ : nodes.add(m);
      }
    } catch (_) {
      failed++;
    }
    return (nodes: nodes, failed: failed);
  }
  for (final raw in text.split(RegExp(r'\s+'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    Map<String, dynamic>? m;
    try {
      m = parseVogueslyNodeLink(line);
    } catch (_) {
      m = null;
    }
    m == null ? failed++ : nodes.add(m);
  }
  return (nodes: nodes, failed: failed);
}

String _prefixed(String name) => name.startsWith(kVogueslyCustomNodePrefix)
    ? name
    : '$kVogueslyCustomNodePrefix$name';

Map<String, dynamic>? _fromClashMap(Map<String, dynamic> m) {
  if (m['type'] is! String || m['server'] is! String || m['port'] == null) {
    return null;
  }
  final port = m['port'] is int ? m['port'] : int.tryParse('${m['port']}');
  if (port == null) return null;
  final name = (m['name'] is String && (m['name'] as String).isNotEmpty)
      ? m['name'] as String
      : '${m['server']}:$port';
  return {...m, 'name': _prefixed(name), 'port': port};
}

String _b64(String s) {
  var t = s.replaceAll('-', '+').replaceAll('_', '/').trim();
  while (t.length % 4 != 0) {
    t += '=';
  }
  return utf8.decode(base64.decode(t));
}

bool _truthy(String? v) => v == '1' || v == 'true';

/// 单条链接 → Clash 节点(失败返回 null)。
Map<String, dynamic>? parseVogueslyNodeLink(String link) {
  final scheme = link.split('://').first.toLowerCase();
  if (scheme == 'vmess') {
    final j = jsonDecode(_b64(link.substring('vmess://'.length))) as Map;
    final net = '${j['net'] ?? 'tcp'}';
    final port = int.tryParse('${j['port']}');
    if (j['add'] == null || port == null || j['id'] == null) return null;
    return {
      'name': _prefixed('${j['ps'] ?? '${j['add']}:$port'}'),
      'type': 'vmess',
      'server': '${j['add']}',
      'port': port,
      'uuid': '${j['id']}',
      'alterId': int.tryParse('${j['aid'] ?? 0}') ?? 0,
      'cipher': '${j['scy'] ?? 'auto'}',
      'udp': true,
      'network': net,
      if ('${j['tls']}' == 'tls') 'tls': true,
      if ((j['sni'] ?? '').toString().isNotEmpty) 'servername': '${j['sni']}',
      if (net == 'ws')
        'ws-opts': {
          'path': '${j['path'] ?? '/'}',
          if ((j['host'] ?? '').toString().isNotEmpty)
            'headers': {'Host': '${j['host']}'},
        },
    };
  }
  final uri = Uri.tryParse(link);
  if (uri == null || uri.host.isEmpty || !uri.hasPort) return null;
  final q = uri.queryParameters;
  final name = _prefixed(
    uri.fragment.isNotEmpty
        ? Uri.decodeComponent(uri.fragment)
        : '${uri.host}:${uri.port}',
  );
  final user = Uri.decodeComponent(uri.userInfo);
  switch (scheme) {
    case 'vless':
      if (user.isEmpty) return null;
      final net = q['type'] ?? 'tcp';
      final security = q['security'] ?? 'none';
      return {
        'name': name,
        'type': 'vless',
        'server': uri.host,
        'port': uri.port,
        'uuid': user,
        'udp': true,
        'network': net,
        if (security == 'tls' || security == 'reality') 'tls': true,
        if ((q['flow'] ?? '').isNotEmpty) 'flow': q['flow'],
        if ((q['sni'] ?? '').isNotEmpty) 'servername': q['sni'],
        if ((q['fp'] ?? '').isNotEmpty) 'client-fingerprint': q['fp'],
        if (_truthy(q['allowInsecure']) || _truthy(q['insecure']))
          'skip-cert-verify': true,
        if (security == 'reality')
          'reality-opts': {
            'public-key': q['pbk'] ?? '',
            if ((q['sid'] ?? '').isNotEmpty) 'short-id': q['sid'],
          },
        if (net == 'ws')
          'ws-opts': {
            'path': q['path'] ?? '/',
            if ((q['host'] ?? '').isNotEmpty) 'headers': {'Host': q['host']},
          },
        if (net == 'grpc' && (q['serviceName'] ?? '').isNotEmpty)
          'grpc-opts': {'grpc-service-name': q['serviceName']},
      };
    case 'hysteria2':
    case 'hy2':
      if (user.isEmpty) return null;
      return {
        'name': name,
        'type': 'hysteria2',
        'server': uri.host,
        'port': uri.port,
        'password': user,
        if ((q['sni'] ?? q['peer'] ?? '').isNotEmpty)
          'sni': q['sni'] ?? q['peer'],
        if (_truthy(q['insecure'])) 'skip-cert-verify': true,
        if ((q['obfs'] ?? '').isNotEmpty) 'obfs': q['obfs'],
        if ((q['obfs-password'] ?? '').isNotEmpty)
          'obfs-password': q['obfs-password'],
        if ((q['mport'] ?? '').isNotEmpty) 'ports': q['mport'],
      };
    case 'trojan':
      if (user.isEmpty) return null;
      final net = q['type'] ?? 'tcp';
      return {
        'name': name,
        'type': 'trojan',
        'server': uri.host,
        'port': uri.port,
        'password': user,
        'udp': true,
        if ((q['sni'] ?? q['peer'] ?? '').isNotEmpty)
          'sni': q['sni'] ?? q['peer'],
        if (_truthy(q['allowInsecure'])) 'skip-cert-verify': true,
        if (net != 'tcp') 'network': net,
        if (net == 'ws')
          'ws-opts': {
            'path': q['path'] ?? '/',
            if ((q['host'] ?? '').isNotEmpty) 'headers': {'Host': q['host']},
          },
      };
    case 'ss':
      // ss://base64(method:password)@host:port#name(SIP002);旧式 ss://base64(method:password@host:port) 由上面 host 为空拦走
      String method, password;
      if (user.contains(':')) {
        final i = user.indexOf(':');
        method = user.substring(0, i);
        password = user.substring(i + 1);
      } else {
        final d = _b64(user);
        final i = d.indexOf(':');
        if (i < 0) return null;
        method = d.substring(0, i);
        password = d.substring(i + 1);
      }
      return {
        'name': name,
        'type': 'ss',
        'server': uri.host,
        'port': uri.port,
        'cipher': method,
        'password': password,
        'udp': true,
      };
  }
  return null;
}
