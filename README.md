# ClipBoard Pro

> 一个 macOS 菜单栏剪切板管理工具,类似 Paste / iPaste 的开源轻量版。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS%2012%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.1-orange)](https://swift.org)

## 特性

- **菜单栏常驻**:点菜单栏图标或 `⌘⇧V` 唤起,失焦自动隐藏
- **三种内容**:纯文本、富文本(HTML)、文件路径
- **即时搜索**:面板内键入即过滤,大小写不敏感
- **键盘优先**:`↑↓` 切换、`Enter` 粘贴、`Esc` 关闭、`⌘⌫` 删除
- **点击即粘贴**:写入剪切板 + 模拟 `⌘V`,无需手动二次操作
- **本地持久化**:`~/Library/Application Support/ClipboardManager/history.json`,重启后历史仍在
- **LRU 上限**:100 条,相邻重复自动合并
- **右键菜单**:关于、清空历史(二次确认)、退出
- **轻量**:单文件 Swift,无第三方依赖,编译产物 < 200KB

## 截图

> TODO:发布前在 release 中补一张面板截图

## 安装

### 方式一:下载预编译版本(推荐)

到 [Releases](../../releases) 下载 `ClipboardManager.app.zip`,解压后拖入"应用程序"文件夹。

首次启动会弹辅助功能授权窗,到 **系统设置 → 隐私与安全 → 辅助功能** 勾选 `ClipboardManager` 后,`⌘⇧V` 即可使用"点击即粘贴"功能。

### 方式二:自行构建

依赖:macOS 12+,系统自带 `swiftc`(Xcode Command Line Tools 即可,无需安装 Xcode IDE)。

```bash
git clone https://github.com/yourname/ClipboardPro.git
cd ClipboardPro
bash build.sh
open ClipboardManager.app
```

## 使用

| 操作 | 效果 |
|---|---|
| 复制任意内容(`⌘C`) | 自动入历史(相邻重复去重) |
| 左键点菜单栏图标 | 在图标下方弹出下拉面板 |
| 右键点菜单栏图标 | 弹菜单:关于 / 清空历史 / 退出 |
| `⌘⇧V` | 任意 App 中弹面板,目标 App 仍是当前 App |
| 面板内输入关键词 | 实时过滤历史 |
| `↑` / `↓` | 在结果中上下移动选择 |
| `Enter` | 写入剪切板 + 模拟 `⌘V` 粘贴到当前 App |
| 单击条目 | 同上 |
| `⌘⌫` | 删除当前选中项 |
| `Esc` / 点空白处 | 关闭面板 |

历史上限 100 条,超出按 LRU 淘汰。

## 自定义

### 修改快捷键

源码里 [ClipboardManager.swift](ClipboardManager.swift) 的 `registerHotkey()` 方法:

```swift
RegisterEventHotKey(UInt32(9),                          // V 键 keyCode
                   UInt32(cmdKey) | UInt32(shiftKey),  // 修饰键
                   hotkeyId,
                   GetApplicationEventTarget(),
                   0,
                   &ref)
```

- **keyCode 查表**:`A=0, B=11, C=8, D=2, E=14, F=3, G=5, H=4, I=34, J=38, K=40, L=37, M=46, N=45, O=31, P=35, Q=12, R=15, S=1, T=17, U=32, V=9, W=13, X=7, Y=16, Z=6`
- **修饰键**:`cmdKey` / `shiftKey` / `optionKey`(=`1<<11`)/ `controlKey`(=`1<<12`)
- 改完后 `bash build.sh` 重新构建

### 修改历史容量上限

源码里 `AppDelegate` 类:

```swift
private let maxItems = 100
```

改数字重新构建即可。

### 修改持久化路径

源码里 `AppDelegate.storageURL`,默认在 `~/Library/Application Support/ClipboardManager/history.json`。

## 文件结构

```
.
├── ClipboardManager.swift   # 单文件源码,所有逻辑都在这里
├── Info.plist                # .app 元数据(LSUIElement=true 隐藏 Dock)
├── build.sh                  # 一键构建脚本
├── LICENSE                   # MIT 许可证
├── CHANGELOG.md              # 变更记录
└── README.md                 # 你正在看的这个文件
```

构建产物 `ClipboardManager.app` 由 `build.sh` 生成,默认不加入 git。

## 开发

### 构建

```bash
bash build.sh
```

构建脚本会:
1. `swiftc -O` 编译单文件,链接 Cocoa / Carbon / ApplicationServices / CoreGraphics
2. 组装 `ClipboardManager.app/Contents/{MacOS,Info.plist}`
3. `codesign -s -` 自签(本地运行即可)

### 发布给其他用户(可选,需要 Apple Developer 账号)

自签版本只能在本机运行,分发给其他用户会触发 Gatekeeper。要正式发布,需要 Developer ID 签名 + 公证:

```bash
# 设置环境变量(替换为你的 Developer ID 和 Apple ID)
export DEV_ID="Developer ID Application: Your Name (XXXXXXXXXX)"
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="XXXXXXXXXX"
export APP_PASSWORD="app-specific-password-from-apple-id"

# 签名 + 公证 + 装订
codesign --force --sign "$DEV_ID" --timestamp ClipboardManager.app
xcrun notarytool submit ClipboardManager.app.zip \
    --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
    --password "$APP_PASSWORD" --wait
xcrun stapler staple ClipboardManager.app
```

公证步骤约 5-10 分钟,完成后用户即可直接双击运行,无需在"系统设置"里手动放行。

## 贡献

欢迎提 Issue 和 PR。

- 代码风格:跟随现有风格,4 空格缩进,中文注释
- 提交前:`bash build.sh` 通过,无编译错误
- 提交信息:中文 / 英文均可,简洁描述改动
- 大改动请先开 Issue 讨论

## 已知限制

- 启用"聚焦搜索"等同样拦截 `⌘⇧V` 的 App 时可能冲突,改其他组合键即可
- 部分 App(终端、VMware 等)对模拟按键有额外限制,可能粘贴不进去;此时仍可手动 `⌘V`
- 富文本回填使用源 HTML,某些富文本编辑器(如 Word)对 HTML 兼容性可能略有问题,以纯文本为准
- 模拟 `⌘V` 需要辅助功能权限,未授权时降级为仅写入剪切板

## 不做的事

- **不持久化 UUID**:加载历史时 UUID 重新生成,不影响去重(去重基于类型+文本)
- **不做云同步**:仅本机,无账号
- **不做设置界面**:快捷键、容量都是源码硬编码;如果未来需要,可加一个简单 `NSWindow`
- **不支持图片**:仅文本、富文本、文件路径

## License

[MIT License](LICENSE) — 可商用、可修改、可分发,保留版权声明即可。

## 鸣谢

- 灵感来源:[Paste](https://pasteapp.io) / [iPaste](http://pasteapp.io)
- 全局快捷键实现参考 [Carbon Event Manager](https://developer.apple.com/documentation/carbon) 旧 API
- 图标来自 [SF Symbols](https://developer.apple.com/sf-symbols/)

## Changelog

见 [CHANGELOG.md](CHANGELOG.md)。
