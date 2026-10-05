import 'package:intl/intl.dart';

/// 拼接几段多语言文案(一句话拆成几个 arb 键嘅情况)。
///
/// [0.9.87] 原本各处直接用 `+` 拼 ⇒ 中文冇问题,但英文 / 俄文接缝处冇空格,
/// 例如「…for now.To try enhanced mode…」「…is not active.Your traffic…」。
/// 规则:中 / 日 / 韩文直接拼;其他语言喺接缝两边都冇空白时补一个空格。
String l10nJoin(List<String> parts) {
  final lang = Intl.getCurrentLocale().split(RegExp('[_-]')).first.toLowerCase();
  final cjk = lang == 'zh' || lang == 'ja' || lang == 'ko';
  final buf = StringBuffer();
  for (final p in parts) {
    if (p.isEmpty) continue;
    final s = buf.toString();
    if (!cjk && s.isNotEmpty && !RegExp(r'\s$').hasMatch(s) && !RegExp(r'^\s').hasMatch(p)) {
      buf.write(' ');
    }
    buf.write(p);
  }
  return buf.toString();
}
