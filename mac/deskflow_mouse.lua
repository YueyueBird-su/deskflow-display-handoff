-- Compatibility for discrete mouse events forwarded by Deskflow.
-- Middle click and vertical/horizontal scrolling outside Safari remain native.
local M = {version = 1, counts = {}}
local types, properties = hs.eventtap.event.types, hs.eventtap.event.properties
local enabled = hs.settings.get("deskflowMouse.enabled") ~= false
local safariTabs = hs.settings.get("deskflowMouse.safariTabs") ~= false
local reverseTabs = hs.settings.get("deskflowMouse.reverseTabs") == true
local heldButtons, heldKeys = {}, {}
local lastTab = 0
local navigationApps = {
    ["com.apple.Safari"] = true, ["com.apple.finder"] = true,
    ["com.google.Chrome"] = true, ["com.google.Chrome.canary"] = true,
    ["org.mozilla.firefox"] = true, ["com.microsoft.edgemac"] = true,
    ["com.brave.Browser"] = true, ["company.thebrowser.Browser"] = true,
    ["com.operasoftware.Opera"] = true, ["com.vivaldi.Vivaldi"] = true,
    ["com.kagi.kagimacOS"] = true,
}
local signals = {}
for number, action in pairs({[13]="missionControl", [14]="spaceLeft", [15]="spaceRight", [16]="missionControl", [17]="appExpose"}) do
    signals[hs.keycodes.map["f" .. number]] = action
end

function M.buttonAction(button, bundle)
    if not navigationApps[bundle] then return nil end
    if button == 3 then return "back" end
    if button == 4 then return "forward" end
end

function M.wheelAction(horizontal, vertical, continuous, bundle)
    if not safariTabs or bundle ~= "com.apple.Safari" or vertical ~= 0 or continuous ~= 0 or horizontal == 0 then return nil end
    local nextTab = horizontal > 0
    if reverseTabs then nextTab = not nextTab end
    return nextTab and "tabNext" or "tabPrevious"
end

function M.signalAction(code, flags)
    if flags.ctrl and flags.alt and flags.shift and not flags.cmd then return signals[code] end
end

local function perform(action)
    M.counts[action] = (M.counts[action] or 0) + 1
    if action == "back" or action == "forward" then
        hs.eventtap.keyStroke({"cmd"}, action == "back" and "[" or "]", 0)
    elseif action == "tabNext" or action == "tabPrevious" then
        hs.eventtap.keyStroke(action == "tabNext" and {"ctrl"} or {"ctrl", "shift"}, "tab", 0)
    elseif action == "missionControl" then
        hs.spaces.toggleMissionControl()
    elseif action == "appExpose" then
        hs.spaces.toggleAppExpose()
    elseif action == "spaceLeft" or action == "spaceRight" then
        local screen = hs.screen.mainScreen()
        local current = hs.spaces.activeSpaceOnScreen(screen)
        local spaces = hs.spaces.spacesForScreen(screen) or {}
        for index, space in ipairs(spaces) do
            if space == current then
                local target = spaces[index + (action == "spaceLeft" and -1 or 1)]
                if target then hs.spaces.gotoSpace(target) end
                break
            end
        end
    end
end

local function afterModifiers(action, remaining)
    remaining = remaining or 40
    hs.timer.doAfter(0.025, function()
        local flags = hs.eventtap.checkKeyboardModifiers()
        if flags.ctrl or flags.alt or flags.shift or flags.cmd then
            if remaining > 0 then afterModifiers(action, remaining - 1) end
        else
            local ok, errorText = pcall(perform, action)
            if not ok then hs.printf("Deskflow mouse action failed: %s", errorText) end
        end
    end)
end

M.tap = hs.eventtap.new({types.otherMouseDown, types.otherMouseUp, types.scrollWheel, types.keyDown, types.keyUp}, function(event)
    local kind = event:getType()
    if kind == types.otherMouseUp then
        local button = event:getProperty(properties.mouseEventButtonNumber)
        if heldButtons[button] then heldButtons[button] = nil; return true end
    elseif kind == types.keyUp then
        local code = event:getKeyCode()
        if heldKeys[code] then heldKeys[code] = nil; return true end
    end
    if not enabled then return false end
    local flags = event:getFlags()
    if kind == types.keyDown then
        local code = event:getKeyCode()
        local action = M.signalAction(code, flags)
        if action then
            if not heldKeys[code] then heldKeys[code] = true; afterModifiers(action) end
            return true
        end
        return false
    end
    if flags.ctrl or flags.alt or flags.shift or flags.cmd then return false end
    local app = hs.application.frontmostApplication()
    local bundle = app and app:bundleID() or ""
    if kind == types.otherMouseDown then
        local button = event:getProperty(properties.mouseEventButtonNumber)
        local action = M.buttonAction(button, bundle)
        if action then heldButtons[button] = true; afterModifiers(action); return true end
    elseif kind == types.scrollWheel then
        local action = M.wheelAction(event:getProperty(properties.scrollWheelEventDeltaAxis2), event:getProperty(properties.scrollWheelEventDeltaAxis1), event:getProperty(properties.scrollWheelEventIsContinuous), bundle)
        if action then
            local now = hs.timer.secondsSinceEpoch()
            if now - lastTab >= 0.16 then lastTab = now; afterModifiers(action) end
            return true
        end
    end
    return false
end)

M.menu = hs.menubar.new()
local function refresh()
    if M.menu then M.menu:setTitle(enabled and "DF鼠✓" or "DF鼠暂停") end
end
if M.menu then
    M.menu:setMenu(function()
        return {
            {title = "启用鼠标兼容", checked = enabled, fn = function() enabled = not enabled; hs.settings.set("deskflowMouse.enabled", enabled); refresh() end},
            {title = "Safari 横滚切换标签（Options+ 同款）", checked = safariTabs, fn = function() safariTabs = not safariTabs; hs.settings.set("deskflowMouse.safariTabs", safariTabs) end},
            {title = "反转标签切换方向", checked = reverseTabs, fn = function() reverseTabs = not reverseTabs; hs.settings.set("deskflowMouse.reverseTabs", reverseTabs) end},
            {title = "中键和其他应用滚动保持原样", disabled = true},
            {title = "手势：总览／应用窗口／左右桌面", disabled = true},
        }
    end)
end
function M.status()
    return {version = M.version, enabled = enabled, safariTabs = safariTabs, reverseTabs = reverseTabs, eventTap = M.tap:isEnabled(), counts = M.counts}
end
M.health = hs.timer.doEvery(5, function()
    if hs.accessibilityState() and not hs.eventtap.isSecureInputEnabled() and not M.tap:isEnabled() then
        heldButtons, heldKeys = {}, {}
        M.tap:start()
    end
    refresh()
end)
if hs.accessibilityState() then M.tap:start() end
refresh()
return M
