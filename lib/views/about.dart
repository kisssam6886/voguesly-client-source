import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/list.dart';
import 'package:fl_clash/widgets/scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_clash/voguesly/voguesly_remote_config.dart' show vogueslyTelegramUrl, vogueslyOfficialSiteUrl, vogueslyText;

class AboutView extends StatelessWidget {
  const AboutView({super.key});

  List<Widget> _buildMoreSection(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return generateSection(
      separated: false,
      title: appLocalizations.more,
      items: [
        ListItem(
          title: Text(currentAppLocalizations.vgTelegramSupport),
          // 自家可信链接直接开,唔弹「外部链接+裸URL」确认框(消费者会觉得似钓鱼)。
          onTap: () => launchUrl(
            Uri.parse(vogueslyTelegramUrl('https://t.me/easysvpn')), // [0.9.92] 可由 app_config.links 下发
            mode: LaunchMode.externalApplication,
          ),
          trailing: const Icon(Icons.launch),
        ),
        ListItem(
          title: Text(currentAppLocalizations.vgOfficialSite),
          // [0.9.83] 官网 → ylink.live(大陆可达 10/10;voguesly.com 整域被封,cp.samseah.qzz.io 只係备用面板域名)
          onTap: () => launchUrl(
            Uri.parse(vogueslyOfficialSiteUrl('https://ylink.live')), // [0.9.92] 可由 app_config.links 下发
            mode: LaunchMode.externalApplication,
          ),
          trailing: const Icon(Icons.launch),
        ),
        // [0.9.83] 头像插画授权署名(CC BY 4.0 要求)
        ListItem(
          title: Text(currentAppLocalizations.vgAvatarCredit),
          subtitle: const Text('DiceBear Adventurer · Lisa Wischofsky · CC BY 4.0'),
          onTap: () => launchUrl(
            Uri.parse('https://www.dicebear.com/styles/adventurer/'),
            mode: LaunchMode.externalApplication,
          ),
          trailing: const Icon(Icons.launch),
        ),
        // [0.9.98] GPL-3.0 合规:注明上游(FlClash / mihomo)+ 源代码入口(每个发布版喺 voguesly-client-source 有对应 tag)
        ListItem(
          title: Text(currentAppLocalizations.vgOpenSource),
          subtitle: Text(currentAppLocalizations.vgOpenSourceDesc),
          onTap: () => launchUrl(
            Uri.parse('https://github.com/kisssam6886/voguesly-client-source'),
            mode: LaunchMode.externalApplication,
          ),
          trailing: const Icon(Icons.launch),
        ),
        // [0.9.98] 第三方组件授权声明(Flutter 自动汇总所有依赖包嘅 LICENSE)
        ListItem(
          title: Text(currentAppLocalizations.vgThirdPartyLicenses),
          onTap: () => showLicensePage(
            context: context,
            applicationName: appName,
            applicationVersion: globalState.packageInfo.version,
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final items = [
      ListTile(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Consumer(
              builder: (_, ref, _) {
                return _DeveloperModeDetector(
                  child: Wrap(
                    spacing: 16,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Image.asset(
                          'assets/images/icon.png',
                          width: 64,
                          height: 64,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appName,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text(
                            globalState.packageInfo.version,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ],
                  ),
                  onEnterDeveloperMode: () {
                    ref
                        .read(appSettingProvider.notifier)
                        .update((state) => state.copyWith(developerMode: true));
                    context.showNotifier(
                      appLocalizations.developerModeEnableTip,
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              vogueslyText('vgAboutTagline', currentAppLocalizations.vgAboutTagline),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      ..._buildMoreSection(context),
    ];
    return BaseScaffold(
      title: appLocalizations.about,
      body: Padding(
        padding: kMaterialListPadding.copyWith(top: 16, bottom: 16),
        child: generateListView(items),
      ),
    );
  }
}

class _DeveloperModeDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onEnterDeveloperMode;

  const _DeveloperModeDetector({
    required this.child,
    required this.onEnterDeveloperMode,
  });

  @override
  State<_DeveloperModeDetector> createState() => _DeveloperModeDetectorState();
}

class _DeveloperModeDetectorState extends State<_DeveloperModeDetector> {
  int _counter = 0;
  Timer? _timer;

  void _handleTap() {
    _counter++;
    if (_counter >= 5) {
      widget.onEnterDeveloperMode();
      _resetCounter();
    } else {
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 1), _resetCounter);
    }
  }

  void _resetCounter() {
    _counter = 0;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: _handleTap, child: widget.child);
  }
}
