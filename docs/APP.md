# Display Handoff 配置助手 0.1（实验）

实验位于 `codex/setup-app`。提供 Windows 安装 EXE 与 Mac 配置应用，复用已有切屏、快捷键和鼠标模块。当前是可构建原型；主分支和已安装的日常版本不会随分支更新。

## 减少哪些操作

| 操作 | Windows 向导 | Mac 应用 |
|---|---|---|
| 检查 | 读取两屏、主屏位置和当前 DDC 输入 | 检测 Deskflow / Hammerspoon |
| 配置 | 界面填写两端名称、DDC 值、选择两个媒体键 | 勾选 Ctrl 快捷键、鼠标模块 |
| 部署 | 采集本机布局、生成配置、编译后台启动器 | 合并 init.lua、复制所选模块 |
| 启动 | 创建普通权限的当前用户登录任务 | 提供 Hammerspoon 和权限设置入口 |
| 恢复 | 备份、核对并恢复 Deskflow.conf，删除自己的任务 | 逐文件备份、核对后恢复或删除新增文件 |

仍需完成：视频接线、DDC/CI 开关、Windows 左主屏＋右扩展布局、两端 Deskflow 安装配对、Mac 辅助功能授权、Hammerspoon Reload Config / 登录启动。Options+ 手势配置仍为可选的独立步骤。本版不自动编辑任意第三方规则，不复制旧电脑的显示布局。

## 获取程序

打开 [Actions → Build experimental setup apps](https://github.com/YueyueBird-su/deskflow-display-handoff/actions/workflows/build-setup.yml)，选择 `codex/setup-app` 对应的成功运行，下载 Artifacts（GitHub 通常要求登录）：

- `DisplayHandoffSetup-Windows-experimental`：解压得到 `DisplayHandoffSetup.exe`。
- `DisplayHandoffSetup-Mac-experimental`：解压后再展开里面的 ZIP，得到 `Display Handoff Setup.app`。

也可从源码构建。本版没有商业代码签名或 Apple 公证。若系统策略阻止启动，按本机允许的开发／签名流程处理，不要求关闭系统安全保护。

## Windows 试用

需要 Windows 10/11 桌面、自带 PowerShell 5.1 / .NET Framework / C# 编译器、Deskflow。Windows ARM64 和受限企业策略未验证。仅适用于两个活动显示器：左侧保留主屏，右侧共享扩展屏。

1. 在物理 Windows 桌面打开 EXE，不通过 SSH、远程桌面或服务会话配置显示。
2. 手动启用左右扩展双屏，共享屏切到 Windows 输入；Deskflow 作为服务端，已完成 Mac 配对。
3. 填写 Deskflow 界面中显示的两端电脑名称。本版支持字母、数字、点、下划线、连字符；默认 Windows 名来自系统，只是待核对建议。
4. 核对输入值与媒体键。默认 DP1=`15`、HDMI1=`17`、音乐 LaunchMedia=`181`、邮件 LaunchMail=`180`。设备可能不同，不自动猜测；其他媒体键可从下拉框选择。
5. 点击“检测并预览”。此步骤只读，不切屏、不监听按键。
6. 从 Windows Deskflow 托盘菜单退出它，勾选已核对，点击安装。仅此时写入配置与登录任务。
7. 重新打开 Deskflow，点击“启动已安装助手”，检查托盘并测试两方向、Windows 单双屏，以及关闭普通 PowerShell 后的表现。

安装目录 `%LOCALAPPDATA%\DisplayHandoffApp`，登录任务 `DisplayHandoffApp`，普通权限交互式桌面，不保存密码。仍通过无控制台启动器运行；输入值和键码保存在本机 `handoff-settings.json`，不需改源码。

向导不强制结束 Deskflow。发现旧 `DisplayHandoff` 任务、已有安装目录或 Deskflow 外部配置时会停止。已有部署迁移前，需按原方式退出／移除旧助手并恢复原 Deskflow 配置；保留原备份，不要让两个助手同时运行。

勾选罗技桥接后会部署 `MouseBridge.cs`，可从安装目录运行 `Configure-OptionsGestures.ps1`；该工具支持本实验任务名，仍检查型号、schema 和现有手势，不会在安装向导里自动修改数据库。参见 [鼠标说明](MOUSE.md)。

**撤销：**退出 Deskflow，在 EXE 中点击撤销。仅当前 INI 与安装时哈希一致时自动恢复；后续编辑会被保留并阻止自动覆盖。备份留在 `setup-backup`，撤销后目录保留供检查，确认不需要后可删除／另存，再次安装前须腾空目录。撤销不切画面，可用显示器菜单与 Windows 显示设置恢复。

本版不设置 `ExecutionPolicy Bypass` 或修改全机策略。策略禁止脚本时会报错，日志仅留本机 `%LOCALAPPDATA%\DisplayHandoffSetup\setup.log`。

## Mac 试用

Universal 应用支持 Apple Silicon + Intel，最低构建目标 macOS 13。已在 Apple Silicon 本机核对界面；Intel 包已交叉编译，尚未在 Intel 硬件运行。

1. 打开 `.app`；缺少依赖时可从界面前往官方下载。
2. 勾选功能，点击“备份并安装所选功能”。
3. 在 Hammerspoon 菜单执行 Reload Config，按系统提示授权辅助功能，需要登录启动时在其偏好中开启。
4. 从 Windows 实体键鼠测试；关闭配置助手不影响 Hammerspoon 后台运行。

目标为默认 `~/.hammerspoon`，不修改自定义配置目录。不同内容的同名模块、符号链接、异常安装标记会阻止安装；相同版本可保留，已有标准 require 不重复加载。

备份在 `~/Library/Application Support/Display Handoff Setup/`。点击撤销可恢复；安装后编辑过的文件会阻止覆盖，需从本机备份合并。恢复后仍需 Reload Config。应用不自动授予权限或更改配对。

## 从源码构建

Windows：分别在**独立的** Windows PowerShell 5.1 进程运行两个测试，随后构建：

```powershell
powershell.exe -NoProfile -File .\tests\Test-Windows.ps1
powershell.exe -NoProfile -File .\tests\Test-WindowsTransaction.ps1
.\app\windows\Build.ps1
```

输出 `dist\DisplayHandoffSetup.exe`，嵌入通用源码，不附带第三方软件或机器配置。事务测试用假显示 API 和内存任务表，不能与真实 native 类型共用进程。

Mac：需 Apple Command Line Tools / Xcode 编译器：

```sh
mkdir -p dist/swift-cache
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path dist/swift-cache \
  app/mac/SetupCore.swift tests/MacSetupTests.swift -o dist/mac-setup-tests
dist/mac-setup-tests
bash app/mac/build.sh
```

输出 `.app` 和 ZIP。运行时无需 Swift、Python 或 Node，第三方功能仍需相应软件。

## 验证范围

此次开发没有替换日常安装，没有实际创建新登录任务、修改 Options+ 数据库或执行切屏。

- Mac：临时目录中的安装／撤销、保留 init、重复加载、旧模块、后续编辑、损坏备份、符号链接测试；Universal 构建；图形界面启动与依赖识别。
- Windows：设置与布局校验、配置注入拦截、INI 合并、原生 C# 编译、EXE 载荷校验；事务夹具验证备份、恢复、注册失败回滚及旧任务拦截。
- CI：分平台构建下载包。夹具通过不代表所有显示器、显卡、系统策略和完整首次安装已实测。

正式使用前还需在目标电脑完成真实安装、登录启动、双向切换测试。后续可增加键码探测向导、DDC 能力枚举、已有安装迁移和签名发行。
