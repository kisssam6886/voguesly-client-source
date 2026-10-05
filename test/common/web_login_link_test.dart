import 'package:fl_clash/common/link.dart';
import 'package:test/test.dart';

// 网页授权登录(2026-09-22):ylink://login?verify=(XBoard Helper::guid())。
// 只认 16-64 位字母数字/横线,其余(空、带符号、超长、注入)一律唔认,唔会触发兑换。
void main() {
  group('isWebLoginCode', () {
    test('XBoard guid 格式(32 位 hex)', () {
      expect(isWebLoginCode('0f3c9a2b7d1e4f5a8b6c0d2e4f6a8b0c'), isTrue);
    });
    test('带横线嘅 uuid 格式都认', () {
      expect(isWebLoginCode('0f3c9a2b-7d1e-4f5a-8b6c-0d2e4f6a8b0c'), isTrue);
    });
    test('太短 / 太长 / 空', () {
      expect(isWebLoginCode(''), isFalse);
      expect(isWebLoginCode('abc123'), isFalse);
      expect(isWebLoginCode('a' * 65), isFalse);
    });
    test('带符号或者注入字符', () {
      expect(isWebLoginCode('0f3c9a2b7d1e4f5a&redirect=x'), isFalse);
      expect(isWebLoginCode('../../0f3c9a2b7d1e4f5a8b6c'), isFalse);
      expect(isWebLoginCode('0f3c9a2b7d1e4f5a 8b6c0d2e'), isFalse);
    });
  });
}
