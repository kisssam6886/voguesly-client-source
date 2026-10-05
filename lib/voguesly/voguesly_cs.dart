import 'dart:async';
import 'dart:io';
import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/print.dart' show commonPrint;
import 'package:fl_clash/enum/enum.dart' show LogLevel, PageLabel;
import 'package:fl_clash/providers/providers.dart'
    show currentPageLabelProvider, isMobileViewProvider, navigationStateProvider;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:fl_clash/widgets/scaffold.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as ww;

import '../state.dart' show globalState;
import '../views/tools.dart' show showVogueslyFeedbackSheet;
import 'voguesly_auth.dart';
import 'voguesly_overlay.dart';
import 'voguesly_remote_config.dart' show vogueslyCsHosts;

/// 客服网页入口(app + 网页共用同一套 cs.html),按次序试。
/// [0.9.83] 09-22 大陆探针(旁路由直连,各 3 轮)实测:
///   cs-sg.syk.ccwu.cc(原本唯一入口)0/6 —— TLS 握手后即断 = 域名(SNI)被封 ⇒ 未连上嘅用户打开客服一直白屏;已唔再用。
///   cs.ylink.live 3/3 ≈0.29 秒(CF → SG,客服专用子域,Sam 定:唔同官网 ylink.live 共用);
///   cs.ylink.im 3/3 ≈1.2 秒(CF → SG,另一个根域做后备 —— 一个根域被封另一个照通)。
const List<String> _kCsHosts = [
  'https://cs.ylink.live/cs.html',
  'https://cs.ylink.im/cs.html',
  'https://cs.yilian.live/cs.html', // [0.9.91] 第三根域(CF 橙云 → HK → SG);ylink.im 整根域被封时仍通
];

/// 每个入口等几耐未载完就换下一个。
const Duration _kCsHostTimeout = Duration(seconds: 10);

/// [0.9.92] 实际用嘅客服入口:version.json app_config.hosts.cs 排先,再接内置 [_kCsHosts]。
List<String> get _csHostList => vogueslyCsHosts(_kCsHosts);

/// 客服页 URL:embed=1 = app 内嵌模式(有关闭桥),embed=0 = 外部浏览器完整页。
Uri _csUri(String email, {required bool embed, int host = 0}) {
  final ver = vogueslyCsAppVersion();
  final hosts = _csHostList;
  return Uri.parse(hosts[host.clamp(0, hosts.length - 1)]).replace(queryParameters: {
    'embed': embed ? '1' : '0',
    if (email.isNotEmpty) 'email': email,
    if (ver.isNotEmpty) 'app_version': ver,
  });
}

/// [0.9.90] 客服页 cs.js 嘅 getClientMeta 读 `?app_version=`,之前冇传 ⇒ 客服睇唔到客户用边个版本
/// (09-24 yydsorz Windows 会话 client_meta.app_version 係空,问「TUN 授权未通过」要人手再问)。
/// 例:`0.9.90+2026092450`。packageInfo 喺启动时载入;未载入(测试 / 极早期)就唔带。
@visibleForTesting
String vogueslyCsAppVersion() {
  try {
    final p = globalState.packageInfo;
    return p.buildNumber.isEmpty ? p.version : '${p.version}+${p.buildNumber}';
  } catch (_) {
    return '';
  }
}

/// 「客服」页标题栏刷新掣 → 通知 panel 由第一个入口重新载入。
final ValueNotifier<int> vogueslyCsReloadTick = ValueNotifier<int>(0);

/// 平台分流:
/// - macOS = webview_flutter(WKWebView)内嵌半框 overlay;
/// - **Windows = webview_windows(in-app 嵌入 WebView2 texture,同 overlay 一致)** ——
///   webview_flutter 无 Windows 实现;desktop_webview_window(独立窗)在部分 Windows native crash
///   (0.9.49 试过、0.9.50 revert)。webview_windows 把 WebView2 当 Flutter texture 嵌在内容区,
///   不开独立窗、不占浏览器 tab、更稳;初始化失败(WebView2 runtime 未装等)自动退外部浏览器,不崩。
/// - Linux = 系统浏览器(无成熟 in-app webview)。
bool get _csUseExternalBrowser => !kIsWeb && Platform.isLinux;
bool get _csUseWindowsWebview => !kIsWeb && Platform.isWindows;

/// 注入 VogueslyCS 桥 shim → cs.html/cs.js 原本的 `VogueslyCS.postMessage('close'|'feedback'|'open:…')`
/// 经 WebView2 postMessage 传回 app(webMessage 流),**无需改 cs.html**。
const String _kCsShim =
    'window.VogueslyCS={postMessage:function(m){try{window.chrome.webview.postMessage(String(m));}catch(e){}}};';

/// 用系统默认浏览器打开客服页(Linux 及 Windows WebView2 不可用时兜底)。全程 try/catch 防崩。
Future<void> _launchCsExternal(ProviderContainer container) async {
  try {
    final email = container.read(vogueslyAuthProvider).user?.email ?? '';
    final ok = await launchUrl(
      _csUri(email, embed: false),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) {
      globalState.showNotifier(currentAppLocalizations.vgCannotOpenSupportManually);
    }
  } catch (_) {
    globalState.showNotifier(currentAppLocalizations.vgOpenSupportFailedRetry);
  }
}

/// 易联 · 在线客服 = 内嵌**共享网页客服页**(app + 网页同一套 cs.html)。
///
/// ⚠️ macOS/Windows 只覆盖**右边内容区**(半框,左侧栏保留可点,Sam 要求),由 app_manager 喺内容
/// Expanded 内 Positioned.fill 渲染。关闭经 `VogueslyCS`.postMessage('close')。
class VogueslyCsPanel extends ConsumerStatefulWidget {
  const VogueslyCsPanel({super.key});

  /// 开客服:Linux → 系统浏览器;手机 → 全页 push webview;桌面 macOS/Windows → 半框 overlay。
  static void open(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    if (_csUseExternalBrowser) {
      _launchCsExternal(container);
      return;
    }
    final w = MediaQuery.maybeOf(context)?.size.width ?? 0;
    final isMobile = w > 0 && w < 640;
    if (isMobile) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const VogueslyCsPanel()),
      );
      return;
    }
    final overlay = container.read(contentOverlayProvider);
    final onSupportTab = overlay == ContentOverlay.none &&
        container.read(currentPageLabelProvider) == PageLabel.support;
    // 已经开住客服再撳一次 = 重新载入(Sam:白屏时撳「在线客服」可以重新加载)
    if (overlay == ContentOverlay.cs || onSupportTab) {
      vogueslyCsReloadTick.value++;
      return;
    }
    // [0.9.84] 桌面统一去一级 tab「在线客服」(保活嗰个 WebView),唔再另开一个半框 overlay ——
    // 否则「账户与设置」入口开嘅系第二个 WebView,切走又重新加载,同侧栏入口唔一致。
    // 万一侧栏冇客服 tab(理论上唔会),先退返旧嘅半框 overlay。
    final hasSupportTab = container
        .read(navigationStateProvider)
        .navigationItems
        .any((e) => e.label == PageLabel.support);
    if (hasSupportTab) {
      container.read(contentOverlayProvider.notifier).close();
      container.read(currentPageLabelProvider.notifier).toPage(PageLabel.support);
      return;
    }
    container.read(contentOverlayProvider.notifier).set(ContentOverlay.cs);
  }

  @override
  ConsumerState<VogueslyCsPanel> createState() => _VogueslyCsPanelState();
}

class _VogueslyCsPanelState extends ConsumerState<VogueslyCsPanel> {
  WebViewController? _ctrl; // webview_flutter(macOS/mobile)
  ww.WebviewController? _winCtrl; // webview_windows(Windows)
  bool _winReady = false;
  bool _winFailed = false;
  // [0.9.83] 多入口 + 超时换入口 + 载入中遮罩 + 全部失败时「重新加载」(以前白屏就一直白屏)
  int _hostIdx = 0;
  bool _loading = true;
  bool _allFailed = false;
  Timer? _hostTimer;
  int _attempt = 0; // 每次 _loadCurrent +1;旧尝试迟到嘅「完成 / 失败」回调一律忽略

  String get _currentHost => Uri.parse(_csHostList[_hostIdx.clamp(0, _csHostList.length - 1)]).host;

  String get _email => ref.read(vogueslyAuthProvider).user?.email ?? '';

  void _loadCurrent() {
    _hostTimer?.cancel();
    if (mounted && (!_loading || _allFailed)) {
      setState(() {
        _loading = true;
        _allFailed = false;
      });
    } else {
      _loading = true;
      _allFailed = false;
    }
    final attempt = ++_attempt;
    _hostTimer = Timer(_kCsHostTimeout, () {
      if (attempt == _attempt) _nextHost('timeout');
    });
    final uri = _csUri(_email, embed: true, host: _hostIdx);
    try {
      if (_winCtrl != null) {
        _winCtrl!.loadUrl(uri.toString());
      } else {
        _ctrl?.loadRequest(uri);
      }
    } catch (_) {
      _onError('load exception');
    }
  }

  void _nextHost(String why) {
    _hostTimer?.cancel();
    if (!mounted) return;
    commonPrint.log('[cs] host#$_hostIdx 载入失败($why),换下一个入口', logLevel: LogLevel.warning);
    if (_hostIdx + 1 < _csHostList.length) {
      _hostIdx++;
      _loadCurrent();
    } else {
      setState(() {
        _loading = false;
        _allFailed = true;
      });
    }
  }

  /// 「页面载完」回调:错误页(Android)/ WebView2 失败时一样会报完成,
  /// 所以等 300ms,期间冇报错(_attempt 未变)先当真载好。
  void _onLoaded() {
    final attempt = _attempt;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || attempt != _attempt || !_loading) return;
      _hostTimer?.cancel();
      setState(() => _loading = false);
    });
  }

  void _onError(String why) {
    if (!_loading) return; // 已经载好,子资源报错唔理
    _nextHost(why);
  }

  void _reloadFromFirst() {
    _hostIdx = 0;
    _loadCurrent();
  }

  @override
  void initState() {
    super.initState();
    vogueslyCsReloadTick.addListener(_reloadFromFirst);
    if (_csUseExternalBrowser) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _launchCsExternal(ProviderScope.containerOf(context, listen: false));
      });
      _giveUpKeepAlive();
      return;
    }
    if (_csUseWindowsWebview) {
      _initWindowsWebview();
      return;
    }
    try {
      _ctrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel('VogueslyCS', onMessageReceived: (m) {
          _handleCsMessage(m.message);
        })
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: (_) => _onLoaded(),
          onWebResourceError: (e) {
            if (!(e.isForMainFrame ?? true)) return;
            // 换入口时 WKWebView 会将上一个导航报「已取消」(-999),唔係失败;
            // 迟到嘅旧入口报错(url 唔係当前入口)亦唔算
            if (e.errorCode == -999) return;
            final failedHost = e.url == null ? null : Uri.tryParse(e.url!)?.host;
            if (failedHost != null && failedHost.isNotEmpty && failedHost != _currentHost) return;
            _onError('error ${e.errorCode} ${e.description}');
          },
        ));
      _loadCurrent();
    } catch (_) {
      // 任何平台 webview 初始化异常都唔崩,交 build 显示回退卡。
      _ctrl = null;
      _giveUpKeepAlive();
    }
  }

  /// 内嵌 WebView 起唔到(WebView2 未装 / 初始化异常 / Linux 外部浏览器)→ **唔保活**,退返旧行为:
  /// 切走即销毁,下次开再重新试一次(Windows 会再自动开外部浏览器)。
  /// 唔系嘅话会一直保住张回退卡,切返嚟唔再自动开浏览器。
  /// ⚠️ initState 入面唔可以直接改 provider(riverpod 会报 build 期间修改),所以推到下一帧。
  void _giveUpKeepAlive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(csAliveProvider.notifier).destroy();
    });
  }

  /// Windows:in-app WebView2。注入 VogueslyCS shim + 监听 webMessage;
  /// 初始化失败(WebView2 runtime 未装等)→ 退外部浏览器,全程 try/catch 不崩。
  Future<void> _initWindowsWebview() async {
    try {
      final c = ww.WebviewController();
      await c.initialize();
      await c.addScriptToExecuteOnDocumentCreated(_kCsShim);
      c.webMessage.listen((message) {
        _handleCsMessage(message is String ? message : message.toString());
      });
      c.loadingState.listen((s) {
        if (s == ww.LoadingState.navigationCompleted) _onLoaded();
      });
      c.onLoadError.listen((st) {
        if (st == ww.WebErrorStatus.WebErrorStatusOperationCanceled) return; // 换入口取消上一个导航
        _onError('webview2 $st');
      });
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _winCtrl = c;
        _winReady = true;
      });
      _loadCurrent();
    } catch (_) {
      if (mounted) setState(() => _winFailed = true);
      _launchCsExternal(ProviderScope.containerOf(context, listen: false));
      _giveUpKeepAlive();
    }
  }

  void _handleCsMessage(String message) {
    if (message == 'close') {
      // 桌面 overlay 走 provider close;手机全页 push 走 Navigator.pop。
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        // 用户喺客服页主动撳关闭 = 真正关闭:销毁保活(下次开重新加载),唔系收埋。
        ref.read(csAliveProvider.notifier).destroy();
        ref.read(contentOverlayProvider.notifier).close();
      }
    } else if (message == 'feedback') {
      if (mounted) showVogueslyFeedbackSheet(context);
    } else if (message.startsWith('open:')) {
      final uri = Uri.tryParse(message.substring(5));
      // [0.9.91] 只开 https(客服页本身都只会传 https;防网页被注入后叫 App 开其他协议)。
      if (uri != null && uri.scheme == 'https') {
        launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  void dispose() {
    _hostTimer?.cancel();
    vogueslyCsReloadTick.removeListener(_reloadFromFirst);
    _winCtrl?.dispose();
    super.dispose();
  }

  /// 载入中遮罩 / 全部入口失败卡(叠喺 webview 上面)。
  Widget _withStatus(Widget web) {
    final cs = Theme.of(context).colorScheme;
    final l = currentAppLocalizations;
    return Stack(
      children: [
        Positioned.fill(child: web),
        if (_loading || _allFailed)
          Positioned.fill(
            child: Container(
              color: cs.surface,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(l.vgCsLoading, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(l.vgCsLoadingHint,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ] else ...[
                    const Icon(Icons.support_agent_outlined, size: 40),
                    const SizedBox(height: 12),
                    Text(l.vgCsAllFailed, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: _reloadFromFirst,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(l.vgCsReload),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _launchCsExternal(ProviderScope.containerOf(context, listen: false)),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: Text(l.vgOpenSupportInBrowser),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    // Windows:WebView2 就绪 → 内嵌;初始化中 → loading;失败 → 回退卡(下方)。
    if (_csUseWindowsWebview && _winReady && _winCtrl != null) {
      return Container(color: surface, child: _withStatus(ww.Webview(_winCtrl!)));
    }
    if (_csUseWindowsWebview && !_winFailed) {
      return Container(
        color: surface,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    // Linux / Windows WebView2 失败 / webview_flutter 初始化失败:回退卡,唔崩。
    if (_csUseExternalBrowser || _csUseWindowsWebview || _ctrl == null) {
      return Container(
        color: surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.support_agent_outlined, size: 40),
                const SizedBox(height: 12),
                Text(
                  _csUseWindowsWebview ? currentAppLocalizations.vgLiveChatUnavailableUseBrowser : currentAppLocalizations.vgLiveChatOpenedInBrowser,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _launchCsExternal(
                    ProviderScope.containerOf(context, listen: false),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(currentAppLocalizations.vgOpenSupportInBrowser),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      color: surface,
      child: _withStatus(WebViewWidget(controller: _ctrl!)),
    );
  }
}

/// 一级 tab「客服」用嘅页(2026-09-18 Sam:客服升一级):CommonScaffold 包住现有 VogueslyCsPanel。
/// 桌面侧栏「在线客服」/ 安卓底栏「客服」都指呢度;「我的」页大按钮仍走 VogueslyCsPanel.open()。
class VogueslySupportPage extends StatelessWidget {
  const VogueslySupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: Intl.message('support'),
      // [0.9.83 Sam] 客服白屏 / 好慢时可以手动重新载入
      actions: [
        IconButton(
          tooltip: currentAppLocalizations.vgCsReload,
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => vogueslyCsReloadTick.value++,
        ),
      ],
      body: const _CsKeepAliveHost(),
    );
  }
}

/// 一级 tab「在线客服」嘅 WebView 宿主:**桌面**切走 tab 时保活(唔 dispose),切返嚟唔再重新加载。
///
/// 做法:tab 本身 keep:true(PageView 保住个壳,见 navigation.dart),WebView 几时真正销毁由
/// csAliveProvider 决定(关闭 / 隐藏 15 分钟 / 登出 / WebView 起唔到)。
/// 隐藏时 ExcludeFocus 唔抢键盘、TickerMode 停动画;PageView 离屏本身唔画、唔命中点击。
/// 手机底栏唔保活(同 0.9.83 一样切走即销毁),免得 Android WebView 长驻后台。
class _CsKeepAliveHost extends ConsumerWidget {
  const _CsKeepAliveHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(contentOverlayProvider) == ContentOverlay.none &&
        ref.watch(currentPageLabelProvider) == PageLabel.support;
    final alive = ref.watch(csAliveProvider);
    final isMobile = ref.watch(isMobileViewProvider);
    final keep = visible || (alive && !isMobile);
    return ExcludeFocus(
      excluding: !visible,
      child: TickerMode(
        enabled: visible,
        child: keep ? const VogueslyCsPanel() : const SizedBox.shrink(),
      ),
    );
  }
}
