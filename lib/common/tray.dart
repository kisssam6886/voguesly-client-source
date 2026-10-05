import 'dart:io';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/services.dart';
import 'package:fl_clash/common/navigation.dart' show vogueslyModeLabel;
import 'package:tray_manager/tray_manager.dart';

import 'app_localizations.dart';
import 'constant.dart';
import 'system.dart';
import 'window.dart';

class Tray {
  static Tray? _instance;

  Tray._internal();

  factory Tray() {
    _instance ??= Tray._internal();
    return _instance!;
  }

  String get trayIconSuffix {
    return system.isWindows ? 'ico' : 'png';
  }

  Future<void> destroy() async {
    await trayManager.destroy();
  }

  String getTryIcon({required bool isStart, required bool tunEnable}) {
    if (system.isMacOS || !isStart) {
      return 'assets/images/icon/status_1.$trayIconSuffix';
    }
    if (!tunEnable) {
      return 'assets/images/icon/status_2.$trayIconSuffix';
    }
    return 'assets/images/icon/status_3.$trayIconSuffix';
  }

  Future _updateSystemTray({
    required bool isStart,
    required bool tunEnable,
  }) async {
    if (Platform.isLinux) {
      await trayManager.destroy();
    }
    await trayManager.setIcon(
      getTryIcon(isStart: isStart, tunEnable: tunEnable),
      // 粗实心 V(去 glow)+ macOS template:自动黑/白高对比剪影,菜单栏清晰(彩色渐变会糊到似冇图标)。
      isTemplate: system.isMacOS,
    );
    if (!Platform.isLinux) {
      await trayManager.setToolTip(appName);
    }
  }

  Future<void> update({
    required TrayState trayState,
    required Traffic traffic,
  }) async {
    if (system.isAndroid) {
      return;
    }
    if (!system.isLinux) {
      await _updateSystemTray(
        isStart: trayState.isStart,
        tunEnable: trayState.tunEnable,
      );
    }
    final List<MenuItem> menuItems = [];
    final ref = globalState.container;
    final commonAction = ref.read(commonActionProvider.notifier);
    final systemAction = ref.read(systemActionProvider.notifier);
    final setupAction = ref.read(setupActionProvider.notifier);
    final appLocalizations = currentAppLocalizations;
    final showMenuItem = MenuItem(
      label: appLocalizations.show,
      onClick: (_) {
        window?.show();
      },
    );
    menuItems.add(showMenuItem);
    final startMenuItem = MenuItem.checkbox(
      label: trayState.isStart ? appLocalizations.stop : appLocalizations.start,
      onClick: (_) async {
        commonAction.updateStart();
      },
      checked: false,
    );
    menuItems.add(startMenuItem);
    if (system.isMacOS) {
      final speedStatistics = MenuItem.checkbox(
        label: appLocalizations.speedStatistics,
        onClick: (_) async {
          commonAction.updateSpeedStatistics();
        },
        checked: trayState.showTrayTitle,
      );
      menuItems.add(speedStatistics);
    }
    menuItems.add(MenuItem.separator());
    // [0.9.83] 同首页一致:唔露「直连」,「规则」叫「易联智能分流」
    for (final mode in Mode.values.where((m) => m != Mode.direct)) {
      menuItems.add(
        MenuItem.checkbox(
          label: vogueslyModeLabel(mode),
          onClick: (_) {
            setupAction.changeMode(mode);
          },
          checked: mode == trayState.mode,
        ),
      );
    }
    menuItems.add(MenuItem.separator());
    if (system.isMacOS) {
      for (final group in trayState.groups) {
        final List<MenuItem> subMenuItems = [];
        for (final proxy in group.all) {
          subMenuItems.add(
            MenuItem.checkbox(
              label: proxy.name,
              checked:
                  ref.read(selectedProxyNameProvider(group.name)) == proxy.name,
              onClick: (_) {
                ref
                    .read(profilesActionProvider.notifier)
                    .updateCurrentSelectedMap(group.name, proxy.name);
                ref
                    .read(proxiesActionProvider.notifier)
                    .changeProxy(groupName: group.name, proxyName: proxy.name);
              },
            ),
          );
        }
        menuItems.add(
          MenuItem.submenu(
            label: group.name,
            submenu: Menu(items: subMenuItems),
          ),
        );
      }
      if (trayState.groups.isNotEmpty) {
        menuItems.add(MenuItem.separator());
      }
    }
    if (trayState.isStart) {
      menuItems.add(
        MenuItem.checkbox(
          label: appLocalizations.tun,
          onClick: (_) {
            systemAction.updateTun();
          },
          checked: trayState.tunEnable,
        ),
      );
      menuItems.add(
        MenuItem.checkbox(
          label: appLocalizations.systemProxy,
          onClick: (_) {
            systemAction.updateSystemProxy();
          },
          checked: trayState.systemProxy,
        ),
      );
      menuItems.add(MenuItem.separator());
    }
    final autoStartMenuItem = MenuItem.checkbox(
      label: appLocalizations.autoLaunch,
      onClick: (_) async {
        systemAction.updateAutoLaunch();
      },
      checked: trayState.autoLaunch,
    );
    final copyEnvVarMenuItem = MenuItem(
      label: appLocalizations.copyEnvVar,
      onClick: (_) async {
        await _copyEnv(trayState.port);
      },
    );
    menuItems.add(autoStartMenuItem);
    menuItems.add(copyEnvVarMenuItem);
    menuItems.add(MenuItem.separator());
    final exitMenuItem = MenuItem(
      label: appLocalizations.exit,
      onClick: (_) async {
        await systemAction.handleExit();
      },
    );
    menuItems.add(exitMenuItem);
    final menu = Menu(items: menuItems);
    await trayManager.setContextMenu(menu);
    if (system.isLinux) {
      await _updateSystemTray(
        isStart: trayState.isStart,
        tunEnable: trayState.tunEnable,
      );
    }
    updateTrayTitle(showTrayTitle: trayState.showTrayTitle, traffic: traffic);
  }

  /// 上次真正落去 NSStatusItem 嘅标题。用嚟去重,见 [updateTrayTitle]。
  String? _lastTrayTitle;

  Future<void> updateTrayTitle({
    required bool showTrayTitle,
    required Traffic traffic,
  }) async {
    if (!system.isMacOS) {
      return;
    }
    final next = showTrayTitle ? traffic.trayTitle : '';

    // 🔴 [2026-09-23] macOS 闲置高 CPU 嘅**官方实锤真凶**,我哋由 fork 点(v0.8.93)一直带住。
    //
    // 原本:`showTrayTitle == false` 都照 `setTitle('')`。而 `trayTitleStateProvider`
    // 含住流量数字 ⇒ **每秒都变** ⇒ `tray_manager.dart:29` 嗰个 `prev != next` 去重
    // 拦唔住 ⇒ 每秒入嚟一次。**设空字符串一样触发完整 NSStatusItem 重绘。**
    //
    // 上游 issue #1644 / #2141 嘅实测:官方 0.8.93、窗口隐藏、showTrayTitle=false
    // ⇒ GUI 持续 36.7–40.0% CPU,5 秒采样入面 `_updateReplicants` 主路径 542 个样本;
    // 加咗去重之后 0.0–0.5%,4349 个样本得 3 个。另一用户退出 FlClash 之后
    // **WindowServer 由 44–53% 跌到 14.6–37.3%**。多显示器会放大(非活动屏每秒闪一次)。
    //
    // ⚠️ 呢度只係**一半**修复。官方 v0.8.94 真正嘅修补喺 `tray_manager` 依赖入面
    // (commit `da2d83dd`「Fix high CPU from NSStatusItem redraw loop on multi-display」),
    // 而我哋 `pubspec.yaml` 仲指住 v0.8.93 时代嘅本地 submodule
    // `plugins/tray_manager/packages/tray_manager`。**另一半见 BACKLOG。**
    if (_lastTrayTitle == next) {
      return;
    }
    _lastTrayTitle = next;
    await trayManager.setTitle(next);
  }

  Future<void> _copyEnv(int port) async {
    final url = 'http://127.0.0.1:$port';

    final cmdline = system.isWindows
        ? 'set \$env:all_proxy=$url'
        : 'export all_proxy=$url';

    await Clipboard.setData(ClipboardData(text: cmdline));
  }
}

final tray = system.isDesktop ? Tray() : null;
