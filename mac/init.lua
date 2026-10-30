-- Mac 常用快捷键的 Windows 别名。配置模块持有事件监听器和菜单。
deskflowKeys = require("deskflow_keys")
if hs.fs.attributes(hs.configdir .. "/deskflow_mouse.lua") then
    deskflowMouse = require("deskflow_mouse")
end
