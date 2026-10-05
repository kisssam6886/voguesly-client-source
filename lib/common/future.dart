import 'dart:async';
import 'dart:ui';

import 'package:fl_clash/common/common.dart';

extension FutureExt<T> on Future<T> {
  Future<T> withTimeout({
    Duration? timeout,
    String? tag,
    VoidCallback? onLast,
    FutureOr<T> Function()? onTimeout,
  }) {
    final realTimeout = timeout ?? const Duration(minutes: 3);

    // 🔴 [2026-09-23] 原本呢个 Timer **从不取消**:每次调用都留低一个
    // 「`realTimeout` + commonDuration 之後先触发」嘅 Timer,而 `timeout` 传 null 時
    // 默认係 **3 分钟**。App 每秒有 2 次核心 IPC(`getTraffic` + `getTotalTraffic`)
    // ⇒ 稳态常驻约 **360 个待触发 Timer + 360 个 `_callbackCompleterMap` 条目**
    // (2/秒 × 180 秒)。有界,唔算泄漏,但係持续嘅 Timer 堆 churn。
    //
    // ⚠️ 唔可以净係 cancel 咗算数 —— `onLast` 唔止係「逾时兜底」,佢仲负责
    //    **删 map 条目 + 兜底完成 completer**(见 `core/service.dart` 嘅 invoke)。
    //    所以改成:边个先到就边个做,而且只做一次。
    //      · 正常收到响应 ⇒ `whenComplete` 即刻清理 + cancel 咗个 Timer
    //      · 一直冇响应   ⇒ Timer 到点先清理(同原本行为一样)
    Timer? lastTimer;
    var lastDone = false;
    void runLast() {
      if (lastDone) return;
      lastDone = true;
      lastTimer?.cancel();
      lastTimer = null;
      onLast?.call();
    }

    lastTimer = Timer(realTimeout + commonDuration, runLast);
    return this
        .timeout(
          realTimeout,
          onTimeout: () async {
            if (onTimeout != null) {
              return onTimeout();
            } else {
              throw TimeoutException('${tag ?? runtimeType} timeout');
            }
          },
        )
        .whenComplete(runLast);
  }
}

extension CompleterExt<T> on Completer<T> {
  void safeCompleter(T value) {
    if (isCompleted) {
      return;
    }
    complete(value);
  }
}
