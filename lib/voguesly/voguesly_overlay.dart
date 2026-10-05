import 'dart:async';

import 'package:fl_clash/enum/enum.dart' show PageLabel;
import 'package:fl_clash/providers/app.dart' show currentPageLabelProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'voguesly_auth.dart';

/// 内容区 overlay(半框):购买套餐 / 邀请返利 / 用户中心 / 在线客服 都只覆盖**右边内容区**,
/// 左侧栏保留可点(Sam 要求)。由 app_manager 喺内容 Expanded 内 Positioned.fill 渲染。
enum ContentOverlay { none, shop, invite, userCenter, cs, notice, stat }

class ContentOverlayNotifier extends Notifier<ContentOverlay> {
  @override
  ContentOverlay build() => ContentOverlay.none;
  void set(ContentOverlay v) => state = v;
  void close() => state = ContentOverlay.none;
}

final contentOverlayProvider =
    NotifierProvider<ContentOverlayNotifier, ContentOverlay>(
        ContentOverlayNotifier.new);

/// 在线客服隐藏后最多保活几耐;超过就真正销毁 WebView 释放内存。
const Duration kCsKeepAliveWhenHidden = Duration(minutes: 15);

/// 在线客服「保活」状态(桌面一级 tab「在线客服」用;手机底栏 / 全页 push 唔保活)。
///
/// 点解要:「在线客服」tab 原本 keep:false,切去其他菜单就 dispose → 切返嚟成个 cs.html 重新加载
/// (聊天滚动位置、打咗一半嘅字全冇,Sam 反馈)。而家分两个状态:
/// - **隐藏(保活)**:客服唔喺眼前但 state == true → WebView 唔销毁,切返嚟即时显示;
/// - **真正关闭(销毁)**:state == false → 面板移出树,下次开重新加载。
///
/// 「喺眼前」= 当前页系 PageLabel.support 且冇半框 overlay 盖住。
/// 只有以下情况先会变 false:cs.html 经桥发 `close` / 明确关闭、隐藏超过 [kCsKeepAliveWhenHidden]、
/// 登出 / 换账号(cs 页 URL 带 email,唔可以畀下个账号见到上个账号会话)、内嵌 WebView 起唔到。
/// 侧栏切去其他页面只改页面 / overlay,唔郁呢个。
class CsAliveNotifier extends Notifier<bool> {
  Timer? _hiddenTimer;

  bool _visibleNow() =>
      ref.read(contentOverlayProvider) == ContentOverlay.none &&
      ref.read(currentPageLabelProvider) == PageLabel.support;

  @override
  bool build() {
    ref.onDispose(() => _hiddenTimer?.cancel());
    // 客服一出现喺眼前就当开咗;离开就开始计隐藏时间。
    ref.listen<ContentOverlay>(contentOverlayProvider, (_, _) => _sync());
    ref.listen<PageLabel>(currentPageLabelProvider, (_, _) => _sync());
    // 登出(token → null)或者换账号(token 变)→ 连保活客服一齐销毁。
    // 放喺呢度统一处理,唔使逐条登出路径(侧栏 / 设置 / 我的 / 用户中心 / 401 自动登出)各自记得清。
    ref.listen<String?>(vogueslyAuthProvider.select((s) => s.token),
        (prev, next) {
      if (prev == next) return;
      destroy();
      if (ref.read(contentOverlayProvider) == ContentOverlay.cs) {
        ref.read(contentOverlayProvider.notifier).close();
      }
    });
    return _visibleNow();
  }

  void _sync() {
    if (_visibleNow()) {
      _hiddenTimer?.cancel();
      _hiddenTimer = null;
      state = true;
      return;
    }
    // 已经喺度计就唔重置:「隐藏 15 分钟」由离开客服嗰刻起计,喺其他页之间切嚟切去唔算重新开始。
    if (state) _hiddenTimer ??= Timer(kCsKeepAliveWhenHidden, destroy);
  }

  /// 真正关闭客服:销毁 WebView(下次开会重新加载)。
  void destroy() {
    _hiddenTimer?.cancel();
    _hiddenTimer = null;
    state = false;
  }
}

final csAliveProvider =
    NotifierProvider<CsAliveNotifier, bool>(CsAliveNotifier.new);

/// 令半框页嘅返回键(vogAppBar)喺无得再 pop 时关闭整个 overlay。
class ContentOverlayScope extends InheritedWidget {
  final VoidCallback close;
  const ContentOverlayScope({
    required this.close,
    required super.child,
    super.key,
  });

  static ContentOverlayScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentOverlayScope>();

  @override
  bool updateShouldNotify(ContentOverlayScope oldWidget) => false;
}
