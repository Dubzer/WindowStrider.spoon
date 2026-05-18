--- === WindowStrider ===
---
--- Keyboard-driven window switcher that cycles through windows of specified applications.
---

local obj = {}
obj.__index = obj

obj.name = "WindowStrider"
obj.version = "2.2"
obj.author = "Dubzer"
obj.license = "MIT"

require("hs.axuielement")

local log = hs.logger.new("WindowStrider")
local prettyAlert = dofile(hs.spoons.resourcePath("prettyAlert.lua"))
local formatHotkey = dofile(hs.spoons.resourcePath("formatHotkey.lua"))

local delayLogThreshold = 0.03
local tinsert = table.insert

---@alias BundleID string
---@alias BundleIDList BundleID[]

---@class WindowEntry
---@field id number
---@field window hs.window
---@field groupKey string|nil
---@field isTabbed boolean|nil

---@class TabGroupCacheEntry
---@field tabCount integer|nil
---@field windowCount integer

---@alias TabGroupCache table<string, TabGroupCacheEntry>

---@class TargetListStats
---@field tabScanCount integer
---@field tabScanTime number

-- keep references to listeners to avoid getting garbage collected
local _keep = {}
---@generic T
---@param it T
---@return T
local function keep(it)
    tinsert(_keep, it)
    return it
end

---@param apps BundleIDList
---@return table<BundleID, boolean>
local function appSetFor(apps)
    local appSet = {}
    for _, app in ipairs(apps) do
        appSet[app] = true
    end
    return appSet
end

---@param apps BundleIDList
---@return WindowEntry[]
local function getWindowEntriesWithTabGroups(apps)
    ---@type WindowEntry[]
    local r = {}

    if #apps == 0 then return r end

    for _, bundleID in ipairs(apps) do
        for _, application in ipairs(hs.application.applicationsForBundleID(bundleID)) do
            ---@type WindowEntry[]
            local windowEntries = {}

            for _, window in ipairs(application:allWindows()) do
                if window:isStandard() then
                    local id = window:id()
                    if id then
                        tinsert(windowEntries, {
                            id = id,
                            window = window,
                        })
                    end
                end
            end

            if #windowEntries == 1 then
                tinsert(r, windowEntries[1])
            elseif #windowEntries > 1 then
                for _, entry in ipairs(windowEntries) do
                    local frame = entry.window:frame()
                    entry.groupKey = ("%s:%s,%s,%s,%s"):format(application:pid(), frame.x, frame.y, frame.w, frame.h)
                    tinsert(r, entry)
                end
            end
        end
    end

    return r
end

-- note: AXUIElement API is slow
---@param window hs.window
---@return integer|nil
local function fetchWindowTabCount(window)
    local element = hs.axuielement.windowElement(window)
    if not element then return nil end

    local children = element:attributeValue("AXChildren")
    if not children then return nil end

    for _, child in ipairs(children) do
        if child:attributeValue("AXRole") == "AXTabGroup" then
            local tabGroupChildren = child:attributeValue("AXChildren")
            if not tabGroupChildren then return nil end
            return #tabGroupChildren
        end
    end
end

---@param apps BundleIDList
---@param tabGroupCache TabGroupCache
---@param reverse boolean
---@return WindowEntry[] windows
---@return TargetListStats stats
local function getTargetList(apps, tabGroupCache, reverse)
    ---@type TargetListStats
    local stats = {
        tabScanCount = 0,
        tabScanTime = 0,
    }

    local windows = getWindowEntriesWithTabGroups(apps)
    ---@type table<string, WindowEntry[]>
    local groups = {}

    for _, w in ipairs(windows) do
        if w.groupKey then
            local group = groups[w.groupKey]
            if not group then
                group = {}
                groups[w.groupKey] = group
            end
            tinsert(group, w)
        end
    end

    ---@type table<number, true>
    local ignoredWindowIds = {}

    for _, group in pairs(groups) do
        if #group > 1 then
            local activeEntry = group[1]
            local cached = tabGroupCache[activeEntry.groupKey]
            local tabCount = nil

            if cached and cached.tabCount and cached.tabCount >= #group then
                tabCount = cached.tabCount
            elseif cached and cached.windowCount == #group then
                tabCount = cached.tabCount
            else
                local scanStart = hs.timer.secondsSinceEpoch()

                tabCount = fetchWindowTabCount(activeEntry.window)

                stats.tabScanTime = stats.tabScanTime + hs.timer.secondsSinceEpoch() - scanStart
                stats.tabScanCount = stats.tabScanCount + 1

                tabGroupCache[activeEntry.groupKey] = {
                    tabCount = tabCount,
                    windowCount = #group,
                }
            end

            -- basically ignore all tabs except the first one
            -- to avoid cycling between tabs in the same window
            if tabCount and tabCount >= #group then
                group[1].isTabbed = true
                for index = 2, #group do
                    ignoredWindowIds[group[index].id] = true
                end
            end
        end
    end

    local visibleWindows = {}
    for _, w in ipairs(windows) do
        if not ignoredWindowIds[w.id] then
            tinsert(visibleWindows, w)
        end
    end

    if reverse then
        local reversed = {}
        for index = #visibleWindows, 1, -1 do
            tinsert(reversed, visibleWindows[index])
        end
        return reversed, stats
    end

    return visibleWindows, stats
end

---@param w WindowEntry
local function focusWindow(w)
    if w.isTabbed then
        w.window:raise()
        local application = w.window:application()
        if application then
            application:activate(false)
            return
        end
    end

    w.window:focus()
end

---@class CycleState
---@field visited table<number, boolean> @Set-like table keyed by window id
---@field count integer                 @Number of windows currently in `visited`
---@field reversed boolean              @Whether the list should be traversed in reverse
local CycleState = {}
CycleState.__index = CycleState

function CycleState.new()
    ---@type CycleState
    local self = setmetatable({}, CycleState)
    self:reset()
    return self
end

function CycleState:reset()
    self.visited = {}
    self.count   = 0
    self.reversed = false
end

---@param windowId number
function CycleState:add(windowId)
    if self.visited[windowId] == nil then
        self.visited[windowId] = true
        self.count = self.count + 1
    end
end

---@param apps BundleIDList
---@return fun() cycleWindows
local function createWindowSwitcher(apps)
    local appSet = appSetFor(apps)
    ---@type TabGroupCache
    local tabGroupCache = {}
    local cycleState = CycleState.new()

    return function()
        local starttime = hs.timer.secondsSinceEpoch()

        local focused = hs.window.focusedWindow()
        if focused and focused:isFullScreen() then
            return
        end

        local focusedApp = focused and focused:application()
        local cycling = focusedApp and appSet[focusedApp:bundleID()] == true

        local targetListStart = hs.timer.secondsSinceEpoch()
        local windows, targetListStats = getTargetList(apps, tabGroupCache, cycleState.reversed)
        local targetListTime = hs.timer.secondsSinceEpoch() - targetListStart

        -- launch the app if no windows are found
        if #windows == 0 then
            hs.application.open(apps[1])
            return
        end

        local focusedId = focused and focused:id()
        if cycling then
            assert(focusedId ~= nil)
            cycleState:add(focusedId)

            -- wrap around if we've visited all windows
            if cycleState.count >= #windows then
                cycleState:reset()
                cycleState:add(focusedId)
                cycleState.reversed = true
            end
        else
            cycleState:reset()
        end

        local focusTime = 0

        -- find first unvisited window
        for _, w in ipairs(windows) do
            if cycleState.visited[w.id] == nil then
                if not focused or w.id ~= focusedId then
                    local focusStart = hs.timer.secondsSinceEpoch()

                    focusWindow(w)

                    focusTime = hs.timer.secondsSinceEpoch() - focusStart
                end
                cycleState:add(w.id)
                break
            end
        end

        local timeTaken = hs.timer.secondsSinceEpoch() - starttime
        if timeTaken > delayLogThreshold then
            log.w(("delay: %.1fms total, %.1fms target list, %.1fms focus, %.1fms ax (%d), %d targets"):format(
                timeTaken * 1000,
                targetListTime * 1000,
                focusTime * 1000,
                targetListStats.tabScanTime * 1000,
                targetListStats.tabScanCount,
                #windows
            ))
        end
    end
end

--- Binds a hotkey to switch between windows of the specified applications.
---@param mods string[] The modifiers for the hotkey (e.g., {"option"})
---@param key string The key for the hotkey (e.g., "2")
---@param apps BundleIDList A list of application bundle IDs (e.g., {"com.brave.Browser"})
function obj:bindHotkey(mods, key, apps)
    local cycleWindows = createWindowSwitcher(apps)
    keep(hs.hotkey.bind(mods, key, cycleWindows))
    return self
end

--- Binds a hotkey for dynamic app pinning.
--- When pressed with the record modifier, pins the currently focused app.
--- When pressed without, cycles through windows of the pinned app.
---@param mods string[] The base modifiers for the hotkey (e.g., {"option"})
---@param key string The key for the hotkey (e.g., "1")
---@param recordMod string Additional modifier for recording (e.g., "shift")
function obj:bindPinHotkey(mods, key, recordMod)
    ---@type BundleID|nil
    local pinnedBundleID = nil
    ---@type fun()|nil
    local cycleWindows = nil

    local recordModifiers = {}
    for _, mod in ipairs(mods) do
        tinsert(recordModifiers, mod)
    end
    tinsert(recordModifiers, recordMod)

    keep(hs.hotkey.bind(recordModifiers, key, function()
        local focused = hs.window.focusedWindow()
        if not focused then
            prettyAlert("⚠️", "No focused window to pin")
            return
        end

        local app = focused:application()
        if not app then
            log.e("focused:application() returned nil")
            return
        end

        pinnedBundleID = app:bundleID()
        cycleWindows = createWindowSwitcher({pinnedBundleID})

        prettyAlert("📌", app:name() .. " → " .. formatHotkey(mods, key))
    end))

    -- Switch hotkey: cycles through pinned app's windows
    keep(hs.hotkey.bind(mods, key, function()
        if not pinnedBundleID then
            prettyAlert("⚠️", "No app pinned")
            return
        end

        cycleWindows()
    end))

    return self
end

return obj
