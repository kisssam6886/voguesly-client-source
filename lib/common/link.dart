import 'dart:async';

import 'package:app_links/app_links.dart';

import 'print.dart';

typedef InstallConfigCallBack = void Function(String url);

class LinkManager {
  static LinkManager? _instance;
  late AppLinks _appLinks;
  StreamSubscription? subscription;

  LinkManager._internal() {
    _appLinks = AppLinks();
  }

  /// [webLoginCallBack]:网页授权登录(2026-09-22)—— 面板撳「在客户端登录」→ ylink://login?verify=<一次性码>。
  /// 码由 XBoard getQuickLoginUrl 发(60 秒、用一次即失效),呢度只做格式检查,兑换同确认喺 application.dart。
  Future<void> initAppLinksListen(
      Function(String url) installConfigCallBack,
      {Function(String verify)? webLoginCallBack}) async {
    commonPrint.log('initAppLinksListen');
    destroy();
    subscription = _appLinks.uriLinkStream.listen(
      (uri) {
        // ⚠️ 唔好 log 完整 uri:verify 码 60 秒内等同登录凭证,日志会被「上传日志」带走。
        commonPrint.log('onAppLink: ${uri.scheme}://${uri.host}');
        if (uri.scheme == 'ylink' && uri.host == 'login') {
          final verify = uri.queryParameters['verify'];
          if (verify != null && isWebLoginCode(verify)) {
            webLoginCallBack?.call(verify);
          }
          return;
        }
        if (uri.host == 'install-config') {
          final parameters = uri.queryParameters;
          final url = parameters['url'];
          if (url != null) {
            installConfigCallBack(url);
          }
        }
      },
    );
  }

  void destroy() {
    if (subscription != null) {
      subscription?.cancel();
      subscription = null;
    }
  }

  factory LinkManager() {
    _instance ??= LinkManager._internal();
    return _instance!;
  }
}

final linkManager = LinkManager();

/// XBoard Helper::guid() 出嘅码(32 位 hex;放宽少少防将来改格式),其余一律唔认。
bool isWebLoginCode(String v) => RegExp(r'^[A-Za-z0-9-]{16,64}$').hasMatch(v);
