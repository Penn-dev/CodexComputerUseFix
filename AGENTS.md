# Codex Computer Use 兼容项目

## 接手顺序

1. 先读 `README.md` 了解用途与操作入口；用 `git status --short --branch` 确认当前分支和未提交改动。本地分支可能停留在已合并 PR 的旧提交，涉及远端状态时先刷新并核对，勿把本地 `origin/main` 当作实时信息。
2. 排查本机 CU 时，先运行 `./manage.ps1 status -SkipIssueCheck -Json`；需要公开 Issue 状态时再运行不带 `-SkipIssueCheck` 的检查。监控基线和提醒日志在 `%LOCALAPPDATA%\CodexComputerUseFix`，基线只保存最新状态，提醒本身不说明功能失效。
3. 根据状态定位到**当前** runtime，再检查对应补丁及实际调用路径。状态为 `installed-and-owned` 只证明文件归属，仍需用真实 CU 调用验证功能。修复后分别验证浏览器与 Windows 原生应用，并记录未验证的场景。

## 组件与历史决策

- `capture-compat/`：Windows 10 x64 的 `version.dll`，处理截图接口和回调；不负责工具路由。
- `proxy-env/`：在 `cua-repl` 动态导入前初始化 Node 代理；曾修复 `nodeRepl.fetch request failed`。默认代理见 `README.md`，当前安装值以状态输出为准。
- `window-target-guard/`：旧版自动目标窗口守卫。它会使部分模态控件编号失效；统一 `manage.ps1 install` 会卸载本项目拥有的守卫。`targetWindowGuard.state = not-installed` 是预期状态。
- `manage.ps1`：统一状态、安装、卸载和计划监控入口。监控仅提示状态变化，不会自动修复；不要仅凭提醒重装补丁。

截至 2026-09-28 的实测：浏览器入口可用；原生应用须在切换目标时显式激活窗口，再读取截图。画图等应用的部分控件编号点击仍可能报缓存缺失，最新截图的窗口相对坐标或快捷键可作为替代。这里记录的是已知限制，不代表未来运行时的状态。

## 路由与验证

先核对当前统一插件暴露的 surfaces。浏览器（Codex 内置浏览器、Chrome）使用浏览器入口；Windows 原生应用若仍无 `computer` surface，按已安装的 `computer-use` Skill 使用 `node_repl + @oai/sky`。本机若有 `$env:USERPROFILE\.codex\docs\runbooks\windows-computer-use.md`，控制原生应用前完整读取。切换后台窗口时，从 `sky.list_windows()` 选准确窗口，调用 `sky.activate_window`，稍候再读取状态。控件编号报缓存错误时，刷新状态并改用对应截图的坐标或快捷键，核对结果。

修改统一管理流程后运行 `capture-compat/tests/manage_tests.ps1`；修改对应安装器后运行其目录下的 `tests/install_tests.ps1`。涉及 DLL 时按 `capture-compat/README.md` 构建、验证，并在可用的交互桌面做真实截图检查。自动测试、补丁状态和真实 CU 验证分别报告。
