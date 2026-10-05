import 'dart:async';
import 'dart:io';

import 'package:fl_clash/pages/error.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/voguesly/voguesly_api.dart' show loadVogueslyRemotePanelHosts;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_api/rust_api.dart';

import 'application.dart';
import 'common/common.dart';
import 'package:fl_clash/voguesly/voguesly_remote_config.dart' show loadVogueslyAppConfig;

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    if (system.isDesktop) {
      await RustLib.init();
    }
    final version = await system.version;
    final container = await globalState.init(version);
    // [0.9.91] 读返上次服务端下发嘅面板入口(切域唔使发版);读唔到就用内置名单。
    await loadVogueslyRemotePanelHosts();
    // [0.9.92] 读返上次服务端下发嘅 app_config(客服入口 / 下载镜像 / 文案 / 横幅等)
    await loadVogueslyAppConfig();
    HttpOverrides.global = FlClashHttpOverrides();
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const Application(),
      ),
    );
  } catch (e, s) {
    return runApp(
      MaterialApp(
        home: InitErrorScreen(error: e, stack: s),
      ),
    );
  }
}
