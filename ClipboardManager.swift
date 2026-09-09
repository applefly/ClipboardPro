// ClipboardManager.swift
// macOS 菜单栏剪切板管理工具(单文件版本)
// 构建:见 build.sh

import Cocoa
import Carbon
import ApplicationServices

// ============================================================================
// MARK: - 数据模型
// ============================================================================

enum ClipboardKind {
    case text
    case richText
    case filePaths

    var color: NSColor {
        switch self {
        case .text:        return .systemGray
        case .richText:    return .systemBlue
        case .filePaths:   return .systemOrange
        }
    }

    var icon: String {
        switch self {
        case .text:        return "text.alignleft"
        case .richText:    return "doc.richtext"
        case .filePaths:   return "doc.on.doc"
        }
    }

    var persistKey: String {
        switch self {
        case .text:        return "text"
        case .richText:    return "richText"
        case .filePaths:   return "filePaths"
        }
    }

    static func from(key: String) -> ClipboardKind {
        switch key {
        case "richText":  return .richText
        case "filePaths": return .filePaths
        default:           return .text
        }
    }
}

struct ClipboardItem {
    let id = UUID()
    let kind: ClipboardKind
    let plainText: String
    let htmlString: String?
    let fileURLs: [URL]?
    let copiedAt: Date

    init(kind: ClipboardKind,
         plainText: String,
         htmlString: String?,
         fileURLs: [URL]?,
         copiedAt: Date = Date()) {
        self.kind = kind
        self.plainText = plainText
        self.htmlString = htmlString
        self.fileURLs = fileURLs
        self.copiedAt = copiedAt
    }

    var displayTitle: String {
        switch kind {
        case .filePaths:
            guard let urls = fileURLs, !urls.isEmpty else { return plainText }
            if urls.count == 1 { return urls[0].lastPathComponent }
            let preview = urls.prefix(3).map { $0.lastPathComponent }.joined(separator: ", ")
            return "\(urls.count) 文件: " + preview + (urls.count > 3 ? "…" : "")
        default:
            let trimmed = plainText.replacingOccurrences(of: "\n", with: " ")
            return trimmed.count > 80 ? String(trimmed.prefix(80)) + "…" : trimmed
        }
    }

    func relativeTime() -> String {
        let elapsed = Int(Date().timeIntervalSince(copiedAt))
        if elapsed < 5     { return "刚刚" }
        if elapsed < 60    { return "\(elapsed)秒前" }
        if elapsed < 3600 { return "\(elapsed / 60)分钟前" }
        return "\(elapsed / 3600)小时前"
    }
}

// ============================================================================
// MARK: - 剪切板监听
// ============================================================================

final class PasteboardWatcher {
    private var timer: Timer?
    private var lastChangeCount: Int
    private let onCapture: (ClipboardItem) -> Void
    private var isSuppressing = false  // 屏蔽自己回填产生的 changeCount

    init(onCapture: @escaping (ClipboardItem) -> Void) {
        self.onCapture = onCapture
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func suppressNext() { isSuppressing = true }

    private func tick() {
        let pb = NSPasteboard.general
        let current = pb.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        if isSuppressing {
            isSuppressing = false
            return
        }
        if let item = capture(pb) {
            onCapture(item)
        }
    }

    private func capture(_ pb: NSPasteboard) -> ClipboardItem? {
        // 1) 文件优先
        if let anyURLs = pb.readObjects(forClasses: [NSURL.self], options: nil),
           let urls = anyURLs as? [URL] {
            let fileURLs = urls.filter { $0.isFileURL }
            if !fileURLs.isEmpty {
                let names = fileURLs.map { $0.lastPathComponent }
                return ClipboardItem(kind: .filePaths,
                                     plainText: names.joined(separator: ", "),
                                     htmlString: nil,
                                     fileURLs: fileURLs)
            }
        }
        // 2) 富文本(同时检测 html)
        var htmlString: String? = nil
        if let data = pb.data(forType: .html),
           let s = String(data: data, encoding: .utf8),
           !s.isEmpty {
            htmlString = s
        }
        // 3) 纯文本兜底
        if let text = pb.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let kind: ClipboardKind = (htmlString != nil) ? .richText : .text
            return ClipboardItem(kind: kind,
                                  plainText: text,
                                  htmlString: htmlString,
                                  fileURLs: nil)
        }
        return nil
    }
}

// ============================================================================
// MARK: - 粘贴模拟
// ============================================================================

enum PasteSimulator {
    static func paste(_ item: ClipboardItem, activate: NSRunningApplication?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.plainText, forType: .string)
        case .richText:
            pb.setString(item.plainText, forType: .string)
            if let html = item.htmlString {
                pb.setString(html, forType: .html)
            }
        case .filePaths:
            if let urls = item.fileURLs {
                let writing: [NSPasteboardWriting] = urls.map { NSURL(fileURLWithPath: $0.path) as NSPasteboardWriting }
                pb.writeObjects(writing)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            if let app = activate, !app.isTerminated {
                app.activate(options: [])
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                simulateCmdV()
            }
        }
    }

    static func simulateCmdV() {
        guard AXIsProcessTrusted() else {
            NSLog("[ClipboardManager] 辅助功能未授权,跳过 Cmd+V 模拟。请到 系统设置→隐私与安全→辅助功能 中授权。")
            return
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let virtualKey: CGKeyCode = 9  // V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

// ============================================================================
// MARK: - AppDelegate
// ============================================================================

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    private var statusItem: NSStatusItem!
    private var watcher: PasteboardWatcher!
    private var panelController: HistoryPanelController!
    private var history: [ClipboardItem] = []
    private let maxItems = 100
    private var hotkeyRef: EventHotKeyRef?
    private var frontmostApp: NSRunningApplication?
    private var saveWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        setupStatusItem()

        panelController = HistoryPanelController()
        panelController.getItems = { [weak self] in self?.history ?? [] }
        panelController.onSelect = { [weak self] item in self?.handleSelect(item) }
        panelController.onDelete = { [weak self] item in self?.handleDelete(item) }

        loadHistory()  // 先恢复历史,再启动监听

        watcher = PasteboardWatcher { [weak self] item in
            self?.addItem(item)
        }
        watcher.start()

        registerHotkey()
        promptAccessibilityIfNeeded()
    }

    // MARK: 状态栏图标
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                   accessibilityDescription: "Clipboard Pro")
            // 让按钮同时响应左键和右键,左键弹面板,右键弹菜单
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        // 判断左右键:NSStatusBar button 的 currentEvent 是触发本次点击的事件
        let isRightClick: Bool
        if let event = NSApp.currentEvent {
            isRightClick = (event.type == .rightMouseUp)
                || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        } else {
            isRightClick = false
        }
        if isRightClick {
            showStatusMenu()
        } else {
            frontmostApp = NSWorkspace.shared.frontmostApplication
            togglePanel()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()

        let aboutItem = NSMenuItem(title: "关于 ClipBoard Pro",
                                    action: #selector(showAbout),
                                    keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: "清空历史",
                                    action: #selector(clearHistory),
                                    keyEquivalent: "")
        clearItem.target = self
        // 危险操作用 ⌫ 时需修饰键,纯 ⌫ 作为 keyEquivalent 不直观
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 ClipBoard Pro",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
        // 用 menu 自动弹出后会复位 statusItem.menu,否则下次左键会变成弹菜单
        // (设 menu 之后点击行为会被菜单接管,这里通过弹完菜单后清空 menu 恢复)
        if let button = statusItem.button {
            button.performClick(nil)
            // performClick 触发菜单弹出后,在下一个 runloop 清空 menu,恢复左键弹面板行为
            DispatchQueue.main.async { [weak self] in
                self?.statusItem.menu = nil
            }
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSImage(systemSymbolName: "doc.on.clipboard",
                             accessibilityDescription: nil)
        alert.messageText = "ClipBoard Pro"
        alert.informativeText = """
            一个 macOS 菜单栏剪切板管理工具

            版本:1.0.0
            许可证:MIT
            源码:https://github.com/yourname/ClipboardPro

            全局快捷键:⌘⇧V 唤起面板
            历史上限:100 条
            """
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "确认清空全部历史?"
        alert.informativeText = "此操作不可撤销,清空后历史不可恢复(重启也不会回来)。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            history.removeAll()
            panelController.refresh()
            schedulePersist()
        }
    }

    // MARK: 全局快捷键
    func togglePanelFromHotkey() {
        frontmostApp = NSWorkspace.shared.frontmostApplication
        togglePanel()
    }

    private func togglePanel() {
        if panelController.isVisible {
            panelController.hide()
        } else {
            panelController.show(attachedTo: statusItem)
        }
    }

    private func registerHotkey() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: @convention(c) (EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus = { _, _, userData in
            guard let userData = userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                delegate.togglePanelFromHotkey()
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(),
                            callback,
                            1,
                            &eventSpec,
                            selfPtr,
                            nil)

        let sig: OSType = 0x4342504D  // 'CBPM'
        let hotkeyId = EventHotKeyID(signature: sig, id: 1)
        var ref: EventHotKeyRef? = nil
        // Swift 桥接顺序:keyCode, modifiers, hotKeyId, target, options, outRef
        RegisterEventHotKey(UInt32(9),                          // V 键
                            UInt32(cmdKey) | UInt32(shiftKey),
                            hotkeyId,
                            GetApplicationEventTarget(),
                            0,
                            &ref)
        self.hotkeyRef = ref
    }

    private func promptAccessibilityIfNeeded() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: 历史管理
    private func addItem(_ item: ClipboardItem) {
        // 去重:与最近一条内容相同(类型+文本)则把旧条移除后再插入
        if let first = history.first,
           first.kind == item.kind,
           first.plainText == item.plainText {
            history.removeFirst()
        }
        history.insert(item, at: 0)
        if history.count > maxItems {
            history = Array(history.prefix(maxItems))
        }
        panelController.refresh()
        schedulePersist()
    }

    private func handleSelect(_ item: ClipboardItem) {
        panelController.hide()
        watcher.suppressNext()  // 屏蔽自己回填的 changeCount,避免历史被自己刷掉
        PasteSimulator.paste(item, activate: frontmostApp)
    }

    private func handleDelete(_ item: ClipboardItem) {
        history.removeAll { $0.id == item.id }
        panelController.refresh()
        schedulePersist()
    }

    // MARK: 持久化
    private static var storageURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ClipboardManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    // 防抖 0.5s 写盘,避免连续复制时频繁 IO
    private func schedulePersist() {
        saveWorkItem?.cancel()
        let snapshot = history  // 捕获当前快照
        let work = DispatchWorkItem {
            Self.persist(snapshot)
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private static func persist(_ items: [ClipboardItem]) {
        struct PersistedItem: Codable {
            let kind: String
            let plainText: String
            let htmlString: String?
            let filePaths: [String]?
            let copiedAt: Date
        }
        let arr = items.map {
            PersistedItem(kind: $0.kind.persistKey,
                          plainText: $0.plainText,
                          htmlString: $0.htmlString,
                          filePaths: $0.fileURLs?.map { $0.path },
                          copiedAt: $0.copiedAt)
        }
        guard let data = try? JSONEncoder().encode(arr) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func loadHistory() {
        struct PersistedItem: Codable {
            let kind: String
            let plainText: String
            let htmlString: String?
            let filePaths: [String]?
            let copiedAt: Date
        }
        guard let data = try? Data(contentsOf: Self.storageURL),
              let arr = try? JSONDecoder().decode([PersistedItem].self, from: data) else { return }
        history = arr.compactMap { p in
            let kind = ClipboardKind.from(key: p.kind)
            let urls = p.filePaths?.map { URL(fileURLWithPath: $0) }
            return ClipboardItem(kind: kind,
                                 plainText: p.plainText,
                                 htmlString: p.htmlString,
                                 fileURLs: urls,
                                 copiedAt: p.copiedAt)
        }
        // 加载后仍要保证不超过上限
        if history.count > maxItems {
            history = Array(history.prefix(maxItems))
        }
    }
}

// ============================================================================
// MARK: - 面板控制器
// ============================================================================

final class HistoryPanelController {
    private let panel: NSPanel
    private let viewController: HistoryViewController
    private var resignKeyObserver: NSObjectProtocol?
    private var keyMonitor: Any?

    var getItems: () -> [ClipboardItem] = { [] }
    var onSelect: (ClipboardItem) -> Void = { _ in }
    var onDelete: (ClipboardItem) -> Void = { _ in }

    var isVisible: Bool { panel.isVisible }

    init() {
        viewController = HistoryViewController()
        // 用 .titled + .fullSizeContentView 实现视觉无边框但能正常成为 key window
        // (纯 .borderless + .nonactivatingPanel 在 accessory app 下收不到键盘事件)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
                        styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.contentViewController = viewController
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true
        // 隐藏标题栏的标准三个按钮(关闭/缩放/最小化)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main) { [weak self] _ in
            self?.hide()
        }
    }

    deinit {
        if let obs = resignKeyObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func show(attachedTo statusItem: NSStatusItem) {
        let items = getItems()
        viewController.configure(items: items,
                                 onSelect: { [weak self] item in self?.onSelect(item) },
                                 onDelete: { [weak self] item in self?.onDelete(item) })

        guard let button = statusItem.button,
              let screen = button.window?.screen ?? NSScreen.main else { return }
        let buttonFrame = button.window?.frame ?? .zero
        let rowH: CGFloat = 36
        let rowsToShow = min(max(items.count, 1), 12)
        let panelHeight = min(420, max(220, CGFloat(rowsToShow) * rowH + 56))
        let panelSize = NSSize(width: 380, height: panelHeight)
        panel.setContentSize(panelSize)

        var panelFrame = NSRect(origin: NSPoint(x: buttonFrame.midX - panelSize.width / 2,
                                                y: buttonFrame.minY - panelSize.height - 4),
                               size: panelSize)
        if panelFrame.maxX > screen.visibleFrame.maxX - 4 {
            panelFrame.origin.x = screen.visibleFrame.maxX - panelSize.width - 4
        }
        if panelFrame.origin.x < screen.visibleFrame.minX + 4 {
            panelFrame.origin.x = screen.visibleFrame.minX + 4
        }
        panel.setFrame(panelFrame, display: true)

        // 显式激活本 app,让面板成为 key window 后能收到键盘事件
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(viewController.searchField)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
        viewController.clearSearch()
    }

    // 本地 + 全局双 monitor,确保面板可见时一定能截获 Esc/方向键/回车
    // 本地 monitor 在面板成为 key window 时生效,可消费事件(return nil)
    // 全局 monitor 作为兜底,在其他 app 仍持焦时也能响应(无法消费,但能先执行操作)
    private func installKeyMonitor() {
        removeKeyMonitor()
        let handler: (NSEvent) -> NSEvent? = { [weak self] event in
            guard let self = self, self.panel.isVisible else { return event }

            let keyCode = event.keyCode
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // ESC
            if keyCode == 53 { self.hide(); return nil }
            // 回车
            if keyCode == 36 || keyCode == 76 {
                self.viewController.confirmSelection()
                return nil
            }
            // ↑
            if keyCode == 126 { self.viewController.moveSelection(-1); return nil }
            // ↓
            if keyCode == 125 { self.viewController.moveSelection(1); return nil }
            // Cmd+Backspace 删除当前项
            if keyCode == 51 && mods.contains(.command) {
                self.viewController.deleteSelection()
                return nil
            }
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    func refresh() {
        if panel.isVisible {
            let items = getItems()
            viewController.configure(items: items,
                                     onSelect: { [weak self] item in self?.onSelect(item) },
                                     onDelete: { [weak self] item in self?.onDelete(item) })
        }
    }
}

// ============================================================================
// MARK: - 面板内容视图
// ============================================================================

final class HistoryViewController: NSViewController {
    let searchField: NSSearchField
    private let tableView: NSTableView
    private var scrollView: NSScrollView!
    private var items: [ClipboardItem] = []
    private var filtered: [ClipboardItem] = []
    private var onSelect: (ClipboardItem) -> Void = { _ in }
    private var onDelete: (ClipboardItem) -> Void = { _ in }

    private let rowHeight: CGFloat = 36
    private let cellId = NSUserInterfaceItemIdentifier("clipCell")

    init() {
        searchField = NSSearchField()
        tableView = NSTableView()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        // 用 NSVisualEffectView 做毛玻璃容器
        let container = NSVisualEffectView()
        container.material = .popover
        container.blendingMode = .behindWindow
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true

        searchField.placeholderString = "搜索历史..."
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false

        tableView.headerView = nil
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.doubleAction = #selector(rowDoubleClicked)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        // 隐藏滚动条但仍可滚
        scrollView.autohidesScrollers = true

        container.addSubview(searchField)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])

        tableView.dataSource = self
        tableView.delegate = self
        searchField.delegate = self

        self.view = container
    }

    func configure(items: [ClipboardItem],
                   onSelect: @escaping (ClipboardItem) -> Void,
                   onDelete: @escaping (ClipboardItem) -> Void) {
        self.items = items
        self.onSelect = onSelect
        self.onDelete = onDelete
        applyFilter()
    }

    func clearSearch() {
        searchField.stringValue = ""
        applyFilter()
    }

    private func applyFilter() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            filtered = items
        } else {
            filtered = items.filter { item in
                if item.displayTitle.lowercased().contains(q) { return true }
                if let urls = item.fileURLs,
                   urls.contains(where: { $0.path.lowercased().contains(q) }) { return true }
                return false
            }
        }
        tableView.reloadData()
        if !filtered.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
    }

    func moveSelection(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        let cur = tableView.selectedRow
        var next = cur + delta
        if next < 0 { next = 0 }
        if next >= filtered.count { next = filtered.count - 1 }
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    func confirmSelection() {
        let row = tableView.selectedRow
        if row >= 0 && row < filtered.count {
            onSelect(filtered[row])
        } else if let first = filtered.first {
            onSelect(first)
        }
    }

    func deleteSelection() {
        let row = tableView.selectedRow
        guard row >= 0, row < filtered.count else { return }
        let item = filtered[row]
        onDelete(item)
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < filtered.count else { return }
        onSelect(filtered[row])
    }

    @objc private func rowDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < filtered.count else { return }
        onSelect(filtered[row])
    }
}

extension HistoryViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filtered.count else { return nil }
        let item = filtered[row]
        let view = tableView.makeView(withIdentifier: cellId, owner: nil) as? ClipRowView
            ?? ClipRowView()
        view.identifier = cellId
        view.configure(item: item)
        return view
    }
}

extension HistoryViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }
}

// ============================================================================
// MARK: - 列表行视图
// ============================================================================

final class ClipRowView: NSTableCellView {
    private let colorBar = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        colorBar.wantsLayer = true
        colorBar.translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageAlignment = .alignCenter
        iconView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isSelectable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = .systemFont(ofSize: 10)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.isSelectable = false
        timeLabel.isBezeled = false
        timeLabel.drawsBackground = false
        timeLabel.maximumNumberOfLines = 1
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(colorBar)
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(timeLabel)

        NSLayoutConstraint.activate([
            colorBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            colorBar.topAnchor.constraint(equalTo: topAnchor),
            colorBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            colorBar.widthAnchor.constraint(equalToConstant: 4),

            iconView.leadingAnchor.constraint(equalTo: colorBar.trailingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),

            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 80),
        ])
    }

    func configure(item: ClipboardItem) {
        colorBar.layer?.backgroundColor = item.kind.color.cgColor
        titleLabel.stringValue = item.displayTitle
        timeLabel.stringValue = item.relativeTime()
        iconView.image = NSImage(systemSymbolName: item.kind.icon, accessibilityDescription: nil)
    }
}

// ============================================================================
// MARK: - 入口
// ============================================================================

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
