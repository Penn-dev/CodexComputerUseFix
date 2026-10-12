# Codex Capture Compat

[简体中文](README.md) | [English](README_en.md)

为 Windows 10 上已确认的 Codex Computer Use 故障提供最小修复。当前方案包含截图 DLL、已有代理传递、原生控制释放，以及按真实截图失败触发的提醒。

[维护核查与实测记录](docs/cu-maintenance-audit.md)记录各项故障的证据和当前验证结果。

## 当前方案

| 项目 | 作用 | 实现位置 |
| --- | --- | --- |
| 截图 DLL | 补齐 Windows 10 缺少的可选边框接口，并处理截图回调阻塞 | `capture-compat/`，DLL 放在实际 helper 旁 |
| 代理传递 | 将机器上已有的代理设置传给官方 CU 子进程 | `browser-proxy/`，固定系统配置和启动脚本 |
| 原生释放 | 操作结束后释放本会话的控制；处理用户按物理 Esc 后的连接清理 | `windows-lifecycle/`，由固定加载器加载 |
| 失败提醒 | 同一会话十分钟内连续两次同类截图错误时弹窗 | `capture-notify/`，直接处理 CU 调用结果 |

固定加载器位于 `native-runtime/`。它使用官方 `NODE_REPL_WORKER_WRAPPER`，保留官方 sandbox 命令、参数、工作目录和输入输出。修复代码放在 `%USERPROFILE%\.codex\plugins\cu-compat`，通过内存加载钩子接入原生客户端，不改写 runtime 的 JavaScript 文件。

加载器随 CU worker 启动，父进程等待对应 worker 退出。没有定时任务、日志轮询或独立长期值守程序。旧代理注入、自动窗口守卫和 `CodexComputerUseFix-Monitor` 已退出当前方案。

## 截图 DLL

已报告的原始故障：[边框接口 #25178](https://github.com/openai/codex/issues/25178)、[截图回调 #35446](https://github.com/openai/codex/issues/35446)。本机处理依据是实际截图失败和修复后的直接结果。

```powershell
.\manage.ps1 status -Json
.\manage.ps1 install
.\manage.ps1 uninstall
```

管理入口从插件启动命令定位配置中的 runtime。多个候选时，使用该会话实际 helper 的路径：

```powershell
.\manage.ps1 status -HelperPath 'C:\actual\runtime\bin\node_modules\@oai\sky\bin\windows\codex-computer-use.exe' -Json
```

示例路径需替换。文件归属由状态命令检查，功能由官方 `sky.get_window_state` 检查。更新后出现新目录或 DLL 缺失不会自动弹窗；先观察真实截图结果。

DLL 保留默认捕获边框，不修改系统 DLL 或官方 helper。安装器保存文件哈希和归属记录，卸载只移除本项目拥有的 DLL。内置浏览器和 Chrome 不使用这项 DLL。

## 代理和原生加载器

使用现有 PowerShell 7 和 Node.js。在官方系统配置 `%ProgramData%\OpenAI\Codex\config.toml` 中安装固定入口：

```powershell
.\browser-proxy\persistent.ps1
.\native-runtime\install.ps1
```

已有本项目代理入口但脚本版本较旧时，使用 `browser-proxy/persistent.ps1 -Action Update`。它保留匹配的旧脚本和归属记录供恢复。

代理启动脚本每次读取桌面端生成的当前 manifest，启动当前官方 CU 程序；协议按字节原样转发。它传递已有 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY`、`NO_PROXY`，并启用 Node 的环境代理。它不修改代理服务和系统代理设置。

原生加载器公开本项目的 `sky.end_turn()`，注册匹配会话和回合的结束清理。正常清理先发送 helper 原有的 `end_turn`，再关闭本客户端的原生连接。其他会话的连接保留；新回合自动建立新客户端。用户按物理 Esc 后，清理关闭当前连接，不重新发起 helper 控制请求。

安装后完全退出并重开 Codex，在官方 `node_repl` 中检查：

```javascript
var { sky } = await import('@oai/sky');
await sky.compat_status();
// captureReminder: 'on-result', polling: false, nativeReleaseAvailable: true
// 完成本轮原生动作后：
await sky.end_turn();
```

旧源码补丁的迁移卸载入口保留在 `windows-lifecycle/install.ps1 -Action Uninstall -ClientPath <原客户端路径>`；它校验归属后恢复原文件。当前安装使用固定加载器。

卸载顺序：

```powershell
.\native-runtime\install.ps1 -Action Uninstall
.\browser-proxy\persistent.ps1 -Action Uninstall
```

安装记录和备份位于系统配置旁。卸载保留其他配置。

## 无轮询提醒

提醒在原生截图调用返回时检查结果。仅识别边框接口失败、`FrameArrived timed out` 和 `window capture timed out`。同一会话十分钟内连续两次同类错误才弹窗；成功截图或其他错误会清除连续失败状态。同一次故障不重复提醒，恢复后再次失败可重新提醒。

状态只存在当前 CU 进程内，不保存截图、页面内容或日志读取位置。沙箱中的 CU worker 通过现有标准错误通道发出标记信号，启动器保留原始字节并调用 Windows 自带 `msg.exe` 显示弹窗，两分钟后自动关闭。无法发出信号时在工具结果中报告；桌面发送错误写入运行日志。没有额外的监听端口、通知文件或后台程序。

版本、目录、文件哈希、补丁缺失、浏览器网络失败和 Issue 状态变化不触发截图失效提醒。

## 构建和验证

```powershell
.\capture-compat\build.ps1
.\capture-compat\tests\install_tests.ps1
.\capture-compat\tests\manage_tests.ps1
node --test windows-lifecycle/tests.mjs capture-notify/tests.mjs native-runtime/tests.mjs
.\native-runtime\install-tests.ps1
.\browser-proxy\persistent-tests.ps1 -NodePath (Get-Command node.exe).Source
.\capture-compat\validate.ps1
```

DLL 构建需要 MSVC x64 C++、MASM 和 Windows SDK。设置 `CU_TEST_MODULES` 为实际 runtime 的 `bin/node_modules` 后，原生测试还会验证当前官方客户端的内存加载。

同时设置 `CU_TEST_CLI` 为当前 Codex CLI 执行文件，可验证真实官方入口在桌面端收窄后的插件可信目录中加载本机已安装的修复。

实机验收包括：官方 CU 截图、正常释放、用户按物理 Esc，以及实际桌面提醒。结果记录在维护核查文档。

## 文档

原截图兼容实现来自[上游项目](https://github.com/MagicalAstrogy/CodexComputerUseFix)。

- [构建与使用指南](capture-compat/README.md)
- [Windows 原生调用指南](docs/windows-computer-use.md)
- [实现说明](capture-compat/docs/implementation.md)
- [验证与排错](capture-compat/docs/validation.md)
- [CI 与 Release](capture-compat/docs/ci.md)
- [许可证](LICENSE)
