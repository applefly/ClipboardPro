# macOS 菜单栏剪切板管理工具

## Context

用户需要一个类似 Paste / iPaste 的本机剪切板管理工具:
- **平台**:仅 macOS,不需要多端同步
- **形态**:菜单栏常驻图标,点选或快捷键唤起下拉面板
- **内容**:纯文本、富文本/HTML、文件路径(不含图片)
- **核心**:全局快捷键唤起、搜索历史、点击即粘贴
- **容量**:100 条历史,内存中保存(不持久化,重启清空)
- **实现**:Swift 原生应用,单文件 `swiftc` 编译成 `.app` 包

## 技术选型理由

- **Swift + AppKit 单文件**:原生性能、`NSPasteboard` 集成完整、`LSUIElement` 隐藏 Dock 图标后纯菜单栏运行;`swiftc` 即可编译,无需 Xcode 工程。
- **菜单栏下拉用 `NSPanel` 而非 `NSMenu`**:`NSMenu` 无法做实时搜索过滤(键入即过滤的体验差),改用无边框 `NSPanel` + `NSTextField` + `NSTableView`,实现 iPaste 那种带搜索框的下拉面板。
- **全局快捷键用 Carbon `RegisterEventHotKey`**:纯 C API,Swift 直接桥接,无需第三方库,且大多数组合键不需要辅助功能权限(模拟 Cmd+V 才需要)。
- **粘贴模拟用 `CGEvent`**:点选后写入 `NSPasteboard.general` 并用 `CGEvent` post 一份 Cmd+V 按键事件,实现"点击即粘贴"。需要辅助功能权限,启动时用 `AXIsProcessTrustedWithOptions` 弹窗引导授权;未授权时降级为"仅复制到剪切板",用户自己 Cmd+V。

## 文件清单(全部新建)

工作目录:`/Users/peppa/Library/Application Support/TRAE SOLO CN/ModularData/ai-agent/work-mode-projects/6aa17135f6cf7c229c50d6a7`

| 文件 | 作用 |
|---|---|
| `ClipboardManager.swift` | 单文件源码,包含所有类(见下方结构) |
| `Info.plist` | `.app` 包元数据:`LSUIElement=true`、`CFBundleIdentifier`、`NSAppleEventsUsageDescription` 等 |
| `build.sh` | 一键构建脚本:调用 `swiftc` 编译,自动生成 `.app` 包并注入 `Info.plist` |
| `README.md` | 使用说明:构建、首次启动授权辅助功能、修改快捷键、卸载方法 |

> 说明:不在源码里写注释类垃圾代码;只在逻辑不自明处加简短中文注释。`README.md` 是工具交付的一部分,属于必要文档。

## `ClipboardManager.swift` 结构

按从上到下的顺序组织:

1. **import 头**
   ```swift
   import Cocoa
   import Carbon              // RegisterEventHotKey
   import ApplicationServices // AXIsProcessTrustedWithOptions
   ```

2. **`ClipboardItem` 结构体**
   ```swift
   struct ClipboardItem {
       let id: UUID
       let kind: Kind          // .text / .richText / .filePaths
       let plainText: String   // 显示文本与纯文本回填
       let htmlString: String? // 富文本场景的 HTML(若有)
       let fileURLs: [URL]?    // 文件路径场景
       let copiedAt: Date
   }
   ```
   - 去重规则:相邻且 `plainText` 完全相同的项不重复入栈;超过 100 条 LRU 弹出最旧。

3. **`AppDelegate: NSObject, NSApplicationDelegate`**
   - `statusItem: NSStatusItem`(图标用 SF Symbol `doc.on.clipboard`)
   - `historyPanelController: HistoryPanelController`
   - `pasteboardWatcher: PasteboardWatcher`
   - `hotkeyRef: EventHotKeyRef`(Cmd+Shift+V,可在 `main` 中改为可配置常量)
   - `applicationDidFinishLaunching`:
     1. 设置 statusItem + 点击 action → toggle 面板
     2. 启动 PasteboardWatcher
     3. 注册全局快捷键(`RegisterEventHotKey` + `InstallEventHandler`)
     4. 触发辅助功能授权引导
     5. 构建 HistoryPanelController

4. **`PasteboardWatcher`**
   - `Timer` 每 0.5s 检查 `NSPasteboard.general.changeCount`
   - changeCount 增量 → 抓取当前内容,判断类型优先级:`fileURLs > htmlString > plainText`
   - 回调闭包把 `ClipboardItem` 推给 AppDelegate;跳过自己回填产生的 changeCount(用一个 `isPasting` 标志位屏蔽)

5. **`HistoryPanelController`**
   - 持有一个 `NSPanel`(borderless,`backingType=.buffered`,`styleMask=[.borderless, .nonactivatingPanel]`)
   - `show(below statusItem:)`:用 statusItem 的 `button!.window` 计算 frame,在图标正下方弹出面板,宽度 360,高度上限 420(条数少时按内容收缩)
   - `hide()`:orderOut
   - 内含 `HistoryViewController`:`NSSearchTextField` + `NSTableView`(单列、行高 32)
   - 失焦自动隐藏:`NSWindowDidResignKeyNotification` → hide

6. **`HistoryViewController: NSViewController, NSTableViewDataSource & Delegate, NSSearchFieldDelegate`**
   - 维护 `allItems: [ClipboardItem]` 与 `filteredItems: [ClipboardItem]`
   - 搜索框变更 → 重建 `filteredItems`(子串匹配,大小写不敏感,匹配 plainText / 文件名)→ `tableView.reloadData`
   - 行视图:左侧 8px 类型色条(文本灰、富文本蓝、文件橙),中间 `plainText` 截断显示,右侧相对时间(`刚刚 / 3 分钟前`)
   - 行点击 / 回车 → 调用 `PasteSimulator.paste(item)` → 关闭面板
   - 上下方向键移动选择,回车确认(标准 NSTableView 行为)
   - `Cmd+Backspace` 删除当前项(可选便利功能,逻辑简单顺手加上)

7. **`PasteSimulator`**
   ```swift
   static func paste(_ item: ClipboardItem) {
       let pb = NSPasteboard.general
       pb.clearContents()
       switch item.kind {
       case .text:        pb.setString(item.plainText, forType: .string)
       case .richText:    pb.setString(item.plainText, forType: .string)
                          if let html = item.htmlString { pb.setString(html, forType: .html) }
       case .filePaths:   if let urls = item.fileURLs { pb.writeObjects(urls) }
       }
       DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
           Self.simulateCmdV()   // CGEvent keydown/keyup V with mask Cmd
       }
   }
   ```
   - `simulateCmdV()`:用 `CGEvent(keyboardEventSource:virtualKey:)` 构造 V 键事件,`flags = .maskCommand`,`post(tap: .cghidEventTap)`。如检测到辅助功能未授权,跳过并打印一次警告。

8. **全局快捷键回调**
   - 用 C 风格的 `EventHandlerUPP` + `GetApplicationEventTarget`
   - 回调里调用 `AppDelegate.shared.togglePanelFromHotkey()`,即"先记住当前最前 app → 显示面板 → 选择后激活原 app → 写 pasteboard → 模拟 Cmd+V"
   - 用一个 `static var shared` 单例方便回调访问

9. **`main`**
   ```swift
   let app = NSApplication.shared
   let delegate = AppDelegate()
   app.delegate = delegate
   app.setActivationPolicy(.accessory)   // 无 Dock 图标
   app.run()
   ```
   - 也写 `Info.plist` 的 `LSUIElement=true` 双保险

## `Info.plist` 关键字段

```xml
<key>LSUIElement</key><true/>
<key>CFBundleName</key><string>ClipBoard Pro</string>
<key>CFBundleIdentifier</key><string>com.local.clipboard-pro</string>
<key>CFBundleExecutable</key><string>ClipboardManager</string>
<key>NSAppleEventsUsageDescription</key><string>用于模拟粘贴与剪切板访问。</string>
```

## `build.sh` 要点

```bash
#!/bin/bash
set -e
APP="ClipboardManager.app"
swiftc -O \
  -framework Cocoa -framework Carbon -framework ApplicationServices \
  ClipboardManager.swift -o ClipboardManager
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ClipboardManager "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
echo "Built: $APP"
```

## 验证步骤(端到端)

1. **构建**
   ```bash
   cd "/Users/peppa/Library/Application Support/TRAE SOLO CN/ModularData/ai-agent/work-mode-projects/6aa17135f6cf7c229c50d6a7"
   bash build.sh
   ```
2. **首次启动 + 授权**
   - `open ClipboardManager.app` → 菜单栏出现剪贴板图标
   - 系统设置 → 隐私与安全 → 辅助功能 → 勾选 `ClipboardManager`
3. **采集测试**(各复制一次,在面板中应出现三项,类型色条不同)
   - 复制纯文本(记事本中选中文本 Cmd+C)
   - 复制富文本(Safari 网页选段 Cmd+C)
   - 复制文件(Finder 选中文件 Cmd+C)
4. **快捷键**:任意输入框聚焦时按 `Cmd+Shift+V` → 面板弹出 → 上下键选择 → 回车 → 内容应粘贴到当前输入框
5. **搜索**:面板内输入关键词 → 列表实时过滤;清空 → 恢复全部
6. **菜单栏点击**:点状态栏图标 → 面板在图标下方弹出;点空白处或 Esc → 面板关闭
7. **容量上限**:连续复制 110 段不同文本 → 面板显示前 100 条,最早条目被淘汰
8. **降级行为**:关闭辅助功能权限后,点选项 → 仅写入剪切板,Console 出现一次"未授权,跳过 Cmd+V 模拟"日志,用户手动 Cmd+V 仍可粘贴

## 不做的事(明确边界)

- 不持久化:重启后历史清空(符合"不需要多端同步,本机即可"的轻量定位;如后续要持久化,加一个 JSON 文件读写即可,改动局限在 `AppDelegate.dealloc` 与 `applicationDidFinishLaunching` 一处)
- 不支持图片(用户未选)
- 不做云同步、不做账号、不做设置窗口(快捷键、容量暂时硬编码,后续可加)
