import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'voguesly_api.dart' show VogueslyUser;
import 'voguesly_auth.dart';
import 'voguesly_onboarding_sheet.dart';
import 'voguesly_subscription.dart';

/// [2026-09-18 0.9.80 Sam] 明确判「呢个账号而家用唔到节点」:未买过套餐,或者套餐已到期。
/// 之前 app 係靠「订阅校验失败」间接当未开通(服务端对无套餐用户出嘅配置有个空组),
/// 结果手动撳「更新订阅」会弹「更新失败」—— 对新注册用户嚟讲係一句冇头冇尾嘅错误。
bool vogueslyUserLacksPlan(VogueslyUser? u) {
  if (u == null) return false; // 未知(网络未拉到)唔当无套餐,免误导已付费用户
  if (u.planId == null) return true;
  return vogueslyPlanExpired(u);
}

bool vogueslyPlanExpired(VogueslyUser? u) {
  final exp = u?.expiredAt;
  if (u == null || u.planId == null || exp == null || exp <= 0) return false;
  return exp * 1000 < DateTime.now().millisecondsSinceEpoch;
}

/// [0.9.98] ¥3.9 验证包(plan 18,服务端 yl_commission_exclude_plan_ids 默认亦係 18)。
/// 认 id 或者名(以后换 id 唔会漏)。
bool vogueslyIsTrialPlan(VogueslyUser? u) {
  if (u == null || u.planId == null) return false;
  final name = u.planName ?? '';
  return u.planId == 18 || name.contains('验证包') || name.contains('驗證包');
}

enum VogueslyTrialStage { none, low, used, expired }

/// [0.9.98 Sam「验证包到期 / 用完要引导升级 Pro,唔好引导续 ¥3.9」]
///   used = 流量剩 ≤ 50MB;expired = 到期;low = 用咗 ≥ 80% 或者剩 ≤ 1 日。
@visibleForTesting
VogueslyTrialStage vogueslyTrialStageAt(VogueslyUser? u, DateTime now) {
  if (!vogueslyIsTrialPlan(u)) return VogueslyTrialStage.none;
  final exp = u!.expiredAt;
  if (exp != null && exp > 0 && exp * 1000 < now.millisecondsSinceEpoch) {
    return VogueslyTrialStage.expired;
  }
  final total = u.transferEnable;
  final left = total - u.upload - u.download;
  if (total > 0 && left <= 50 * 1024 * 1024) return VogueslyTrialStage.used;
  final lowTraffic = total > 0 && left <= total * 0.2;
  final lowTime = exp != null && exp > 0 && exp * 1000 - now.millisecondsSinceEpoch <= 86400000;
  return (lowTraffic || lowTime) ? VogueslyTrialStage.low : VogueslyTrialStage.none;
}

VogueslyTrialStage vogueslyTrialStage(VogueslyUser? u) => vogueslyTrialStageAt(u, DateTime.now());

String _gbLeft(VogueslyUser u) {
  final left = (u.transferEnable - u.upload - u.download).clamp(0, 1 << 62);
  return '${(left / 1073741824).toStringAsFixed(1)} GB';
}

/// 跳去 app 内「购买套餐」tab(¥3.9 验证包同正式套餐都喺度,支付全程 app 内完成)。
void vogueslyGoToShop() {
  final c = globalState.container;
  c.read(currentPageLabelProvider.notifier).toPage(PageLabel.shop);
}

/// 无套餐时用嚟代替「更新失败」toast:弹开通引导(免费试用一键开通 / 购买)。
/// 返 true = 已处理(调用方唔好再弹失败 toast)。
bool vogueslyGuideIfNoPlan([BuildContext? context]) {
  final user = globalState.container.read(vogueslyAuthProvider).user;
  if (!vogueslyUserLacksPlan(user)) return false;
  final ctx = context ?? globalState.navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return false;
  if (vogueslyPlanExpired(user)) {
    globalState.showNotifier(vogueslyIsTrialPlan(user)
        ? currentAppLocalizations.vgTrialExpiredBanner
        : currentAppLocalizations.vgPlanExpiredBanner);
    vogueslyGoToShop();
  } else {
    showVogueslyOnboarding(ctx);
  }
  return true;
}

/// 首页顶常驻提示条:未有套餐 / 已到期。有可用订阅(profile)就唔显示。
class VogueslyNoPlanBanner extends ConsumerWidget {
  const VogueslyNoPlanBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(vogueslyAuthProvider.select((s) => s.user));
    // [0.9.98] 验证包:快用完 / 用完 / 到期 ⇒ 引导升级正式套餐(唔引导再买 ¥3.9;流量用完但未到期以前完全冇提示)
    final trial = vogueslyTrialStage(user);
    if (!vogueslyUserLacksPlan(user) && trial == VogueslyTrialStage.none) {
      return const SizedBox.shrink();
    }
    final expired = vogueslyPlanExpired(user);
    final importing = ref.watch(vogueslyImportingProvider);
    if (importing) return const SizedBox.shrink();
    final cs = context.colorScheme;
    final l = currentAppLocalizations;
    final isTrial = trial != VogueslyTrialStage.none;
    final text = switch (trial) {
      VogueslyTrialStage.expired => l.vgTrialExpiredBanner,
      VogueslyTrialStage.used => l.vgTrialEndedBanner,
      VogueslyTrialStage.low => l.vgTrialLowBanner(_gbLeft(user!)),
      VogueslyTrialStage.none => expired ? l.vgPlanExpiredBanner : l.vgNoPlanBanner,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.card_membership_outlined,
                      color: cs.onTertiaryContainer),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      text,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: cs.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!expired && !isTrial)
                    TextButton(
                      onPressed: () => showVogueslyOnboarding(context),
                      style: TextButton.styleFrom(
                          foregroundColor: cs.onTertiaryContainer),
                      child: Text(l.vgTryFreeFirst),
                    ),
                  FilledButton(
                    onPressed: vogueslyGoToShop,
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    child: Text(isTrial
                        ? l.vgUpgradePlan
                        : (expired ? l.vgRenewNow : Intl.message('shop'))),
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
