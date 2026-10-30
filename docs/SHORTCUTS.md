# Mac 快捷键模块

把仓库中 `mac/deskflow_keys.lua` 放入 `~/.hammerspoon/`，在已有 `init.lua` 中增加 `deskflowKeys = require("deskflow_keys")`，保留已有配置。首次授权和加载步骤见 [安装与迁移](MIGRATION.md)。

- 菜单 `DF键✓` 表示启用；`Ctrl+Alt+Shift+P` 暂停／恢复。
- 常用 Ctrl+A/C/V/X/Z/S/F/N/O/P/W/T/L/R 转换为对应 Command 组合；Ctrl+Y 为重做，按 Office 与其他应用区分。
- Ctrl+Shift+Z、Ctrl+Shift+T 保留对应的 Command+Shift 行为。
- Ctrl+左右按词移动，加入 Shift 按词选择；Ctrl+Backspace 删除前词；Ctrl+Home/End 到文首／文末。
- 普通 Home/End 仅在可识别的文字编辑区转换为行首／行尾；Shift 加选区。
- macOS“终端”和 iTerm 完全排除；浏览器和 IDE 内嵌终端仍属于其所在应用，需要时用暂停入口。
- 浏览器／Finder 中 Alt+左右转换为后退／前进，可在菜单关闭。
- 原生 Command、Ctrl+空格、Ctrl+Tab 与未列出的组合按原规则处理。
- 模块菜单偏好存于 Hammerspoon 本机设置，新 Mac 重新设置；macOS 安全输入会阻止事件监听，离开密码输入状态后再核对。

模块不依赖原 Windows 的名称或 IP。若新系统使用其他终端应用，可在 `excludedTerminals` 中按实际应用标识增加排除项。
