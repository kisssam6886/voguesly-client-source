import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/config.dart';
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

class Window {
  static Window? _instance;

  Window._internal();

  factory Window() {
    _instance ??= Window._internal();
    return _instance!;
  }

  Future<void> init(int version, WindowProps props) async {
    final acquire = await singleInstanceLock.acquire();
    if (!acquire) {
      exit(0);
    }
    if (system.isWindows) {
      // [0.9.96] 只登记自己嘅 ylink://。原本仲登记 clash:// clashmeta:// flclash:// —— 易联自己完全唔用,
      //   但每次启动都会抢走 Clash Verge / 官方 FlClash 嘅一键导入(09-30 实测;面板「导入 Clash Verge」就係 clash://)。
      //   旧版抢咗嘅(命令指住我哋自己个 exe)顺手交还。
      protocol.register('ylink'); // 网页授权登录(2026-09-22)
      for (final scheme in const ['clash', 'clashmeta', 'flclash']) {
        protocol.unregisterIfOwned(scheme);
      }
    }
    await windowManager.ensureInitialized();
    // kDebugMode ? Size(680, 580) :
    final WindowOptions windowOptions = WindowOptions(
      size: props.size,
      // 最小尺寸升到 900×660:令内容(主页 8 卡 + 检测结果)喺任何窗口都够位,
      // 亦令现有用户之前持久化嘅过细窗口启动时被顶返到可用尺寸(Sam:框要适配所有菜单)。
      minimumSize: const Size(900, 660),
    );
    if (!system.isMacOS || version > 10) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }
    await windowManager.setMaximizable(true);
    await _windowPosition(props);
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setPreventClose(true);
    });
  }

  Future<void> _windowPosition(WindowProps props) async {
    if (!system.isMacOS) {
      final left = props.left ?? 0;
      final top = props.top ?? 0;
      final right = left + props.width;
      final bottom = top + props.height;
      if (left == 0 && top == 0) {
        await windowManager.setAlignment(Alignment.center);
      } else {
        final displays = await screenRetriever.getAllDisplays();
        final isPositionValid = displays.any((display) {
          final displayBounds = Rect.fromLTWH(
            display.visiblePosition!.dx,
            display.visiblePosition!.dy,
            display.size.width,
            display.size.height,
          );
          return displayBounds.contains(Offset(left, top)) ||
              displayBounds.contains(Offset(right, bottom));
        });
        if (isPositionValid) {
          await windowManager.setPosition(Offset(left, top));
        }
      }
    }
  }

  Future<void> show() async {
    render?.resume();
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setSkipTaskbar(false);
  }

  Future<bool> get isVisible async {
    final value = await windowManager.isVisible();
    commonPrint.log('window visible check: $value');
    return value;
  }

  Future<void> close() async {
    await windowManager.close();
  }

  void forceExit() {
    exit(0);
  }

  Future<void> hide() async {
    render?.pause();
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }
}

final window = system.isDesktop ? Window() : null;
