# awakeforagent — 菜单栏 Agent 防休眠工具

让 Mac 在 AI agent 运行时保持唤醒，agent 停止后自动恢复正常休眠。菜单栏常驻显示状态，一眼看清当前哪个 agent 在跑、防休眠是否生效。

纯 Swift 菜单栏 App + bash 防休眠引擎，无第三方依赖。

## 特性

- 菜单栏常驻：☕ 防休眠中 / 🌙 空闲，每 5 秒刷新
- 中文菜单：状态行、监控列表（✓ 运行中 / ○ 未运行）、停用/启用防休眠、查看日志、退出
- 菜单打开时实时重建（NSMenuDelegate），状态不过期
- 无 Dock 图标（LSUIElement），只占状态栏
- 引擎自愈：每次防休眠只持续 35 秒并循环刷新，引擎崩溃最多 35 秒后自动恢复休眠
- **合盖防休眠**：agent 运行时 `pmset disablesleep 1`（需一次性 sudoers 授权），合盖也不休眠
- 省电：电池 ≤10% 时不再防休眠

## 结构

```
Sources/AgentAwake/main.swift   # 菜单栏 App 源码（Swift）
LICENSE                         # MIT
```

## 编译与安装

要求 macOS + Xcode Command Line Tools（`swiftc`）。

```bash
swiftc -O -o build/AgentAwake Sources/AgentAwake/main.swift
mkdir -p build/AgentAwake.app/Contents/MacOS
cp build/AgentAwake build/AgentAwake.app/Contents/MacOS/AgentAwake
# Info.plist（LSUIElement=true 无 Dock 图标）
cp -R build/AgentAwake.app ~/Applications/
```

开机自启（可选）：注册 LaunchAgent 后加载。

## 配置：监控哪些 agent

默认列表覆盖常见 agent：Command Code / Antigravity / Codex / Claude / OpenCode。
本机特定安装可写配置文件覆盖，**App 和防休眠引擎都读同一份**：

```json
// ~/.config/agentawake/agents.json
[
  {"path": "/Applications/Command Code.app", "name": "Command Code"},
  {"path": "opencode", "name": "OpenCode"}
]
```

- `path`：`ps -axo comm` 输出中的路径特征（子串匹配）
- `name`：菜单栏显示名

> **为什么用路径特征而非 pgrep -x**：`pgrep -x` 对带空格的进程名（如
> `Command Code`）匹配失败；且裸 `node` 会误伤任意 node 服务。用
> `ps -axo comm` 路径子串匹配两者都解决。

## 防休眠引擎

App 控制的是 `~/.caffeinate-agents/caffeinate-agents.sh`（launchd 后台循环：
每 20 秒检测 agent 进程，有则 `caffeinate -i -t 35` 防休眠并循环刷新，无则释放；
电池 ≤10% 让位）。「停用/启用」= 该 LaunchAgent 的 load/unload。

**合盖防休眠**：引擎在 agent 运行时还会执行 `sudo -n /usr/bin/pmset -a disablesleep 1`
（阻止合盖休眠），agent 停止时恢复 0。需要一次性配置 sudoers 免密（只放行这两条命令）：

```bash
echo "$(whoami) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" | sudo tee /etc/sudoers.d/agentawake >/dev/null && sudo chmod 440 /etc/sudoers.d/agentawake && sudo visudo -cf /etc/sudoers.d/agentawake
```

引擎基于 <https://github.com/rileycx/caffeinate-agents>（MIT）扩展而来。

## 已知编译坑

若 `swiftc` 报 `redefinition of module 'SwiftBridging'`，是 CLT 旧版
`/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap` 与新版
`bridging.modulemap` 重复定义，删除旧文件后重试。

## License

MIT
