# 安装与迁移

以下路径相对于仓库根目录。先备份目标电脑已有配置，再采集本机显示布局，核对主机名、输入源和键码。原 Windows 助手的进程互斥锁标签已改为通用名称。

目标是：音乐键进入 Windows 左右扩展双屏；邮件键恢复左 Windows、右 Mac，键鼠同时切到对应系统。

## 按更换范围选择步骤

| 更换范围 | 需要做什么 |
|---|---|
| 只换 Mac，Windows／键盘／显示器接线不变 | 安装 Mac 端、重新配对 Deskflow，并更新服务端配置中的 Mac 名称；Windows 布局通常可以保留，但要复测两模式 |
| 只换 Windows，Mac 不变 | 在新 Windows 安装 Deskflow 和助手，重新采集布局、重新配对；Mac 端快捷键文件可保留 |
| Windows 重装、换显卡、换接口、换共享显示器 | 重新采集 Windows 布局；换显示器时还要确认 DDC 输入源编号 |
| 只想复用 Mac 的 Ctrl 快捷键规则 | 只做下面的 Mac 快捷键步骤，无需 Windows 显示切换助手 |
| 整套搬到另一组电脑 | 按全部步骤完成 |

## 1. 准备硬件与 Deskflow

- 实体键鼠连接 Windows；Windows 是 Deskflow 服务端，Mac 是客户端。
- 左屏始终接 Windows；共享右屏分别接 Windows 与 Mac 的视频输出。
- 在共享显示器菜单开启 DDC/CI（如果有该选项）。现有程序使用 Windows DP、Mac HDMI；其他接线先核对输入源控制值。
- 先手动切右屏到 Windows，设置“扩展这些显示器”，把左屏设为主屏，右屏在其右边；再切回 Mac，确认两种画面均正常。
- 当前源码的适用布局是两台活动显示器、左屏为 Windows 主屏、共享屏位于右侧且使用独立输入。笔记本内屏、多于两屏或镜像布局要调整程序。
- 两端安装原版 Deskflow。原机器已验证的版本是 1.27.0；不同版本先核对配置格式。
- 在 Deskflow 中重新建立“Windows 在左、Mac 在右”的连接，按正常流程完成新机器配对／指纹确认。记录两端 Deskflow 显示的电脑名称，以及新 Windows 的连接地址。保持修饰键原样，避免再把 Ctrl 与 Command 全局交换。

下载与说明：[Deskflow 官方仓库](https://github.com/deskflow/deskflow)、[文本配置说明](https://github.com/deskflow/deskflow/wiki/Server-Text-Config)。

## 2. 在新 Mac 恢复 Ctrl 快捷键

1. 安装并启动 Hammerspoon，按官方引导为它开启“辅助功能”。安装说明见 [Hammerspoon 官方入门](https://www.hammerspoon.org/go/)。
2. 把 `mac/deskflow_keys.lua` 放到新 Mac 的 `~/.hammerspoon/deskflow_keys.lua`。
3. 如果 `~/.hammerspoon/init.lua` 已有内容，先备份，在末尾增加下面一行；如果没有现有配置，可以使用 `mac/init.lua`。不要重复加载同一个模块。

   ```lua
   deskflowKeys = require("deskflow_keys")
   ```

4. 在 Hammerspoon 菜单选择 Reload Config，确认出现 `DF键✓`。按需设置登录时打开 Hammerspoon 和 Deskflow。
5. 从 Windows 键盘测试 Ctrl+A/C/V、Ctrl+Shift+方向键，以及 Ctrl+Alt+Shift+P 暂停／恢复。macOS“终端”与 iTerm 的排除规则已经在模块中。

详细规则见 [快捷键说明](SHORTCUTS.md)。新 Mac 的辅助功能授权、登录项和 Hammerspoon 菜单偏好须重新设置；复制 Lua 文件不会复制这些系统状态。

## 3. 在新 Windows 准备助手

以下均在新 Windows 的本地桌面、普通用户 Windows PowerShell 5.1 中操作；不要在 SSH、远程桌面或后台服务会话中采集／控制显示。部署路径使用目标电脑的用户环境变量。

1. 创建 `%LOCALAPPDATA%\DisplayHandoff`，把 `windows/DisplayHandoff.ps1` 和 `windows/DisplayNative.cs` 放进去。
2. 此时保持 Windows 已经扩展到左右两屏，右屏显示 Windows。
3. 在同一个 Windows PowerShell 窗口执行下面的采集步骤。它只读取当前显示器信息并保存到文件，不改变显示设置。已有 `display-layout.json` 时先备份，再决定是否重新采集。

```powershell
$displayHandoffRoot = Join-Path $env:LOCALAPPDATA 'DisplayHandoff'
$displayHandoffLayoutFile = Join-Path $displayHandoffRoot 'display-layout.json'
if (Test-Path $displayHandoffLayoutFile) { throw 'Layout file exists; back it up before recapturing.' }
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path (Join-Path $displayHandoffRoot 'DisplayNative.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing
if ([Diagnostics.Process]::GetCurrentProcess().SessionId -ne [DisplayHandoff.Native]::WTSGetActiveConsoleSessionId()) {
    throw 'Use the signed-in physical Windows desktop.'
}
$displayHandoffActive = @([DisplayHandoff.Native]::Adapters() | Where-Object { ($_.Flags -band 1) -ne 0 })
$displayHandoffActive | Format-Table Device,MonitorId,Flags,X,Y,Width,Height -AutoSize
$displayHandoffLeft = @($displayHandoffActive | Where-Object { ($_.Flags -band 5) -eq 5 })
$displayHandoffRight = @($displayHandoffActive | Where-Object { ($_.Flags -band 5) -ne 5 })
if ($displayHandoffActive.Count -ne 2 -or $displayHandoffLeft.Count -ne 1 -or $displayHandoffRight.Count -ne 1) {
    throw 'Expected two active displays with exactly one primary.'
}
if ($displayHandoffRight[0].X -lt ($displayHandoffLeft[0].X + $displayHandoffLeft[0].Width)) {
    throw 'Arrange the shared display to the right of the primary first.'
}
if (-not $displayHandoffLeft[0].MonitorId -or -not $displayHandoffRight[0].MonitorId -or -not $displayHandoffRight[0].Mode) {
    throw 'Display identity or current mode is unavailable.'
}
$displayHandoffLayout = @{ left=$displayHandoffLeft[0]; right=$displayHandoffRight[0] }
[IO.File]::WriteAllText($displayHandoffLayoutFile, ($displayHandoffLayout | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
```

必须确认表格中的主屏确实是左侧保留屏，另一屏确实是要切换的右屏。不要把旧电脑的 `display-layout.json` 搬过来。微软建议使用当前设备实际返回的显示模式来更改该设备，参见 [ChangeDisplaySettingsExW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-changedisplaysettingsexw)。

### 核对右屏输入源

在上面的同一窗口，先将显示器菜单选到 Windows 输入，运行只读命令：

```powershell
([DisplayHandoff.Native]::Input($displayHandoffLayout.right.Device, -1) -band 255)
```

然后保持 Windows 的两屏扩展逻辑不变，手动把右屏切到 Mac 输入，在左侧 Windows 再运行一次相同的读取命令。已验证环境的控制值是 Windows DP=15、Mac HDMI=17；这两个值写在 `DisplayHandoff.ps1` 中 `$displayHandoffValue` 的选择处。新显示器如果返回其他值，按实测更新该处；控制通道不可用或读数不能确认时，先解决 DDC 支持问题，再测试自动切换。

### 核对实体功能键

继续使用同一把键盘时，可以先试现有绑定：音乐键 LaunchMedia=0xB5（181），邮件键 LaunchMail=0xB4（180）。换键盘时，按键上的图案不能保证键码相同。

需要重新检测时，在正式助手尚未运行的情况下，把 `windows/key-probe` 的两个文件放到同一目录，在 Windows 桌面运行：

```powershell
powershell.exe -NoLogo -NoProfile -File .\MediaProbe.ps1
```

先按音乐键、再按邮件键，读取旁边生成的 `media-key-probe.json`。探测器只捕获 0xB0 到 0xB7 的媒体／应用启动键，收到两个不同键后退出，超时为 15 分钟；无结果时关闭探测进程，检查键盘驱动。不要把“播放／暂停”自动当成 LaunchMedia。若结果不同，需相应调整 `DisplayNative.cs` 中的键码判断和模式选择，并重新测试。

## 4. 更新新 Windows 的 Deskflow 配置

1. 先用 Deskflow GUI 建好并测试两端连接，记录实际电脑名称。复制 `windows/deskflow-server.template.conf`，将 `__WINDOWS_SCREEN__`、`__MAC_SCREEN__` 全部替换为新电脑在 Deskflow 中的名称，保存成 `%LOCALAPPDATA%\DisplayHandoff\deskflow-server.conf`。不能留有占位符。
2. 模板用于 1.27.0 已在 GUI 定义电脑的外部配置追加文件。它保留内部 F22／F23 控制与左右关系。已有自定义规则时合并，不要丢失原规则。
3. 从左侧 Windows 桌面退出 Deskflow，并备份它新生成的 `%APPDATA%\Deskflow\Deskflow.conf`。
4. 对该新文件已有的 `[server]` 段修改下面三个字段（不要覆盖整个 INI、不要重复创建字段）。路径替换成新 Windows 用户的实际绝对路径，采用正斜杠：

   ```ini
   externalConfig=true
   externalConfigFile=C:/Users/NEW_USER/AppData/Local/DisplayHandoff/deskflow-server.conf
   disableLockToComputer=false
   ```

5. 重新启动 Deskflow，确认新客户端连接正常。不同版本若没有上述配置字段或路径，先按该版本的官方说明核对，不要套用旧文件。

内部信号含义：Ctrl+Alt+Shift+F22 将键鼠切到 Windows 并锁定；Ctrl+Alt+Shift+F23 解除锁定并切到 Mac。这些由助手发送，日常只按音乐／邮件键。修改主机名时，链接与这两条规则的目标名称都要同步更新。

## 5. 先验证，再设登录启动

在新 Windows 的本地桌面先前台运行：

```powershell
& (Join-Path $env:LOCALAPPDATA 'DisplayHandoff\DisplayHandoff.ps1') -Mode Run
```

依次确认：

- 音乐键：Windows 左右扩展，窗口能拖到右侧，键鼠留在 Windows。
- 邮件键：右屏恢复 Mac，Windows 只保留左屏，键鼠可操作 Mac。
- 通过上述两种状态各再试一次，确认双向触发都能到达。
- Mac 的 Ctrl 复制／粘贴、文字导航和终端排除仍符合预期。


测试通过后，用 Windows“任务计划程序”为当前用户创建 `DisplayHandoff` 任务：

- 触发：当前用户登录时。
- 仅当该用户已登录时运行，普通权限，不勾选最高权限。
- 程序：`C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`。
- 参数：`-NoLogo -NoProfile -WindowStyle Hidden -File "C:\Users\NEW_USER\AppData\Local\DisplayHandoff\DisplayHandoff.ps1" -Mode Run`，替换实际路径。
- 取消任务运行时限；如需电池下使用，也取消“仅交流电源下运行”相关限制。
- 确认 Windows Deskflow 和 Mac Deskflow／Hammerspoon 都按各自设置登录启动。先退出前台测试助手，再启动正式任务。

如果系统执行策略拒绝脚本，按该电脑允许的签名／执行策略处理；本说明不要求关闭全机策略。辅助程序在登录后的物理桌面运行，不需要 SSH 常驻、管理员常驻或保存密码。

## 恢复与排查

配置前保留新机器自己的 Deskflow 备份。撤销时退出托盘助手、删除新建的登录任务，退出 Deskflow 后恢复新机器的备份，再启动 Deskflow；显示器输入源和 Windows 单屏／双屏先用各自菜单恢复。不要运行旧电脑的恢复脚本或使用旧电脑的备份覆盖新电脑。

新助手目录中 `controller-state.json` 显示当前阶段／错误，`controller-log.jsonl` 记录模式切换结果。若能切画面但键鼠没切换，核对 Deskflow 名称、连接状态、F22／F23 配置和锁定设置；若画面没切换，先查 DDC；若 Windows 仍有隐藏扩展屏，核对新布局文件和显卡驱动。

两键完整切换已在一套双主机环境中实测；迁移到另一套硬件后需要重新验证。更换显卡驱动、接口或电脑后应重做布局核对。
