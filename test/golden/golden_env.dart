// [0.9.83] 离线出图(golden)环境:只喺 YL_GOLDEN=1 先跑,平时 / CI 自动跳过(字体路径系本机)。
// 用法:YL_GOLDEN=1 flutter test test/golden --update-goldens → PNG 出喺 test/golden/goldens/(已 gitignore)。
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

final bool goldenEnabled = Platform.environment['YL_GOLDEN'] == '1';
const _cjk = '/Users/sam/Developer/voguesly-buddy/font/NotoSansSC-VariableFont_wght.ttf';
const _materialIcons = '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';

Future<void> _load(String family, List<String> paths) async {
  final l = FontLoader(family);
  for (final p in paths) {
    final b = File(p).readAsBytesSync();
    l.addFont(Future.value(ByteData.view(Uint8List.fromList(b).buffer)));
  }
  await l.load();
}

/// 页面级出图要嘅假环境:版本号、app 目录(path_provider)、SharedPreferences。
void setupGoldenStubs() {
  TestWidgetsFlutterBinding.ensureInitialized();
  globalState.packageInfo = PackageInfo(appName: 'Voguesly', packageName: 'com.voguesly.app', version: '0.9.83', buildNumber: '2026092301');
  SharedPreferences.setMockInitialValues({});
  final dir = Directory.systemTemp.createTempSync('ylgold').path;
  for (final ch in ['plugins.flutter.io/path_provider', 'plugins.flutter.io/path_provider_macos']) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(ch), (_) async => dir);
  }
}

Future<void> loadGoldenFonts() async {
  setupGoldenStubs();
  await _load('NotoSansSC', [_cjk]);
  await _load('MaterialIcons', [_materialIcons]);
  await _load('Gelasio', ['assets/fonts/Gelasio-Regular.ttf', 'assets/fonts/Gelasio-SemiBold.ttf']);
}

ThemeData goldenTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'NotoSansSC',
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF7C5CF6),
        brightness: Brightness.dark,
        dynamicSchemeVariant: DynamicSchemeVariant.content,
      ),
    );

/// 包住被测 widget:本地化(简中)+ 主题 + 初始化 globalState.measure / theme(dashboard 卡要用)。
Widget goldenApp(Widget child, {List overrides = const [], Size size = const Size(420, 300)}) {
  return ProviderScope(
    overrides: [...overrides],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: goldenTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(builder: (context) {
        globalState.measure = Measure.of(context, 1.0);
        globalState.theme = CommonTheme.of(context, 1.0);
        return Scaffold(
          body: Center(child: SizedBox(width: size.width, child: child)),
        );
      }),
    ),
  );
}

Future<void> pumpGolden(WidgetTester tester, Widget w, {Size surface = const Size(460, 340), List overrides = const []}) async {
  tester.view.physicalSize = surface * 2;
  tester.view.devicePixelRatio = 2;
  await tester.pumpWidget(goldenApp(w, overrides: overrides, size: Size(surface.width - 40, surface.height)));
  // 图片资源(头像 webp)要真解码
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      final img = e.widget as Image;
      await precacheImage(img.image, e);
    }
  });
  await tester.pumpAndSettle();
}
