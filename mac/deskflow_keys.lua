-- Windows-style shortcut aliases on a Mac Deskflow CLIENT.
-- Original Command shortcuts and standalone modifiers remain unchanged.
local M = {version = 4, pauseShortcut = "Ctrl+Alt+Shift+P", ctrlScope = "allApplicationsExceptTerminals"}
local events = hs.eventtap.event.types
local keycodes = hs.keycodes.map
local accessibility = hs.axuielement
local pending = {}
local enabled = hs.settings.get("deskflowKeys.enabled") ~= false
local altHistory = hs.settings.get("deskflowKeys.altHistory") ~= false
local textEditing = hs.settings.get("deskflowKeys.textEditing") ~= false
local pauseHeld, pausePending = false, false

local excludedTerminals = {
    ["com.apple.Terminal"] = true,
    ["com.googlecode.iterm2"] = true,
}

local browsers = {
    ["com.apple.Safari"] = true,
    ["com.google.Chrome"] = true,
    ["com.google.Chrome.canary"] = true,
    ["org.mozilla.firefox"] = true,
    ["com.microsoft.edgemac"] = true,
    ["com.brave.Browser"] = true,
    ["company.thebrowser.Browser"] = true,
    ["com.operasoftware.Opera"] = true,
    ["com.vivaldi.Vivaldi"] = true,
    ["com.kagi.kagimacOS"] = true,
}
local officeRedo = {
    ["com.microsoft.Word"] = true,
    ["com.microsoft.Excel"] = true,
    ["com.microsoft.Powerpoint"] = true,
}
local common = {}
for _, key in ipairs({"c", "v", "a", "x", "z", "s", "f", "n", "o", "p", "w", "t", "l", "r"}) do
    common[keycodes[key]] = true
end

-- Read only editing metadata, never the field's contents or selected text.
function M.editableElement(element)
    if not element then return {editable = false} end
    local ok, info = pcall(function()
        element:setTimeout(0.025)
        local role = element:attributeValue("AXRole")
        local subrole = element:attributeValue("AXSubrole")
        local result = {editable = false, role = role, subrole = subrole}
        if subrole == "AXSecureTextField" then return result end
        if role ~= "AXTextField" and role ~= "AXTextArea" and role ~= "AXComboBox"
            and role ~= "AXWebArea" then return result end
        if element:attributeValue("AXEnabled") == false then return result end
        local editable = element:attributeValue("AXEditable")
        if editable == false then return result end
        result.editable = editable == true
            or element:isAttributeSettable("AXValue") == true
            or element:isAttributeSettable("AXSelectedText") == true
        return result
    end)
    return ok and info or {editable = false}
end

function M.focusInfo(app)
    if hs.eventtap.isSecureInputEnabled() then return {editable = false, secureInput = true} end
    app = app or hs.application.frontmostApplication()
    if not app then return {editable = false} end
    local ok, element = pcall(function()
        local root = accessibility.applicationElement(app)
        root:setTimeout(0.025)
        return root:attributeValue("AXFocusedUIElement")
    end)
    return ok and M.editableElement(element) or {editable = false}
end

local function textMapping(code, flags)
    if flags.cmd or flags.alt then return nil end
    local resultFlags = {cmd = true, shift = flags.shift or nil}
    -- Extended PC navigation keys can carry the macOS fn flag.
    if code == keycodes.home or code == keycodes["end"] then
        local first = code == keycodes.home
        local target = flags.ctrl and (first and keycodes.up or keycodes.down)
            or (first and keycodes.left or keycodes.right)
        return {code = target, flags = resultFlags}
    end
    if flags.ctrl and (code == keycodes.left or code == keycodes.right) then
        return {code = code, flags = {alt = true, shift = flags.shift or nil}}
    end
    if flags.ctrl and not flags.shift and not flags.fn and code == keycodes.delete then
        return {code = code, flags = {alt = true}}
    end
    return nil
end

-- Decide using key codes, so Chinese input mode does not change letter matching.
function M.mappingFor(code, flags, bundleID, isEditable)
    if not enabled or flags.cmd or excludedTerminals[bundleID] then return nil end
    -- Ctrl aliases apply outside terminal apps, including apps without AX metadata.
    -- Plain Home/End still require a recognized editable field.
    if textEditing and (flags.ctrl or isEditable) then
        local editing = textMapping(code, flags)
        if editing then return editing end
    end
    local finder = bundleID == "com.apple.finder"
    local browser = browsers[bundleID]
    if altHistory and (browser or finder) and flags.alt and not flags.ctrl and not flags.shift then
        if code == keycodes.left then return {code = keycodes["["], flags = {cmd = true}} end
        if code == keycodes.right then return {code = keycodes["]"], flags = {cmd = true}} end
    end
    if not flags.ctrl or flags.alt or flags.fn then return nil end
    if flags.shift then
        if code == keycodes.z then return {code = code, flags = {cmd = true, shift = true}} end
        if code == keycodes.t then return {code = code, flags = {cmd = true, shift = true}} end
        return nil
    end
    if code == keycodes.y then
        if officeRedo[bundleID] then return {code = code, flags = {cmd = true}} end
        return {code = keycodes.z, flags = {cmd = true, shift = true}}
    end
    if common[code] then
        return {code = code, flags = {cmd = true}}
    end
    return nil
end

-- The one new global chord also works while aliases are paused.
-- Suppress repeat toggles, and consume its matching key-up after modifiers release.
function M.handleShortcut(event, notify)
    local kind, flags = event:getType(), event:getFlags()
    if kind == events.flagsChanged then
        if not (flags.ctrl and flags.alt and flags.shift) then pauseHeld = false end
        return false
    end
    local code = event:getKeyCode()
    if code ~= keycodes.p then return false end
    if kind == events.keyUp and pausePending then
        pauseHeld, pausePending = false, false
        return true
    end
    if kind ~= events.keyDown then return false end
    if flags.ctrl and flags.alt and flags.shift and not flags.cmd and not flags.fn then
        if not pauseHeld then M.setEnabled(not enabled, notify) end
        pauseHeld, pausePending = true, true
        pending[code] = nil
        return true
    end
    pauseHeld, pausePending = false, false
    return false
end

-- Modify key-down/up in place: preserve repeat, timestamp and Deskflow source.
-- Track the matching key-up even if Ctrl is released or the front app changes.
local function onKey(event)
    if M.handleShortcut(event) then return true end
    if event:getType() == events.flagsChanged then return false end
    local code = event:getKeyCode()
    local mapping
    if event:getType() == events.keyUp then
        mapping = pending[code]
        pending[code] = nil
    else
        local flags = event:getFlags()
        if not enabled or flags.cmd then return false end
        local editing = textEditing and textMapping(code, flags)
        if not flags.ctrl and not flags.alt and not editing then return false end
        local app = hs.application.frontmostApplication()
        local bundleID = app and app:bundleID() or ""
        if excludedTerminals[bundleID] then
            pending[code] = nil
            return false
        end
        local isEditable = editing and not flags.ctrl and M.focusInfo(app).editable or false
        mapping = M.mappingFor(code, flags, bundleID, isEditable)
        pending[code] = mapping
    end
    if mapping then
        event:setKeyCode(mapping.code):setFlags(mapping.flags)
    end
    return false
end

M.tap = hs.eventtap.new({events.keyDown, events.keyUp, events.flagsChanged}, onKey)
M.menu = hs.menubar.new()

function M.status()
    return {
        enabled = enabled,
        altHistory = altHistory,
        textEditing = textEditing,
        pauseShortcut = M.pauseShortcut,
        ctrlScope = M.ctrlScope,
        terminalExclusions = {"com.apple.Terminal", "com.googlecode.iterm2"},
        version = M.version,
        accessibility = hs.accessibilityState(),
        secureInput = hs.eventtap.isSecureInputEnabled(),
        eventTap = M.tap:isEnabled(),
    }
end

local function refresh()
    local state = M.status()
    local title = "DF键✓"
    if not enabled then title = "DF键暂停"
    elseif not state.accessibility or not state.eventTap then title = "DF键!"
    elseif state.secureInput then title = "DF键锁" end
    if M.menu then
        M.menu:setTitle(title)
        M.menu:setTooltip("Ctrl 别名适用于终端以外的软件；Ctrl+Alt+Shift+P 暂停／恢复")
    end
end

local function showStatus(message)
    hs.timer.doAfter(0, function() hs.alert.show(message, {textSize = 20}, 0.9) end)
end

function M.setEnabled(value, notify)
    local changed = enabled ~= (value == true)
    enabled = value == true
    hs.settings.set("deskflowKeys.enabled", enabled)
    refresh()
    if changed and notify ~= false then showStatus(enabled and "DF：快捷键映射已恢复" or "DF：快捷键映射已暂停") end
end

function M.setTextEditing(value)
    textEditing = value == true
    hs.settings.set("deskflowKeys.textEditing", textEditing)
    refresh()
end

function M.setAltHistory(value)
    altHistory = value == true
    hs.settings.set("deskflowKeys.altHistory", altHistory)
    refresh()
end

if M.menu then
    M.menu:setMenu(function()
        local state = M.status()
        local items = {
            {title = (enabled and "暂停快捷键映射" or "恢复快捷键映射") .. "  Ctrl+Alt+Shift+P",
                fn = function() M.setEnabled(not enabled) end},
            {title = "Ctrl 别名：终端以外的软件（含 IDE／远程桌面）", disabled = true},
            {title = "终端、iTerm 保留原有按键", disabled = true},
            {title = "文字编辑增强（Ctrl 全局；Home/End 仅编辑区）", checked = textEditing,
                fn = function() M.setTextEditing(not textEditing) end},
            {title = "Ctrl+←/→ 按词移动；加 Shift 选择", disabled = true},
            {title = "Home/End 行首尾；加 Ctrl 到文稿首尾", disabled = true},
            {title = "Ctrl+Backspace 删除前一个词", disabled = true},
            {title = "Alt+←/→ 浏览器、Finder 后退/前进", checked = altHistory,
                fn = function() M.setAltHistory(not altHistory) end},
            {title = "关闭上项即可保留 Option+方向键移动光标", disabled = true},
            {title = "-"},
            {title = "Ctrl+C/V/A/X/Z/Y/S/F/N/O/P/W → Mac 对应操作", disabled = true},
            {title = "Ctrl+T/L/R、Ctrl+Shift+T → 对应 Command 操作", disabled = true},
            {title = "Ctrl+空格 → 系统原有输入法切换", disabled = true},
            {title = "网页／IDE 内嵌终端需要原 Ctrl 操作时先暂停", disabled = true},
        }
        if not state.accessibility then
            table.insert(items, {title = "需要开启 Hammerspoon 辅助功能权限", disabled = true})
        elseif state.secureInput then
            table.insert(items, {title = "安全输入启用中；离开密码框后自动恢复", disabled = true})
        end
        table.insert(items, {title = "-"})
        table.insert(items, {title = "重新加载配置", fn = hs.reload})
        return items
    end)
end

-- Recover after sleep or the user granting Accessibility permission.
M.health = hs.timer.doEvery(5, function()
    if hs.accessibilityState() and not hs.eventtap.isSecureInputEnabled() and not M.tap:isEnabled() then
        pending = {}
        pauseHeld, pausePending = false, false
        M.tap:start()
    end
    refresh()
end)
if hs.accessibilityState() then M.tap:start() end
refresh()
return M
