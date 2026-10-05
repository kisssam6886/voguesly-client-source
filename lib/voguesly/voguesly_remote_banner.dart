import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart' show Profile;
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'voguesly_cs.dart' show VogueslyCsPanel;
import 'voguesly_noplan.dart' show vogueslyGuideIfNoPlan;
import 'voguesly_remote_config.dart';
import 'voguesly_subscription.dart' show importVogueslySubscription, isVogueslyProfile;

/// [0.9.92] 首页紧急横幅:version.json `app_config.banner` 下发(切域 / 线路出事时直接叫用户「更新订阅」,唔使发版)。
/// 纯文本(Text 显示,唔解析 HTML / 链接);按钮只可以係 [kVogueslyBannerActions] 几种。
/// 「知道了」按 banner id 记低(存本机),同一个 id 唔再出;服务端换 id = 新一条。
const _kDismissedPref = 'yl_banner_dismissed_v1';

class _Dismissed extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final ids = p.getStringList(_kDismissedPref);
      if (ids != null && ids.isNotEmpty) state = {...state, ...ids};
    } catch (_) {}
  }

  Future<void> add(String id) async {
    state = {...state, id};
    try {
      final p = await SharedPreferences.getInstance();
      final ids = state.toList();
      await p.setStringList(_kDismissedPref, ids.sublist(ids.length > 20 ? ids.length - 20 : 0));
    } catch (_) {}
  }
}

final _dismissedProvider = NotifierProvider<_Dismissed, Set<String>>(_Dismissed.new);

class VogueslyRemoteBanner extends ConsumerWidget {
  const VogueslyRemoteBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<int>(
      valueListenable: vogueslyAppConfigRevision,
      builder: (context, _, _) {
        final b = vogueslyActiveBanner();
        final dismissed = ref.watch(_dismissedProvider);
        if (b == null || dismissed.contains(b.id)) return const SizedBox.shrink();
        return _BannerCard(banner: b);
      },
    );
  }
}

class _BannerCard extends ConsumerWidget {
  const _BannerCard({required this.banner});

  final VogueslyBanner banner;

  Future<void> _updateSubscription(WidgetRef ref) async {
    final action = ref.read(profilesActionProvider.notifier);
    final vog = ref.read(profilesProvider).where(isVogueslyProfile);
    final Profile? profile = vog.isEmpty ? null : vog.first;
    final ok = profile == null
        ? await importVogueslySubscription()
        : await action.refreshVogueslyProfile(profile, showLoading: true);
    if (!ok && vogueslyGuideIfNoPlan()) return;
    globalState.showNotifier(
      ok ? currentAppLocalizations.vgSubscriptionUpdated : currentAppLocalizations.vgUpdateFailedRetry,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.colorScheme;
    final l = currentAppLocalizations;
    final warn = banner.level == 'warn';
    final bg = warn ? cs.errorContainer : cs.secondaryContainer;
    final fg = warn ? cs.onErrorContainer : cs.onSecondaryContainer;
    final (String?, VoidCallback?) act = switch (banner.action) {
      'open_cs' => (l.vgContactSupport, () => VogueslyCsPanel.open(context)),
      'update_app' => (
          context.appLocalizations.goDownload,
          () => ref.read(commonActionProvider.notifier).manualCheckUpdate()
        ),
      'update_sub' => (l.vgUpdateSubShort, () => _updateSubscription(ref)),
      _ => (null, null),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10), // [0.9.93] 右边 8 → 14:0.9.92 实机见文字贴边
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(warn ? Icons.warning_amber_rounded : Icons.info_outline_rounded, color: fg),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      banner.text,
                      style: context.textTheme.bodyMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => ref.read(_dismissedProvider.notifier).add(banner.id),
                    style: TextButton.styleFrom(foregroundColor: fg),
                    child: Text(l.vgGotIt),
                  ),
                  if (act.$1 != null)
                    FilledButton(
                      onPressed: act.$2,
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: Text(act.$1!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
