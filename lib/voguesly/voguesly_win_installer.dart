import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'voguesly_update_download.dart';
import 'voguesly_remote_config.dart' show vogueslyDownloadPageUrl;

/// Windows app 内自我更新:下载 setup.exe(带进度)→ 直接起系统安装程序(NSIS/Inno)。
/// 对齐安卓体验:用户唔使去浏览器/Downloads 揾文件再双击。macOS 的 dmg 系拖拽安装,
/// 冇静默安装呢回事,仍走 launchUrl 浏览器下载(caller 分流)。
enum WinInstallStage { downloading, launching, error }

class WinInstallState {
  final WinInstallStage stage;
  final double progress; // 0.0-1.0,只喺 downloading 阶段有意义
  final String? errorMessage;

  const WinInstallState({
    required this.stage,
    this.progress = 0,
    this.errorMessage,
  });
}

class WinInstaller {
  static Future<String> _download(
    String url,
    void Function(double progress) onProgress,
    CancelToken cancelToken,
    String? sha256,
  ) async {
    final dir = await appPath.homeDirPath;
    final updatesDir = Directory(p.join(dir, 'updates'));
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }
    final savePath = p.join(updatesDir.path, 'voguesly-setup.exe');
    // [0.9.85] 下载完核对 Content-Length + version.json 的 sha256,不对就续传 / 重下(最多 3 次);
    // 旧残留由下载模块先删,半截 setup.exe 永远不会被运行。
    final file = await downloadVerifiedUpdate(
      dio: request.dio,
      url: url,
      savePath: savePath,
      expectedSha256: sha256,
      cancelToken: cancelToken,
      onProgress: (received, total) {
        if (total <= 0) return;
        onProgress(received / total);
      },
      log: (m) => commonPrint.log(m),
    );
    return file.path;
  }

  /// 一站式:下载 → 起安装程序(detached,installer 自己管关旧进程/替换文件)。
  static Future<void> downloadAndRun({
    required String url,
    String? sha256,
    required void Function(WinInstallState state) onState,
    CancelToken? cancelToken,
  }) async {
    final token = cancelToken ?? CancelToken();
    onState(const WinInstallState(stage: WinInstallStage.downloading));
    try {
      final path = await _download(
        url,
        (progress) => onState(
          WinInstallState(
            stage: WinInstallStage.downloading,
            progress: progress,
          ),
        ),
        token,
        sha256,
      );
      if (token.isCancelled) return; // 下载完先至关弹窗:唔好再起安装程序
      onState(const WinInstallState(stage: WinInstallStage.launching));
      // detached:安装程序独立进程,即使本 app 之后被 installer 关掉都唔影响。
      // [2026-09-18 一键更新] /SILENT = 只显示安装进度条、唔使逐页撳 Next;
      // 安装程序 [Code] InitializeSetup 会停 helper 服务 + 关旧 app,
      // [Run] postinstall(已拿走 skipifsilent)装完自动重开新版。
      await Process.start(
        path,
        const ['/SILENT', '/NORESTART', '/SP-'],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
    } catch (e) {
      commonPrint.log('[update] windows download/launch failed: $e');
      onState(
        WinInstallState(
          stage: WinInstallStage.error,
          errorMessage: e is UpdateDownloadException
              ? currentAppLocalizations.vgUpdateDownloadIncomplete
              : currentAppLocalizations.vgDownloadFailedRetry,
        ),
      );
    }
  }
}

/// Windows 下载/安装进度弹窗(对齐 ApkUpdateSheet 样式:标题 + 版本号 + 进度条)。
class WinUpdateSheet extends StatefulWidget {
  const WinUpdateSheet({
    super.key,
    required this.url,
    required this.version,
    this.sha256,
  });

  final String url;
  final String version;

  /// version.json 对应条目的 sha256;没有(旧 manifest)= 只核长度。
  final String? sha256;

  @override
  State<WinUpdateSheet> createState() => _WinUpdateSheetState();
}

class _WinUpdateSheetState extends State<WinUpdateSheet> {
  WinInstallState _state = const WinInstallState(
    stage: WinInstallStage.downloading,
  );

  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    // [0.9.88] 弹窗关咗(dispose)就取消:之前关咗照样下载完、静默安装 / 退出重开;再撳一次会两条下载写同一个档。
    _cancel?.cancel();
    super.dispose();
  }

  void _start() {
    _cancel?.cancel();
    final t = CancelToken();
    _cancel = t;
    WinInstaller.downloadAndRun(
      url: widget.url,
      sha256: widget.sha256,
      cancelToken: t,
      onState: (state) {
        if (!mounted) return;
        setState(() => _state = state);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title, style: context.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              currentAppLocalizations.vgVersionNumber(widget.version),
              style: context.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (_state.stage == WinInstallStage.downloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _state.progress > 0 ? _state.progress : null,
                  minHeight: 6,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_state.progress * 100).toStringAsFixed(0)}%',
                style: context.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            if (_state.stage == WinInstallStage.launching) ...[
              Text(
                currentAppLocalizations.vgInstallerStartedHint,
                style: context.textTheme.bodyMedium,
              ),
            ],
            if (_state.stage == WinInstallStage.error) ...[
              Text(
                _state.errorMessage ??
                    currentAppLocalizations.vgSomethingWentWrongRetry,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFEF4444),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      setState(
                        () => _state = const WinInstallState(
                          stage: WinInstallStage.downloading,
                        ),
                      );
                      _start();
                    },
                    child: Text(currentAppLocalizations.vgRetry),
                  ),
                  TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(vogueslyDownloadPageUrl()),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(currentAppLocalizations.vgOpenDownloadPage),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _title {
    switch (_state.stage) {
      case WinInstallStage.downloading:
        return currentAppLocalizations.vgDownloadingUpdate;
      case WinInstallStage.launching:
        return currentAppLocalizations.vgOpeningInstaller;
      case WinInstallStage.error:
        return currentAppLocalizations.vgDownloadFailed;
    }
  }
}
