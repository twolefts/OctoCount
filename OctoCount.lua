local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

local function SetSize(frame, width, height)
    frame:SetWidth(width)
    frame:SetHeight(height)
end

local function ApplyBackdrop(frame, red, green, blue, alpha)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropBorderColor(.9, .8, .5, 1)
    frame:SetBackdropColor(red, green, blue, alpha)
end

local function EnableDragging(frame, controlOnly)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame.controlDrag = controlOnly
    frame:SetScript("OnDragStart", function()
        if not this.controlDrag or IsControlKeyDown() then
            this:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
end

local function CreatePanelButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    SetSize(button, width, 20)
    button:SetText(text)
    return button
end

local function HideTooltip()
    GameTooltip:Hide()
end

local OctoCount = CreateFrame("Button", "OctoCount", Minimap)
OctoCount:Hide()
OctoCount:SetFrameLevel(64)
OctoCount:SetFrameStrata("MEDIUM")
SetSize(OctoCount, 36, 23)
ApplyBackdrop(OctoCount, .4, .4, .4, 1)

OctoCount:SetClampedToScreen(true)
EnableDragging(OctoCount, true)
OctoCount:SetUserPlaced(true)
OctoCount:RegisterForClicks("LeftButtonUp", "RightButtonDown")
OctoCount:SetScript("OnClick", function()
    if (arg1 == "RightButton" and IsControlKeyDown()) then
        this:SetUserPlaced(false)            
        OctoCount:Position()
    elseif (arg1 == "LeftButton" and not IsControlKeyDown()) then
        OctoCount:ToggleGraph()
    end
end)

function OctoCount:Position()
    OctoCount:ClearAllPoints()
    OctoCount:SetPoint("TOP", Minimap, "BOTTOM", 0, -12)
end

OctoCount.text = OctoCount:CreateFontString("Status", "LOW", "GameFontNormal")
OctoCount.text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
OctoCount.text:SetPoint("RIGHT", OctoCount, "RIGHT", -5, 1)
OctoCount.text:SetFontObject(GameFontWhite)
OctoCount.text:SetText("0")

OctoCount.icon = OctoCount:CreateTexture(nil, 'ARTWORK')
SetSize(OctoCount.icon, 13, 13)
OctoCount.icon:SetPoint("LEFT", OctoCount, "LEFT", 5, 0)
OctoCount.icon:SetTexture("Interface\\Addons\\OctoCount\\img\\octo.tga")

local refreshRemaining = 1
local onlineCount
local maxCount
local highCount
local lowCount
local queried
local queriedTime = 0
local queryMatched
local disabled
local validated
local QUERY_TIMEOUT = 5
local SERIES = {
    minute = { key = "minutes", seconds = 60, limit = 120, format = "%d %b %Y %H:%M", tooltip = "Players online" },
    hour = { key = "hours", seconds = 3600, limit = 168, format = "%d %b %Y %H:00", tooltip = "Hourly average" },
    day = { key = "days", seconds = 86400, limit = 30, format = "%d %b %Y", tooltip = "Daily average" }
}
local DETAIL_INTERVALS = { 1, 5, 15, 30, 60 }
local databaseReady
local EMPTY_DATA = {}
local currentRealm
local currentData

local function GetDayStart(timestamp)
    local hour = tonumber(date("%H", timestamp)) or 0
    local minute = tonumber(date("%M", timestamp)) or 0
    local second = tonumber(date("%S", timestamp)) or 0
    return timestamp - hour * 3600 - minute * 60 - second
end

local function AddSample(config, timestamp, count)
    local data = currentData.series[config.key]
    local bucket
    if config.key == "days" then
        bucket = GetDayStart(timestamp)
    else
        bucket = math.floor(timestamp / config.seconds) * config.seconds
    end
    local size = table.getn(data)
    local last = data[size]

    if last and last.time == bucket then
        if config.key == "minutes" then
            last.count = count
            last.sum = count
            last.samples = 1
        else
            last.sum = (last.sum or last.count * (last.samples or 1)) + count
            last.samples = (last.samples or 1) + 1
            last.count = math.floor(last.sum / last.samples + .5)
        end
    else
        table.insert(data, { time = bucket, count = count, sum = count, samples = 1 })
        size = size + 1
    end

    local cutoff = bucket - (config.limit - 1) * config.seconds
    while size > 0 and (size > config.limit or data[1].time < cutoff) do
        table.remove(data, 1)
        size = size - 1
    end
end

function OctoCount:StoreCount(count, timestamp)
    if not databaseReady then return end
    count = tonumber(count)
    if not count then return end

    timestamp = timestamp or time()
    AddSample(SERIES.minute, timestamp, count)
    AddSample(SERIES.hour, timestamp, count)
    AddSample(SERIES.day, timestamp, count)

    local day = GetDayStart(timestamp)
    local minute = math.floor((timestamp - day) / SERIES.minute.seconds) + 1
    currentData.rawDays[day] = currentData.rawDays[day] or {}
    currentData.rawDays[day][minute] = count

    local cutoff = day - (SERIES.day.limit - 1) * SERIES.day.seconds
    local savedDay
    for savedDay in pairs(currentData.rawDays) do
        if savedDay < cutoff then
            currentData.rawDays[savedDay] = nil
        end
    end
end

local function InitializeDatabase()
    OctoCountDB = OctoCountDB or {}
    currentRealm = GetRealmName()
    if not currentRealm or currentRealm == "" then
        currentRealm = GetCVar("realmName")
    end
    currentRealm = currentRealm or "Unknown Realm"

    currentData = OctoCountDB[currentRealm]
    if not currentData then
        currentData = {
            series = { minutes = {}, hours = {}, days = {} },
            rawDays = {}
        }
        OctoCountDB[currentRealm] = currentData
    end

    currentData.series = currentData.series or {}
    currentData.series.minutes = currentData.series.minutes or {}
    currentData.series.hours = currentData.series.hours or {}
    currentData.series.days = currentData.series.days or {}
    currentData.rawDays = currentData.rawDays or {}
    databaseReady = true
end

function OctoCount:GetGraphData(mode)
    if not databaseReady then return EMPTY_DATA end
    local config = SERIES[mode] or SERIES.minute
    return currentData.series[config.key]
end

function OctoCount:GetDayData(day, interval)
    if not databaseReady or not day then return EMPTY_DATA end

    local source = currentData.rawDays[day]
    local data = {}
    if not source then return data end

    local bucket
    for bucket = 0, math.floor(1440 / interval) - 1 do
        local total = 0
        local samples = 0
        local minute
        for minute = bucket * interval + 1, (bucket + 1) * interval do
            if source[minute] then
                total = total + source[minute]
                samples = samples + 1
            end
        end
        if samples > 0 then
            table.insert(data, {
                time = day + bucket * interval * 60,
                count = math.floor(total / samples + .5)
            })
        end
    end
    return data
end

local Controller = CreateFrame("Frame")
Controller:RegisterEvent("ADDON_LOADED")
Controller:SetScript("OnEvent", function()
    if arg1 == "OctoCount" then
        InitializeDatabase()
        this:UnregisterEvent("ADDON_LOADED")
    end
end)

local Graph = CreateFrame("Frame", "OctoCountGraph", UIParent)
SetSize(Graph, 380, 270)
Graph:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
Graph:SetFrameStrata("DIALOG")
EnableDragging(Graph)
ApplyBackdrop(Graph, .05, .05, .05, .95)
Graph:Hide()
Graph.mode = "minute"
Graph.interval = 60
Graph.points = {}

Graph.title = Graph:CreateFontString(nil, "OVERLAY", "GameFontNormal")
Graph.title:SetPoint("TOP", Graph, "TOP", 0, -12)
Graph.title:SetText("Players Online History")

Graph.titleLine = Graph:CreateTexture(nil, "ARTWORK")
Graph.titleLine:SetTexture(.9, .8, .5, .65)
Graph.titleLine:SetPoint("TOPLEFT", Graph, "TOPLEFT", 12, -32)
Graph.titleLine:SetPoint("TOPRIGHT", Graph, "TOPRIGHT", -12, -32)
Graph.titleLine:SetHeight(1)

Graph.maxLabel = Graph:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
Graph.maxLabel:SetPoint("TOPLEFT", Graph, "TOPLEFT", 12, -96)
Graph.minLabel = Graph:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
Graph.minLabel:SetPoint("BOTTOMLEFT", Graph, "BOTTOMLEFT", 12, 28)
Graph.timeLabel = Graph:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
Graph.timeLabel:SetPoint("BOTTOM", Graph, "BOTTOM", 0, 10)

Graph.close = CreateFrame("Button", nil, Graph, "UIPanelCloseButton")
Graph.close:SetPoint("TOPRIGHT", Graph, "TOPRIGHT", -3, -3)

local GRAPH_MODES = {
    { text = "Minutes", mode = "minute" },
    { text = "Hours", mode = "hour" },
    { text = "Days", mode = "day" }
}
Graph.modeButtons = {}
local modeAnchor
local modeIndex
for modeIndex = 1, table.getn(GRAPH_MODES) do
    local mode = GRAPH_MODES[modeIndex]
    local button = CreatePanelButton(Graph, mode.text, 65)
    if modeAnchor then
        button:SetPoint("LEFT", modeAnchor, "RIGHT", 4, 0)
    else
        button:SetPoint("TOPLEFT", Graph, "TOPLEFT", 12, -40)
    end
    button.mode = mode.mode
    button:SetScript("OnClick", function()
        Graph.mode = this.mode
        OctoCount:DrawGraph()
    end)
    Graph.modeButtons[modeIndex] = button
    modeAnchor = button
end

Graph.backButton = CreatePanelButton(Graph, "Back", 45)
Graph.backButton:SetPoint("TOPLEFT", Graph, "TOPLEFT", 12, -66)
Graph.backButton:SetScript("OnClick", function()
    Graph.mode = "day"
    OctoCount:DrawGraph()
end)
Graph.backButton:Hide()

Graph.detailButtons = {}
local detailAnchor = Graph.backButton
local detailIndex
for detailIndex = 1, table.getn(DETAIL_INTERVALS) do
    local detailButton = CreatePanelButton(Graph, "", 42)
    detailButton:SetPoint("LEFT", detailAnchor, "RIGHT", 3, 0)
    detailButton.interval = DETAIL_INTERVALS[detailIndex]
    if detailButton.interval == 60 then
        detailButton:SetText("1h")
    else
        detailButton:SetText(detailButton.interval .. "m")
    end
    detailButton:SetScript("OnClick", function()
        Graph.interval = this.interval
        OctoCount:DrawGraph()
    end)
    detailButton:Hide()
    Graph.detailButtons[detailIndex] = detailButton
    detailAnchor = detailButton
end

local function GraphPointOnEnter()
    GameTooltip:ClearLines()
    GameTooltip:SetOwner(this, ANCHOR_RIGHT)
    GameTooltip:AddLine(date(this.dateFormat, this.timestamp))
    GameTooltip:AddDoubleLine(this.tooltip, OctoCount.Commas(this.count) .. " players", 1, 1, 1, 1, 1, 1)
    if this.mode == "day" then
        GameTooltip:AddLine("Click to inspect this day", .9, .8, .5)
    end
    GameTooltip:Show()
end

local function GraphPointOnClick()
    if this.mode == "day" then
        GameTooltip:Hide()
        Graph.selectedDay = this.timestamp
        Graph.mode = "detail"
        OctoCount:DrawGraph()
    end
end

local function CreateGraphPoint()
    local point = CreateFrame("Button", nil, Graph)
    point:RegisterForClicks("LeftButtonUp")
    point.texture = point:CreateTexture(nil, "ARTWORK")
    point.texture:SetAllPoints(point)
    point.texture:SetTexture(.63, .31, 1)
    point:SetScript("OnEnter", GraphPointOnEnter)
    point:SetScript("OnLeave", HideTooltip)
    point:SetScript("OnClick", GraphPointOnClick)
    return point
end

function OctoCount:DrawGraph()
    local detailMode = Graph.mode == "detail"
    local data
    if detailMode then
        data = OctoCount:GetDayData(Graph.selectedDay, Graph.interval)
        Graph.title:SetText((currentRealm or "Unknown Realm") .. " - " .. date("%d %b %Y", Graph.selectedDay))
        Graph.backButton:Show()
    else
        data = OctoCount:GetGraphData(Graph.mode)
        Graph.title:SetText("Players Online - " .. (currentRealm or "Unknown Realm"))
        Graph.backButton:Hide()
    end

    local buttonIndex
    for buttonIndex = 1, table.getn(Graph.detailButtons) do
        if detailMode then
            Graph.detailButtons[buttonIndex]:Show()
        else
            Graph.detailButtons[buttonIndex]:Hide()
        end
    end

    local count = table.getn(data)
    local i
    local minimum
    local maximum

    for i = 1, table.getn(Graph.points) do
        Graph.points[i]:Hide()
    end

    if count == 0 then
        Graph.maxLabel:SetText("No saved data yet")
        Graph.minLabel:SetText("")
        if detailMode then
            Graph.timeLabel:SetText("No minute data saved for this day")
        else
            Graph.timeLabel:SetText("Counts are saved once per minute")
        end
        return
    end

    for i = 1, count do
        if not minimum or data[i].count < minimum then minimum = data[i].count end
        if not maximum or data[i].count > maximum then maximum = data[i].count end
    end

    local range = maximum - minimum
    if range < 1 then range = 1 end
    local plotLeft = 48
    local plotBottom = 32
    local plotWidth = 318
    local plotHeight = 125
    local pointWidth = math.min(8, math.max(1, math.floor(plotWidth / math.max(count, 1)) - 1))
    local timeStart = data[1].time
    local timeEnd = data[count].time
    if detailMode then
        timeStart = Graph.selectedDay
        timeEnd = Graph.selectedDay + SERIES.day.seconds - Graph.interval * SERIES.minute.seconds
    end
    local timeRange = timeEnd - timeStart

    for i = 1, count do
        local point = Graph.points[i]
        if not point then
            point = CreateGraphPoint()
            Graph.points[i] = point
        end
        local x
        if timeRange < 1 then
            x = plotLeft + (plotWidth - pointWidth) / 2
        else
            x = plotLeft + ((data[i].time - timeStart) / timeRange) * (plotWidth - pointWidth)
        end
        local height = 3 + ((data[i].count - minimum) / range) * (plotHeight - 3)
        point:ClearAllPoints()
        point:SetPoint("BOTTOMLEFT", Graph, "BOTTOMLEFT", x, plotBottom)
        SetSize(point, pointWidth, height)
        point.timestamp = data[i].time
        point.count = data[i].count
        point.mode = Graph.mode
        if detailMode then
            point.dateFormat = "%d %b %Y %H:%M"
            if Graph.interval == 1 then
                point.tooltip = "Players online"
            elseif Graph.interval == 60 then
                point.tooltip = "Hourly average"
            else
                point.tooltip = Graph.interval .. " minute average"
            end
        else
            local config = SERIES[Graph.mode] or SERIES.minute
            point.dateFormat = config.format
            point.tooltip = config.tooltip
        end
        point:Show()
    end

    Graph.maxLabel:SetText(OctoCount.Commas(maximum))
    Graph.minLabel:SetText(OctoCount.Commas(minimum))
    local firstTime = date("%d %b %H:%M", timeStart)
    local lastTime = date("%d %b %H:%M", timeEnd)
    Graph.timeLabel:SetText(firstTime .. "  -  " .. lastTime)
end

function OctoCount:ToggleGraph()
    if Graph:IsVisible() then
        Graph:Hide()
    else
        OctoCount:DrawGraph()
        Graph:Show()
    end
end

OctoCount.Commas = function(number)
    local formatted = tostring(math.floor(tonumber(number) or 0))
    local sign = ""
    local result = ""

    if string.sub(formatted, 1, 1) == "-" then
        sign = "-"
        formatted = string.sub(formatted, 2)
    end
    while string.len(formatted) > 3 do
        result = "," .. string.sub(formatted, -3) .. result
        formatted = string.sub(formatted, 1, -4)
    end
    return sign .. formatted .. result
end

local function UpdateCount(online, maximum)
    onlineCount = tonumber(online)
    maxCount = tonumber(maximum)
    if not onlineCount or not maxCount then return end

    if not validated then
        validated = true
        OctoCount:Show()
        DEFAULT_CHAT_FRAME:AddMessage("|cffa050ffOcto|rCount Loaded!")
    end

    OctoCount:StoreCount(onlineCount)
    OctoCount:UpdateText(onlineCount)

    if not highCount then
        highCount = onlineCount
        lowCount = onlineCount
    else
        highCount = math.max(highCount, onlineCount)
        lowCount = math.min(lowCount, onlineCount)
    end

    if Graph:IsVisible() then
        OctoCount:DrawGraph()
    end
end

function OctoCount:UpdateText(count)
    count = OctoCount.Commas(count)
    OctoCount.text:SetText(count)
    OctoCount:SetWidth(27 + math.ceil(OctoCount.text:GetStringWidth()))
end

function OctoCount:Disable(reason)
    if disabled then return end
    disabled = true
    queried = nil
    Controller:SetScript("OnUpdate", nil)
    self:Hide()
    Graph:Hide()
    DEFAULT_CHAT_FRAME:AddMessage("|cffa050ffOcto|cffe6b300Count|r: " .. reason)
end

function OctoCount:ServerInfo()
    if disabled then return end
    SendChatMessage(".server info")
    queriedTime = GetTime()
    queried = true
    queryMatched = nil
end

-- Example of Octo WoW .server info
-- Players online: 1111 (0 queued). Max online: 2222 (33 queued).
-- Server uptime: 11 Hours 22 Minutes 33 Seconds.
-- Server Time: Mon, 01.01.2023 01:02:03

local HookChatFrame_OnEvent = ChatFrame_OnEvent
function ChatFrame_OnEvent(event)    
    if event == "CHAT_MSG_SYSTEM" and queried then
        if string.find(arg1, "^Players online:") then
            local _, _, online, maximum = string.find(arg1, "^Players online:%s*(%d+).-Max online:%s*(%d+)")

            if online and maximum then
                queryMatched = true
                UpdateCount(online, maximum)
            else
                OctoCount:Disable("The .server info response format is not supported.")
            end
            return
        elseif string.find(arg1, "^Server uptime:") then
            return
        elseif string.find(arg1, "^Server Time:") then
            queried = nil
            if not queryMatched then
                OctoCount:Disable("The .server info response did not include a player count.")
            end
            return
        end
    end
    HookChatFrame_OnEvent(event)
end

Controller:SetScript("OnUpdate", function()
    if queried then
        if GetTime() - queriedTime > QUERY_TIMEOUT then
            queried = nil
            if not queryMatched then
                OctoCount:Disable("No compatible .server info response was received.")
            end
        end
        return
    end

    refreshRemaining = refreshRemaining - arg1
    if refreshRemaining <= 0 then
        OctoCount:ServerInfo()
        refreshRemaining = 60
    end
end)

OctoCount:SetScript("OnEnter", function()
    if not highCount then return end
    GameTooltip:ClearLines()
    GameTooltip:SetOwner(this, ANCHOR_BOTTOMLEFT)
    GameTooltip:AddLine((currentRealm or "Unknown Realm") .. ": " .. OctoCount.Commas(onlineCount) .. " online")
    GameTooltip:AddLine("Session range: " .. OctoCount.Commas(lowCount) .. " - " .. OctoCount.Commas(highCount), .8, .8, .8)
    GameTooltip:AddLine("Click for history", .9, .8, .5)
    GameTooltip:Show()
end)

OctoCount:SetScript("OnLeave", HideTooltip)

OctoCount:Position()
OctoCount:UpdateText(0)
