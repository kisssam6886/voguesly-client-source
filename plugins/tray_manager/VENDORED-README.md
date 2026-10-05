# 呢个目录係 vendored(唔再係 submodule)

**2026-09-23 转 vendored。**

## 点解

原本係一个**孤儿 submodule** —— gitlink 喺 index 度,但 `.gitmodules` 入面
**冇佢嘅条目**;而个 remote 係 `git@github.com:chen08209/tray_manager.git`
(上游作者嘅仓库,我哋冇推送权限)。

后果:父仓库只记 gitlink(commit hash),**唔记文件内容** ⇒
我哋喺呢度嘅改动完全冇办法提交,而且 CI 一跑 `git submodule update` 就会被冲走。

## 我哋改咗咩

`packages/tray_manager/macos/Classes/TrayIcon.swift` 嘅 `setTitle()`:
加 `lastTitle` 去重 + **只喺显隐状态变化先 `button.sizeToFit()`**。

`sizeToFit()` 会触发 **NSStatusItem 完整重绘**,而 App 每秒都落一次标题
(流量数字每秒变)⇒ macOS 闲置高 CPU。
关键前提:`textField` 係 **Auto Layout 固定宽度 42pt** + `.byClipping`,
所以文本内容变根本唔会改变尺寸,嗰阵 `sizeToFit()` 係纯浪费。

上游同一个问题嘅官方修补喺 `da2d83dd`(改 `TrayIcon.swift` +71/-23),
但佢喺 `main`,而我哋个 submodule HEAD 係更早嘅 `6163dc8`。

## 将来要同上游对比

    git clone git@github.com:chen08209/tray_manager.git /tmp/tm
    cd /tmp/tm && git diff 6163dc8 main -- packages/tray_manager/macos/

`6163dc8 Optimize macos statusItem` = 我哋当初 pin 住嗰个 commit。
