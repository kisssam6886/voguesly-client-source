import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

class Protocol {
  static Protocol? _instance;

  Protocol._internal();

  factory Protocol() {
    _instance ??= Protocol._internal();
    return _instance!;
  }

  void register(String scheme) {
    final String protocolRegKey = 'Software\\Classes\\$scheme';
    const RegistryValue protocolRegValue = RegistryValue.string(
      'URL Protocol',
      '',
    );
    const String protocolCmdRegKey = 'shell\\open\\command';
    final RegistryValue protocolCmdRegValue = RegistryValue.string(
      '',
      '"${Platform.resolvedExecutable}" "%1"',
    );
    final regKey = Registry.currentUser.createKey(protocolRegKey);
    regKey.createValue(protocolRegValue);
    regKey.createKey(protocolCmdRegKey).createValue(protocolCmdRegValue);
  }

  /// [0.9.96] 如果 `scheme://` 而家指住**我哋自己个 exe**(旧版登记落嘅),就删走,交还畀其他软件。
  /// 指住其他软件嘅就唔郁。任何读写失败都当冇事(唔可以因为呢个令 App 起唔到)。
  void unregisterIfOwned(String scheme) {
    try {
      final key = 'Software\\Classes\\$scheme';
      final cmdKey = Registry.openPath(
        RegistryHive.currentUser,
        path: '$key\\shell\\open\\command',
      );
      final cmd = cmdKey.getValueAsString('') ?? '';
      cmdKey.close();
      if (!cmd.toLowerCase().contains(Platform.resolvedExecutable.toLowerCase())) return;
      Registry.currentUser.deleteKey(key, recursive: true);
    } catch (_) {}
  }
}

final protocol = Protocol();
