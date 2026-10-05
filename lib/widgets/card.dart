import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';

import 'fade_box.dart';
import 'text.dart';

class Info {
  final String label;
  final IconData? iconData;

  const Info({required this.label, this.iconData});
}

class InfoHeader extends StatelessWidget {
  final Info info;
  final List<Widget> actions;
  final EdgeInsets? padding;

  const InfoHeader({
    super.key,
    required this.info,
    this.padding,
    List<Widget>? actions,
  }) : actions = actions ?? const [];

  @override
  Widget build(BuildContext context) {
    EdgeInsetsGeometry nextPadding = (padding ?? baseInfoEdgeInsets);
    if (actions.isNotEmpty) {
      nextPadding = nextPadding.subtract(EdgeInsets.symmetric(vertical: 8.mAp));
    }
    return Padding(
      padding: nextPadding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 1,
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                if (info.iconData != null) ...[
                  Icon(
                    info.iconData,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  flex: 1,
                  child: TooltipText(
                    text: Text(
                      info.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (actions.isNotEmpty)
            SizedBox(
              height: globalState.measure.titleSmallHeight + 16.ap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [...actions],
              ),
            ),
        ],
      ),
    );
  }
}

class CommonCard extends StatelessWidget {
  const CommonCard({
    super.key,
    bool? isSelected,
    this.type = CommonCardType.plain,
    this.onPressed,
    this.selectWidget,
    this.radius,
    required this.child,
    this.padding,
    this.enterAnimated = false,
    this.info,
    this.onLongPress,
    this.shape,
    this.isError = false,
  }) : isSelected = isSelected ?? false;

  final bool enterAnimated;
  final bool isSelected;
  final bool isError;
  final void Function()? onPressed;
  final void Function()? onLongPress;
  final Widget? selectWidget;
  final Widget child;
  final EdgeInsets? padding;
  final Info? info;
  final CommonCardType type;
  final double? radius;
  final OutlinedBorder? shape;

  BorderSide _buildBorderSide(BuildContext context, Set<WidgetState> states) {
    final colorScheme = context.colorScheme;
    if (isError) {
      if (type == CommonCardType.filled) {
        return BorderSide(color: colorScheme.error);
      }
      final hoverColor = isSelected
          ? colorScheme.error.opacity80
          : colorScheme.error.opacity38;
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused) ||
          states.contains(WidgetState.pressed)) {
        return BorderSide(color: hoverColor);
      }
      return BorderSide(
        color: isSelected
            ? colorScheme.error.opacity60
            : colorScheme.error.opacity30,
      );
    }
    if (type == CommonCardType.filled) {
      return BorderSide.none;
    }
    final hoverColor = isSelected
        ? colorScheme.primary.opacity80
        : colorScheme.primary.opacity60;
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused) ||
        states.contains(WidgetState.pressed)) {
      return BorderSide(color: hoverColor);
    }
    if (isSelected) {
      // 选中态保留品牌色边框 —— 佢係最重要嘅状态反馈,而且同时只有一张卡係选中。
      return BorderSide(color: colorScheme.primary);
    }
    // 🔴 [2026-09-23 Sam 拍板「一切以稳定为主,观感无所谓,用最简单嘅办法,保留品牌感」]
    //
    // 原本非选中态画一条 `surfaceContainerHighest` 嘅淡灰分隔线。问题係:
    // 卡片用嘅係 `RoundedSuperellipseBorder`,而超椭圆嘅 **fill / clip 喺 Skia 上
    // 係直接 fall back 做 `drawRRect`(零成本),但 stroke 会真係走 path**
    // (`dl_builder.cc`:「DrawRoundSuperellipseOp only supports filling. Anything
    //  related to stroking must use path approximation.」—— 而且係喺 DisplayListBuilder
    //  层,Impeller / Skia 一样,换渲染后端都冇用)。
    //
    // 实测(2026-09-23 Sam 部 Mac):`SkCanvas::drawPath` 占光栅线程工作量约 **49%**,
    // `SoftwarePathRenderer` 单独食 **6.3% 整核**。节点列表几十张卡同时可见时按张数线性放大。
    //
    // 非选中 + 非 hover 係列表入面**绝大多数**卡嘅状态 ⇒ 呢度返 none 就消走绝大部分
    // stroke path。层次靠背景色差做(`_buildBackgroundColor` 返 `surfaceContainerLow`,
    // 同页面底色有差),品牌色仍然留喺选中态同 hover 态。
    return BorderSide.none;
  }

  Color? _buildBackgroundColor(BuildContext context) {
    final colorScheme = context.colorScheme;
    // if (isError) {
    //   if (type == CommonCardType.filled) {
    //     return isSelected
    //         ? colorScheme.errorContainer.opacity80
    //         : colorScheme.errorContainer;
    //   }
    //   return isSelected
    //       ? colorScheme.errorContainer.opacity60
    //       : colorScheme.errorContainer.opacity12;
    // }
    if (type == CommonCardType.filled) {
      if (isSelected) {
        return colorScheme.secondaryContainer.opacity80;
      }
      return colorScheme.surfaceContainerHigh;
    }
    if (isSelected) {
      return colorScheme.secondaryContainer;
    }
    return colorScheme.surfaceContainerLow;
  }

  Color? _buildForegroundColor(BuildContext context) {
    final colorScheme = context.colorScheme;
    if (isError) {
      return colorScheme.error;
    }
    if (type == CommonCardType.filled) {
      if (isSelected) {
        return colorScheme.onSecondaryContainer;
      }
      return colorScheme.onSurfaceVariant;
    }
    if (isSelected) {
      return colorScheme.onSecondaryContainer;
    }
    return colorScheme.onSurfaceVariant;
  }

  Color? _buildIconColor(BuildContext context) {
    final colorScheme = context.colorScheme;
    if (isError) {
      return colorScheme.error;
    }
    return colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    var childWidget = child;

    if (info != null) {
      childWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InfoHeader(
            padding: baseInfoEdgeInsets.copyWith(bottom: 0),
            info: info!,
          ),
          Flexible(flex: 1, child: child),
        ],
      );
    }

    if (selectWidget != null && isSelected) {
      final List<Widget> children = [];
      children.add(childWidget);
      children.add(Positioned.fill(child: selectWidget!));
      childWidget = Stack(children: children);
    }

    final card = switch (type == CommonCardType.filled) {
      true => FilledButton(
        onLongPress: onLongPress,
        clipBehavior: Clip.antiAlias,
        style:
            FilledButton.styleFrom(
              padding: padding ?? EdgeInsets.zero,
              shape:
                  shape ??
                  RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(radius ?? 14),
                  ),
              iconSize: 20,
              iconColor: _buildIconColor(context),
              foregroundColor: _buildForegroundColor(context),
              side: BorderSide.none,
              elevation: 0,
            ).copyWith(
              backgroundColor: WidgetStatePropertyAll(
                _buildBackgroundColor(context),
              ),
              side: WidgetStateProperty.resolveWith(
                (states) => _buildBorderSide(context, states),
              ),
            ),
        onPressed: onPressed,
        child: childWidget,
      ),
      false => OutlinedButton(
        onLongPress: onLongPress,
        clipBehavior: Clip.antiAlias,
        style:
            OutlinedButton.styleFrom(
              padding: padding ?? EdgeInsets.zero,
              shape:
                  shape ??
                  RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(radius ?? 14),
                  ),
              iconSize: 20,
              iconColor: _buildIconColor(context),
              backgroundColor: _buildBackgroundColor(context),
              foregroundColor: _buildForegroundColor(context),
              elevation: 0,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => _buildBorderSide(context, states),
              ),
            ),
        onPressed: onPressed,
        child: childWidget,
      ),
    };

    return switch (enterAnimated) {
      true => FadeScaleEnterBox(child: card),
      false => card,
    };
  }
}

class SelectIcon extends StatelessWidget {
  const SelectIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.inversePrimary,
      shape: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.all(4),
        child: const Icon(Icons.check, size: 16),
      ),
    );
  }
}

class SettingsBlock extends StatelessWidget {
  final String title;
  final List<Widget> settings;

  const SettingsBlock({super.key, required this.title, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          InfoHeader(info: Info(label: title)),
          Card(
            color: context.colorScheme.surfaceContainer,
            child: Column(children: settings),
          ),
        ],
      ),
    );
  }
}
