import Cocoa

// MARK: - 配置
/// 监控的 agent:pathFragment 是 ps -axo comm 中的路径特征(子串匹配),name 是显示名
/// 默认列表覆盖常见 agent;本机特定安装可写配置文件覆盖:
/// ~/.config/agentawake/agents.json  →  [{"path": "...", "name": "..."}]
struct Agent: Codable {
    let path: String
    let name: String
}

let defaultAgentList: [Agent] = [
    Agent(path: "/Applications/Command Code.app", name: "Command Code"),
    Agent(path: "/Applications/Antigravity.app", name: "Antigravity"),
    Agent(path: "/Applications/ChatGPT.app/Contents/Resources/codex", name: "Codex"),
    Agent(path: "/Applications/Claude.app", name: "Claude"),
    Agent(path: "opencode", name: "OpenCode"),
]

/// 读配置文件覆盖默认列表;文件不存在或解析失败时用默认
func loadAgentList() -> [Agent] {
    let configPath = NSHomeDirectory() + "/.config/agentawake/agents.json"
    guard let data = FileManager.default.contents(atPath: configPath),
          let agents = try? JSONDecoder().decode([Agent].self, from: data),
          !agents.isEmpty else {
        return defaultAgentList
    }
    return agents
}

let agentList = loadAgentList()

let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/com.caffeinate-agents.plist"
let logPath = "/tmp/caffeinate-agents.log"

// MARK: - 系统查询

/// launchd 是否加载了防休眠 watcher
func watcherEnabled() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = ["list"]
    p.standardOutput = Pipe()
    p.standardError = Pipe()
    try? p.run()
    let data = (p.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8)?.contains("caffeinate-agents") ?? false
}

/// 某个 agent(路径特征)是否在运行 — ps -axo comm 子串匹配
/// 比 pgrep -x 可靠:支持带空格进程名(Command Code),能区分专用 node(WorkBuddy)
func processExists(_ pathFragment: String) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-axo", "comm"]
    p.standardOutput = Pipe()
    p.standardError = Pipe()
    try? p.run()
    let data = (p.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
    p.waitUntilExit()
    let out = String(data: data, encoding: .utf8) ?? ""
    return out.contains(pathFragment)
}

func toggleWatcher(enable: Bool) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = enable ? ["load", plistPath] : ["unload", plistPath]
    p.standardOutput = Pipe()
    p.standardError = Pipe()
    try? p.run()
    p.waitUntilExit()
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // 无 Dock 图标

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = NSFont.systemFont(ofSize: 13)
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()

        // 每 5 秒刷新菜单栏图标
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshIcon()
        }
    }

    /// 菜单栏图标：☕ 保持唤醒（棕）/ 🌙 空闲（灰）
    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        if watcherEnabled() && processExists("caffeinate") {
            button.title = "☕"
            button.toolTip = "Agent 防休眠中"
        } else {
            button.title = "🌙"
            button.toolTip = "空闲"
        }
    }

    // MARK: - NSMenuDelegate：每次打开菜单时重建，保证实时状态

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        menu.autoenablesItems = false

        // 标题
        let titleItem = NSMenuItem(title: "Agent 防休眠", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let enabled = watcherEnabled()
        let active = enabled && processExists("caffeinate")

        // 状态行
        let statusText: String
        if active {
            statusText = "● 正在保持唤醒"
        } else if enabled {
            statusText = "○ 空闲 — 无 Agent 运行"
        } else {
            statusText = "○ 已停用"
        }
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        if active { statusItem.attributedTitle = greenText(statusText) }
        menu.addItem(statusItem)

        // Agent 状态列表
        menu.addItem(.separator())
        let header = NSMenuItem(title: "监控列表:", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for agent in agentList {
            let running = processExists(agent.path)
            let title = running ? "✓ \(agent.name) · 运行中" : "○ \(agent.name)"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            if running { item.attributedTitle = greenText(title) }
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // 开关
        if enabled {
            let disable = NSMenuItem(title: "停用防休眠", action: #selector(disableTapped), keyEquivalent: "")
            disable.target = self
            menu.addItem(disable)
        } else {
            let enable = NSMenuItem(title: "启用防休眠", action: #selector(enableTapped), keyEquivalent: "")
            enable.target = self
            menu.addItem(enable)
        }

        // 查看日志
        let logItem = NSMenuItem(title: "查看日志", action: #selector(viewLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        // 退出
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func greenText(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.foregroundColor: NSColor.systemGreen])
    }

    @objc private func disableTapped() {
        toggleWatcher(enable: false)
        refreshIcon()
        rebuildMenu()
    }

    @objc private func enableTapped() {
        toggleWatcher(enable: true)
        refreshIcon()
        rebuildMenu()
    }

    @objc private func viewLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }
}

// MARK: - 入口

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
