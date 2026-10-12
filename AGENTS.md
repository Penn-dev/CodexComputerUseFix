# Windows 10 截图兼容项目

先读 `README.md`，再确认 Git 分支、工作区改动和实际失败的功能。

## 排查和实施

1. `./manage.ps1 status -Json` 从插件启动命令定位配置中的 runtime；这不是所有已运行会话的进程证明。必要时核对该会话实际进程路径。多个候选时指定实际 `-HelperPath`，不按目录修改时间选目标。
2. `capture-compat/` 的 DLL 只处理 Windows 10 截图接口和回调。文件归属与功能是否正常分别判断。对照真实 `sky.get_window_state` 的失败和成功结果后，才决定安装、保留或卸载。
3. `manage.ps1 install` 只安装截图 DLL。`browser-proxy/` 通过固定系统配置传递已有代理；`native-runtime/` 通过官方 worker wrapper 加载 `windows-lifecycle/` 和 `capture-notify/`。这些修复分别验收。旧代理注入、自动窗口守卫和定时监控已撤销。
4. 控制 Windows 原生应用前，完整读取本机 `~/.codex/docs/runbooks/windows-computer-use.md` 和已安装 computer-use Skill。使用官方 `node_repl + @oai/sky`。切换后台目标时显式激活一次；模态窗口出现后使用刚返回的状态，不反复重新绑定窗口。
5. 内置浏览器、Chrome 和原生截图分别验收。查询被拒绝访问时状态是未知；不能隐藏错误，再把空结果判断为端口未监听。
6. 完成本次 UI 动作和测试窗口清理后，已安装生命周期修复时执行 `await sky.end_turn()`，再重置脚本。脚本重置和 helper 进程存在均不能单独证明控制已释放；保持其他会话的共享 helper。生命周期核查见 README 的历史核查链接。

## 提醒和验证

提醒直接处理 CU 返回的原生截图结果。连续两次同类捕获错误须来自同一会话、间隔不超过十分钟；成功截图清除失败状态。版本、目录、哈希和 Issue 状态变化不触发提醒。没有定时任务、日志轮询或独立值守程序。加载器保留官方 sandbox 命令、参数、工作目录和协议。

管理入口修改后运行 `capture-compat/tests/manage_tests.ps1`。原生修复修改后运行 `node --test windows-lifecycle/tests.mjs capture-notify/tests.mjs native-runtime/tests.mjs`；设置 `CU_TEST_MODULES` 为实际 runtime 的 `bin/node_modules`，验证当前官方客户端。安装器修改后运行对应安装测试；DLL 源码修改后按该目录 README 构建并验证。实机分别验证截图、正常释放、物理 Esc 和桌面提醒。保留直接证据。
