import 'package:fl_clash/voguesly/voguesly_diag_report.dart';
import 'package:flutter_test/flutter_test.dart';

// [0.9.89] 上传日志「失败连接汇总」解析:用真实 mihomo warning 行(09-24 旁路由 OpenClash 日志抄)。
void main() {
  const l1 =
      '2026-09-24 16:50:05 [warning] [TCP] dial 🚀 快线·通用 (match DomainSuffix/gstatic.com) 127.0.0.1:50464(curl) --> www.gstatic.com:80 error: cf4.octolink.xyz:2087 connect error: connect failed: dial tcp 104.21.82.42:2087: i/o timeout';
  const l2 =
      '2026-09-24 16:51:00 [warning] [TCP] dial 🏦 AI·金融·住宅 (match DomainSuffix/anthropic.com) 10.10.10.251:55665(Claude) --> api.anthropic.com:443 error: us5.samge.ccwu.cc:31820 connect error: read tcp 10.10.10.252:50690->216.36.109.195:31820: read: connection reset by peer';
  const l3 =
      '2026-09-24 16:52:00 [warning] [TCP] dial 🏦 AI·金融·住宅 (match DomainSuffix/anthropic.com) 10.10.10.251:55666(Claude) --> api.anthropic.com:443 error: us5.samge.ccwu.cc:31820 connect error: read tcp 10.10.10.252:50691->216.36.109.195:31820: read: connection reset by peer';

  test('按 域名 × 组 × 原因 × 入口 汇总,次数多嘅排前', () {
    final r = buildFailureSummary([l1, l2, l3, '2026-09-24 16:53:00 [info] 无关行']);
    expect(r.total, 3);
    expect(r.top, 'api.anthropic.com 被重置');
    expect(r.text, contains('api.anthropic.com ← 🏦 AI·金融·住宅 · 被重置 ×2 · 入口 us5.samge.ccwu.cc:31820'));
    expect(r.text, contains('www.gstatic.com ← 🚀 快线·通用 · 超时 ×1 · 入口 cf4.octolink.xyz:2087'));
  });

  test('唔带来源 IP 同进程名(私隐)', () {
    final r = buildFailureSummary([l2]);
    expect(r.text, isNot(contains('10.10.10.251')));
    expect(r.text, isNot(contains('(Claude)')));
  });

  test('0.9.89 模拟器实测:内核自己发起(冇 match 段)都要计;context canceled 单独计唔入最多', () {
    const internal =
        '2026-09-24 20:31:32 [warning] [TCP] dial 🏠 住宅池 mihomo --> dns.google:443 error: tyo-relay.corelane.xyz:24842 connect error: i/o timeout';
    const canceled =
        '2026-09-24 20:31:32 [warning] [TCP] dial 🚀 快线·通用 mihomo --> 1.1.1.1:443 error: tyo2-relay.corelane.xyz:24852 connect error: context canceled';
    final r = buildFailureSummary([internal, canceled]);
    expect(r.total, 1);
    expect(r.top, 'dns.google 超时');
    expect(r.text, contains('dns.google ← 🏠 住宅池 · 超时 ×1 · 入口 tyo-relay.corelane.xyz:24842'));
    expect(r.text, contains('另有 1 次「被取消」'));
  });

  test('冇失败行 ⇒ 显示「无」', () {
    final r = buildFailureSummary(['2026-09-24 16:53:00 [warning] something else']);
    expect(r.total, 0);
    expect(r.top, isNull);
    expect(r.text, contains('(无)'));
  });
}
