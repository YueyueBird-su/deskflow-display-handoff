# Logi Options+ 与 Deskflow 鼠标兼容

适用：罗技鼠标连接 Windows，Windows 为 Deskflow 服务端，Mac 为客户端。验证设备为 MX Master 3S；也提供 MX Master 2S 的配置识别。先在 Options+ 中确认正在使用的鼠标，历史配对记录不等于当前输入设备。

## 功能

| 输入 | Mac | Windows |
|---|---|---|
| 侧键后退／前进 | 浏览器、Finder 中后退／前进 | 保持 Options+ 原设置 |
| 主滚轮、滚轮中键 | 原生滚动、中键点击链接开新标签 | 保持原设置 |
| 拇指横滚轮 | Safari 切标签；其他应用原生水平滚动 | 保持原设置 |
| 手势单击 | 窗口总览 | 任务视图 |
| 手势向上 | 窗口总览 | 开始菜单 |
| 手势向下 | 当前应用窗口 | 显示／隐藏桌面 |
| 手势向左／向右 | 相邻桌面 | 相邻虚拟桌面 |

桌面切换需要存在相邻桌面。Mac 的桌面动作使用 Hammerspoon 的实验性 `hs.spaces` 接口，系统升级后需要复测。

`DF鼠✓` 菜单可暂停鼠标兼容、关闭 Safari 横滚切标签，或反转标签方向。它与 `DF键✓` 的键盘映射独立。普通中键不会额外实现 Windows 式的网页自动滚动；应用仍决定中键的具体用途。

## 为什么两端都有 Options+ 仍需要桥接

Options+ 管理直接连接的设备；Deskflow 转发的是输入事件。Mac 收到普通鼠标事件后，不会自动套用另一台电脑或另一只实体鼠标的 Options+ 配置。

本方案让 Windows Options+ 识别物理手势并发送控制信号。Mac 的 Hammerspoon 模块把侧键、Safari 横滚及手势转换为相应动作。模块默认采用窗口导航行为；它不会自动同步之后在 Mac Options+ 中做的任意配置修改，鼠标兼容偏好在 `DF鼠` 菜单中设置。

## 安装

1. Windows 安装 [Logi Options+](https://www.logitech.com/en-us/software/logi-options-plus)。Mac 运行 Hammerspoon 与 Deskflow。Mac Options+ 可继续用于直接连接 Mac 的设备，但不是这个桥接模块的运行依赖。
2. 把 `mac/deskflow_mouse.lua` 放入 `~/.hammerspoon/`，在原 `init.lua` 中合并一行：

   ```lua
   deskflowMouse = require("deskflow_mouse")
   ```

3. Reload Config，确认出现 `DF鼠✓`。原有 `deskflow_keys.lua` 和终端排除无需修改。
4. 在 Windows 的助手目录部署更新后的 `DisplayHandoff.ps1` 和 `MouseBridge.cs`，退出并重启 DisplayHandoff 登录任务。助手将注册五个本地控制信号；先确认 `mouse-bridge-state.json` 显示 `ready`、`registered` 为 `5`。
5. 复制 `Configure-OptionsGestures.ps1`、`ReadOptions.cs`、`OptionsPatch.cs` 到同一助手目录。在 Windows PowerShell 5.1 中运行配置脚本：

   ```powershell
   & (Join-Path $env:LOCALAPPDATA 'DisplayHandoff\Configure-OptionsGestures.ps1')
   ```

   脚本优先识别活跃鼠标的蓝牙 HID 型号。若接收器或多个设备导致无法唯一识别，应在 Options+ 确认型号后明确传参：

   ```powershell
   & (Join-Path $env:LOCALAPPDATA 'DisplayHandoff\Configure-OptionsGestures.ps1') -Model mx-master-3s
   ```

6. 在 Mac 和 Windows 各单击一次手势键，再测试方向、侧键、横滚、中键及原音乐／邮件切屏键。

配置脚本只针对 Options+ 2.9／设置 schema 26 验证过的格式：要求现有手势为“虚拟桌面”，自定义手势尚未被使用。已自定义或格式不匹配时会停止，避免覆盖已有操作。它在 Windows 本机备份数据库，通过事务只修改目标鼠标的自定义手势和预设选择，并检查其他设置没有变化，最后恢复原 Options+ 后台进程。

只读检查可使用 `-InspectOnly`，不会改变设置。可选鼠标模块初始化失败时，基本切屏仍继续运行，错误会写入本机鼠标状态文件。

该脚本操作的是 Options+ 本机设置格式，不是 Logitech 的公开配置 API。Options+ 更新后应重新核对；备份留在 `mouse-options-backup-*`，不要提交这些文件。

## 控制信号

| Options+ 自定义手势 | 信号 |
|---|---|
| 单击 | Ctrl+Alt+Shift+F13 |
| 左 | Ctrl+Alt+Shift+F14 |
| 右 | Ctrl+Alt+Shift+F15 |
| 上 | Ctrl+Alt+Shift+F16 |
| 下 | Ctrl+Alt+Shift+F17 |

这些组合供桥接使用，日常直接操作鼠标。Windows 的本地注册热键在 Deskflow 底层输入钩子之后接收事件：转发到 Mac 的事件由 Deskflow 截获，在 Windows 本机使用的信号才交给本地动作，避免两边一起执行。

## 暂停、恢复与排查

- 只暂停 Mac 的额外鼠标处理：在 `DF鼠` 菜单取消“启用鼠标兼容”。
- 恢复原 Windows 手势行为：在 Options+ 把手势预设改回“虚拟桌面”。自定义信号此时不再启用。
- 完全移除：恢复上述 Windows 预设，删除 Mac 入口中的 `deskflow_mouse` 行并 Reload Config；退出助手后移除 Windows `MouseBridge.cs`，再重启助手。基础切屏与原 Ctrl 映射可继续运行。
- Safari 若更希望横滚移动宽页面，在 `DF鼠` 菜单关闭“Safari 横滚切换标签”。连续触控板滚动不会被这个离散滚轮转换规则处理。
- 没有手势动作：检查实际活跃鼠标型号、Options+ 后台进程、五个信号的注册状态，以及 Mac `DF鼠` 是否启用。不要只根据历史配对设备名称修改配置。

参考：[Logitech 按钮／手势设置说明](https://hub.sync.logitech.com/options/post/programming-buttons-and-keys-in-options-ntwM6VsAEKhHACY)、[Hammerspoon 输入事件](https://www.hammerspoon.org/docs/hs.eventtap.html)、[Spaces 接口](https://www.hammerspoon.org/docs/hs.spaces.html)。

## 验证范围

已在 MX Master 3S 上实测侧键、Safari 横滚切标签、中键打开链接、Mac 窗口总览／应用窗口，以及 Windows 本地任务视图。两端手势只触发当前操作的电脑；音乐／邮件切屏和原 Ctrl 快捷键回归正常。左右桌面切换的信号与规则已配置，但测试环境仅有一个桌面，未做多桌面实体实测。
