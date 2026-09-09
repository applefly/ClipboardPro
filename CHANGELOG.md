# Changelog

本项目所有重要变更记录于此文件。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/),遵循 [SemVer](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [1.0.0] - 2026-09-09

### Added
- 菜单栏常驻图标(`NSStatusItem` + SF Symbol `doc.on.clipboard`)
- 全局快捷键 `⌘⇧V` 唤起下拉面板(Carbon `RegisterEventHotKey`)
- 剪切板监听(`NSPasteboard.changeCount` 轮询),支持纯文本 / 富文本(HTML) / 文件路径三类内容
- 带毛玻璃的下拉面板(`NSPanel` + `NSVisualEffectView(.popover)`),在状态栏图标正下方弹出
- 实时搜索过滤(`NSSearchField`,子串匹配大小写不敏感)
- 列表行:左侧类型色条(灰=文本 / 蓝=富文本 / 橙=文件),中部截断标题,右侧相对时间
- 键盘操作:面板内 `↑↓` 切换、`Enter` 确认、`Esc` 关闭、`⌘⌫` 删除当前项
- 点击即粘贴:写入 `NSPasteboard` + `CGEvent` 模拟 `⌘V`,自动激活原前 App
- 本地 JSON 持久化:`~/Library/Application Support/ClipboardManager/history.json`,防抖 0.5s 写盘,启动时恢复
- 历史上限 100 条 LRU 淘汰,相邻重复内容自动去重
- 状态栏右键菜单:关于 / 清空历史(带二次确认)/ 退出
- 辅助功能未授权降级:仅写入剪切板,Console 提示

### Technical
- 单文件 Swift 源码,`swiftc -O` 编译,无需 Xcode 工程
- 链接 Cocoa / Carbon / ApplicationServices / CoreGraphics
- `LSUIElement=true` 纯菜单栏运行,无 Dock 图标
- 自签 `codesign -s -` 即可运行;分发给其他用户需 Developer ID 签名 + 公证
- MIT 许可证,允许商用、修改、分发
