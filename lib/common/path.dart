import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class AppPath {
  static AppPath? _instance;
  Completer<Directory> dataDir = Completer();
  Completer<Directory> downloadDir = Completer();
  Completer<Directory> tempDir = Completer();
  Completer<Directory> cacheDir = Completer();
  late String appDirPath;

  /// dataDir 解析后的同步快照 —— corePath 是同步 getter,拿不到 Future。
  String? _dataDirPath;

  AppPath._internal() {
    appDirPath = join(dirname(Platform.resolvedExecutable));
    getApplicationSupportDirectory().then((value) async {
      // ⚠️ 迁移要喺 dataDir.complete() **之前**做完,否则后面嘅代码会读到空目录。
      await _migrateLinuxLegacyDataDir(value);
      _dataDirPath = value.path;
      dataDir.complete(value);
      // 唔 await —— 收窄权限唔应该阻住启动;失败只记 log。
      _hardenDataDirPermissions(value.path);
    });
    getTemporaryDirectory().then((value) {
      tempDir.complete(value);
    });
    getDownloadsDirectory().then((value) {
      downloadDir.complete(value);
    });
    getApplicationCacheDirectory().then((value) {
      cacheDir.complete(value);
    });
  }

  /// Linux:`APPLICATION_ID` 由 `com.follow.clash` 改做 `com.voguesly.app` 之后,
  /// 把旧数据目录搬过嚟。
  ///
  /// `path_provider_linux` 喺 **dlopen 到 libgio-2.0.so 嘅机**(装咗 libglib2.0-dev)
  /// 用 APPLICATION_ID 做数据目录名;其余机用可执行档名(`~/.local/share/Voguesly`,
  /// 唔受呢次改名影响)。所以只有前者要搬。
  ///
  /// 保守做法(存量用户约等于零 —— Linux 版 2026-09-22 先加 —— 所以唔值得冒险):
  ///   · 新目录**已经有嘢** ⇒ 当已经迁移过 / 新装,乜都唔做
  ///   · 旧目录唔存在 / 空 ⇒ 乜都唔做
  ///   · **唔删旧目录** ⇒ 出事可以人手复原
  /// ⚠️ 旧目录名同官方 FlClash 完全一样,入面可能撈埋人哋嘅嘢 —— 所以只搬
  ///    我哋认得嘅档,唔好成个目录扫过嚟。
  static Future<void> _migrateLinuxLegacyDataDir(Directory newDir) async {
    if (!Platform.isLinux) return;
    try {
      if (await newDir.exists() && !await newDir.list().isEmpty) return;
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return;
      final legacy = Directory(join(home, '.local', 'share', 'com.follow.clash'));
      if (!await legacy.exists()) return;

      await newDir.create(recursive: true);
      var moved = 0;
      // ⚠️ **刻意唔搬 `FlClashCore`** —— copy 会丢失 setuid 位 / file capabilities,
      //    搬过嚟就係一个冇权限嘅核心,TUN 反而起唔到。
      //    核心本来就由 `provisionExternalCore()` 由 bundle 重新铺 + 重新授权。
      for (final name in const ['config.yaml', 'database.sqlite']) {
        final src = File(join(legacy.path, name));
        if (!await src.exists()) continue;
        await src.copy(join(newDir.path, name));
        moved++;
      }
      commonPrint.log(
        'linux data dir migrated from ${legacy.path}: $moved file(s); '
        'legacy dir kept for rollback',
      );
    } catch (e) {
      commonPrint.log(
        'linux legacy data dir migration failed: $e',
        logLevel: LogLevel.warning,
      );
    }
  }

  /// 把数据目录同入面**已知会含凭证**嘅档收窄权限。
  ///
  /// 🔴 [2026-09-23] 实测 Sam 部 Mac:目录 `755`、`config.yaml` `644`,
  /// 而 `config.yaml` 入面有**订阅 URL(含用户 token)** ⇒ 本机其他用户读得到。
  ///
  /// ⚠️⚠️ **唔可以一刀切扫成个目录** —— macOS / Linux 嘅 `FlClashCore` 係
  /// **setuid root**(`-rwsr-xr-x`),chmod 落去会即刻清走 setuid 位,
  /// 跟住增强模式(TUN)就永远起唔到。所以只逐个点名收窄。
  static Future<void> _hardenDataDirPermissions(String dirPath) async {
    // Windows 靠 ACL 唔係 POSIX mode,chmod 冇意义。
    if (system.isWindows) return;
    try {
      await Process.run('chmod', ['700', dirPath]);
      for (final name in const ['config.yaml', 'database.sqlite']) {
        final f = File(join(dirPath, name));
        if (await f.exists()) {
          await Process.run('chmod', ['600', f.path]);
        }
      }
    } catch (e) {
      commonPrint.log(
        'harden data dir permissions failed: $e',
        logLevel: LogLevel.warning,
      );
    }
  }

  factory AppPath() {
    _instance ??= AppPath._internal();
    return _instance!;
  }

  String get executableExtension {
    return system.isWindows ? '.exe' : '';
  }

  String get executableDirPath {
    final currentExecutablePath = Platform.resolvedExecutable;
    return dirname(currentExecutablePath);
  }

  /// App bundle / 安装目录内自带的核心(签名产物,视为只读母本)。
  String get bundledCorePath {
    return join(executableDirPath, 'FlClashCore$executableExtension');
  }

  /// 实际拿来跑的核心路径。
  ///
  /// ⚠️ macOS 26 起,已公证签名的 app bundle 受「App 管理」保护:bundle 内的文件
  /// **连 root 都改不了**(实测 `sudo chown root:admin <bundle内核心>` →
  /// `Operation not permitted`,而同一条命令对 Application Support 下的文件成功)。
  /// 后果:`authorizeCore()` 的 `chown+chmod +s` 永远失败 → `checkIsAdmin()` 永远
  /// false → 每次 `_setupConfig`(含每小时订阅自动更新)都重新弹一次管理员密码,
  /// 而 TUN 仍被降级成 false。所以 macOS 改从 Application Support 下的副本执行,
  /// 该目录不受此保护,setuid 打得上、且一次授权长期有效。
  ///
  /// 副本由 [provisionExternalCore] 在 app 启动时铺好;若尚未就绪则回退到 bundle 内
  /// 路径(至少能把核心跑起来,只是 TUN 授权仍会失败)。
  ///
  /// ⚠️ [0.9.86] Linux 同样从数据目录的副本执行:AppImage 的核心在**只读 squashfs**
  /// 挂载点里(`/tmp/.mount_*`),`authorizeCore()` 的 `sudo chown + chmod +sx` 改不动
  /// ⇒ AppImage 用户永远开不了增强模式;deb / rpm 的核心虽然改得动,但每次升级包都会
  /// 覆盖回非 setuid。铺到 `~/.local/share/...` 之后三种包的授权路径一致。
  String get corePath {
    if ((system.isMacOS || system.isLinux) && _dataDirPath != null) {
      return join(_dataDirPath!, 'FlClashCore');
    }
    return bundledCorePath;
  }

  /// 把安装目录内的核心铺到用户数据目录供执行(macOS = Application Support,Linux = ~/.local/share/…)。
  ///
  /// 只在「不存在」或「与 bundle 母本对不上」时才复制(核心 ~100MB,不能每次启动都搬)。
  /// 用母本 SHA-256 戳做比对,避免只靠 mtime 导致无谓替换并清掉 setuid。
  /// 复制走 `.new` + rename 原子替换,
  /// 避免旧核心进程仍在跑时写入报 ETXTBSY。
  ///
  /// 复制必然清掉 setuid 位(内核行为),所以只有核心内容真正更新时才需要重新授权一次。
  Future<void> provisionExternalCore() async {
    if (!system.isMacOS && !system.isLinux) return;
    try {
      final dir = await dataDir.future;
      _dataDirPath = dir.path;
      final src = File(bundledCorePath);
      if (!await src.exists()) {
        commonPrint.log('provisionExternalCore: bundle 内核心不存在,跳过');
        return;
      }
      final dstPath = join(dir.path, 'FlClashCore');
      final stampFile = File('$dstPath.stamp');
      final digest = await sha256.bind(src.openRead()).first;
      final stamp = digest.toString();
      if (await File(dstPath).exists() &&
          await stampFile.exists() &&
          (await stampFile.readAsString()).trim() == stamp) {
        return;
      }
      final tmpPath = '$dstPath.new';
      await File(tmpPath).delete().catchError((_) => File(tmpPath));
      // macOS:优先用 APFS clonefile(`cp -c`):瞬时完成、不额外占 100MB 磁盘。
      // 非 APFS 卷会失败,回退到普通字节复制。Linux 的 cp 没有 -c,直接复制
      //(btrfs / xfs 用 --reflink=auto 也能省空间,失败照样回退)。
      final clone = system.isMacOS
          ? await Process.run('cp', ['-c', bundledCorePath, tmpPath])
          : await Process.run('cp', ['--reflink=auto', bundledCorePath, tmpPath]);
      if (clone.exitCode != 0) {
        await src.copy(tmpPath);
      }
      await Process.run('chmod', ['755', tmpPath]);
      await File(tmpPath).rename(dstPath);
      await stampFile.writeAsString(stamp);
      commonPrint.log('provisionExternalCore: 已铺设核心 → $dstPath');
    } catch (e) {
      commonPrint.log('provisionExternalCore failed: $e');
    }
  }

  String get helperPath {
    return join(executableDirPath, '$appHelperService$executableExtension');
  }

  Future<String> get downloadDirPath async {
    final directory = await downloadDir.future;
    return directory.path;
  }

  Future<String> get homeDirPath async {
    final directory = await dataDir.future;
    return directory.path;
  }

  Future<String> get databasePath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'database.sqlite');
  }

  Future<String> get backupFilePath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'backup.zip');
  }

  Future<String> get restoreDirPath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'restore');
  }

  Future<String> get tempFilePath async {
    final mTempDir = await tempDir.future;
    return join(mTempDir.path, 'temp${utils.id}');
  }

  Future<String> get lockFilePath async {
    final homeDirPath = await appPath.homeDirPath;
    return join(homeDirPath, 'FlClash.lock');
  }

  Future<String> get configFilePath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'config.yaml');
  }

  Future<String> get sharedFilePath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'shared.json');
  }

  Future<String> get sharedPreferencesPath async {
    final directory = await dataDir.future;
    return join(directory.path, 'shared_preferences.json');
  }

  Future<String> get profilesPath async {
    final directory = await dataDir.future;
    return join(directory.path, profilesDirectoryName);
  }

  Future<String> getProfilePath(String fileName) async {
    return join(await profilesPath, '$fileName.yaml');
  }

  Future<String> get scriptsDirPath async {
    final path = await homeDirPath;
    return join(path, 'scripts');
  }

  Future<String> getScriptPath(String fileName) async {
    final path = await scriptsDirPath;
    return join(path, '$fileName.js');
  }

  Future<String> getIconsCacheDir() async {
    final directory = await cacheDir.future;
    return join(directory.path, 'icons');
  }

  Future<String> getProvidersRootPath() async {
    final directory = await profilesPath;
    return join(directory, 'providers');
  }

  Future<String> getProvidersDirPath(String id) async {
    final directory = await profilesPath;
    return join(directory, 'providers', id);
  }

  Future<String> getProvidersFilePath(
    String id,
    String type,
    String url,
  ) async {
    final directory = await profilesPath;
    return join(directory, 'providers', id, type, url.toMd5());
  }

  Future<String> get tempPath async {
    final directory = await tempDir.future;
    return directory.path;
  }
}

final appPath = AppPath();
