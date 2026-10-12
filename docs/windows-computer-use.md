# Windows 原生 Computer Use

仅在查看或操作 Windows 原生应用时读取本文。Chrome、Edge 和 Codex 内置浏览器使用当前官方浏览器入口。

## 当前路由

- Windows 原生应用使用已安装 `computer-use` Skill 所述的 `node_repl + @oai/sky`。工具未直接显示时，在延迟工具列表中查找 `mcp__node_repl__js`。
- 当前 `mcp__cua_repl` 是浏览器入口。如果它的文档显示 native APIs disabled，不用它控制 Windows 原生应用。
- 后续官方入口若同时提供 Windows 原生能力，核对安装版本的文档和实际调用后采用该入口。

## 调用顺序

1. 完整读取已安装的 computer-use Skill、guidance、API 和 confirmations；先完成日志检查和耗时终端准备。
2. 首次只读枚举应用或窗口。从返回对象中选取唯一目标；预检失败时不点击或输入。
3. 开始占用窗口前告知用户；控制期间不穿插长时间终端任务。
4. 每次操作使用刚观察到的状态。动作后刷新，检查实际结果。切换后台目标时显式激活一次；模态窗口出现后保留刚返回的窗口和状态，避免反复重新绑定。
5. 结束本轮 UI 动作后关闭自己创建的测试窗口。已安装本项目生命周期修复时，执行 `await sky.end_turn()`，再重置脚本。该方法由本项目公开原有 helper 清理请求，尚不是官方 API；调用前检查 `typeof sky.end_turn === 'function'`。
6. 生命周期修复同时按会话和回合登记结束回调。清理先发送官方 `end_turn`，再关闭本客户端的原生连接；其他会话的连接保留。显式释放后同一回合的再次输入会被拒绝，新回合自动建立新客户端。可用 `await sky.compat_status()` 核对固定加载器；返回 `captureReminder: 'on-result'`、`polling: false` 和 `nativeReleaseAvailable: true`。确认边框和指针恢复后报告释放。物理 Esc 验证需用户按真实键盘上的 Esc；程序发送 Escape 不代表该路径通过。
7. 初始化失败按官方恢复指南进行有限重试；区分入口、原生连接、截图和目标应用错误，不循环尝试相同失败路径。

截图由官方方法自动显示。原生操作只使用该 Skill 的官方 API，不混用 PowerShell UI Automation，也不创建自定义 helper 协议客户端。

## 本机兼容和提醒

- 项目说明：[CodexComputerUseFix](../README.md)。DLL 只处理 Windows 10 原生截图接口和回调，不负责浏览器网络或工具路由。
- `manage.ps1 status -Json` 从插件启动命令定位配置中的 runtime；必要时另查会话进程路径。多个候选须指定实际 helper，不按目录时间选择。
- 文件归属和功能结果分开判断。更新后先核对实际截图结果，不能由新目录、哈希变化或 DLL 缺失断定 CU 损坏。
- 管理入口的安装和卸载只处理截图 DLL。针对已证实的启动代理缺口及生命周期缺口，分别使用独立修复；见项目 README。自动窗口守卫已撤销。
- `native-runtime/` 在官方 CU worker 启动时加载固定目录中的清理和提醒代码。提醒直接处理实际原生截图结果；同一会话十分钟内连续两次同类截图错误才弹窗，成功清除失败状态。无定时任务和日志轮询。
- 端口或进程查询被沙箱拒绝时应报告未知，不隐藏错误后把空结果当成“未监听”或“未运行”。

[历史证据及验收边界](cu-maintenance-audit.md)。
