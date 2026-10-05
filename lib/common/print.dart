import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';

class CommonPrint {
  static CommonPrint? _instance;

  CommonPrint._internal();

  factory CommonPrint() {
    _instance ??= CommonPrint._internal();
    return _instance!;
  }

  void log(String? text, {LogLevel logLevel = LogLevel.info}) {
    final payload = '[APP] $text';
    debugPrint(payload);
    if (!globalState.isAttach) {
      return;
    }
    globalState.container
        .read(logsProvider.notifier)
        .add(Log.app(payload).copyWith(logLevel: logLevel));
  }
}

final commonPrint = CommonPrint();

/// [0.9.82] 日志去凭证:订阅链接 `/s/<token>`、`?token=` / `?verify=`(网页授权登录一次性码)/ `auth_data=`、
/// `Bearer xxx`。「上传日志」会把日志发去工单,订阅 token 係长期有效嘅凭证,唔应该出现喺度。
final _redactSubPath = RegExp(r'(/s/)[A-Za-z0-9]{8,}');
final _redactQuery =
    RegExp(r'((?:token|verify|auth_data|auth)=)[^&#\s]+', caseSensitive: false);
final _redactBearer = RegExp(r'(Bearer\s+)[A-Za-z0-9._|-]{8,}');

String redactSecrets(String s) => s
    .replaceAllMapped(_redactSubPath, (m) => '${m[1]}***')
    .replaceAllMapped(_redactQuery, (m) => '${m[1]}***')
    .replaceAllMapped(_redactBearer, (m) => '${m[1]}***');
