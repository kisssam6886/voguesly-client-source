import 'package:fl_clash/common/print.dart';
import 'package:test/test.dart';

// [0.9.82] 日志去凭证:上传日志会去工单,订阅 token / 一次性登录码 / Bearer 唔可以原文出现。
void main() {
  test('订阅链接 /s/<token> 抹走 token,保留域名同 _t', () {
    expect(redactSecrets('find https://ylink.im/s/0123456789abcdef0123456789abcdef?_t=1790011833170 proxy: false'),
        'find https://ylink.im/s/***?_t=1790011833170 proxy: false');
  });
  test('?verify= / ?token= / auth_data= 抹走值', () {
    expect(redactSecrets('https://ylink.im/api/v1/passport/auth/token2Login?verify=0123456789abcdef0123456789abcdef'),
        'https://ylink.im/api/v1/passport/auth/token2Login?verify=***');
    expect(redactSecrets('https://ylink.im/api/v1/client/subscribe?token=abcdef1234567890&flag=meta'),
        'https://ylink.im/api/v1/client/subscribe?token=***&flag=meta');
    expect(redactSecrets('x?auth_data=Bearer%20abc123456789'), 'x?auth_data=***');
  });
  test('Bearer token 抹走', () {
    expect(redactSecrets('Authorization: Bearer 12|abcdefghijklmnop'), 'Authorization: Bearer ***');
  });
  test('普通日志唔郁', () {
    const s = '[APP] updateGroups /api/v1/user/getSubscribe proxy: false';
    expect(redactSecrets(s), s);
  });
}
