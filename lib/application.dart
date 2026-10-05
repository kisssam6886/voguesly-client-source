import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/hotkey_manager.dart';
import 'package:fl_clash/manager/manager.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'voguesly/voguesly_auth.dart';
import 'voguesly/voguesly_gate.dart';

class Application extends ConsumerStatefulWidget {
  const Application({super.key});

  @override
  ConsumerState<Application> createState() => ApplicationState();
}

class ApplicationState extends ConsumerState<Application> {
  Timer? _autoUpdateProfilesTaskTimer;
  bool _preHasVpn = false;

  final _pageTransitionsTheme = const PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: commonSharedXPageTransitions,
      TargetPlatform.windows: commonSharedXPageTransitions,
      TargetPlatform.linux: commonSharedXPageTransitions,
      TargetPlatform.macOS: commonSharedXPageTransitions,
    },
  );

  ColorScheme _getAppColorScheme({
    required Brightness brightness,
    int? primaryColor,
  }) {
    return ref.read(genColorSchemeProvider(brightness));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      if (globalState.navigatorKey.currentContext != null) {
        await globalState.attach();
      } else {
        exit(0);
      }
      _autoUpdateProfilesTask();
      _initLink();
      app?.initShortcuts();
    });
  }

  void _initLink() {
    linkManager.initAppLinksListen((url) async {
      final res = await globalState.showMessage(
        title: currentAppLocalizations.addProfile,
        message: TextSpan(
          children: [
            TextSpan(text: currentAppLocalizations.doYouWantToPass),
            TextSpan(
              text: ' $url ',
              style: TextStyle(
                color: context.colorScheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: context.colorScheme.primary,
              ),
            ),
            TextSpan(text: currentAppLocalizations.createProfile),
          ],
        ),
      );
      if (res != true) return;
      ref.read(profilesActionProvider.notifier).addProfileFormURL(url);
    }, webLoginCallBack: _onWebLogin);
  }

  /// 网页授权登录(2026-09-22):面板「在客户端登录」→ ylink://login?verify=…。
  /// 先兑换一次性码(60 秒有效,唔可以等用户睇完确认框先换)→ 确认框显示网页账号邮箱 → 用户同意先登入。
  /// 确认框防「恶意网页塞自己个码,令客户端静静登入咗人哋账号」。
  bool _webLoginBusy = false;
  Future<void> _onWebLogin(String verify) async {
    if (_webLoginBusy) return;
    _webLoginBusy = true;
    try {
      // 冷启动由链接唤起:等登录态恢复完先判断(最多 5 秒)
      for (var i = 0;
          i < 25 &&
              ref.read(vogueslyAuthProvider).status ==
                  VogueslyAuthStatus.restoring;
          i++) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      final auth = ref.read(vogueslyAuthProvider.notifier);
      final peek = await auth.peekWebLogin(verify);
      final token = peek.token;
      if (token == null) {
        globalState.showNotifier(
            peek.error ?? currentAppLocalizations.vgWebLoginExpired);
        return;
      }
      final email = peek.email ?? '';
      final cur = ref.read(vogueslyAuthProvider);
      final curEmail = cur.user?.email;
      if (cur.isLoggedIn && email.isNotEmpty && curEmail == email) {
        globalState.showNotifier(currentAppLocalizations.vgWebLoginAlready(email));
        return;
      }
      final res = await globalState.showMessage(
        title: currentAppLocalizations.vgWebLoginTitle,
        message: TextSpan(
          text: cur.isLoggedIn
              ? currentAppLocalizations.vgWebLoginConfirmSwitch(email)
              : currentAppLocalizations.vgWebLoginConfirm(email),
        ),
        confirmText: currentAppLocalizations.vgWebLoginAction,
      );
      if (res != true) return;
      final ok = await auth.loginWithToken(token);
      globalState.showNotifier(ok
          ? currentAppLocalizations.vgWebLoginDone(email)
          : (ref.read(vogueslyAuthProvider).error ??
              currentAppLocalizations.vgWebLoginExpired));
    } finally {
      _webLoginBusy = false;
    }
  }

  void _autoUpdateProfilesTask() {
    _autoUpdateProfilesTaskTimer = Timer(const Duration(minutes: 20), () async {
      await ref.read(profilesActionProvider.notifier).autoUpdateProfiles();
      _autoUpdateProfilesTask();
    });
  }

  Widget _buildPlatformState({required Widget child}) {
    if (system.isDesktop) {
      return WindowManager(
        child: TrayManager(
          child: HotKeyManager(child: ProxyManager(child: child)),
        ),
      );
    }
    return AndroidManager(child: TileManager(child: child));
  }

  Widget _buildState({required Widget child}) {
    return AppStateManager(
      child: CoreManager(
        child: ConnectivityManager(
          onConnectivityChanged: (results) async {
            commonPrint.log('connectivityChanged ${results.toString()}');
            ref.read(systemActionProvider.notifier).updateLocalIp();
            final hasVpn = results.contains(ConnectivityResult.vpn);
            if (_preHasVpn == hasVpn) {
              ref.read(checkIpNumProvider.notifier).add();
            }
            _preHasVpn = hasVpn;
          },
          child: child,
        ),
      ),
    );
  }

  Widget _buildPlatformApp({required Widget child}) {
    if (system.isDesktop) {
      return WindowHeaderContainer(child: child);
    }
    return VpnManager(child: child);
  }

  Widget _buildApp({required Widget child}) {
    return StatusManager(child: ThemeManager(child: child));
  }

  @override
  Widget build(context) {
    return Consumer(
      builder: (_, ref, child) {
        final locale = ref.watch(
          appSettingProvider.select((state) => state.locale),
        );
        final themeProps = ref.watch(themeSettingProvider);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: globalState.navigatorKey,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          builder: (_, child) {
            return AppEnvManager(
              child: _buildApp(
                child: _buildPlatformState(
                  child: _buildState(child: _buildPlatformApp(child: child!)),
                ),
              ),
            );
          },
          scrollBehavior: BaseScrollBehavior(),
          title: appName,
          locale: utils.getLocaleForString(locale),
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          themeMode: themeProps.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            pageTransitionsTheme: _pageTransitionsTheme,
            colorScheme: _getAppColorScheme(
              brightness: Brightness.light,
              primaryColor: themeProps.primaryColor,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            pageTransitionsTheme: _pageTransitionsTheme,
            colorScheme: _getAppColorScheme(
              brightness: Brightness.dark,
              primaryColor: themeProps.primaryColor,
            ).toPureBlack(themeProps.pureBlack),
          ),
          home: child!,
        );
      },
      child: const VogueslyGate(),
    );
  }

  @override
  Future<void> dispose() async {
    linkManager.destroy();
    _autoUpdateProfilesTaskTimer?.cancel();
    await coreController.destroy();
    await ref.read(systemActionProvider.notifier).handleExit();
    super.dispose();
  }
}
