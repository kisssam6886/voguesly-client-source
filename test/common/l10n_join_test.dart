import 'package:fl_clash/common/l10n_join.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  test('英文接缝补空格,已有空白唔重复', () {
    Intl.defaultLocale = 'en';
    expect(l10nJoin(['for now.', 'To try again.']), 'for now. To try again.');
    expect(l10nJoin(['a ', 'b']), 'a b');
    expect(l10nJoin(['a', '', 'b']), 'a b');
  });
  test('中日韩直接拼', () {
    Intl.defaultLocale = 'zh_CN';
    expect(l10nJoin(['暂时无法接管。', '要再试请重连。']), '暂时无法接管。要再试请重连。');
    Intl.defaultLocale = 'ja';
    expect(l10nJoin(['接続済み。', '再接続。']), '接続済み。再接続。');
  });
}
