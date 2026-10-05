import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

double get listHeaderHeight {
  final measure = globalState.measure;
  return 20 + measure.titleMediumHeight + 4 + measure.bodyMediumHeight + 2;
}

double getItemHeight(ProxyCardType proxyCardType) {
  final measure = globalState.measure;
  final baseHeight =
      16 + measure.bodyMediumHeight * 2 + measure.bodySmallHeight + 8 + 4;
  return switch (proxyCardType) {
    ProxyCardType.expand => baseHeight + measure.labelSmallHeight + 6,
    ProxyCardType.shrink => baseHeight,
    ProxyCardType.min => baseHeight - measure.bodyMediumHeight,
  };
}

List<Group> getCurrentGroups() {
  return globalState.container.read(currentGroupsStateProvider).value;
}

List<Group> getGroups() {
  return globalState.container.read(groupsProvider);
}

String? getCurrentGroupName() {
  return globalState.container.read(
    currentProfileProvider.select((state) => state?.currentGroupName),
  );
}

void updateCurrentGroupName(String groupName) {
  globalState.container
      .read(proxiesActionProvider.notifier)
      .updateCurrentGroupName(groupName);
}

void updateCurrentUnfoldSet(Set<String> value) {
  globalState.container
      .read(proxiesActionProvider.notifier)
      .updateCurrentUnfoldSet(value);
}

Future<void> proxyDelayTest(Proxy proxy, [String? testUrl]) async {
  final ref = globalState.container;
  final groups = getGroups();
  final selectedMap = ref.read(
    currentProfileProvider.select((state) => state?.selectedMap ?? {}),
  );
  final state = computeRealSelectedProxyState(
    proxy.name,
    groups: groups,
    selectedMap: selectedMap,
  );
  final currentTestUrl = state.testUrl.takeFirstValid([
    ref.read(realTestUrlProvider(testUrl)),
  ]);
  if (state.proxyName.isEmpty) {
    return;
  }
  final pendingKey = '$currentTestUrl|${state.proxyName}';
  _pendingUserDelayTests.update(pendingKey, (n) => n + 1, ifAbsent: () => 1);
  try {
    ref
        .read(proxiesActionProvider.notifier)
        .setDelay(Delay(url: currentTestUrl, name: state.proxyName, value: 0));
    var result = await coreController.getDelay(currentTestUrl, state.proxyName);
    // [2026-09-18 0.9.79 Sam 拍板] Timeout 先自动再测一次先算「未连通」(同巡检脚本一致):
    //   单次 timeout 好多时係冷握手/瞬时抖动,唔係节点死。
    if ((result.value ?? -1) <= 0) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      result = await coreController.getDelay(currentTestUrl, state.proxyName);
    }
    ref
        .read(proxiesActionProvider.notifier)
        .setDelay(_smoothDelay(result));
  } finally {
    // 多留 2 秒:核心嘅 hook 事件可能比回调迟到,迟到嘅都要当手动测速忽略。
    Future<void>.delayed(const Duration(seconds: 2), () {
      final n = (_pendingUserDelayTests[pendingKey] ?? 1) - 1;
      if (n <= 0) {
        _pendingUserDelayTests.remove(pendingKey);
      } else {
        _pendingUserDelayTests[pendingKey] = n;
      }
    });
  }
}

/// [0.9.87] 用户手动测速进行中嘅 `url|节点名`。
/// 核心每次 URLTest 都会经 `UrlTestHook` 推一个**原始值**事件(`onDelay`),连用户手动测速都推 ——
/// 之前事件同回调两边都 setDelay,边个后到就显示边个 ⇒ 0.9.79 嘅平滑有一半时间畀原始值覆盖咗。
/// 而家:手动测速期间嘅事件忽略,只认回调嗰个平滑值。
final Map<String, int> _pendingUserDelayTests = {};

/// [0.9.87] 核心推嚟嘅延迟事件(主要係 url-test / fallback 组每 5 分钟嘅**后台健康检查**)。
/// - 属于用户手动测速 ⇒ 忽略(回调会处理)。
/// - 成功 ⇒ 照样入平滑样本。
/// - 失败 ⇒ **唔再显示红色「未连通」**:后台一次 5 秒超时好多时只係瞬时抖动,
///   之前令「切换线路」一片红,用户以为节点死晒。改为清空样本、显示「未测试」,
///   用户撳一下就会真测(真测都失败先显示「未连通」)。亦唔会继续显示旧嘅好数字。
void onCoreDelayEvent(Delay delay) {
  if (_pendingUserDelayTests.containsKey('${delay.url}|${delay.name}')) return;
  final action = globalState.container.read(proxiesActionProvider.notifier);
  if ((delay.value ?? -1) > 0) {
    action.setDelay(_smoothDelay(delay));
  } else {
    _delaySamples.remove('${delay.url}|${delay.name}');
    action.setDelay(delay.copyWith(value: null));
  }
}

/// [0.9.87 Sam 拍板,取代 0.9.79 嘅中位数] 显示「最近 3 次 unified-delay 嘅**最小值**」。
/// 点解唔用中位数:① 2 个样本时 `sorted[2 ~/ 2]` = 较慢嗰次 ⇒ 用户第二次撳测速,见到嘅永远係两次中差嗰个;
///   ② 延迟噪音係单边嘅 —— 拥塞 / 冷握手只会令数字变大,唔会无端变细,所以最小值先最接近条链路真实能力
///   (ping 报 min/avg/max、估路径容量都用 min,同一个道理)。
/// timeout 唔入样本,而且会清空样本(节点由通变死,唔应该仲显示旧嘅好数字)。样本只喺本次运行内保留。
final Map<String, List<int>> _delaySamples = {};
const int _kDelaySampleWindow = 3;

Delay _smoothDelay(Delay latest) {
  final key = '${latest.url}|${latest.name}';
  final v = latest.value ?? -1;
  if (v <= 0) {
    _delaySamples.remove(key);
    return latest;
  }
  final samples = (_delaySamples[key] ??= <int>[])..add(v);
  if (samples.length > _kDelaySampleWindow) samples.removeAt(0);
  final best = samples.reduce((a, b) => a < b ? a : b);
  return latest.copyWith(value: best);
}

/// 整组延迟测试嘅并发上限。
///
/// 点解要限:原本 `batch(100)` 等于一次过掟 100 条落 Core。超出 Core 自己嘅
/// 并发处理能力嗰批会喺入面排队,排到嘅时候已经食晒 5 秒 timeout ⇒ 明明活嘅节点
/// 报「超时/红」。Sam 2026-09-08 实测:52 条节点一次过测,大量报死;改逐条顺序测
/// 之后只有 6 条係真死。上游 chen08209 亦独立撞到同一个坑(commit 7fb4f4f,
/// 佢哋 cap 喺 50 —— 但我哋实测 52 已经出事,所以要更保守)。
///
/// 同一个根因喺 `voguesly_detection.dart` 嘅 `_pingBounded` 已经写过:
/// 并发暴发会令个别探针嘅暖连接建唔起、量到冷握手(虚高≈4×RTT)。
///
/// 12 = 准确度同总时长嘅折衷:52 条约 5 轮,每条结果一完成即刻回填 UI(唔係等
/// 成批先刷),所以用户见到嘅係逐个亮起,唔会觉得卡住。
const _kDelayTestConcurrency = 12;

Future<void> delayTest(List<Proxy> proxies, [String? testUrl]) async {
  final list = List<Proxy>.of(proxies);
  var index = 0;

  Future<void> worker() async {
    while (true) {
      final i = index++;
      if (i >= list.length) return;
      await proxyDelayTest(list[i], testUrl);
    }
  }

  final workerCount =
      list.length < _kDelayTestConcurrency ? list.length : _kDelayTestConcurrency;
  await Future.wait([for (var w = 0; w < workerCount; w++) worker()]);
  globalState.container.read(sortNumProvider.notifier).add();
}

double getScrollToSelectedOffset({
  required String groupName,
  required List<Proxy> proxies,
}) {
  final ref = globalState.container;
  final columns = ref.read(proxiesColumnsProvider);
  final proxyCardType = ref.read(
    proxiesStyleSettingProvider.select((state) => state.cardType),
  );
  final selectedProxyName = ref.read(selectedProxyNameProvider(groupName));
  final findSelectedIndex = proxies.indexWhere(
    (proxy) => proxy.name == selectedProxyName,
  );
  final selectedIndex = findSelectedIndex != -1 ? findSelectedIndex : 0;
  final rows = (selectedIndex / columns).floor();
  return rows * getItemHeight(proxyCardType) + (rows - 1) * 8;
}

/// [0.9.87] 切去某个线路组(标签页切换 / 列表展开)时,**自动补测呢个组入面「未测试」嘅节点**。
/// 点解:手动测速只测当前 tab,其他组一直冇数(之前仲会被后台失败标成红色「未连通」),
/// 用户睇落以为成片线路死晒。
/// - 只测冇数嘅(已经有数 / 测紧嘅唔重测),唔会同用户手动测速撞;
/// - 同一个组 5 分钟内最多自动补测一次;核心未启动唔测(测咗都係失败)。
final Map<String, DateTime> _autoTestedAt = {};

Future<void> autoTestUntested(
  String groupName,
  List<Proxy> proxies, [
  String? testUrl,
]) async {
  final c = globalState.container;
  if (!c.read(isStartProvider) || proxies.isEmpty) return;
  final last = _autoTestedAt[groupName];
  if (last != null && DateTime.now().difference(last) < const Duration(minutes: 5)) {
    return;
  }
  final untested = proxies
      .where((p) => c.read(delayProvider(proxyName: p.name, testUrl: testUrl)) == null)
      .toList();
  if (untested.isEmpty) return;
  _autoTestedAt[groupName] = DateTime.now();
  await delayTest(untested, testUrl);
}
