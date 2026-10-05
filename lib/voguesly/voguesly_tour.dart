import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [0.9.83] 聚光灯新手引导(Sam 09-22:「像网页那样把它框住,第一步、第二步、第三步」)。
/// 全屏压暗 + 目标位置挖一个圆角窗 + 紫色描边,旁边卡片讲一句;「跳过 / 下一步」。
/// 第一次连接成功后自动出一次(取代旧「新手小贴士」弹窗);「账户与设置 → 遇到问题 → 新手引导」可以再睇。
///
/// 目标用 GlobalKey 标记。桌面侧栏同手机底栏各用一套 key(两套 layout 理论上唔会同时存在,
/// 分开放就一定唔会撞「duplicate GlobalKey」);边个 key 有 context 就用边个,都冇就跳过嗰步。

final GlobalKey vogueslyTourConnectKey = GlobalKey(debugLabel: 'tour_connect');

const List<PageLabel> _kTourNavLabels = [
  PageLabel.proxies,
  PageLabel.detection,
  PageLabel.support,
  PageLabel.tools,
];

final Map<PageLabel, GlobalKey> vogueslyTourDesktopNavKeys = {
  for (final l in _kTourNavLabels) l: GlobalKey(debugLabel: 'tour_d_${l.name}'),
};
final Map<PageLabel, GlobalKey> vogueslyTourMobileNavKeys = {
  for (final l in _kTourNavLabels) l: GlobalKey(debugLabel: 'tour_m_${l.name}'),
};

const String _kTourSeenKey = 'vg_tour_v1';

class _TourStep {
  const _TourStep(this.key, this.title, this.body, {this.pad = 8, this.extraBottom = 0});

  final GlobalKey key;
  final String title;
  final String body;
  final double pad;
  final double extraBottom; // 手机底栏:key 只包住 icon,向下延伸框埋下面嘅文字

  static _TourStep nav(PageLabel l, String title, String body) {
    final d = vogueslyTourDesktopNavKeys[l]!;
    if (d.currentContext != null) return _TourStep(d, title, body, pad: 4);
    return _TourStep(vogueslyTourMobileNavKeys[l]!, title, body, pad: 10, extraBottom: 20);
  }
}

/// 第一次连接成功后调用:未睇过先出(先写 flag 再出,唔会重复弹)。
Future<void> maybeStartVogueslyTour(BuildContext context) async {
  try {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_kTourSeenKey) == true) return;
    await p.setBool(_kTourSeenKey, true);
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  startVogueslyTour(context);
}

/// 即刻开始引导(「新手引导」重看入口亦用呢个)。
void startVogueslyTour(BuildContext context) {
  final l = currentAppLocalizations;
  final steps = <_TourStep>[
    _TourStep(vogueslyTourConnectKey, l.vgTour1Title, l.vgTour1Body, pad: 6),
    _TourStep.nav(PageLabel.proxies, l.vgTour2Title, l.vgTour2Body),
    _TourStep.nav(PageLabel.detection, l.vgTour3Title, l.vgTour3Body),
    _TourStep.nav(PageLabel.support, l.vgTour4Title, l.vgTour4Body),
    _TourStep.nav(PageLabel.tools, l.vgTour5Title, l.vgTour5Body),
  ].where((s) => s.key.currentContext != null).toList();
  if (steps.isEmpty) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  var index = 0;
  late final OverlayEntry entry;
  void close() {
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _TourLayer(
      step: steps[index],
      index: index,
      total: steps.length,
      onSkip: close,
      onNext: () {
        if (index + 1 >= steps.length) {
          close();
        } else {
          index++;
          entry.markNeedsBuild();
        }
      },
    ),
  );
  overlay.insert(entry);
}

class _TourLayer extends StatelessWidget {
  const _TourLayer({
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onSkip,
  });

  final _TourStep step;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  Rect? _targetRect() {
    final ro = step.key.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) return null;
    final o = ro.localToGlobal(Offset.zero);
    final r = (o & ro.size).inflate(step.pad);
    return Rect.fromLTRB(r.left, r.top, r.right, r.bottom + step.extraBottom);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final rect = _targetRect() ?? Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0);
    final cs = Theme.of(context).colorScheme;
    final l = currentAppLocalizations;
    const cardMaxW = 320.0;
    final cardW = (size.width - 32).clamp(200.0, cardMaxW);
    // 卡片放目标下面;下面位唔够就放上面;目标喺左边窄条(桌面侧栏)就放右边
    final besideRight = rect.right + 16 + cardW < size.width && rect.width < size.width * 0.3 && rect.height < 90;
    double left, top;
    if (besideRight) {
      left = rect.right + 16;
      top = (rect.center.dy - 70).clamp(16.0, size.height - 200);
    } else {
      left = (rect.center.dx - cardW / 2).clamp(16.0, size.width - cardW - 16);
      final below = rect.bottom + 16;
      top = below + 190 < size.height ? below : (rect.top - 16 - 180).clamp(16.0, size.height - 200);
    }
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // 压暗 + 挖洞;吞晒点击,避免引导期间误触后面嘅嘢
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(painter: _HolePainter(rect, cs.primary)),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: cardW,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(index),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 220),
              builder: (_, v, child) => Opacity(
                opacity: v,
                child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child),
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.45)),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        l.vgTourStepOf(index + 1, total),
                        style: TextStyle(color: cs.primary, fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(step.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(step.body,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.45,
                            )),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (index + 1 < total)
                          TextButton(onPressed: onSkip, child: Text(l.vgTourSkip)),
                        const Spacer(),
                        FilledButton(
                          onPressed: onNext,
                          child: Text(index + 1 < total ? l.vgTourNext : l.vgTourDone),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HolePainter extends CustomPainter {
  _HolePainter(this.hole, this.accent);

  final Rect hole;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(hole, const Radius.circular(16));
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(r),
    );
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.66));
    if (hole.width > 0) {
      canvas.drawRRect(
        r,
        Paint()
          ..color = accent.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawRRect(
        r,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_HolePainter old) => old.hole != hole || old.accent != accent;
}
