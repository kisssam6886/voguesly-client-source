import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

const _allTargets = <String, String>{
  'android': 'apk',
  'linux': 'deb', // appimage + rpm added for amd64 only
  'macos': 'dmg',
  'windows': 'exe,zip',
};

const _androidFlutterTarget = {
  'arm': 'android-arm',
  'arm64': 'android-arm64',
  'amd64': 'android-x64',
};

const _hostPlatform = {
  'linux': 'linux',
  'macos': 'macos',
  'windows': 'windows',
};

Future<void> main(List<String> args) async {
  final parser = createSetupArgParser();

  if (args.contains('--help') || args.contains('-h')) {
    _showHelp(parser);
    exit(0);
  }

  final results = parser.parse(args);
  final rest = results.rest;

  final hostOs = Platform.operatingSystem;
  final host = _hostPlatform[hostOs];
  if (host == null) {
    stderr.writeln('Unsupported host platform: $hostOs');
    exit(1);
  }

  final platform = rest.isNotEmpty ? rest.first : host;

  if (platform != host && platform != 'android') {
    stderr.writeln(
      'Cannot build "$platform" on $hostOs. Allowed: $host, android',
    );
    _showHelp(parser);
    exit(1);
  }

  final env = results['env'] as String;
  final rootDir = Directory.current.path;
  final arch = _detectArch();
  final targets = _getTargets(platform, arch, results['targets']);
  final androidArch = results['arch'] as String?;
  final verbose = results['verbose'] as bool;

  final exitCode = await _package(
    platform,
    env,
    targets,
    rootDir,
    arch,
    androidArch: androidArch,
    verbose: verbose,
  );
  exit(exitCode);
}

ArgParser createSetupArgParser() {
  return ArgParser()
    ..addOption(
      'env',
      defaultsTo: 'pre',
      allowed: ['pre', 'stable'],
      help: 'Application environment',
    )
    ..addOption(
      'targets',
      valueHelp: 'exe,zip,dmg,apk,...',
      help: 'Package targets (default: all for platform)',
    )
    ..addOption(
      'arch',
      valueHelp: 'arm,arm64,amd64',
      allowed: ['arm', 'arm64', 'amd64'],
      help: 'Target architecture (Android only)',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Enable verbose Flutter build output',
    );
}

List<String> createFlutterBuildArgs({
  required String platform,
  required bool verbose,
}) {
  final flutterBuildArgs = <String>[
    if (verbose) 'verbose',
    'dart-define-from-file=env.json',
  ];
  if (platform == 'android') {
    flutterBuildArgs.add('split-per-abi');
  }
  return flutterBuildArgs;
}

String _getTargets(String platform, String arch, String? customTargets) {
  if (customTargets != null) return customTargets;
  if (platform == 'linux' && arch == 'amd64') return 'deb,appimage,rpm';
  return _allTargets[platform]!;
}

void _showHelp(ArgParser parser) {
  stderr.writeln('Usage: dart setup.dart [platform] [options]');
  stderr.writeln('Platform: current host platform (default) or android');
  stderr.writeln();
  stderr.writeln('Default package targets:');
  _allTargets.forEach((p, t) => stderr.writeln('  $p: $t'));
  stderr.writeln();
  stderr.writeln(parser.usage);
}

Future<int> _package(
  String platform,
  String env,
  String targets,
  String rootDir,
  String arch, {
  String? androidArch,
  required bool verbose,
}) async {
  final distributorDir = p.join(
    rootDir,
    'plugins',
    'flutter_distributor',
    'packages',
    'flutter_distributor',
  );
  if (platform == 'linux') {
    final patchExit = await _patchDistributorForLinux(rootDir);
    if (patchExit != 0) return patchExit;
  }

  final activateResult = await Process.run('dart', [
    'pub',
    'global',
    'activate',
    '-s',
    'path',
    distributorDir,
  ]);
  if (activateResult.exitCode != 0) {
    stderr.write(activateResult.stderr);
    return activateResult.exitCode;
  }

  final coreSha256 = platform == 'windows' ? await _buildGoCore(rootDir) : null;

  final file = File(p.join(rootDir, 'env.json'));

  await file.writeAsString(
    jsonEncode({'APP_ENV': env, 'CORE_SHA256': ?coreSha256}),
  );

  final flutterBuildArgs = createFlutterBuildArgs(
    platform: platform,
    verbose: verbose,
  );
  final descriptionArgs = <String>[];
  if (platform != 'android') {
    descriptionArgs.addAll(['--description', arch]);
  }

  final depExit = await _ensureDependencies(platform, arch);
  if (depExit != 0) return depExit;
  if (platform == 'linux' && targets.split(',').contains('appimage')) {
    final dbExit = await _refreshLocateDb();
    if (dbExit != 0) return dbExit;
  }

  final process = await Process.start(
    'flutter_distributor',
    [
      'package',
      '--skip-clean',
      '--platform',
      platform,
      '--targets',
      targets,
      if (androidArch != null)
        '--build-target-platform=${_androidFlutterTarget[androidArch]!}',
      if (flutterBuildArgs.isNotEmpty)
        '--flutter-build-args=${flutterBuildArgs.join(',')}',
      ...descriptionArgs,
    ],
    includeParentEnvironment: true,
    environment: {'ANDROID_ARCH': ?androidArch},
    runInShell: Platform.isWindows,
  );

  process.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  process.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });
  final exitCode = await process.exitCode;
  if (exitCode != 0) return exitCode;
  if (platform == 'linux' && targets.split(',').contains('appimage')) {
    return _pruneAppImages(rootDir, arch);
  }
  return exitCode;
}

/// AppImage 官方 excludelist(github.com/AppImageCommunity/pkg2appimage/blob/master/excludelist):
/// 必须用目标系统自己嘅版本、唔可以打包嘅基础库。flutter_app_packager 会按 ldd 把佢哋一齐抄入 usr/lib
/// (冇 exclude 选项),Ubuntu 22.04 嘅 GL / EGL / gbm / drm 喺 Debian 12 令 Flutter 起唔到
/// (「No provider of glGetShaderiv found」,2026-09-22 D Band 实测;剔走之后正常启动 + 登录 + 连接)。
const _appImageExcludedLibs = <String>[
  'ld-linux.so.2',
  'ld-linux-x86-64.so.2',
  'libanl.so.1',
  'libBrokenLocale.so.1',
  'libcidn.so.1',
  'libc.so.6',
  'libdl.so.2',
  'libm.so.6',
  'libmvec.so.1',
  'libnss_compat.so.2',
  'libnss_dns.so.2',
  'libnss_files.so.2',
  'libnss_hesiod.so.2',
  'libnss_nisplus.so.2',
  'libnss_nis.so.2',
  'libpthread.so.0',
  'libresolv.so.2',
  'librt.so.1',
  'libthread_db.so.1',
  'libutil.so.1',
  'libstdc++.so.6',
  'libGL.so.1',
  'libEGL.so.1',
  'libGLdispatch.so.0',
  'libGLX.so.0',
  'libOpenGL.so.0',
  'libdrm.so.2',
  'libglapi.so.0',
  'libgbm.so.1',
  'libxcb.so.1',
  'libX11.so.6',
  'libX11-xcb.so.1',
  'libwayland-client.so.0',
  'libasound.so.2',
  'libfontconfig.so.1',
  'libfreetype.so.6',
  'libharfbuzz.so.0',
  'libcom_err.so.2',
  'libexpat.so.1',
  'libgcc_s.so.1',
  'libgpg-error.so.0',
  'libICE.so.6',
  'libSM.so.6',
  'libusb-1.0.so.0',
  'libuuid.so.1',
  'libz.so.1',
  'libjack.so.0',
  'libpipewire-0.3.so.0',
  'libxcb-dri3.so.0',
  'libxcb-dri2.so.0',
  'libfribidi.so.0',
  'libgmp.so.10',
];

/// [0.9.86] 修 flutter_distributor(submodule = 上游 chen08209 嘅 fork,我哋 push 唔到)两个 Linux 打包缺陷。
/// 打包前直接改 submodule 内嘅 Dart 源(要喺 `dart pub global activate` 之前),改唔到就报错 —— 
/// 避免上游改咗字串之后我哋静静地冇 patch 到、又出一次有问题嘅包。
///
/// ① rpm spec 写死 `%attr(4755, root, root) %{_datadir}/pixmaps/%{name}.png`
///    ⇒ 图标档带 **setuid root**(Fedora 44 实测:`[ -u file ]` 命中,`rpm -V` 干净 = 打包时烤入去)。
///    PNG 唔可执行,直接利用唔到,但 rpmlint / 安全扫描必红 ⇒ 改 0644。
/// ② deb / rpm 生成嘅 .desktop 写 `Version=<app 版本>`;freedesktop 规范入面 Version= 係
///    **desktop entry 规范版本**(1.0),写 app 版本会令 `desktop-file-validate` 直接报 error ⇒ 改 '1.0'。
///    ⚠️ deb 嘅 CONTROL 段都有同一句 `'Version': appVersion.toString(),`(嗰个係包版本,啱嘅)
///    ⇒ 只改 `'DESKTOP': {` 之后嗰段。
Future<int> _patchDistributorForLinux(String rootDir) async {
  final base = p.join(
    rootDir,
    'plugins',
    'flutter_distributor',
    'packages',
    'flutter_app_packager',
    'lib',
    'src',
    'makers',
  );
  const desktopVersionOld = "'Version': appVersion.toString(),";
  const desktopVersionNew = "'Version': '1.0',";

  int patchFile(String path, List<List<String>> edits, {bool desktopOnly = false}) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('patch distributor: missing $path');
      return 1;
    }
    var content = file.readAsStringSync();
    for (final edit in edits) {
      final from = edit[0];
      final to = edit[1];
      if (content.contains(to) && !content.contains(from)) {
        stdout.writeln('patch distributor: already patched -> $to');
        continue;
      }
      if (!content.contains(from)) {
        stderr.writeln('patch distributor: pattern not found in $path: $from');
        return 1;
      }
      if (desktopOnly && from == desktopVersionOld) {
        const marker = "'DESKTOP': {";
        final idx = content.indexOf(marker);
        if (idx < 0) {
          stderr.writeln('patch distributor: DESKTOP block not found in $path');
          return 1;
        }
        final head = content.substring(0, idx);
        final tail = content.substring(idx).replaceFirst(from, to);
        content = head + tail;
      } else {
        content = content.replaceAll(from, to);
      }
      stdout.writeln('patch distributor: ${p.basename(path)}: $from -> $to');
    }
    file.writeAsStringSync(content);
    return 0;
  }

  final rpmExit = patchFile(
    p.join(base, 'rpm', 'make_rpm_config.dart'),
    [
      ["'(4755, root, root) %{_datadir}/pixmaps/%{name}.png'",
       "'(0644, root, root) %{_datadir}/pixmaps/%{name}.png'"],
      [desktopVersionOld, desktopVersionNew],
    ],
    desktopOnly: true,
  );
  if (rpmExit != 0) return rpmExit;

  return patchFile(
    p.join(base, 'deb', 'make_deb_config.dart'),
    [
      [desktopVersionOld, desktopVersionNew],
    ],
    desktopOnly: true,
  );
}

/// 打包完再修 AppImage:解开 → 剔走 excludelist 嘅库 → 确认 libjpeg.so.8 仲喺度 → appimagetool 重新封装。
Future<int> _pruneAppImages(String rootDir, String arch) async {
  final distDir = Directory(p.join(rootDir, 'dist'));
  final images = distDir.existsSync()
      ? distDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.AppImage'))
            .toList()
      : <File>[];
  if (images.isEmpty) {
    stderr.writeln('AppImage prune: no .AppImage found under ${distDir.path}');
    return 1;
  }
  for (final image in images) {
    final work = await Directory.systemTemp.createTemp('appimage-prune-');
    try {
      final extract = await Process.run(image.absolute.path, [
        '--appimage-extract',
      ], workingDirectory: work.path);
      final appDir = p.join(work.path, 'squashfs-root');
      if (extract.exitCode != 0 || !Directory(appDir).existsSync()) {
        stderr.writeln('AppImage prune: extract failed: ${extract.stderr}');
        return extract.exitCode == 0 ? 1 : extract.exitCode;
      }
      final libDir = p.join(appDir, 'usr', 'lib');
      final removed = <String>[];
      for (final name in _appImageExcludedLibs) {
        final file = File(p.join(libDir, name));
        if (file.existsSync()) {
          file.deleteSync();
          removed.add(name);
        }
      }
      stdout.writeln(
        'AppImage prune: removed ${removed.length}: ${removed.join(', ')}',
      );
      if (!File(p.join(libDir, 'libjpeg.so.8')).existsSync()) {
        stderr.writeln(
          'AppImage prune: usr/lib/libjpeg.so.8 missing (see appimage make_config include)',
        );
        return 1;
      }
      final pruned = '${image.absolute.path}.pruned';
      final pack = await Process.run(
        'appimagetool',
        [appDir, pruned],
        environment: {'ARCH': arch == 'arm64' ? 'aarch64' : 'x86_64'},
      );
      if (pack.exitCode != 0) {
        stderr.write(pack.stdout);
        stderr.write(pack.stderr);
        return pack.exitCode;
      }
      await File(pruned).rename(image.absolute.path);
      stdout.writeln('AppImage prune: repacked ${image.path}');
    } finally {
      await work.delete(recursive: true);
    }
  }
  return 0;
}

Future<String?> _buildGoCore(String rootDir) async {
  final buildToolDir = p.join(
    rootDir,
    'plugins',
    'setup',
    'buildkit',
    'build_tool',
  );
  final result = await Process.run('dart', [
    'run',
    'build_tool',
    'windows',
    '--root-dir',
    rootDir,
  ], workingDirectory: buildToolDir);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    return null;
  }
  final shaFile = File(p.join(rootDir, 'core_sha256.json'));
  if (!shaFile.existsSync()) return null;
  final content =
      jsonDecode(shaFile.readAsStringSync()) as Map<String, dynamic>;
  return content['CORE_SHA256'] as String?;
}

String _detectArch() {
  if (Platform.isWindows) {
    final pa = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'AMD64';
    return pa.toUpperCase() == 'ARM64' ? 'arm64' : 'amd64';
  }
  final result = Process.runSync('uname', ['-m']);
  final machine = (result.stdout as String).trim();
  if (machine == 'aarch64') return 'arm64';
  if (machine == 'x86_64') return 'amd64';
  return machine;
}

Future<bool> _hasCommand(String cmd) async {
  final which = Platform.isWindows ? 'where' : 'command';
  final args = Platform.isWindows ? [cmd] : ['-v', cmd];
  final result = await Process.run(which, args);
  return result.exitCode == 0;
}

Future<int> _ensureDependencies(String platform, String arch) async {
  switch (platform) {
    case 'macos':
      return _ensureMacosDependencies();
    case 'linux':
      return _ensureLinuxDependencies(arch);
    default:
      return 0;
  }
}

Future<int> _ensureMacosDependencies() async {
  if (await _hasCommand('appdmg')) {
    stdout.writeln('appdmg already installed, skipping.');
    return 0;
  }
  stdout.writeln('Installing appdmg (DMG creator)...');
  final result = await Process.run('npm', ['install', '-g', 'appdmg']);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
  }
  return result.exitCode;
}

Future<int> _ensureLinuxDependencies(String arch) async {
  final pkgGroups = <List<String>>[
    ['ninja-build', 'libgtk-3-dev'],
    ['libayatana-appindicator3-dev'],
    ['libkeybinder-3.0-dev'],
    // flutter_web_auth_2 → desktop_webview_window 嘅 Linux 插件要 webkit2gtk(冇就 CMake 直接失败)
    ['libwebkit2gtk-4.1-dev'],
    ['locate'],
  ];
  if (arch == 'amd64') {
    pkgGroups.addAll([
      ['rpm', 'patchelf'],
      ['libfuse2'],
    ]);
  }

  final missingGroups = <List<String>>[];
  for (final group in pkgGroups) {
    final missingPkgs = <String>[];
    for (final pkg in group) {
      if (!await _isDebianPackageInstalled(pkg)) {
        missingPkgs.add(pkg);
      }
    }
    if (missingPkgs.isNotEmpty) {
      missingGroups.add(missingPkgs);
    }
  }

  if (missingGroups.isEmpty) {
    stdout.writeln('All Linux build dependencies already installed, skipping.');
  } else {
    stdout.writeln('Updating apt package lists...');
    final updateExit = await _runLinuxDependencyCommand([
      'apt-get',
      'update',
      '-y',
    ]);
    if (updateExit != 0) {
      stderr.writeln(
        'apt-get update exited with $updateExit; continuing and verifying '
        'dependency installation directly.',
      );
    }

    for (final missingPkgs in missingGroups) {
      stdout.writeln(
        'Installing Linux build dependencies: ${missingPkgs.join(', ')}...',
      );
      final installExit = await _installLinuxPackages(missingPkgs);
      if (installExit != 0) return installExit;
    }
  }

  if (arch == 'amd64') {
    const appimagetool = '/usr/local/bin/appimagetool';
    if (File(appimagetool).existsSync()) {
      stdout.writeln('appimagetool already installed, skipping.');
      return 0;
    }
    stdout.writeln('Downloading appimagetool...');
    final downloadName = arch == 'amd64' ? 'x86_64' : 'aarch64';
    final dlResult = await Process.run('wget', [
      '-O',
      appimagetool,
      'https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-$downloadName.AppImage',
    ]);
    if (dlResult.exitCode != 0) {
      stderr.write(dlResult.stderr);
      return dlResult.exitCode;
    }
    await Process.run('chmod', ['+x', appimagetool]);
  }

  return 0;
}

Future<bool> _isDebianPackageInstalled(String pkg) async {
  final result = await Process.run('dpkg', ['-s', pkg]);
  return result.exitCode == 0 &&
      (result.stdout as String).contains('Status: install ok installed');
}

Future<bool> _areDebianPackagesInstalled(List<String> pkgs) async {
  for (final pkg in pkgs) {
    if (!await _isDebianPackageInstalled(pkg)) {
      return false;
    }
  }
  return true;
}

Future<int> _installLinuxPackages(List<String> pkgs) async {
  final exitCode = await _runLinuxDependencyCommand([
    'apt-get',
    'install',
    '-y',
    ...pkgs,
  ]);
  if (exitCode == 0) return 0;

  if (await _areDebianPackagesInstalled(pkgs)) {
    stderr.writeln(
      'apt-get install exited with $exitCode, but all requested packages are '
      'installed; continuing.',
    );
    return 0;
  }

  return exitCode;
}

/// AppImage 打包器用 `locate` 揾 linux/packaging/appimage/make_config.yaml `include` 列嘅 .so
/// (libjpeg.so.8,见该档注释)。CI 新装嘅 locate 冇数据库 ⇒ 打包前生成;只索引 /usr/lib,几秒搞掂。
Future<int> _refreshLocateDb() async {
  stdout.writeln('Refreshing locate database for AppImage include...');
  var exitCode = await _runLinuxDependencyCommand([
    'updatedb',
    '--localpaths=/usr/lib',
  ]);
  if (exitCode != 0) {
    // plocate / mlocate 嘅 updatedb 唔识 --localpaths ⇒ 改为全盘索引。
    exitCode = await _runLinuxDependencyCommand(['updatedb']);
  }
  return exitCode;
}

Future<int> _runLinuxDependencyCommand(List<String> command) async {
  final sudoCommand = [
    'env',
    'DEBIAN_FRONTEND=noninteractive',
    'NEEDRESTART_MODE=a',
    ...command,
  ];
  stdout.writeln('exec: sudo ${sudoCommand.join(' ')}');
  final result = await Process.start('sudo', sudoCommand);
  result.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  result.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });
  final exitCode = await result.exitCode;
  if (exitCode != 0) {
    stderr.writeln('Linux dependency command failed with exit code $exitCode.');
  }
  return exitCode;
}
