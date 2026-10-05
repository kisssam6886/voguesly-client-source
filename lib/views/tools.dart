import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/voguesly/voguesly_custom_nodes_view.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/about.dart';
import 'package:fl_clash/views/access.dart';
import 'package:fl_clash/views/application_setting.dart';
import 'package:fl_clash/views/backup_and_restore.dart';
import 'package:fl_clash/views/config/config.dart';
import 'package:fl_clash/views/hotkey.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:fl_clash/voguesly/voguesly_noplan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' show dirname, join;
import 'package:connectivity_plus/connectivity_plus.dart';

import '../voguesly/voguesly_auth.dart';
import '../voguesly/voguesly_cs.dart';
import '../voguesly/voguesly_diag_report.dart';
import '../voguesly/voguesly_diagnosis.dart' show diagnoseLocal;
import '../voguesly/voguesly_invite.dart';
import '../voguesly/voguesly_notice.dart';
import '../voguesly/voguesly_shop.dart';
import '../voguesly/voguesly_stat.dart';
import '../voguesly/voguesly_subscription.dart';
import '../voguesly/voguesly_tickets.dart';
import '../voguesly/voguesly_user_center.dart';
import 'profiles/profiles.dart';
import 'config/advanced.dart';
import 'dashboard/widgets/outbound_mode.dart' show showGlobalModeNoticeIfNeeded;
import 'dashboard/widgets/voguesly_account.dart' show VogueslyAccount;
import '../voguesly/voguesly_tour.dart' show startVogueslyTour;
import 'developer.dart';
import 'logs.dart';
import 'theme.dart';

class ToolsView extends ConsumerStatefulWidget {
  const ToolsView({super.key});

  @override
  ConsumerState<ToolsView> createState() => _ToolViewState();
}

class _ToolViewState extends ConsumerState<ToolsView> {
  List<Widget> _getOtherList(bool enableDeveloperMode) {
    return generateSection(
      title: context.appLocalizations.other,
      separated: false,
      items: [
        // 移除 FlClash 免责声明项(「仅供学习交流·严禁商业」同付费产品自打脸,且点退出会强杀App)。
        if (enableDeveloperMode) const _DeveloperItem(),
        const _InfoItem(),
        const _VersionItem(),
        const _LogoutItem(),
      ],
    );
  }

  List<Widget> _getSettingList() {
    return generateSection(
      title: context.appLocalizations.settings,
      separated: false, // [0.9.83] 同「服务 / 遇到问题」一致,唔要分隔线
      items: [
        const _AccelModeItem(),
        const _LocaleItem(),
        const _ThemeItem(),
        // 进阶项全部收埋落子页(应用设置/日志/基本配置/请求/连接/资源/备份/访问控制/进阶配置),保持简洁
        const _AdvancedItem(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm2 = ref.watch(
      appSettingProvider.select(
        (state) => VM2(state.locale, state.developerMode),
      ),
    );
    // [0.9.83 门面改版] 按「常用 → 唔常用」分组加标题:账号 → 保持最新(更新订阅)→ 购买 / 客服 → 服务 → 遇到问题 → 设置 → 其他
    final items = [
      // [0.9.83] 同首页共用新版账号卡(头像圈 / 套餐胶囊 / 衬线数字 / 渐变进度条 / 在线设备),唔再维护两套
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
        child: VogueslyAccount(),
      ),
      const _SubscriptionEntry(),
      // [0.9.91] 高级功能开住先有:添加单独节点(Sam 09-25,为新疆呢类要单独开节点嘅客户)
      if (vm2.b) const _CustomNodesItem(),
      const _QuickActions(),
      ...generateSection(
        title: currentAppLocalizations.vgSectionServices,
        separated: false,
        items: const [_AccountServices()],
      ),
      // ⚠️ [2026-09-18 Sam 明确要求] 反馈问题/上传日志 · 我的工单 · 查看日志 三项**必须留喺一级**,
      //   係特登为小白设计:一键上传日志 → Sam 即时收到 TG 通知;工单未关时唔可以再上传,所以要有「我的工单」入口;
      //   服务器出事时用户可以自己复制日志链接。唔准再收入「进阶」。只有「应用设置」(12 个开关)收入进阶。
      //   [0.9.83] 只係加个「遇到问题」标题归埋一组,仍然一级。
      ...generateSection(
        title: currentAppLocalizations.vgSectionHelp,
        separated: false,
        items: const [_FeedbackItem(), _MyTicketsItem(), _LogsViewItem(), _TourReplayItem()],
      ),
      ..._getSettingList(),
      // 诊断项(请求/连接/资源)收入「进阶工具」子页,「我的」一级唔再露工程化菜单。
      ..._getOtherList(vm2.b),
    ];
    return CommonScaffold(
      title: context.appLocalizations.tools,
      body: ListView.builder(
        key: toolsStoreKey,
        itemCount: items.length,
        itemBuilder: (_, index) => items[index],
        padding: const EdgeInsets.only(bottom: 20),
      ),
    );
  }
}

class _LocaleItem extends ConsumerWidget {
  const _LocaleItem();

  String _getLocaleString(BuildContext context, Locale? locale) {
    if (locale == null) return context.appLocalizations.defaultText;
    const names = {
      'zh_CN': '简体中文',
      'zh_Hant': '繁體中文',
      'en': 'English',
      'ja': '日本語',
      'ru': 'Русский',
    };
    return names[locale.toString()] ?? Intl.message(locale.toString());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(
      appSettingProvider.select((state) => state.locale),
    );
    final currentLocale = utils.getLocaleForString(locale);
    return ListItem<Locale?>.options(
      leading: const Icon(Icons.language_outlined),
      title: Text(context.appLocalizations.language),
      subtitle: Text(_getLocaleString(context, currentLocale)),
      delegate: OptionsDelegate(
        title: context.appLocalizations.language,
        options: [null, ...AppLocalizations.delegate.supportedLocales],
        onChanged: (Locale? locale) {
          ref
              .read(appSettingProvider.notifier)
              .update((state) => state.copyWith(locale: locale?.toString()));
        },
        textBuilder: (locale) => _getLocaleString(context, locale),
        value: currentLocale,
      ),
    );
  }
}

class _ThemeItem extends StatelessWidget {
  const _ThemeItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const Icon(Icons.style),
      title: Text(context.appLocalizations.theme),
      subtitle: Text(context.appLocalizations.themeDesc),
      delegate: const OpenDelegate(widget: ThemeView()),
    );
  }
}

class _BackupItem extends StatelessWidget {
  const _BackupItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const Icon(Icons.cloud_sync),
      title: Text(context.appLocalizations.backupAndRestore),
      subtitle: Text(context.appLocalizations.backupAndRestoreDesc),
      delegate: const OpenDelegate(widget: BackupAndRestore()),
    );
  }
}

class _HotkeyItem extends StatelessWidget {
  const _HotkeyItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const Icon(Icons.keyboard),
      title: Text(context.appLocalizations.hotkeyManagement),
      subtitle: Text(context.appLocalizations.hotkeyManagementDesc),
      delegate: const OpenDelegate(widget: HotKeyView()),
    );
  }
}

class _LoopbackItem extends StatelessWidget {
  const _LoopbackItem();

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: const Icon(Icons.lock),
      title: Text(context.appLocalizations.loopback),
      subtitle: Text(context.appLocalizations.loopbackDesc),
      onTap: () {
        windows?.runas(
          '"${join(dirname(Platform.resolvedExecutable), "EnableLoopback.exe")}"',
          '',
        );
      },
    );
  }
}

class _AccessItem extends StatelessWidget {
  const _AccessItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const Icon(Icons.view_list),
      title: Text(context.appLocalizations.accessControl),
      subtitle: Text(context.appLocalizations.accessControlDesc),
      delegate: const OpenDelegate(widget: AccessView()),
    );
  }
}

class _ConfigItem extends StatelessWidget {
  const _ConfigItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const Icon(Icons.edit),
      title: Text(context.appLocalizations.basicConfig),
      subtitle: Text(context.appLocalizations.basicConfigDesc),
      delegate: const OpenDelegate(widget: ConfigView()),
    );
  }
}

class _AdvancedConfigItem extends StatelessWidget {
  const _AdvancedConfigItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const Icon(Icons.build),
      title: Text(context.appLocalizations.advancedConfig),
      subtitle: Text(context.appLocalizations.advancedConfigDesc),
      delegate: const OpenDelegate(widget: AdvancedConfigView()),
    );
  }
}

/// 进阶入口:把唔常用嘅项(备份/访问控制/进阶配置/快捷键/loopback)收埋落子页,保持工具页简洁。
class _AdvancedItem extends StatelessWidget {
  const _AdvancedItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const Icon(Icons.settings_suggest_outlined), // [0.9.83] 原本同「分流模式」都係 tune 图标
      title: Text(context.appLocalizations.advancedTools),
      subtitle: Text(currentAppLocalizations.vgAdvancedSubtitle), // [0.9.83] 提示一般唔使改
      delegate: const OpenDelegate(widget: _AdvancedToolsView()),
    );
  }
}

class _AdvancedToolsView extends ConsumerWidget {
  const _AdvancedToolsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 诊断项(请求/连接/资源)由「我的」一级收落嚟呢度,普通用户唔会见到工程化菜单。
    final diagnostics =
        ref.watch(moreToolsSelectorStateProvider).navigationItems;
    final items = <Widget>[
      const _SettingItem(), // 应用设置(12 个开关)—— 2026-09-18 由「我的」一级收落嚟
      const _ConfigItem(),
      const _BackupItem(),
      if (system.isDesktop) const _HotkeyItem(),
      if (system.isWindows) const _LoopbackItem(),
      if (system.isAndroid) const _AccessItem(),
      const _AdvancedConfigItem(),
      for (final item in diagnostics)
        ListItem.open(
          leading: item.icon,
          title: Text(Intl.message(item.label.name)),
          subtitle: item.description != null
              ? Text(Intl.message(item.description!))
              : null,
          delegate: OpenDelegate(widget: item.builder(context)),
        ),
    ];
    return BaseScaffold(
      title: context.appLocalizations.advancedTools,
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, index) => items[index],
        padding: const EdgeInsets.only(bottom: 20),
      ),
    );
  }
}

class _SettingItem extends StatelessWidget {
  const _SettingItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const Icon(Icons.settings),
      title: Text(context.appLocalizations.application),
      subtitle: Text(context.appLocalizations.applicationDesc),
      delegate: const OpenDelegate(widget: ApplicationSettingView()),
    );
  }
}

// ignore: unused_element
class _DisclaimerItem extends ConsumerWidget {
  const _DisclaimerItem();

  @override
  Widget build(BuildContext context, ref) {
    return ListItem(
      leading: const Icon(Icons.gavel),
      title: Text(context.appLocalizations.disclaimer),
      onTap: () async {
        final isDisclaimerAccepted = await globalState.showDisclaimer();
        if (!isDisclaimerAccepted) {
          await ref.read(systemActionProvider.notifier).handleExit();
        }
      },
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const Icon(Icons.info),
      title: Text(context.appLocalizations.about),
      delegate: const OpenDelegate(widget: AboutView()),
    );
  }
}

/// 版本号展示 + 点击手动检查更新(唔理「不再提示」开关,一定检查+一定俾结果,
/// 含「已是最新版」个案)。数据源见 kVogueslyVersionCheckUrls 自家域名,唔再打上游 GitHub。
class _VersionItem extends ConsumerStatefulWidget {
  const _VersionItem();

  @override
  ConsumerState<_VersionItem> createState() => _VersionItemState();
}

class _VersionItemState extends ConsumerState<_VersionItem> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    await ref.read(commonActionProvider.notifier).manualCheckUpdate();
    if (!mounted) return;
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final pkg = globalState.packageInfo;
    return ListItem(
      leading: const Icon(Icons.system_update_outlined),
      title: Text(currentAppLocalizations.vgVersionLabel),
      subtitle: Text(currentAppLocalizations.vgVersionTapToCheck(pkg.version)),
      trailing: _checking
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _check,
    );
  }
}

/// 顶部「购买/续费 + 联系客服」并排大按钮(显眼)。
/// ⚠️ 全部原生:购买续费开原生商城(webview 唔共享登录会弹登录页);联系客服开自建 AI 客服浮窗。
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _QuickActionCard(
              icon: Icons.shopping_bag_outlined,
              label: currentAppLocalizations.vgBuyOrRenew,
              onTap: () => VogueslyShopPage.open(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QuickActionCard(
              icon: Icons.support_agent_rounded,
              label: currentAppLocalizations.vgContactSupport,
              highlight: true, // [0.9.83 Sam] 客服要醒目:淡紫底 + 绿色在线点
              onTap: () => VogueslyCsPanel.open(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return Material(
      color: highlight
          ? cs.primary.withValues(alpha: 0.14)
          : cs.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              highlight
                  ? Badge(
                      smallSize: 8,
                      backgroundColor: const Color(0xFF22C55E),
                      child: Icon(icon, color: cs.primary, size: 26),
                    )
                  : Icon(icon, color: cs.primary, size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                style: context.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「加速模式」消费者向二选一:智能分流(推荐) / 全局加速。
/// 刻意唔暴露 FlClash 原版「直连」(= 唔加速嘅地雷:会显绿但流量裸奔)。
class _AccelModeItem extends ConsumerWidget {
  const _AccelModeItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(patchClashConfigProvider.select((s) => s.mode));
    final isGlobal = mode == Mode.global;
    // ⚠️ 三态判:direct=裸奔(会显绿但流量唔走节点),唔可以当「智能分流(推荐)」谎报。
    final (subtitle, warn) = switch (mode) {
      // 全局 = 唔再自动分流,IP 跟手选线路走(选机房就显示机房 IP),要讲明白。
      Mode.global => (currentAppLocalizations.vgGlobalModeSummary, false),
      Mode.direct => (currentAppLocalizations.vgDirectModeSummary, true),
      _ => (currentAppLocalizations.vgRuleModeSummary, false),
    };
    return ListItem(
      leading: Icon(Icons.call_split_rounded, color: warn ? const Color(0xFFEF4444) : null), // [0.9.83] 同首页分流卡同一图标
      title: Text(currentAppLocalizations.vgAccelerationMode),
      subtitle: Text(
        subtitle,
        style: warn
            ? const TextStyle(color: Color(0xFFEF4444))
            : null,
      ),
      onTap: () => _choose(context, ref, isGlobal),
    );
  }

  void _choose(BuildContext context, WidgetRef ref, bool isGlobal) {
    final cs = context.colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              isThreeLine: true,
              leading: Icon(Icons.alt_route, color: cs.primary),
              title: Text(currentAppLocalizations.vgSmartRoutingRecommended),
              subtitle: Text(
                currentAppLocalizations.vgSmartRoutingDesc1 +
                currentAppLocalizations.vgSmartRoutingDesc2,
              ),
              trailing: !isGlobal ? Icon(Icons.check, color: cs.primary) : null,
              onTap: () {
                ref.read(setupActionProvider.notifier).changeMode(Mode.rule);
                Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              isThreeLine: true,
              leading: Icon(Icons.public, color: cs.primary),
              title: Text(currentAppLocalizations.vgGlobalAcceleration),
              // ⚠️ 呢句係重点:全局会覆盖智能分流,IP 检测站会显示你手选嗰条线路。
              // 用户选咗机房线路再去测 IP,会以为「买咗住宅 IP 但显示机房」= 产品信任伤害。
              subtitle: Text(
                currentAppLocalizations.vgGlobalAccelDesc1 +
                currentAppLocalizations.vgGlobalAccelDesc2 +
                currentAppLocalizations.vgGlobalAccelDesc3,
              ),
              trailing: isGlobal ? Icon(Icons.check, color: cs.primary) : null,
              onTap: () {
                ref.read(setupActionProvider.notifier).changeMode(Mode.global);
                Navigator.of(ctx).pop();
                // 同仪表盘嗰个切换入口一致:rule → global 弹一次说明。
                showGlobalModeNoticeIfNeeded(
                  context,
                  isGlobal ? Mode.global : Mode.rule,
                  Mode.global,
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 全局可调:打开「反馈问题 / 上传日志」表单(设置页 + 在线客服「上传诊断日志」共用)。
void showVogueslyFeedbackSheet(BuildContext context) {
  showSheet(
    context: context,
    builder: (_) => AdaptiveSheetScaffold(
      body: const _FeedbackBody(),
      title: currentAppLocalizations.vgReportIssueUploadLogs,
    ),
  );
}

/// 「反馈问题 / 上传日志」—— 一键把描述 + 设备/版本 + 近期日志发俾客服(建工单)。
/// 客服喺面板见到工单 + Telegram 通知,凭用户 ID 快速定位问题。
/// 账号服务区(手机「我的」页):用户中心/邀请/公告/流量明细。
/// 桌面靠侧栏 ContentOverlay 入呢啲功能,手机无侧栏,喺度用全页 push 补齐入口。
class _AccountServices extends StatelessWidget {
  const _AccountServices();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListItem(
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(currentAppLocalizations.vgUserCenter),
          subtitle: Text(currentAppLocalizations.vgUserCenterSubtitle),
          onTap: () => VogueslyUserCenterPage.open(context),
        ),
        ListItem(
          leading: const Icon(Icons.card_giftcard_outlined),
          title: Text(currentAppLocalizations.vgReferralRewards),
          subtitle: Text(currentAppLocalizations.vgReferralSubtitle),
          onTap: () => VogueslyInvitePage.open(context),
        ),
        ListItem(
          leading: Consumer(
            builder: (_, ref, _) => Badge(
              isLabelVisible: ref.watch(vogueslyNoticeUnreadProvider),
              smallSize: 8,
              child: const Icon(Icons.campaign_outlined),
            ),
          ),
          title: Text(currentAppLocalizations.vgAnnouncements),
          subtitle: Text(currentAppLocalizations.vgAnnouncementsSubtitle),
          onTap: () => VogueslyNoticePage.open(context),
        ),
        ListItem(
          leading: const Icon(Icons.bar_chart_outlined),
          title: Text(currentAppLocalizations.vgDataUsage),
          subtitle: Text(currentAppLocalizations.vgDataUsageSubtitle),
          onTap: () => VogueslyStatPage.open(context),
        ),
      ],
    );
  }
}

/// [0.9.83] 再睇一次新手引导:跳返首页(引导要框住首页连接圆 + 导航),等一阵先开始。
class _TourReplayItem extends StatelessWidget {
  const _TourReplayItem();

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: const Icon(Icons.tips_and_updates_outlined),
      title: Text(currentAppLocalizations.vgTourReplay),
      subtitle: Text(currentAppLocalizations.vgTourReplaySubtitle),
      onTap: () {
        globalState.container.read(currentPageLabelProvider.notifier).toPage(PageLabel.dashboard);
        Future.delayed(const Duration(milliseconds: 700), () {
          final ctx = globalState.navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) startVogueslyTour(ctx);
        });
      },
    );
  }
}

class _FeedbackItem extends StatelessWidget {
  const _FeedbackItem();

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: const Icon(Icons.feedback_outlined),
      title: Text(currentAppLocalizations.vgReportIssueUploadLogs),
      subtitle: Text(currentAppLocalizations.vgReportIssueSubtitle),
      onTap: () => showVogueslyFeedbackSheet(context),
    );
  }
}

/// 2026-07-27 补:提交完反馈之后用户睇唔到客服有冇回、亦冇得跟进,唯有再开多张工单。
/// 呢度补返「我的工单」——列表 / 详情 / 继续回复 / 关闭,全部行 XBoard 现成 API。
class _MyTicketsItem extends StatelessWidget {
  const _MyTicketsItem();

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: const Icon(Icons.confirmation_number_outlined),
      title: Text(currentAppLocalizations.vgMyTickets),
      subtitle: Text(currentAppLocalizations.vgMyTicketsSubtitle),
      onTap: () => VogueslyTicketsPage.open(context),
    );
  }
}

/// 2026-07-27 补:上面「反馈问题/上传日志」只能上传,冇地方睇——LogsView 一直存在
/// 但成个 app 冇任何入口跳过去(孤儿页)。呢度补返个一级入口,等用户/客服自己都睇到实时日志。
class _LogsViewItem extends StatelessWidget {
  const _LogsViewItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const Icon(Icons.article_outlined),
      title: Text(currentAppLocalizations.vgViewLogs),
      subtitle: Text(currentAppLocalizations.vgViewLogsSubtitle),
      delegate: const OpenDelegate(widget: LogsView()),
    );
  }
}

class _FeedbackBody extends ConsumerStatefulWidget {
  const _FeedbackBody();

  @override
  ConsumerState<_FeedbackBody> createState() => _FeedbackBodyState();
}

class _FeedbackBodyState extends ConsumerState<_FeedbackBody> {
  final _desc = TextEditingController();
  bool _busy = false;
  // [0.9.90] 网络抖动自动重试时,按钮显示「网络不稳，正在重试（2/3）…」
  String? _retryHint;

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  /// 上传日志正文 + 工单主题。
  /// [0.9.89] 大改(09-24 审计):最前面一行摘要(TG 通知正文只显示前 600 字);加全部分组状态(内核实时)、
  ///   现场检测(关键组节点 + 国内站 + 面板)、本机诊断、订阅拉取记录、近 48 小时失败连接汇总;
  ///   警告 / 错误改由持久化问题日志出(之前 info 连接行 2 分钟就挤走晒,App 重启全冇)。
  Future<({String body, String subject})> _collectDiagnostics() async {
    final head = StringBuffer();
    var ver = '';
    try {
      final pkg = await PackageInfo.fromPlatform();
      ver = pkg.version;
      head.writeln(currentAppLocalizations.vgVersionBuildWith(pkg.version, pkg.buildNumber));
    } catch (_) {}
    // [2026-09-21] 之前只写 Android 设备资料,iOS / macOS / Windows 上传嘅日志连系统版本都冇。
    head.writeln('系统: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final d = await info.androidInfo;
        head.writeln(currentAppLocalizations.vgDeviceInfoWith(d.manufacturer, d.model, d.version.release));
      } else if (Platform.isIOS) {
        final d = await info.iosInfo;
        head.writeln('设备: ${d.utsname.machine} ${d.systemName} ${d.systemVersion}');
      } else if (Platform.isMacOS) {
        final d = await info.macOsInfo;
        head.writeln('设备: ${d.model} ${d.arch} macOS ${d.osRelease}');
      } else if (Platform.isWindows) {
        final d = await info.windowsInfo;
        head.writeln('设备: ${d.productName} build ${d.buildNumber}');
      }
    } catch (_) {}
    final c = globalState.container;
    var tun = false;
    var started = false;
    try {
      tun = c.read(realTunEnableProvider);
      started = c.read(isStartProvider);
      head.writeln('接管方式: TUN=$tun · 系统代理=${c.read(networkSettingProvider).systemProxy}');
    } catch (_) {}
    try {
      final net = await Connectivity().checkConnectivity();
      head.writeln('网络类型: ${net.map((e) => e.name).join('+')}'); // 只记类型,唔记 Wi-Fi 名称
    } catch (_) {}
    try {
      head.writeln('时区: ${DateTime.now().timeZoneName} (UTC${DateTime.now().timeZoneOffset.inHours >= 0 ? '+' : ''}${DateTime.now().timeZoneOffset.inHours})');
    } catch (_) {}
    // [0.9.83] 现场快照:连咗未、分流模式、订阅(来源域名)、手动揀过嘅组
    try {
      head.writeln(redactSecrets(buildLogSnapshot()));
    } catch (_) {}

    final sections = StringBuffer();
    // [2026-09-29] 其他代理软件 / 系统代理 / 代理环境变量 —— 唔理连未连都写(客户多数断开咗先传日志)。
    //   起因:客户关咗 Clash Verge 窗口,verge-mihomo.exe 仲喺后台,易联 TUN 起唔到 + Codex 报 10061,客服估咗成晚。
    var otherProcs = const <String>[];
    String? osProxy;
    var proxyEnv = const <String>[];
    if (Platform.isMacOS || Platform.isWindows) {
      try {
        otherProcs = await system.listOtherProxyProcesses();
        osProxy = await system.readOsSystemProxy();
        proxyEnv = await system.readProxyEnvVars();
        final myPort = c.read(patchClashConfigProvider.select((s) => s.mixedPort));
        sections.writeln('--- 其他代理软件 / 代理设置 ---');
        sections.writeln('  正在运行的其他代理软件: ${otherProcs.isEmpty ? '无' : otherProcs.join('、')}');
        sections.writeln('  系统代理: ${osProxy ?? '未开启'}${osProxy != null && !osProxy.contains(':$myPort') ? ' ⚠️ 不是易联(易联端口 $myPort)' : ''}');
        sections.writeln('  代理环境变量: ${proxyEnv.isEmpty ? '无' : proxyEnv.join(' · ')}');
      } catch (_) {}
    }
    // ① 全部分组状态(内核实时)
    GroupStatusReport? groups;
    if (started) {
      try {
        groups = await buildGroupStatusReport();
        sections.writeln(redactSecrets(groups.text));
      } catch (e) {
        sections.writeln('--- 全部分组状态: 读取失败 $e ---');
      }
    } else {
      sections.writeln('--- 全部分组状态: 未连接,跳过 ---');
    }
    // ② 现场检测
    LiveCheckResult? live;
    try {
      live = await runLiveChecks(started ? (groups?.keyLeaves ?? const []) : const [], started: started);
      sections.writeln(live.text);
    } catch (e) {
      sections.writeln('--- 现场检测失败: $e ---');
    }
    // ③ 本机诊断(有冇第三方 VPN / 代理抢占、TUN 状态)—— 桌面先有
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        final diag = await diagnoseLocal(
          mixedPort: c.read(patchClashConfigProvider.select((s) => s.mixedPort)),
          coreRunning: started,
          tunPreferred: c.read(patchClashConfigProvider.select((s) => s.tun.enable)),
        );
        sections.writeln('--- 本机诊断: ${diag.verdict} ---');
        for (final it in diag.items) {
          sections.writeln('  [${it.level.name}] ${it.title}: ${it.value}${it.detail == null ? '' : ' · ${it.detail}'}');
        }
      } catch (_) {}
    }
    // ④ 订阅拉取记录(每个镜像域名成功 / 失败)
    final fetches = vogueslySubscriptionFetchLog();
    sections.writeln('--- 订阅拉取记录(本次运行,最近 ${fetches.length} 次) ---');
    for (final l in fetches) {
      sections.writeln('  $l');
    }
    // ⑤ 失败连接汇总 + 警告 / 错误(持久化,近 48 小时,重启唔丢)
    final issues = VogueslyIssueLog.instance.recent();
    final fail = buildFailureSummary(issues);
    sections.writeln(fail.text);
    final errTail = issues.length > 150 ? issues.sublist(issues.length - 150) : issues;
    sections.writeln('--- 警告/错误(近 48 小时最近 ${errTail.length} 条,共 ${issues.length} 条) ---');
    for (final l in errTail) {
      sections.writeln(l); // 入库时已去凭证
    }

    // ⑥ 摘要(放最前,TG 通知正文只显示前 600 字)
    final sum = <String>[
      started ? '已连接' : '未连接',
      tun ? 'TUN' : '系统代理',
      if (groups != null) '分组异常 ${groups.bad}/${groups.total}',
      if (groups != null && groups.pinnedManual.isNotEmpty) '手动钉死 ${groups.pinnedManual.length} 组',
      if (live != null && live.nodesTested > 0) '关键节点现测 ${live.nodesOk}/${live.nodesTested} 通',
      if (live != null) '国内直连${live.domesticOk ? '正常' : '失败'}',
      if (live != null) '面板${live.panelOk ? '可达' : '不可达'}',
      '近48h失败连接 ${fail.total} 次${fail.top == null ? '' : '(最多: ${fail.top})'}',
      if (otherProcs.isNotEmpty) '⚠️其他代理在运行: ${otherProcs.join('、')}',
      if (osProxy != null && !osProxy.contains(':${c.read(patchClashConfigProvider.select((s) => s.mixedPort))}')) '⚠️系统代理指向 $osProxy',
      if (proxyEnv.isNotEmpty) '⚠️有代理环境变量',
    ].join(' · ');

    final b = StringBuffer()
      ..writeln('【摘要】$sum')
      ..write(head)
      ..write(sections);

    // ⑦ 近期日志(最后):连续重复嘅合并成一行;按剩余字节预算由尾向前收。
    final logs = c.read(logsProvider).list;
    final merged = <String>[];
    String? lastKey;
    var repeat = 0;
    for (final l in logs) {
      final key = '[${l.logLevel.name}] ${l.payload}';
      if (key == lastKey) {
        repeat++;
        continue;
      }
      if (repeat > 0) merged.add('  (上一条重复 $repeat 次)');
      repeat = 0;
      merged.add('${l.dateTime} $key');
      lastKey = key;
    }
    if (repeat > 0) merged.add('  (上一条重复 $repeat 次)');
    // 上限:上传落 v2_ticket_message.message(MySQL TEXT,65,535 bytes);全份控制喺 50,000 bytes,最多 2000 行。
    const kTotalBytes = 50000, kRecentLines = 2000;
    var budget = kTotalBytes - utf8.encode(b.toString()).length - 64;
    var start = merged.length;
    while (start > 0 && merged.length - start < kRecentLines) {
      final len = utf8.encode(merged[start - 1]).length + 1;
      if (len > budget) break;
      budget -= len;
      start--;
    }
    b.writeln(currentAppLocalizations.vgRecentLogsHeader);
    for (final line in merged.sublist(start)) {
      b.writeln(redactSecrets(line)); // [0.9.82] 兜底:任何地方漏记咗凭证,上传前都抹走
    }
    var body = b.toString();
    // 前面几段本身都有可能超预算(极端情况:好多组 + 好多失败),硬截,唔好令工单写入失败。
    final bytes = utf8.encode(body);
    if (bytes.length > 60000) {
      body = '${utf8.decode(bytes.sublist(0, 60000), allowMalformed: true)}\n…(已截断)';
    }
    final subject = 'App 日志 · ${Platform.operatingSystem} $ver · ${groups == null ? (started ? '已连接' : '未连接') : '异常 ${groups.bad}/${groups.total}'}'
        '${fail.total > 0 ? ' · 失败 ${fail.total}' : ''}${live != null && !live.domesticOk ? ' · 本地网络异常' : ''}';
    return (body: body, subject: subject);
  }

  Future<void> _submit() async {
    final token = ref.read(vogueslyAuthProvider).token;
    if (token == null) {
      globalState.showNotifier(currentAppLocalizations.vgSignInBeforeFeedback);
      return;
    }
    setState(() {
      _busy = true;
      _retryHint = null;
    });
    final diag = await _collectDiagnostics();
    final msg = currentAppLocalizations.vgFeedbackBodyWith(_desc.text.trim(), diag.body);
    final res = await ref.read(vogueslyApiProvider).submitFeedback(
      token,
      message: msg,
      subject: diag.subject,
      onRetry: (n, total) {
        if (mounted) setState(() => _retryHint = currentAppLocalizations.vgSubmitRetrying(n, total));
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _retryHint = null;
    });
    if (res.ok) {
      globalState.showNotifier(res.message);
      Navigator.of(context).pop();
      return;
    }
    // [0.9.90] 失败唔再只闪一个 toast(客户以为已上传,面板 0 请求):弹框讲清楚冇发出去,
    // 表单唔关、写咗嘅内容保留,等用户自己再撳。
    await globalState.showMessage(
      title: res.maybeSent
          ? currentAppLocalizations.vgSubmitMaybeSentTitle
          : currentAppLocalizations.vgSubmitNotSentTitle,
      message: TextSpan(
        text: res.maybeSent ? res.message : currentAppLocalizations.vgSubmitNotSentBody(res.message),
      ),
      cancelable: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            currentAppLocalizations.vgFeedbackHint,
            style: context.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _desc,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: currentAppLocalizations.vgFeedbackPlaceholder,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(_busy ? (_retryHint ?? currentAppLocalizations.vgSubmitting) : currentAppLocalizations.vgSubmitToSupport),
          ),
        ],
      ),
    );
  }
}

class _CustomNodesItem extends StatelessWidget {
  const _CustomNodesItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const Icon(Icons.add_link),
      title: Text(currentAppLocalizations.vgCustomNodesTitle),
      subtitle: Text(currentAppLocalizations.vgCustomNodesSubtitle),
      delegate: const OpenDelegate(widget: VogueslyCustomNodesView()),
    );
  }
}

class _DeveloperItem extends StatelessWidget {
  const _DeveloperItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const Icon(Icons.developer_board),
      title: Text(context.appLocalizations.developerMode),
      delegate: const OpenDelegate(widget: DeveloperView()),
    );
  }
}

class _SubscriptionEntry extends ConsumerWidget {
  const _SubscriptionEntry();

  // 上次更新时间:今日显「今天 HH:mm」,否则「MM-dd HH:mm」;从未更新显占位。
  String _lastUpdate(BuildContext context, DateTime? d) {
    if (d == null) return currentAppLocalizations.vgTapBelowToFetchNodes;
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final t = DateFormat('HH:mm').format(d);
    return sameDay ? currentAppLocalizations.vgLastUpdatedTodayWith(t) : currentAppLocalizations.vgLastUpdatedWith(DateFormat('MM-dd').format(d), t);
  }

  Future<void> _refresh(BuildContext context, WidgetRef ref, Profile profile) async {
    final ok = await ref
        .read(profilesActionProvider.notifier)
        .refreshVogueslyProfile(profile, showLoading: true);
    if (!context.mounted) return;
    if (!ok && vogueslyGuideIfNoPlan(context)) return; // [0.9.80] 未有套餐 → 引导,唔弹「更新失败」
    globalState.showNotifier(ok ? currentAppLocalizations.vgSubscriptionUpdated : currentAppLocalizations.vgUpdateFailedRetry);
  }

  void _openManage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => CommonScaffoldBackActionProvider(
          backAction: () => Navigator.of(ctx).pop(),
          child: const ProfilesView(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.colorScheme;
    // 当前账号订阅 profile(揾唔到就用 null → 引导先入管理页导入)。
    final profiles = ref.watch(profilesProvider);
    final vog = profiles.where(isVogueslyProfile);
    final profile = vog.isEmpty ? null : vog.first;
    final updating = profile == null
        ? false
        : ref.watch(isUpdatingProvider(profile.updatingKey));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      Icon(Icons.cloud_sync_outlined, color: cs.primary, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentAppLocalizations.vgMySubscription,
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        profile == null
                            ? currentAppLocalizations.vgNoSubscriptionImported
                            : _lastUpdate(context, profile.lastUpdateDate),
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    // [0.9.80] 未有订阅时唔好灰咗个掣:撳落去 = 开通引导(无套餐)或者重新导入
                    onPressed: updating
                        ? null
                        : (profile == null
                            ? () async {
                                if (vogueslyGuideIfNoPlan(context)) return;
                                final ok = await importVogueslySubscription();
                                globalState.showNotifier(ok
                                    ? currentAppLocalizations.vgSubscriptionUpdated
                                    : currentAppLocalizations.vgUpdateFailedRetry);
                              }
                            : () => _refresh(context, ref, profile)),
                    icon: updating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 20),
                    label: Text(updating ? currentAppLocalizations.vgUpdating : currentAppLocalizations.vgUpdateSubscription),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => _openManage(context),
                  child: Text(currentAppLocalizations.vgManageSubscription),
                ),
              ],
            ),
            // [0.9.83 Sam] 讲清楚「更新订阅」係做咩:保持线路 / 分流规则最新(application.dart 每 20 分钟亦会自动同步)
            const SizedBox(height: 10),
            Text(
              currentAppLocalizations.vgKeepLatestHint,
              style: context.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoutItem extends ConsumerWidget {
  const _LogoutItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.colorScheme;
    return ListItem(
      leading: Icon(Icons.logout, color: cs.error),
      title: Text(currentAppLocalizations.vgSignOut, style: TextStyle(color: cs.error)),
      onTap: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(currentAppLocalizations.vgSignOut),
            content: Text(currentAppLocalizations.vgSignOutConfirmShort),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.appLocalizations.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(currentAppLocalizations.vgExit),
              ),
            ],
          ),
        );
        if (ok == true) {
          // 先删本账号订阅(防换账号串号),再清登录态。两条登出路径共用同一清理。
          await clearVogueslyProfiles();
          ref.read(vogueslyAuthProvider.notifier).logout();
        }
      },
    );
  }
}
