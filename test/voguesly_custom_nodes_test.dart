// [0.9.91] 高级功能「添加单独节点」:链接解析 + 注入位置
import 'dart:convert';

import 'package:fl_clash/voguesly/voguesly_custom_nodes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vless reality 链接(我哋节点格式)', () {
    final n = parseVogueslyNodeLink(
      'vless://11111111-2222-3333-4444-555555555555@nl-relay.corelane.xyz:24473?encryption=none&security=reality&sni=yahoo.com&fp=chrome&pbk=PUBKEY&sid=abcd&type=tcp&flow=xtls-rprx-vision#%E6%97%A5%E6%9C%AC',
    )!;
    expect(n['type'], 'vless');
    expect(n['server'], 'nl-relay.corelane.xyz');
    expect(n['port'], 24473);
    expect(n['tls'], true);
    expect(n['servername'], 'yahoo.com');
    expect(n['flow'], 'xtls-rprx-vision');
    expect(n['reality-opts'], {'public-key': 'PUBKEY', 'short-id': 'abcd'});
    expect(n['name'], '🧪 自定义·日本');
  });

  test('hysteria2 / trojan / ss / vmess', () {
    expect(parseVogueslyNodeLink('hysteria2://pw@a.b.c:443?sni=www.bing.com&insecure=1#hy')!['type'], 'hysteria2');
    expect(parseVogueslyNodeLink('trojan://pw@a.b.c:443?sni=x.com#t')!['password'], 'pw');
    final ss = parseVogueslyNodeLink('ss://${base64.encode(utf8.encode('aes-256-gcm:pw'))}@a.b.c:8388#s')!;
    expect(ss['cipher'], 'aes-256-gcm');
    final vm = base64.encode(utf8.encode(jsonEncode({'add': 'a.b.c', 'port': '443', 'id': 'u', 'net': 'ws', 'path': '/p', 'tls': 'tls', 'ps': 'vm'})));
    final v = parseVogueslyNodeLink('vmess://$vm')!;
    expect(v['ws-opts'], {'path': '/p'});
    expect(v['tls'], true);
  });

  test('多行输入:好嘅入、坏嘅计失败', () {
    final r = parseVogueslyNodeInput('vless://u@a.b.c:443?security=tls#a\nnot-a-link\nhy2://p@d.e.f:8443#b');
    expect(r.nodes.length, 2);
    expect(r.failed, 1);
  });

  test('注入:只入三个 select 组,排喺手动逃生口前,唔入自动组', () {
    final cfg = {
      'proxies': [
        {'name': 'A', 'type': 'vless', 'server': 's', 'port': 1},
      ],
      'proxy-groups': [
        {'name': '🌐 全局线路·总开关', 'type': 'select', 'proxies': ['A', '🛠 全部节点·手动']},
        {'name': '🏦 AI·金融·住宅', 'type': 'select', 'proxies': ['A', '🛠 全部节点·手动']},
        {'name': '🛠 全部节点·手动', 'type': 'select', 'proxies': ['A']},
        {'name': '🛡 自动·🏦 AI·金融·住宅', 'type': 'fallback', 'proxies': ['A']},
      ],
    };
    final node = {'name': '🧪 自定义·X', 'type': 'vless', 'server': 'x', 'port': 2};
    final out = injectVogueslyCustomNodes(cfg, [node]);
    final g = {for (final x in out['proxy-groups'] as List) x['name']: x['proxies']};
    expect(g['🌐 全局线路·总开关'], ['A', '🧪 自定义·X', '🛠 全部节点·手动']);
    expect(g['🏦 AI·金融·住宅'], ['A', '🧪 自定义·X', '🛠 全部节点·手动']);
    expect(g['🛠 全部节点·手动'], ['A', '🧪 自定义·X']);
    expect(g['🛡 自动·🏦 AI·金融·住宅'], ['A']);
    expect((out['proxies'] as List).length, 2);
    // 重复注入唔会再加
    final again = injectVogueslyCustomNodes(out, [node]);
    expect((again['proxies'] as List).length, 2);
  });
}
