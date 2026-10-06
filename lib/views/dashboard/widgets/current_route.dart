import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 当前线路卡:显示主组(易聯 Residential IP)选中嘅线路,撳→线路页换。
class CurrentRoute extends ConsumerWidget {
  const CurrentRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.colorScheme;
    final groupName = ref.watch(
      proxiesTabStateProvider.select((s) => s.currentGroupName),
    );
    final selected = (groupName == null)
        ? ''
        : (ref.watch(selectedProxyNameProvider(groupName)) ?? '');
    // 有订阅但 now 未就绪(核心载入中 / 主组 select 默认走第一项 url-test「快线」)→
    // 唔好显示「未选择」吓人(其实连得到):显示「自动选择中…」。
    final hasProfile = ref.watch(profilesProvider.select((s) => s.isNotEmpty));
    // [0.9.91] 全局模式常驻提示(Sam 09-25:佢自己都唔知开咗全局,仲係 5x 线路 ⇒ 国内网站都按 5 倍扣)。
    //   全局时流量行 GLOBAL 组,所以倍率要睇 GLOBAL 实际落到嘅节点;读唔到先退返主组。
    final mode = ref.watch(patchClashConfigProvider.select((s) => s.mode));
    var globalLeaf = '';
    if (mode == Mode.global) {
      try {
        globalLeaf = ref
            .watch(realSelectedProxyStateProvider('GLOBAL'))
            .proxyName;
      } catch (_) {}
      if (globalLeaf.isEmpty && groupName != null) {
        try {
          globalLeaf = ref
              .watch(realSelectedProxyStateProvider(groupName))
              .proxyName;
        } catch (_) {}
      }
      if (globalLeaf.isEmpty) globalLeaf = selected;
    }
    final routeText = selected.isNotEmpty
        ? selected
        : (hasProfile
              ? currentAppLocalizations.vgAutoSelecting
              : currentAppLocalizations.vgNoRouteSelected);
    return SizedBox(
      width: double.infinity,
      child: CommonCard(
        onPressed: () {
          ref.read(currentPageLabelProvider.notifier).toPage(PageLabel.proxies);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.lan_outlined, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentAppLocalizations.vgCurrentRoute,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        EmojiText(
                          routeText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
              if (mode == Mode.global) ...[
                const SizedBox(height: 12),
                _GlobalModeBanner(
                  rate: vogueslyRouteRate(globalLeaf),
                  onSwitch: () => ref
                      .read(setupActionProvider.notifier)
                      .changeMode(Mode.rule),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 由节点名读倍率:「【3x】中转·…」「【5x】中转·…」(Clash / sing-box)或「5x中转E·…」(小火箭 v3 名);冇标就当 1x。
int vogueslyRouteRate(String name) {
  final m =
      RegExp(r'【(\d+)x】').firstMatch(name) ??
      RegExp(r'(\d+)x中转').firstMatch(name);
  return m == null ? 1 : (int.tryParse(m.group(1)!) ?? 1);
}

/// 全局模式常驻横条:唔可以关,切返智能分流先会消失。
class _GlobalModeBanner extends StatelessWidget {
  const _GlobalModeBanner({required this.rate, required this.onSwitch});

  final int rate;
  final VoidCallback onSwitch;

  static const _amber = Color(0xFFFFB300);

  @override
  Widget build(BuildContext context) {
    final l = currentAppLocalizations;
    final text = rate > 1
        ? '${l.vgGlobalBanner}\n${l.vgGlobalBannerRate(rate)}'
        : l.vgGlobalBanner;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _amber.withValues(alpha: 0.55)),
      ),
      // [0.9.98] 之前「图标 + 文字 + 掣」同一行:窄屏时掣食咗宽度,文字挤成一条窄柱(Sam 10-05 安卓截图)。
      //   改为文字整行、掣放下面靠右。
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.warning_amber_rounded, color: _amber, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onSurface,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: onSwitch,
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(l.vgGlobalBannerSwitch),
            ),
          ),
        ],
      ),
    );
  }
}
