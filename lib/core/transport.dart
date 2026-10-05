import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:rust_api/rust_api.dart';

// ── Binary frame types (mirrors Rust ipc.rs) ────────────────────────────────

const _typeReady = 0x00;
const _typeConnected = 0x01;
const _typeDisconnected = 0x02;
const _typeData = 0x03;
const _typeError = 0x04;

class IPCCoreTransport {
  final String address;
  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>();
  StreamSubscription<Uint8List>? _subscription;
  Completer<void> _completer = Completer<void>();
  Completer<void> _readyCompleter = Completer<void>();

  /// [2026-09-23] 核心「而家连住冇」。
  ///
  /// 🔴 点解要加呢样:原本全靠 `_completer`,而 `_completer` 喺 `_typeDisconnected`
  /// 会被**整个换走**(`_completer = Completer<void>()`)。任何 `await
  /// connectionCompleter.future` 攞住嘅係**换走之前嗰个**引用 —— 新嗰个 complete
  /// 唔会叫醒佢,旧嗰个又永远唔会 complete ⇒ **等嘅人永久卡死**。
  ///
  /// 2026-09-23 喺 Sam 部 Mac 实锤咗呢条链:核心 PID 活住、係 root、socket 连咗,
  /// 但**零监听端口、零 config**(收唔到启动指令);App 卡喺 await,UI 一直渲染
  /// loading 转圈 ⇒ 实测 39–53% CPU 八分钟。而此时 `isStart` 已经係 true,
  /// 於是 `http.dart` 把所有 HTTP 掟去 `PROXY localhost:mixedPort` —— 嗰个埠根本
  /// 未监听 ⇒ **连订阅都更新唔到**。一个 bug,两个症状。
  bool _connected = false;

  /// 连接状态变化广播(true=连上,false=断开)。用 stream 唔用 completer,
  /// 就係为咗避免「攞住一个已经被换走嘅 future」。
  final StreamController<bool> _connectionState =
      StreamController<bool>.broadcast();

  void Function()? onDisconnect;

  IPCCoreTransport({required this.address});

  bool get isConnected => _connected;

  /// 等核心连上;逾时返 false(唔再无限等)。
  ///
  /// ⚠️ 调用方**必须**处理 false —— 返 false = 核心冇连上,呢一刻唔可以当佢已经起咗。
  Future<bool> waitConnected({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    // 🔴🔴 [2026-09-23] **真相源係 Rust 侧嘅 `CONNECTED` 原子标志,唔係 Dart 呢边嘅
    // `_connected` 快照。** 呢个係 2026-09-23 实机撞到嘅根因,一定要留住:
    //
    // Rust 只喺 **accept 新连接嗰一刻**发一次 `TYPE_CONNECTED`。而 Dart 呢边
    // `CoreService._shutdownImpl()` 会主动 call `disconnected()` 把 `_connected`
    // 置返 false —— 但嗰阵核心条 IPC 连接**未必真係断咗**(例如只係 kill 咗进程
    // 而 Rust 侧个 listener 仲 hold 住,或者根本冇新进程要起)。
    // Rust 唔会再发多一次 `TYPE_CONNECTED` ⇒ `_connected` **永远卡喺 false**
    // ⇒ `sendMessage()` 之后把**全部**核心指令静静丢走
    // ⇒ 核心进程活住、socket 连住、但**零监听埠、零 config**,而 UI 显示已连接。
    //
    // 实机现场(Sam 部 Mac,0.9.86+2026092403):核心 PID 活住 4 分半、0% CPU、
    // App 持住 accepted fd,但 `lsof` 见唔到任何 LISTEN,订阅更新报错
    // (下载其实成功咗 —— 係跟住嘅 `validateConfig` 要经核心,核心收唔到指令)。
    //
    // ⚠️ 旧代码(改成 waitConnected 之前)係 `await connectionCompleter.future`,
    //    同一个病嘅另一种表现:等一个永远唔会 complete 嘅 completer = **永久卡死**。
    //    所以「卡死」同「静静丢走」係同一个根 —— 都係信咗 Dart 侧嘅本地快照。
    if (await isIpcConnected()) {
      _connected = true; // 同步返本地快照,费事下次再过一次 FFI
      return true;
    }
    if (_connected) return true;
    try {
      return await _connectionState.stream
          .firstWhere((connected) => connected)
          .timeout(timeout);
    } catch (_) {
      // 最后再问一次 Rust —— 广播可能喺我哋 listen 之前就发过咗
      return isIpcConnected();
    }
  }

  /// 兼容旧调用点。⚠️ 唔好再喺新代码用 —— 佢会被 `_typeDisconnected` 换走,
  /// 攞住旧引用 await 会永久卡死。一律改用 [waitConnected]。
  @Deprecated('用 waitConnected():呢个 completer 会喺断线时被替换,await 旧引用会永久卡死')
  Completer<void> get connectionCompleter => _completer;

  Stream<Uint8List> get dataStream => _dataController.stream;

  Future<void> init() async {
    try {
      final stream = restartIpcServer(name: address);
      _subscription = stream.listen(
      (data) {
        if (data.isEmpty) return;
        final type = data[0];
        final payload = data.length > 1 ? data.sublist(1) : Uint8List(0);
        switch (type) {
          case _typeReady:
            commonPrint.log('IPC Ready');
            if (_readyCompleter.isCompleted) {
              break;
            }
            _readyCompleter.complete();
            break;
          case _typeConnected:
            commonPrint.log('IPC Connected');
            // [2026-09-23] 先更新状态再广播,令 waitConnected() 无论喺边个时序
            // 入嚟都睇到真相(佢第一件事就係检查 _connected)。
            _connected = true;
            if (!_connectionState.isClosed) {
              _connectionState.add(true);
            }
            if (_completer.isCompleted) {
              break;
            }
            _completer.complete();
            break;
          case _typeDisconnected:
            commonPrint.log('IPC Disconnected');
            _connected = false;
            if (!_connectionState.isClosed) {
              _connectionState.add(false);
            }
            _completer = Completer<void>();
            onDisconnect?.call();
            break;
          case _typeData:
            _dataController.add(payload);
            break;
          case _typeError:
            final msg = utf8.decode(payload);
            commonPrint.log('IPC error: $msg', logLevel: LogLevel.error);
            break;
          default:
            commonPrint.log(
              'IPC unknown frame type: $type',
              logLevel: LogLevel.warning,
            );
        }
      },
      onError: (error) {
        commonPrint.log('IPC error: $error', logLevel: LogLevel.error);
      },
      cancelOnError: false,
    );
    await _readyCompleter.future;
    } catch (e) {
      commonPrint.log(
        'Failed to start IPC server: $e',
        logLevel: LogLevel.error,
      );
      rethrow;
    }
  }

  void send(String message) {
    sendIpcMessage(data: utf8.encode(message));
  }

  void disconnected() {
    // [2026-09-23] 同步更新 _connected,否则 waitConnected() 会因为 _connected
    // 仲係 true 而即刻返 true,当咗一条已经拆咗嘅连接仲喺度。
    _connected = false;
    if (!_connectionState.isClosed) {
      _connectionState.add(false);
    }
    _completer = Completer<void>();
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await stopIpcServer();
    // [2026-09-23] ⚠️ 要同 disconnected() 一样 reset `_connected`,否则条传输
    // 已经拆咗而 _connected 仲係 true ⇒ waitConnected() 会**即刻返 true**,
    // 调用方以为核心仲连住,然后所有指令静静掉落黑洞。
    _connected = false;
    if (!_connectionState.isClosed) {
      _connectionState.add(false);
    }
    _readyCompleter = Completer<void>();
    _completer = Completer<void>();
    await _dataController.close();
    await _connectionState.close();
  }
}
