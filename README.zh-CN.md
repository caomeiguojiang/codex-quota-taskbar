# Codex Quota Taskbar

语言: [English](README.md) | **简体中文**

Codex Quota Taskbar 是一个 Windows 任务栏额度浮层。它会在任务栏内垂直居中显示 Codex 的 5 小时额度和本周额度，并可选显示 Codex Desktop 当前对话状态。

![任务栏内垂直居中的额度浮层](plugins/codex-quota-taskbar/assets/screenshot.png)

![浮层右键菜单](plugins/codex-quota-taskbar/assets/menu.png)

## 任务状态同步支持

支持同步 Codex Desktop 的对话执行状态。状态图标位于浮层最左侧，不额外占用文字区域。

![Idle 到 Running 到 Complete 的状态同步动图](plugins/codex-quota-taskbar/assets/task-status-sync-real.gif)

- `Idle`：灰色小点，表示当前没有对话在推进。
- `Running`：蓝色虚线圆环旋转，表示至少一个对话正在执行。
- `Complete`：绿色 check，表示刚完成一次对话；默认保留 5 秒后回到 idle。
- 状态来源优先使用 Codex Desktop IPC 的 `thread-stream-state-changed` 广播。
- 从 `Running` 变为 `Complete` 时，会立即排队刷新一次额度。

## 通过 Codex Desktop 图形界面接入

不需要使用命令行。按下面步骤在 Codex Desktop 里完成插件市场添加、插件安装和启动。

1. 打开 Codex Desktop。
2. 在左侧导航栏点击「插件」。

![从左侧导航栏进入插件页](plugins/codex-quota-taskbar/assets/desktop-sidebar-plugins.png)

3. 在插件页右上角点击「+」旁边的下拉按钮。
4. 选择「添加插件市场」。

![从插件页添加插件市场](plugins/codex-quota-taskbar/assets/desktop-add-marketplace-menu.png)

5. 在「添加插件市场」弹窗里按下面内容填写：

```text
来源: caomeiguojiang/codex-quota-taskbar
Git 引用: main
稀疏路径: 留空
```

如果「来源」输入框不接受 GitHub 简写，改填：

```text
https://github.com/caomeiguojiang/codex-quota-taskbar.git
```

不要在「稀疏路径」里填写 `plugins/codex-quota-taskbar`。这个仓库的根目录已经包含插件市场配置，插件市场会把 Codex Desktop 指向插件子目录。

6. 点击「添加市场」。

![添加插件市场弹窗](plugins/codex-quota-taskbar/assets/desktop-add-marketplace-dialog.png)

7. 回到插件页，搜索 `Codex Quota Taskbar`。
8. 打开插件卡片，安装并启用它。
9. 新建一个 Codex Desktop 对话。
10. 输入：`安装并启动 Codex Quota Taskbar`。

![在 Codex Desktop 对话中启动插件](plugins/codex-quota-taskbar/assets/desktop-start-plugin-prompt.png)

11. 安装完成后，任务栏内会出现额度浮层。

## 使用方式

- 左键点击浮层：立即刷新额度。
- 右键点击浮层：打开菜单。
- 双击浮层：切回 Codex Desktop。
- 右键菜单「设置...」：打开设置界面。
- 右键菜单「切换显示器」：切换浮层所在显示器。
- 右键菜单「退出」：关闭 companion。

## 当前能力

- 显示 5 小时额度和本周额度。
- 浮层在目标显示器任务栏内垂直居中。
- 支持多显示器选择，并显示更友好的显示器名称。
- 支持中文和英文界面。
- 支持根据系统语言选择默认语言，不支持时回退到英文。
- 支持可选 Codex 状态图标。
- Codex 正在执行时显示 running/loading 状态。
- 对话完成后显示 5 秒 complete 状态。
- 空闲时显示 idle 状态。
- 额度每 15 秒后台刷新一次。
- Codex 从 running 变为 complete 时立即刷新一次额度。

## 设置和运行数据

设置文件：

```text
%APPDATA%\CodexQuotaTaskbar\settings.json
```

日志目录：

```text
%LOCALAPPDATA%\CodexQuotaTaskbar\logs
```

运行状态目录：

```text
%LOCALAPPDATA%\CodexQuotaTaskbar\runtime
```

## 实现说明

当前主运行时是原生 C# companion：

```text
plugins\codex-quota-taskbar\companion\bin\CodexQuotaTaskbar.exe
plugins\codex-quota-taskbar\companion\native\CodexQuotaTaskbar.cs
```

PowerShell 仍保留在包内，用于安装、启动、停止、测试包装和旧实现参考。实际任务栏浮层、托盘监控、设置界面、Codex IPC 活动监听和额度轮询已经迁移到原生可执行文件。

## 刷新策略

- 任务栏可见性和置顶保活：每 2 秒。
- Codex 活动状态采样：每 250 ms。
- 额度 remaining 后台刷新：每 15 秒。
- Codex 从 running 变 complete：立即排队刷新一次。
- 手动刷新：浮层左键、右键菜单刷新、托盘菜单刷新。

额度刷新在后台串行执行。如果刷新正在进行，新的刷新请求会排队一次，并在当前刷新结束后执行。

## Codex 活动状态来源

状态图标优先使用 Codex Desktop IPC：

```text
\\.\pipe\codex-ipc
```

companion 会监听 `thread-stream-state-changed` 广播，并推断：

- `Running`：至少一个已知对话仍在推进。
- `Complete`：所有推进结束后的 5 秒窗口。
- `Idle`：没有对话推进，且 complete 显示窗口已过期。

如果 IPC 不可用，会回退到本地进程活动启发式判断。

## 限制

- 这是本地 Windows companion，不会把 UI 注入到 Codex Desktop 内部。
- 无法覆盖 UAC 安全桌面、锁屏、独占全屏应用或更强置顶窗口。
- 额度读取依赖本地 Codex app-server 行为。如果 Codex 改动该内部接口，companion 也需要同步更新。
- Codex Desktop IPC 目前适合监听活动状态；额度读取仍需要本地 app-server 路径。

## 后续维护建议

当前 native 代码仍是单文件打包，主要是为了匹配现有简单构建和分发路径。后续最值得推进的是拆分 `CodexQuotaTaskbar.cs`。

建议拆分边界：

- options、paths、logging、settings。
- quota service 和 Codex app-server 协议。
- Codex IPC activity source 和 activity state machine。
- monitor context 和 tray menu。
- overlay layout、WPF window、context menu style。
- settings dialog 和 monitor display-name helpers。
- native self-tests 和 visual QA context。
