-- Deepwoken Script for Matcha (Standard)
-- Player/Mob/NPC/Artifact ESP, Mob Filter, Nearby Box + Staff Warning,
-- Proximity Notify, Fullbright, No Fog, Optimization

-------------------------------
-- CRASH LOG: writes each startup step to dw_crashlog.txt in your Matcha
-- workspace folder. Files survive a crash, so the LAST line in that file
-- is the step that killed Matcha.
-------------------------------
pcall(function() writefile("dw_crashlog.txt", "DW crash log\n") end)
local loggedOnce = {}
local function logStep(msg, once)
    if once then
        local tag = string.match(msg, "^(%S+)") or msg
        if loggedOnce[tag] then return end
        loggedOnce[tag] = true
    end
    pcall(function() appendfile("dw_crashlog.txt", string.format("%.2f  %s\n", tick(), msg)) end)
    print("[DW] " .. msg)
end
logStep("1 script started")

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-------------------------------
-- BASIC HELPERS
-------------------------------

logStep("2 services ok")
local FONT = nil
pcall(function() FONT = Drawing.Fonts.System end)

local function V(id, default)
    local ok, val = pcall(function() return UI.GetValue(id) end)
    if ok and val ~= nil then return val end
    return default
end

local reported = {}
local function report(tag, err)
    local msg = tag .. ": " .. tostring(err)
    if not reported[msg] then
        reported[msg] = true
        warn("[DW] " .. msg)
    end
end

local function clamp(x, a, b)
    if x < a then return a end
    if x > b then return b end
    return x
end

local function newText(size, color, center)
    local t = Drawing.new("Text")
    t.Text = ""
    if not pcall(function() t.Size = size end) then
        pcall(function() t.FontSize = size end)
    end
    t.Color = color
    t.Outline = true
    t.Center = center ~= false
    t.Visible = false
    if FONT then pcall(function() t.Font = FONT end) end
    pcall(function() t.ZIndex = 3 end)
    return t
end

local function newSquare(color, filled, z)
    local s = Drawing.new("Square")
    s.Color = color
    s.Filled = filled
    s.Visible = false
    pcall(function() s.ZIndex = z or 1 end)
    return s
end

local function newLine(color)
    local l = Drawing.new("Line")
    l.Color = color
    l.Thickness = 1
    l.Visible = false
    pcall(function() l.ZIndex = 2 end)
    return l
end

local function kill(obj)
    if obj then pcall(function() obj:Remove() end) end
end

-- Matcha returns a NEW wrapper object every time you read an instance, so
-- instances can't be used as table keys. Use the memory address instead.
local function keyOf(inst)
    local ok, n = pcall(function() return inst.Name end)
    if ok and n then return n end
    return tostring(inst)
end

-- Stepped HP colors: green > yellow > orange > red
local C_GREEN  = Color3.fromRGB(60, 230, 90)
local C_YELLOW = Color3.fromRGB(240, 220, 50)
local C_ORANGE = Color3.fromRGB(255, 140, 30)
local C_RED    = Color3.fromRGB(235, 50, 50)
-- User-changeable colors (set by the color pickers, saved in the config)
local COL = {
    player   = Color3.fromRGB(235, 235, 235),
    staff    = Color3.fromRGB(255, 110, 0),
    mob      = Color3.fromRGB(255, 130, 130),
    artifact = Color3.fromRGB(80, 200, 255),
    chest    = Color3.fromRGB(255, 200, 40),
    npcesp   = Color3.fromRGB(255, 225, 130),
    ingred   = Color3.fromRGB(120, 255, 160),
    box      = Color3.fromRGB(90, 90, 110),
    parry    = Color3.fromRGB(60, 230, 90),
}

local function hpColor(pct)
    if pct > 0.75 then return C_GREEN end
    if pct > 0.50 then return C_YELLOW end
    if pct > 0.25 then return C_ORANGE end
    return C_RED
end

local function cleanMobName(name)
    local n = string.gsub(name, "^%.", "")
    n = string.gsub(n, "%d+$", "")
    n = string.gsub(n, "_", " ")
    return n
end

local function safeId(s)
    return (string.gsub(string.lower(s), "[^%w]", "_"))
end

-------------------------------
-- MOD LIST
-------------------------------

local modList = {
    [4416634] = "Owner", [151239872] = "Owner",
    [143237270] = "Developer", [122538624] = "Developer", [68362141] = "Developer",
    [29272034] = "Developer", [146109955] = "Developer", [1427798376] = "Developer",
    [10190020] = "Developer", [167825083] = "Developer", [10717875] = "Developer",
    [9144458] = "Developer", [8925483] = "Developer", [8132835] = "Developer",
    [432848746] = "Developer", [3254] = "Developer", [1026894079] = "Developer",
    [1185647] = "Developer", [29407034] = "Developer",
    [51453069] = "Mod Lead", [23489822] = "Mod Lead", [15293614] = "Mod Lead",
    [341792] = "Mod Lead", [27354397] = "Mod Lead",
    [35852847] = "Sr Mod", [82905358] = "Sr Mod", [28163453] = "Sr Mod",
    [31181702] = "Sr Mod", [121058059] = "Sr Mod", [83785067] = "Sr Mod",
    [553986819] = "Sr Mod", [20469570] = "Sr Mod",
    [109892496] = "Mod", [122598575] = "Mod", [113695282] = "Mod", [51142252] = "Mod",
    [126208842] = "Mod", [18667798] = "Mod", [291380637] = "Mod", [117044513] = "Mod",
    [80808932] = "Mod", [55332463] = "Mod", [213565267] = "Mod", [10904620] = "Mod",
    [155817248] = "Mod", [95808320] = "Mod", [8233562] = "Mod", [245790632] = "Mod",
    [587468931] = "Mod", [101273010] = "Mod", [99196411] = "Mod", [15451529] = "Mod",
    [143052619] = "Mod", [117026263] = "Mod", [66934974] = "Mod", [44121665] = "Mod",
    [15695298] = "Mod", [13255300] = "Mod",
    [55944924] = "Jr Mod", [17054215] = "Jr Mod", [86913830] = "Jr Mod",
    [1269574560] = "Jr Mod", [1078018311] = "Jr Mod", [2975163959] = "Jr Mod",
    [195198267] = "Jr Mod", [198667286] = "Jr Mod", [70933833] = "Jr Mod",
    [412116471] = "Jr Mod", [1354276726] = "Jr Mod", [162870581] = "Jr Mod",
    [225329784] = "Jr Mod", [137969643] = "Jr Mod", [210958273] = "Jr Mod",
    [3438650762] = "Jr Mod", [77552243] = "Jr Mod", [593988103] = "Jr Mod",
    [16304417] = "Jr Mod",
    [5326301003] = "Observer", [163500404] = "Observer", [122019256] = "Observer",
    [492610478] = "Observer", [3129894313] = "Observer", [95976559] = "Observer",
    [7200829] = "Contractor", [570582890] = "Contractor", [146254221] = "Contractor",
    [40118429] = "Contractor", [15147688] = "Contractor", [35680196] = "Contractor",
    [48707829] = "Contributor", [14539037] = "Contributor", [202693941] = "Contributor",
    [15285997] = "Contributor", [56537645] = "Contributor", [276698027] = "Contributor",
    [1919162] = "Contributor", [45124920] = "Contributor",
}

-------------------------------
-- SHARED STATE
-------------------------------

local cfg = {}              -- settings cache, refreshed ~10x/sec
local entities = {}         -- [key] = entity (players + mobs from workspace.Live)
local objects = {}          -- [key] = object (artifacts, chests, npcs, etc.)
local mobTypes = {}         -- [typeName] = true (discovered)
local mobTypeList = {}      -- sorted list for UI (mobs present right now)
local mobTypeCounts = {}
local savedMobs = {}       -- mob checkbox values, kept even when that mob isn't around
local nearbyList = {}       -- players in range, sorted
local staffList = {}        -- staff in server
local myAnchor = nil
local myModel = nil
local frameDt = 1 / 60
local myTorso = nil
local posInfo = { gap = 0, usingCam = false }

-- Your real position. Checks your root part, torso, and camera. If your body
-- parts are far from the camera (fly / position scripts can leave them behind),
-- it measures from the camera instead so distances stay correct.
local function getMyPos()
    local camPos = nil
    pcall(function() camPos = workspace.CurrentCamera.CFrame.Position end)
    local best, bestGap = nil, math.huge
    for _, part in ipairs({ myAnchor, myTorso }) do
        if part then
            local ok, p = pcall(function() return part.Position end)
            if ok and p then
                local gap = camPos and (p - camPos).Magnitude or 0
                if gap < bestGap then best, bestGap = p, gap end
            end
        end
    end
    if best and (not camPos or bestGap <= (cfg.camGap or 80)) then
        posInfo.gap, posInfo.usingCam = bestGap, false
        return best
    end
    posInfo.gap = (bestGap < math.huge) and bestGap or -1
    posInfo.usingCam = camPos ~= nil
    return camPos or best
end
local camInfo = { focal = 500, vx = 1920, vy = 1080 }
local stats = { live = 0, drawn = 0, objects = 0 }
local lastErr = nil

-------------------------------
-- SETTINGS CACHE (UI.GetValue is slow-ish, don't call it per entity per frame)
-------------------------------

local function readSettings()
    cfg.esp       = V("dw_esp", false)
    cfg.mobesp    = V("dw_mobesp", false)
    cfg.npcesp    = V("dw_npcesp", false)
    cfg.artifact  = V("dw_artifact", false)
    cfg.chest     = V("dw_chest", false)
    cfg.misc      = V("dw_miscobj", false)
    cfg.ingred    = V("dw_ingred", false)
    cfg.playerdist = V("dw_playerdist", 5000)
    cfg.mobdist   = V("dw_mobdist", 1000)
    cfg.espdist   = math.max(cfg.playerdist, cfg.mobdist)
    cfg.smooth    = V("dw_smooth", true)
    cfg.smoothAmt = V("dw_smoothamt", 12)
    cfg.objdist   = V("dw_objdist", 1500)
    cfg.artdist   = V("dw_artdist", 20000)
    cfg.artalert  = V("dw_artalert", true)
    cfg.camGap    = V("dw_camgap", 80)
    cfg.maxdraw   = V("dw_maxdraw", 30)
    cfg.showDist  = V("dw_showdist", true)
    cfg.showHp    = V("dw_showhp", true)
    cfg.showUser  = V("dw_showuser", true)
    cfg.hpColorName = V("dw_hpcolorname", false)
    cfg.barDist   = V("dw_bardist", 200)
    cfg.parry     = V("dw_parry", false)
    cfg.parryCd   = V("dw_parrycd", 100) / 100
    cfg.parryKey  = V("dw_parrykey", 0)
    cfg.parryY    = V("dw_parryy", 25)
    cfg.parryReset = V("dw_parryreset", "CLIENT_SOUND_4954186776")
    cfg.parryResetOn = V("dw_parryreseton", true)
    cfg.parryWin  = V("dw_parrywin", 25) / 100
    cfg.nearby    = V("dw_nearby", false)
    cfg.prox      = V("dw_prox", false)
    cfg.proxdist  = V("dw_proxdist", 1000)
    cfg.mods      = V("dw_mods", true)
    cfg.bigwarn   = V("dw_bigwarn", true)
    cfg.status    = V("dw_status", true)
    cfg.lowimpact = V("dw_lowimpact", false)
    if cfg.lowimpact then
        cfg.maxdraw = math.min(cfg.maxdraw, 15)
        cfg.smooth = false
    end
end

-------------------------------
-- ENTITY ESP DRAWINGS
-------------------------------

local function makeDrawings(e)
    e.d = {
        name  = newText(13, Color3.fromRGB(235, 235, 235), true),
        info  = newText(12, Color3.fromRGB(200, 200, 200), true),
        barBg = newSquare(Color3.fromRGB(0, 0, 0), true, 1),
        bar   = newSquare(C_GREEN, true, 2),
        lines = {},
        last  = {},
    }
    for i = 1, 4 do e.d.lines[i] = newLine(Color3.fromRGB(0, 0, 0)) end
end

local function hideBar(d)
    d.barBg.Visible = false
    d.bar.Visible = false
    for i = 1, 4 do d.lines[i].Visible = false end
end

local function hideDrawings(e)
    local d = e.d
    if not d or not d.shown then return end
    d.name.Visible = false
    d.info.Visible = false
    hideBar(d)
    d.shown = false
end

local function freeDrawings(e)
    local d = e.d
    if not d then return end
    kill(d.name); kill(d.info); kill(d.barBg); kill(d.bar)
    for i = 1, 4 do kill(d.lines[i]) end
    e.d = nil
end

-------------------------------
-- REFRESH: heavy lookups, ~4x per second
-------------------------------

local proxAlerted = {}
local staffNotified = {}

local function refreshEntities()
    logStep("R1 first entity refresh", true)
    local stamp = tick()

    logStep("R1a camera", true)
    -- Camera info for size scaling
    pcall(function()
        local cam = workspace.CurrentCamera
        local vs = cam.ViewportSize
        local fov = cam.FieldOfView
        camInfo.vx, camInfo.vy = vs.X, vs.Y
        camInfo.focal = vs.Y / (2 * math.tan(math.rad(fov) / 2))
    end)

    logStep("R1b players", true)
    -- Players
    local byName = {}
    local staff = {}
    for _, p in ipairs(Players:GetPlayers()) do
        local pname = p.Name
        if pname then
            byName[pname] = p
            if pname ~= LocalPlayer.Name then
                local role = modList[p.UserId]
                if role then
                    local charName = nil
                    table.insert(staff, { id = p.UserId, name = pname, char = charName, role = role })
                end
            end
        end
    end
    staffList = staff

    -- Staff notify (once per staff member)
    if cfg.mods then
        for _, s in ipairs(staff) do
            if not staffNotified[s.id] then
                staffNotified[s.id] = true
                pcall(function() notify(s.name .. " is " .. s.role, "STAFF IN SERVER", 20) end)
            end
        end
    end

    local live = workspace:FindFirstChild("Live")
    if not live then return end

    logStep("R1c reading Live", true)
    local children = live:GetChildren()
    stats.live = #children
    logStep("R1d Live has " .. #children .. " models", true)

    -- My own anchor
    local me = live:FindFirstChild(LocalPlayer.Name)
    myModel = me
    myAnchor = me and me:FindFirstChild("HumanoidRootPart") or nil
    myTorso = me and me:FindFirstChild("Torso") or nil
    local myPos = getMyPos()

    local nearby = {}
    local filterCache = {}
    local usedKeys = {}
    local presentTypes = {}

    local processed = 0
    for _, model in ipairs(children) do
        processed = processed + 1
        if processed % 15 == 0 then wait() end
        local mname = model.Name
        if mname and mname ~= LocalPlayer.Name then
            local key = mname
            if usedKeys[key] then
                usedKeys[key] = usedKeys[key] + 1
                key = mname .. "#" .. usedKeys[key]
            else
                usedKeys[key] = 1
            end
            local e = entities[key]
            if not e then
                e = { key = key, model = model, name = mname }
                e.isMob = string.sub(mname, 1, 1) == "."
                if e.isMob then
                    e.mobType = cleanMobName(mname)
                    -- Rain skips these: hidden internal models, not real mobs
                    if string.find(string.lower(mname), "watcher", 1, true) then
                        e.hidden = true
                    end
                end
                entities[key] = e
            end
            e.stamp = stamp
            if e.isMob and not e.hidden and e.mobType then
                presentTypes[e.mobType] = (presentTypes[e.mobType] or 0) + 1
            end

            logStep("R1e first model: " .. tostring(mname), true)
            -- Resolve parts once (re-resolve if lost)
            if not e.anchor then
                e.anchor = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("Head")
            end
            if not e.hum then
                e.hum = model:FindFirstChild("Humanoid")
            end

            logStep("R1f parts found", true)
            -- Health (read 4x/sec, not every frame)
            e.pct, e.hp, e.maxhp = nil, nil, nil
            if e.hum then
                pcall(function()
                    local mx = e.hum.MaxHealth
                    local hp = e.hum.Health
                    if mx and mx > 0 then
                        e.pct = clamp(hp / mx, 0, 1)
                        e.hp, e.maxhp = hp, mx
                    end
                end)
            end

            logStep("R1g health read", true)
            -- Labels
            local player = byName[mname]
            e.player = player
            if e.isMob then
                e.label = e.mobType
                e.color = COL.mob
                e.role = nil
            elseif player then
                local charName = nil
                e.charName = charName
                e.role = modList[player.UserId]
                -- Deepwoken name first (like the leaderboard), username on line 2
                e.label = charName or mname
                e.username = mname
                if e.role then
                    e.label = "[" .. e.role .. "] " .. e.label
                    e.color = COL.staff
                else
                    e.color = COL.player
                end
            else
                e.label = mname
                e.color = Color3.fromRGB(200, 200, 255)
            end

            -- Distance + should we draw it?
            e.dist = nil
            if e.anchor and myPos then
                pcall(function() e.dist = (e.anchor.Position - myPos).Magnitude end)
            end

            local want = false
            local maxD = cfg.playerdist
            if e.isMob then
                want = cfg.mobesp and not e.hidden
                maxD = cfg.mobdist
                if want then
                    local f = filterCache[e.mobType]
                    if f == nil then
                        local id = "dw_mt_" .. safeId(e.mobType)
                        f = savedMobs[id]
                        if f == nil then f = V(id, nil) end
                        if f == nil then f = true end
                        filterCache[e.mobType] = f
                    end
                    want = f
                end
            else
                want = cfg.esp
            end
            e.want = want and e.dist ~= nil and e.dist <= maxD

            -- Nearby + proximity (players only)
            if player and e.dist then
                if e.dist <= cfg.proxdist then
                    table.insert(nearby, { name = mname, char = e.charName, dist = e.dist, role = e.role })
                    if cfg.prox and not proxAlerted[mname] then
                        proxAlerted[mname] = true
                        local who = e.charName and (mname .. " (" .. e.charName .. ")") or mname
                        pcall(function() notify(who .. " is " .. math.floor(e.dist) .. "m away", "Proximity", 4) end)
                    end
                elseif e.dist > cfg.proxdist + 200 then
                    proxAlerted[mname] = nil
                end
            end
        end
    end

    logStep("R1h all models done", true)
    local list = {}
    for t, _ in pairs(presentTypes) do table.insert(list, t) end
    table.sort(list)
    mobTypeList = list
    mobTypeCounts = presentTypes
    -- Keep only the N closest wanted entities
    local wanted = {}
    for _, e in pairs(entities) do
        if e.want then table.insert(wanted, e) end
    end
    table.sort(wanted, function(a, b) return a.dist < b.dist end)
    for i, e in ipairs(wanted) do
        if i > cfg.maxdraw then e.want = false end
    end

    -- Remove entities that left Live
    for key, e in pairs(entities) do
        if e.stamp ~= stamp then
            freeDrawings(e)
            entities[key] = nil
        end
    end

    table.sort(nearby, function(a, b) return a.dist < b.dist end)
    nearbyList = nearby
end

-------------------------------
-- OBJECT ESP (artifacts, chests, NPCs, campfires, bags, ingredients) ~every 2s
-------------------------------

local OBJ_STYLE = {
    BigArtifact = { label = "ARTIFACT", color = Color3.fromRGB(80, 200, 255), size = 15, flag = "artifact" },
    -- A freshly spawned artifact shows up in workspace.Thrown as "ForgeEffects"
    ForgeEffects = { label = "ARTIFACT", color = Color3.fromRGB(80, 200, 255), size = 15, flag = "artifact" },
    Chest       = { label = "Chest",    color = Color3.fromRGB(255, 200, 40), size = 12, flag = "chest" },
    Campfire    = { label = "Campfire", color = Color3.fromRGB(255, 120, 40), size = 12, flag = "misc" },
    BagDrop     = { label = "Bag",      color = Color3.fromRGB(200, 160, 255), size = 12, flag = "misc" },
    ExplodeCrate = { label = "Crate",   color = Color3.fromRGB(220, 180, 120), size = 12, flag = "misc" },
    BellMeteor  = { label = "Meteor",   color = Color3.fromRGB(255, 80, 200), size = 13, flag = "misc" },
    EventFeatherRef = { label = "Owl Feather", color = Color3.fromRGB(255, 255, 160), size = 12, flag = "misc" },
}

local function objPart(obj)
    local ok, isPart = pcall(function() return obj:IsA("BasePart") end)
    if ok and isPart then return obj end
    local p = nil
    pcall(function() p = obj.PrimaryPart end)
    return p or obj:FindFirstChildWhichIsA("BasePart")
end

local objNameCount = {}
local objectsPrimed = false   -- skip alerts for artifacts that already existed on load
local function addObject(found, obj, label, color, size, flag)
    local base = flag .. ":" .. keyOf(obj)
    local n = (objNameCount[base] or 0) + 1
    objNameCount[base] = n
    local key = base .. "#" .. n
    local o = objects[key]
    if not o then
        o = { key = key, obj = obj }
        objects[key] = o
    end
    if not o.part then
        o.part = objPart(obj)
        if not o.part then
            pcall(function()
                for i, d in ipairs(obj:GetDescendants()) do
                    if i > 60 then break end
                    if d:IsA("BasePart") then o.part = d break end
                end
            end)
        end
    end
    if not o.seen then
        o.seen = true
        if flag == "artifact" and objectsPrimed and cfg.artalert then
            pcall(function() notify("An artifact just spawned!", "Artifact", 6) end)
        end
    end
    o.label, o.color, o.size, o.flag = label, color, size, flag
    found[key] = true
end

local function refreshObjects()
    logStep("R2 first object refresh", true)
    local found = {}
    objNameCount = {}

    local thrown = workspace:FindFirstChild("Thrown")
    if thrown and (cfg.artifact or cfg.chest or cfg.misc) then
        local scanned = 0
        for _, obj in ipairs(thrown:GetChildren()) do
            scanned = scanned + 1
            if scanned % 40 == 0 then wait() end
            local n = obj.Name
            local style = OBJ_STYLE[n]
            if not style and obj:FindFirstChild("Lid") then style = OBJ_STYLE.Chest end
            if style and cfg[style.flag] then
                if n ~= "BigArtifact" or #obj:GetChildren() > 0 then
                    addObject(found, obj, style.label, style.color, style.size, style.flag)
                end
            end
        end
    end

    if cfg.misc then
        local destr = workspace:FindFirstChild("Destructibles")
        if destr then
            for _, obj in ipairs(destr:GetChildren()) do
                if obj.Name == "Campfire" then
                    local s = OBJ_STYLE.Campfire
                    addObject(found, obj, s.label, s.color, s.size, s.flag)
                end
            end
        end
    end

    if cfg.npcesp then
        local npcs = workspace:FindFirstChild("NPCs")
        if npcs then
            for _, obj in ipairs(npcs:GetChildren()) do
                addObject(found, obj, obj.Name, Color3.fromRGB(255, 225, 130), 12, "npcesp")
            end
        end
    end

    if cfg.ingred then
        local ing = workspace:FindFirstChild("Ingredients")
        if ing then
            for _, obj in ipairs(ing:GetChildren()) do
                addObject(found, obj, obj.Name, Color3.fromRGB(120, 255, 160), 11, "ingred")
            end
        end
    end

    -- Remove stale objects, and work out which ones are close enough to draw.
    -- Rendering only the closest 60 stops NPC/Ingredient ESP from eating
    -- hundreds of position reads every frame.
    local count = 0
    local myPosO = getMyPos()
    local inRange = {}
    for key, o in pairs(objects) do
        if not found[key] then
            kill(o.text)
            objects[key] = nil
        else
            count = count + 1
            o.near = false
            if myPosO and o.part then
                local okP, pp = pcall(function() return o.part.Position end)
                if okP and pp then
                    local d = (pp - myPosO).Magnitude
                    local limit = (o.flag == "artifact") and cfg.artdist or cfg.objdist
                    if d <= limit + 100 then
                        o.sortD = d
                        table.insert(inRange, o)
                    end
                end
            end
        end
    end
    table.sort(inRange, function(a, b) return a.sortD < b.sortD end)
    local cap = cfg.lowimpact and 25 or 60
    for i, o in ipairs(inRange) do
        if i > cap and o.flag ~= "artifact" then break end
        o.near = true
    end
    stats.objects = count
    -- only start alerting after one full scan with artifact ESP on
    objectsPrimed = cfg.artifact and true or false
end

-------------------------------
-- NEARBY BOX (right side) + STAFF WARNING
-------------------------------

local box = nil
local BOX_W = 300
local ROW_H = 18
local MAX_ROWS = 15

local function makeBox()
    box = {
        bg      = newSquare(Color3.fromRGB(14, 14, 18), true, 1),
        border  = newSquare(Color3.fromRGB(90, 90, 110), false, 2),
        title   = newText(15, Color3.fromRGB(255, 255, 255), false),
        warnBg  = newSquare(Color3.fromRGB(170, 0, 0), true, 2),
        warn    = newText(16, Color3.fromRGB(255, 255, 255), false),
        rows    = {},
    }
    pcall(function() box.bg.Transparency = 0.75 end)
    for i = 1, MAX_ROWS do
        box.rows[i] = newText(14, Color3.fromRGB(255, 255, 255), false)
    end
end

-- Big center-screen warning
local bigWarn = nil
local function makeBigWarn()
    bigWarn = {
        bg   = newSquare(Color3.fromRGB(160, 0, 0), true, 5),
        text = newText(22, Color3.fromRGB(255, 255, 255), true),
        sub  = newText(15, Color3.fromRGB(255, 220, 220), true),
    }
    pcall(function() bigWarn.bg.Transparency = 0.85 end)
    pcall(function() bigWarn.text.ZIndex = 6 end)
    pcall(function() bigWarn.sub.ZIndex = 6 end)
end

local function hideBox()
    if not box then return end
    box.bg.Visible = false; box.border.Visible = false; box.title.Visible = false
    box.warnBg.Visible = false; box.warn.Visible = false
    for i = 1, MAX_ROWS do box.rows[i].Visible = false end
end

local function updateBox()
    logStep("R3 first nearby box update", true)
    local hasStaff = cfg.mods and #staffList > 0

    -- Big warning (independent of nearby box)
    if hasStaff and cfg.bigwarn then
        if not bigWarn then makeBigWarn() end
        local cx = camInfo.vx / 2
        bigWarn.bg.Position = Vector2.new(cx - 220, 110)
        bigWarn.bg.Size = Vector2.new(440, 56)
        bigWarn.bg.Visible = true
        bigWarn.text.Text = "/!\\  STAFF IN YOUR SERVER  /!\\"
        bigWarn.text.Position = Vector2.new(cx, 116)
        bigWarn.text.Visible = true
        local names = {}
        for i, s in ipairs(staffList) do
            if i > 3 then table.insert(names, "+" .. (#staffList - 3) .. " more") break end
            table.insert(names, s.name .. " (" .. s.role .. ")")
        end
        bigWarn.sub.Text = table.concat(names, ", ")
        bigWarn.sub.Position = Vector2.new(cx, 142)
        bigWarn.sub.Visible = true
    elseif bigWarn then
        bigWarn.bg.Visible = false; bigWarn.text.Visible = false; bigWarn.sub.Visible = false
    end

    if not cfg.nearby then
        hideBox()
        return
    end
    if not box then makeBox() end

    local x = camInfo.vx - BOX_W - 20
    local y = 220
    local cursor = y + 8

    local rowsUsed = 0
    local h = 34

    -- Staff banner inside the box
    local warnH = 0
    if hasStaff then
        warnH = 26 + (math.min(#staffList, 4) * ROW_H)
    end

    local shown = math.min(#nearbyList, MAX_ROWS - (hasStaff and math.min(#staffList, 4) or 0))
    if shown < 0 then shown = 0 end
    h = h + warnH + math.max(shown, 1) * ROW_H

    box.bg.Position = Vector2.new(x, y)
    box.bg.Size = Vector2.new(BOX_W, h)
    box.bg.Visible = true
    box.border.Position = Vector2.new(x, y)
    box.border.Size = Vector2.new(BOX_W, h)
    box.border.Color = hasStaff and C_RED or COL.box
    box.border.Visible = true

    if hasStaff then
        box.warnBg.Position = Vector2.new(x + 1, cursor - 4)
        box.warnBg.Size = Vector2.new(BOX_W - 2, warnH)
        box.warnBg.Visible = true
        box.warn.Text = "/!\\ STAFF IN SERVER (" .. #staffList .. ") /!\\"
        box.warn.Position = Vector2.new(x + 10, cursor)
        box.warn.Visible = true
        cursor = cursor + 24
        for i = 1, math.min(#staffList, 4) do
            rowsUsed = rowsUsed + 1
            local s = staffList[i]
            local r = box.rows[rowsUsed]
            r.Text = s.role .. ": " .. s.name .. (s.char and (" | " .. s.char) or "")
            r.Color = Color3.fromRGB(255, 255, 255)
            r.Position = Vector2.new(x + 14, cursor)
            r.Visible = true
            cursor = cursor + ROW_H
        end
        cursor = cursor + 6
    else
        box.warnBg.Visible = false
        box.warn.Visible = false
    end

    box.title.Text = "NEARBY PLAYERS (" .. #nearbyList .. ")  -  " .. cfg.proxdist .. "m"
    box.title.Position = Vector2.new(x + 10, cursor)
    box.title.Visible = true
    cursor = cursor + ROW_H + 2

    if #nearbyList == 0 then
        rowsUsed = rowsUsed + 1
        local r = box.rows[rowsUsed]
        r.Text = "No one nearby"
        r.Color = Color3.fromRGB(150, 150, 150)
        r.Position = Vector2.new(x + 14, cursor)
        r.Visible = true
    else
        for i = 1, shown do
            rowsUsed = rowsUsed + 1
            if rowsUsed > MAX_ROWS then break end
            local n = nearbyList[i]
            local r = box.rows[rowsUsed]
            local label = n.name
            if n.char and n.char ~= "" then label = label .. " | " .. n.char end
            label = label .. "  -  " .. math.floor(n.dist) .. "m"
            local color = Color3.fromRGB(120, 255, 140)
            if n.role then
                label = "[" .. n.role .. "] " .. label
                color = C_ORANGE
            elseif n.dist < 150 then
                color = C_RED
            elseif n.dist < 400 then
                color = C_YELLOW
            end
            r.Text = label
            r.Color = color
            r.Position = Vector2.new(x + 14, cursor)
            r.Visible = true
            cursor = cursor + ROW_H
        end
    end

    for i = rowsUsed + 1, MAX_ROWS do box.rows[i].Visible = false end
end

-------------------------------
-- RENDER: every frame, only positions (cheap)
-------------------------------

local function fmtDist(d)
    if d >= 1000 then return string.format("%.1fkm", d / 1000) end
    return math.floor(d) .. "m"
end

local UP = Vector3.new(0, 1, 0)

local function renderEntity(e, myPos)
    logStep("R5 first ESP drawn", true)
    local anchor = e.anchor
    if not anchor then hideDrawings(e) return false end

    local ok, pos = pcall(function() return anchor.Position end)
    if not ok or not pos then
        e.anchor = nil
        hideDrawings(e)
        return false
    end

    -- Smooth out choppy movement from laggy servers: glide toward the real
    -- position instead of jumping. Snaps if they teleport far.
    if cfg.smooth then
        local sm = e.sm
        if not sm or (pos - sm).Magnitude > 40 then
            sm = pos
        else
            local a = clamp(frameDt * cfg.smoothAmt, 0.05, 1)
            sm = sm:Lerp(pos, a)
        end
        e.sm = sm
        pos = sm
    else
        e.sm = nil
    end

    -- Project the top of the head and the feet so everything is sized to the
    -- character on screen (the bar can never be taller than the character).
    local headPos, onHead = WorldToScreen(pos + UP * 2.6)
    local feetPos, onFeet = WorldToScreen(pos - UP * 3)
    if not onHead and not onFeet then hideDrawings(e) return false end
    if not onHead then headPos = feetPos end
    if not onFeet then feetPos = headPos end

    if not e.d then makeDrawings(e) end
    local d = e.d
    local last = d.last

    local dist = myPos and (pos - myPos).Magnitude or (e.dist or 100)
    local charH = feetPos.Y - headPos.Y
    if charH < 2 then charH = 2 end
    local cx = (headPos.X + feetPos.X) / 2
    local top = headPos.Y

    -- Line 1: [1.6km] Quincy Adaset (87%) (475/542hp)
    local pct = e.pct
    local line1 = e.label
    if cfg.showDist then line1 = "[" .. fmtDist(dist) .. "] " .. line1 end
    if cfg.showHp and pct then
        line1 = line1 .. " (" .. math.floor(pct * 100 + 0.5) .. "%)"
        if e.hp and e.maxhp then
            line1 = line1 .. " (" .. math.floor(e.hp + 0.5) .. "/" .. math.floor(e.maxhp + 0.5) .. "hp)"
        end
    end

    -- Line 2: [Power 20] [90ms] @username
    local parts = {}
    if not e.isMob then
        if cfg.showUser and e.username and e.username ~= e.label then
            table.insert(parts, "@" .. e.username)
        end
    end
    local line2 = table.concat(parts, " ")

    -- Name color: white normally, orange for staff, HP color if enabled
    local nameColor = e.color
    -- Only recolor when hurt; at full-ish HP the name keeps your picked color
    if cfg.hpColorName and pct and pct <= 0.75 and not e.role then nameColor = hpColor(pct) end

    if last.l1 ~= line1 then d.name.Text = line1; last.l1 = line1 end
    if last.c1 ~= nameColor then d.name.Color = nameColor; last.c1 = nameColor end
    local nameY = top - (line2 ~= "" and 30 or 16)
    d.name.Position = Vector2.new(cx, nameY)
    d.name.Visible = true

    if line2 ~= "" then
        if last.l2 ~= line2 then d.info.Text = line2; last.l2 = line2 end
        d.info.Position = Vector2.new(cx, nameY + 14)
        d.info.Visible = true
    else
        d.info.Visible = false
    end

    -- Health bar: only inside the bar radius, left side, exactly character height
    if pct and cfg.showHp and dist <= cfg.barDist and charH >= 8 then
        local barW = (charH > 80) and 3 or 2
        local width = charH * 0.55
        local bx = cx - width / 2 - barW - 4
        local by = top

        d.barBg.Position = Vector2.new(bx - 1, by - 1)
        d.barBg.Size = Vector2.new(barW + 2, charH + 2)
        d.barBg.Visible = true

        local fill = charH * pct
        d.bar.Position = Vector2.new(bx, by + (charH - fill))
        d.bar.Size = Vector2.new(barW, fill)
        local bc = hpColor(pct)
        if last.bc ~= bc then d.bar.Color = bc; last.bc = bc end
        d.bar.Visible = true

        if charH >= 40 then
            for i = 1, 4 do
                local ly = by + charH * (1 - i * 0.2)
                d.lines[i].From = Vector2.new(bx, ly)
                d.lines[i].To = Vector2.new(bx + barW, ly)
                d.lines[i].Visible = true
            end
        else
            for i = 1, 4 do d.lines[i].Visible = false end
        end
    else
        hideBar(d)
    end

    d.shown = true
    return true
end

local function renderObject(o, myPos)
    local show = cfg[o.flag] and o.part ~= nil and o.near
    local pos = nil
    if show then
        local ok, p = pcall(function() return o.part.Position end)
        if ok and p then pos = p else o.part = nil; show = false end
    end

    local dist = nil
    if show and myPos then
        dist = (pos - myPos).Magnitude
        local limit = (o.flag == "artifact") and cfg.artdist or cfg.objdist
        if dist > limit then show = false end
    end

    local screen, onScreen
    if show then
        screen, onScreen = WorldToScreen(pos)
        show = onScreen
    end

    if not show then
        if o.text and o.shown then o.text.Visible = false; o.shown = false end
        return false
    end

    if not o.text then
        o.text = newText(o.size, o.color, true)
    end
    local txt = o.label .. (dist and (" [" .. math.floor(dist) .. "m]") or "")
    if o.lastText ~= txt then o.text.Text = txt; o.lastText = txt end
    o.text.Color = COL[o.flag] or o.color
    o.text.Position = screen
    o.text.Visible = true
    o.shown = true
    return true
end

local lastFrameAt = tick()
frameDt = 1 / 60
local function renderFrame()
    logStep("R4 first render frame", true)
    local nowT = tick()
    frameDt = clamp(nowT - lastFrameAt, 0.001, 0.25)
    lastFrameAt = nowT
    local myPos = getMyPos()

    local drawn = 0
    for _, e in pairs(entities) do
        if e.want then
            if renderEntity(e, myPos) then drawn = drawn + 1 end
        elseif e.d and e.d.shown then
            hideDrawings(e)
        end
    end
    for _, o in pairs(objects) do
        renderObject(o, myPos)
    end
    stats.drawn = drawn
end

-------------------------------
-- LIGHTING
-------------------------------

local orig = {}
pcall(function() orig.Ambient = Lighting.Ambient end)
pcall(function() orig.ClockTime = Lighting.ClockTime end)
pcall(function() orig.Exposure = Lighting.ExposureCompensation end)
pcall(function() orig.FogEnd = Lighting.FogEnd end)
local fbOn, fogOn, atmoOrig = false, false, nil

local function updateLighting()
    logStep("R7 first lighting update", true)
    if V("dw_fullbright", false) then
        local lvl = math.floor(255 * (V("dw_fbintensity", 100) / 100))
        pcall(function() Lighting.Ambient = Color3.fromRGB(lvl, lvl, lvl) end)
        pcall(function() Lighting.ClockTime = 12 end)
        pcall(function() Lighting.ExposureCompensation = V("dw_exposure", 1) end)
        fbOn = true
    elseif fbOn then
        pcall(function() Lighting.Ambient = orig.Ambient end)
        pcall(function() Lighting.ClockTime = orig.ClockTime end)
        pcall(function() Lighting.ExposureCompensation = orig.Exposure end)
        fbOn = false
    end

    if V("dw_nofog", false) then
        pcall(function() Lighting.FogEnd = 1000000 end)
        pcall(function()
            local atmo = Lighting:FindFirstChild("Atmosphere")
            if atmo then
                if atmoOrig == nil then atmoOrig = atmo.Density end
                atmo.Density = 0
            end
        end)
        fogOn = true
    elseif fogOn then
        pcall(function() Lighting.FogEnd = orig.FogEnd end)
        pcall(function()
            local atmo = Lighting:FindFirstChild("Atmosphere")
            if atmo and atmoOrig then atmo.Density = atmoOrig end
        end)
        fogOn = false
    end
end

-------------------------------
-- OPTIMIZATION
-------------------------------

local FOLIAGE_WORDS = {
    "grass", "bush", "leaf", "leaves", "tree", "plant", "fern", "flower",
    "foliage", "vine", "weed", "shrub", "coral", "kelp", "seaweed", "reed",
    "mushroom", "hay", "moss", "branch", "twig", "pebble", "debris", "decor",
}

local hiddenParts = {}   -- list of { part = BasePart, t = originalTransparency }
local optBusy = false
local optStatus = "Idle"

local function nameIsFoliage(n)
    n = string.lower(n)
    for _, w in ipairs(FOLIAGE_WORDS) do
        if string.find(n, w, 1, true) then return true end
    end
    return false
end

local function hideFoliage()
    if optBusy then return end
    optBusy = true
    optStatus = "Scanning map..."
    task.spawn(function()
        local ok, err = pcall(function()
            local skip = {}
            for _, n in ipairs({ "Live", "NPCs", "Thrown", "Ingredients", "Shops", "Mechanisms" }) do
                local f = workspace:FindFirstChild(n)
                if f then skip[keyOf(f)] = true end
            end

            local count = 0
            local scanned = 0
            for _, top in ipairs(workspace:GetChildren()) do
                if not skip[keyOf(top)] then
                    local desc = {}
                    pcall(function() desc = top:GetDescendants() end)
                    for _, inst in ipairs(desc) do
                        scanned = scanned + 1
                        if scanned % 400 == 0 then
                            optStatus = "Scanning... hidden " .. count
                            wait()
                        end
                        local okA, isPart = pcall(function() return inst:IsA("BasePart") end)
                        if okA and isPart then
                            local n = inst.Name or ""
                            local pn = ""
                            pcall(function() pn = inst.Parent.Name or "" end)
                            if nameIsFoliage(n) or nameIsFoliage(pn) then
                                local okT, t = pcall(function() return inst.Transparency end)
                                if okT and type(t) == "number" and t < 1 then
                                    if pcall(function() inst.Transparency = 1 end) then
                                        table.insert(hiddenParts, { part = inst, t = t })
                                        count = count + 1
                                    end
                                end
                            end
                        end
                    end
                end
            end
            optStatus = "Hid " .. count .. " parts (scanned " .. scanned .. ")"
        end)
        if not ok then optStatus = "Failed: " .. tostring(err); report("hideFoliage", err) end
        optBusy = false
    end)
end

local function restoreFoliage()
    if optBusy then return end
    optBusy = true
    task.spawn(function()
        for i, h in ipairs(hiddenParts) do
            pcall(function() h.part.Transparency = h.t end)
            if i % 400 == 0 then wait() end
        end
        optStatus = "Restored " .. #hiddenParts .. " parts"
        hiddenParts = {}
        optBusy = false
    end)
end

local grassWasOff = false
local function updateGrass()
    local off = V("dw_nograss", false)
    if off ~= grassWasOff then
        local terrain = workspace:FindFirstChild("Terrain")
        if terrain then
            pcall(function() terrain.Decoration = not off end)
            local okR, now = pcall(function() return terrain.Decoration end)
            if off then
                if okR and now == false then optStatus = "Grass off (worked)"
                else optStatus = "Matcha ignored the grass toggle" end
            end
        end
        grassWasOff = off
    end
end

-------------------------------
-- PARRY COOLDOWN BAR
-- Watches YOUR parry key. Green = ready, white = parry window,
-- red refilling = cooldown. It's only a timer, it never presses anything.
-- "Reset on" lets a successful parry refresh the bar: once we know the name
-- of the effect Deepwoken spawns on a landed parry (use the Recorder).
-------------------------------

local parry = nil
local parryState = { down = false, pressedAt = -100, flashUntil = 0, baseline = {} }
local PARRY_W, PARRY_H = 340, 14
local PARRY_KEYS = { [0] = 0x46, [1] = 0x02, [2] = 0x51, [3] = 0x45, [4] = 0x52, [5] = 0x47 }
local parryLast = {}

local function makeParry()
    parry = {
        bg    = newSquare(Color3.fromRGB(10, 10, 10), true, 7),
        fill  = newSquare(C_GREEN, true, 8),
        label = newText(16, Color3.fromRGB(255, 255, 255), true),
    }
    pcall(function() parry.label.ZIndex = 9 end)
    parryLast = {}
end

local function hideParry()
    if not parry then return end
    parry.bg.Visible = false; parry.fill.Visible = false; parry.label.Visible = false
    parryLast = {}
end

-- Names to watch for, from the "Reset on" box (comma separated)
local DEFAULT_RESET = "CLIENT_SOUND_4954186776"   -- landed-parry sound (from your recorder log)
local function resetNames()
    local list = {}
    if not cfg.parryResetOn then return list end
    local raw = cfg.parryReset or ""
    if raw == "" then raw = DEFAULT_RESET end
    for name in string.gmatch(raw, "[^,]+") do
        name = string.gsub(name, "^%s+", "")
        name = string.gsub(name, "%s+$", "")
        if name ~= "" then table.insert(list, name) end
    end
    return list
end

-- Where parry effects could show up: on you, your root/torso, or workspace.Thrown
local function effectSpots()
    local spots = {}
    if myModel then
        table.insert(spots, myModel)
        local r = myModel:FindFirstChild("HumanoidRootPart")
        if r then table.insert(spots, r) end
        local t = myModel:FindFirstChild("Torso")
        if t then table.insert(spots, t) end
    end
    local th = workspace:FindFirstChild("Thrown")
    if th then table.insert(spots, th) end
    return spots
end

local function countNamed(name)
    local n = 0
    for _, spot in ipairs(effectSpots()) do
        for _, c in ipairs(spot:GetChildren()) do
            if c.Name == name then n = n + 1 end
        end
    end
    return n
end

-- Recorder: after you press parry, log every NEW child name that appears
local recorder = { armed = false, active = false }

local function snapshotNames()
    local seen = {}
    for _, spot in ipairs(effectSpots()) do
        local sname = spot.Name
        for _, c in ipairs(spot:GetChildren()) do
            local key = sname .. "/" .. c.Name
            seen[key] = (seen[key] or 0) + 1
        end
    end
    return seen
end

local function runRecorder()
    recorder.active = true
    task.spawn(function()
        local ok, err = pcall(function()
            local base = snapshotNames()
            local start = tick()
            local logged = {}
            pcall(function() appendfile("dw_parrylog.txt", "\n--- parry pressed ---\n") end)
            while tick() - start < 1.2 do
                local now = snapshotNames()
                for key, count in pairs(now) do
                    if count > (base[key] or 0) and not logged[key] then
                        logged[key] = true
                        local line = string.format("+%.2fs  %s", tick() - start, key)
                        print("[DW parry] " .. line)
                        pcall(function() appendfile("dw_parrylog.txt", line .. "\n") end)
                    end
                end
                wait(0.03)
            end
        end)
        if not ok then report("recorder", err) end
        recorder.active = false
    end)
end

-- Watches for the reset effect while the bar is in window/cooldown
task.spawn(function()
    while true do
        if cfg.parry then
            local total = cfg.parryWin + cfg.parryCd
            local since = tick() - parryState.pressedAt
            if since < total then
                local names = resetNames()
                for _, name in ipairs(names) do
                    local ok, n = pcall(countNamed, name)
                    if ok and n > (parryState.baseline[name] or 0) then
                        parryState.pressedAt = -100
                        parryState.flashUntil = tick() + 0.35
                        break
                    end
                end
            end
        end
        wait(0.03)
    end
end)

local function setIf(obj, prop, key, value)
    if parryLast[key] ~= value then
        obj[prop] = value
        parryLast[key] = value
    end
end

local function updateParry()
    logStep("R6 first parry update", true)
    if not cfg.parry then
        if parry and parryLast.shown then hideParry() end
        return
    end
    if not parry then makeParry() end

    local key = PARRY_KEYS[cfg.parryKey or 0] or 0x46
    local held = false
    pcall(function() held = iskeypressed(key) end)
    local now = tick()
    local total = cfg.parryWin + cfg.parryCd

    if held and not parryState.down then
        if (now - parryState.pressedAt) >= total then
            parryState.pressedAt = now
            -- remember how many reset effects already exist, so old ones don't count
            parryState.baseline = {}
            for _, name in ipairs(resetNames()) do
                local ok, n = pcall(countNamed, name)
                parryState.baseline[name] = ok and n or 0
            end
        end
        if recorder.armed and not recorder.active then
            recorder.armed = false
            runRecorder()
        end
    end
    parryState.down = held

    local x = math.floor(camInfo.vx / 2 - PARRY_W / 2)
    local y = math.floor(camInfo.vy * (cfg.parryY or 25) / 100)

    -- static parts only get written when they change (less work = smoother)
    setIf(parry.bg, "Position", "bgp", Vector2.new(x - 2, y - 2))
    setIf(parry.bg, "Size", "bgs", Vector2.new(PARRY_W + 4, PARRY_H + 4))
    setIf(parry.bg, "Visible", "bgv", true)
    setIf(parry.fill, "Position", "fp", Vector2.new(x, y))
    setIf(parry.label, "Position", "lp", Vector2.new(x + PARRY_W / 2, y + PARRY_H + 4))

    local since = now - parryState.pressedAt
    local frac, color, text
    if now < parryState.flashUntil then
        frac, color, text = 1, COL.parry, "PARRIED!"
    elseif since < cfg.parryWin then
        frac, color, text = 1, Color3.fromRGB(255, 255, 255), "PARRYING"
    elseif since < total then
        frac = (since - cfg.parryWin) / math.max(cfg.parryCd, 0.01)
        color = C_RED
        text = string.format("PARRY %.1fs", total - since)
    else
        frac, color, text = 1, COL.parry, "PARRY READY"
    end

    -- the fill width is the only thing that changes every frame
    parry.fill.Size = Vector2.new(math.floor(PARRY_W * clamp(frac, 0, 1) + 0.5), PARRY_H)
    setIf(parry.fill, "Color", "fc", color)
    setIf(parry.fill, "Visible", "fv", true)
    setIf(parry.label, "Text", "lt", text)
    setIf(parry.label, "Color", "lc", color)
    setIf(parry.label, "Visible", "lv", true)
    parryLast.shown = true
end

-------------------------------
-- STATUS LINE
-------------------------------

local status = nil
pcall(function()
    status = newText(13, Color3.fromRGB(0, 255, 120), true)
    status.Text = "DW Script: starting..."
end)

-------------------------------
-- LOOPS
-------------------------------

logStep("3 functions defined, starting loops")
-- Settings: 10x/sec
task.spawn(function()
    while true do
        pcall(readSettings)
        wait(0.1)
    end
end)
pcall(readSettings)
logStep("4 settings loop ok")

-- Entities + nearby box: ~4x/sec
task.spawn(function()
    while true do
        local ok, err = pcall(refreshEntities)
        if not ok then lastErr = tostring(err); report("refresh", err) end
        local ok2, err2 = pcall(updateBox)
        if not ok2 then lastErr = tostring(err2); report("box", err2) end
        local waitFor = V("dw_refresh", 250) / 1000
        if cfg.lowimpact then waitFor = math.max(waitFor, 0.5) end
        local waited = 0
        while waited < waitFor and not stats.force do
            wait(0.05)
            waited = waited + 0.05
        end
        stats.force = false
    end
end)

-- Objects + lighting + optimization toggles: every 2s / 0.5s
task.spawn(function()
    local t = 0
    while true do
        if t % (cfg.lowimpact and 8 or 4) == 0 or stats.forceObj then
            stats.forceObj = false
            local ok, err = pcall(refreshObjects)
            if not ok then lastErr = tostring(err); report("objects", err) end
        end
        pcall(updateLighting)
        pcall(updateGrass)
        t = t + 1
        wait(0.5)
    end
end)

-- Render: every frame. Prefer RenderStepped (smoothest), fall back to a loop.
local frameCount = 0
local function onFrame()
    -- Low Impact: move ESP every other frame (parry bar stays every frame)
    if not (cfg.lowimpact and frameCount % 2 == 1) then
        local ok, err = pcall(renderFrame)
        if not ok then lastErr = tostring(err); report("render", err) end
    end
    local okP, errP = pcall(updateParry)
    if not okP then lastErr = tostring(errP); report("parry", errP) end

    frameCount = frameCount + 1
    if status and frameCount % 30 == 0 then
        if cfg.status then
            status.Position = Vector2.new(camInfo.vx / 2, 70)
            if lastErr then
                status.Color = C_RED
                status.Text = "DW ERROR: " .. string.sub(lastErr, 1, 90)
            else
                status.Color = Color3.fromRGB(0, 255, 120)
                status.Text = string.format("DW%s | Live %d | ESP drawn %d | objects %d | pos: %s (body-cam %dm)",
                    cfg.lowimpact and " [LOW IMPACT]" or "", stats.live, stats.drawn, stats.objects,
                    posInfo.usingCam and "CAMERA" or "body", math.floor(posInfo.gap))
            end
            status.Visible = true
        else
            status.Visible = false
        end
    end
end

logStep("5 data loops started")
local connected = pcall(function()
    RunService.RenderStepped:Connect(onFrame)
end)
if not connected then
    task.spawn(function()
        while true do
            onFrame()
            task.wait()
        end
    end)
end

-------------------------------
-- RICE SPOOFER
-------------------------------

logStep("6 render hooked (RenderStepped=" .. tostring(connected) .. ")")
-- Rice is a whole second script running inside Matcha. Skip it with the
-- "Don't Load Rice On Execute" button (makes dw_norice.txt) to save CPU.
local riceState = "Loading..."
task.spawn(function()
    local skip = false
    pcall(function() skip = isfile("dw_norice.txt") end)
    if skip then riceState = "Not loaded (turned off)"; return end
    local ok, err = pcall(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/Exly78/Rice-Public/main/main.lua"))()
    end)
    if ok then riceState = "Loaded" else riceState = "Failed to load"; report("Rice load", err) end
end)

-------------------------------
-- TALENT TRACKER (your deepwoken.co build)
-- Owned talents = Backpack items named "Talent:<name>".
-- Talent cards  = PlayerGui.TalentGui.ChoiceFrame / ChoicePrompt cards.
-- Build list is kept in dw_build.txt (JSON) so it survives re-executes.
-------------------------------

local TT = {}   -- talent tracker exports (kept in one table: Lua has a 200-local limit)
do
local HttpT = game:GetService("HttpService")
local BUILD_FILE = "dw_build.txt"

-- Default: "saltchem craz am7 blood sustain" (deepwoken.co id kWkA0YWx)
local DEFAULT_BUILD = {
    name = "saltchem craz am7 blood sustain",
    id = "kWkA0YWx",
    talents = {
        "Kick Off", "Everchanging Aegis", "Neural Overload", "Perfect Flash", "Apothecary",
        "Placebo Effect", "Potion Quaffer", "Approaching Singularity", "Conditioned Runner",
        "Endurance Runner", "Scaredy Cat", "Sunken Predator", "Master Craftsman",
        "Braced Collapse", "Moving Fortress", "Adept Bloodrender", "Bloodrender",
        "Expert Bloodrender", "Brazen Blow", "Heavy Fatigue", "Impairing Blow",
        "Rending Impact", "Evasive Expert", "Risky Moves", "Swift Rebound",
        "Justicar Whistle", "Chaotic Charm", "Charismatic Cast", "Lasting Charisma",
        "Tough Love", "Give and Take", "Ether Absorption", "Keen Recovery", "Exoskeleton",
        "To The Finish", "Neuroplasticity", "Critical Engine", "Thresher Claws",
        "Ready or Not", "Replenishing Knockout", "Padded Armor", "Steel Scales",
        "Fast Blade", "Lightspeed Reflexes", "Blood Bag", "Blood Transfusion",
        "Will o' Wisp", "Oath: Saltchemist", "Blood Bank", "Donation Drive",
        "Sharing is Caring", "Gruesome Harvest", "Hemolytic Transfusion", "Vasculitis",
        "Golden Tongue", "Ether Overdrive", "Bloodiron Spirit", "Manipulator",
        "Cyclical Exsanguination", "Embolism", "Hypovolemic Focus", "Sow and Mend",
        "Speed Demon", "Chronostasis", "Brutal Momentum",
        -- the builder flags Sow and Mend as needing this one:
        "Master Bloodrender",
    },
    -- come from your gear, never flag them as "get rid of"
    innate = { "Blood Siphon", "Blood Pact", "Blood Plague", "Blood Convergence" },
    mantras = {
        "Bloodtide Ritual", "Bloodcurdle", "Crimson Rain", "Neural Pathway", "Enforcer Pull",
        "Dread Whisper", "Blood Wisp", "Bloodedge", "Soulflare Siphon", "Abyssal Tendrils",
    },
}

local build = DEFAULT_BUILD
local buildSet, innateSet, mantraSet = {}, {}, {}
local talentStatus = "Using built-in build"
local trackState = { owned = {}, need = {}, extra = {}, ownedCount = 0, cards = {}, lastCardSig = "" }

local function tclean(s)
    s = string.lower(tostring(s or ""))
    s = string.gsub(s, "^talent:", "")
    s = string.gsub(s, "%[.-%]", "")       -- [HVY] tags
    s = string.gsub(s, "<.->", "")         -- rich text tags
    s = string.gsub(s, "[^%w]", "")
    return s
end

local function rebuildSets()
    buildSet, innateSet, mantraSet = {}, {}, {}
    for _, n in ipairs(build.talents or {}) do buildSet[tclean(n)] = n end
    for _, n in ipairs(build.innate or {}) do innateSet[tclean(n)] = n end
    for _, n in ipairs(build.mantras or {}) do mantraSet[tclean(n)] = n end
end

local function saveBuildFile()
    pcall(function() writefile(BUILD_FILE, HttpT:JSONEncode(build)) end)
end

local function loadBuildFile()
    local ok = pcall(function()
        if isfile(BUILD_FILE) then
            local data = HttpT:JSONDecode(readfile(BUILD_FILE))
            if type(data) == "table" and type(data.talents) == "table" and #data.talents > 0 then
                build = data
                build.innate = build.innate or {}
                build.mantras = build.mantras or {}
                talentStatus = "Loaded " .. #build.talents .. " talents from dw_build.txt"
            end
        else
            saveBuildFile()
        end
    end)
    if not ok then talentStatus = "dw_build.txt broken, using built-in build" end
    rebuildSets()
end
loadBuildFile()

-- names in the API can be strings or { name = "..." }
local function nameList(t)
    local out = {}
    if type(t) ~= "table" then return out end
    for k, v in pairs(t) do
        if type(v) == "string" then table.insert(out, v)
        elseif type(v) == "table" and type(v.name) == "string" then table.insert(out, v.name)
        elseif type(k) == "string" and v then table.insert(out, k) end
    end
    return out
end

local function loadBuildFromLink(link)
    task.spawn(function()
        local id = string.match(tostring(link or ""), "id=([%w]+)") or string.match(tostring(link or ""), "^%s*([%w]+)%s*$")
        if not id then talentStatus = "Paste the full builder link first"; return end
        talentStatus = "Downloading build " .. id .. "..."
        local body = nil
        for _, url in ipairs({
            "https://new.deepwoken.co/api/proxy/builds/" .. id,
            "https://deepwoken.co/api/proxy/builds/" .. id,
        }) do
            local ok, res = pcall(function() return game:HttpGet(url) end)
            if ok and type(res) == "string" and string.sub(res, 1, 1) == "{" then body = res; break end
        end
        if not body then
            talentStatus = "Site blocked the download. Edit dw_build.txt instead"
            pcall(function() notify("Couldn't download that build. Edit dw_build.txt by hand.", "Talent Tracker", 6) end)
            return
        end
        local ok, data = pcall(function() return HttpT:JSONDecode(body) end)
        if not ok or type(data) ~= "table" then talentStatus = "Build data was unreadable"; return end
        local src = data.content or data.build or data
        local talents = nameList(src.talents)
        if #talents == 0 then talentStatus = "That build has no talents?"; return end
        build = {
            name = (src.stats and src.stats.buildName) or src.name or src.title or id,
            id = id,
            talents = talents,
            innate = nameList(src.innates or src.innate),
            mantras = nameList(src.mantras),
        }
        rebuildSets()
        saveBuildFile()
        talentStatus = "Loaded " .. #talents .. " talents from the link"
        pcall(function() notify("Loaded build: " .. tostring(build.name), "Talent Tracker", 5) end)
    end)
end

local function ignoreSet()
    local set = {}
    local raw = V("dw_talentignore", "")
    for part in string.gmatch(tostring(raw), "[^,]+") do set[tclean(part)] = true end
    return set
end

-- What you own vs what the build wants
local function scanOwned()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not bp then return end
    local owned, count = {}, 0
    for _, item in ipairs(bp:GetChildren()) do
        local n = item.Name
        if n and string.sub(n, 1, 7) == "Talent:" then
            local c = tclean(n)
            if not owned[c] then
                owned[c] = string.sub(n, 8)
                count = count + 1
            end
        end
    end
    local ign = ignoreSet()
    local need, extra = {}, {}
    for _, n in ipairs(build.talents or {}) do
        if not owned[tclean(n)] then table.insert(need, n) end
    end
    for c, display in pairs(owned) do
        if not buildSet[c] and not innateSet[c] and not ign[c] then
            table.insert(extra, display)
        end
    end
    table.sort(extra)
    trackState.owned, trackState.need, trackState.extra = owned, need, extra
    trackState.ownedCount = count
end

-- Read the talent / mantra cards on screen right now
local function cardName(card)
    local name = nil
    pcall(function()
        local cf = card:FindFirstChild("CardFrame") or card
        local title = cf:FindFirstChild("Title")
        if title and title.Text and title.Text ~= "" then name = title.Text end
    end)
    if not name then pcall(function() name = card.Name end) end
    return name
end

local function cardRect(card)
    local r = nil
    pcall(function()
        local cf = card:FindFirstChild("CardFrame") or card
        local p, s = cf.AbsolutePosition, cf.AbsoluteSize
        if p and s and s.X > 10 and s.Y > 10 then r = { x = p.X, y = p.Y, w = s.X, h = s.Y } end
    end)
    return r
end

local function readCards()
    local cards = {}
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return cards end
    pcall(function()
        local tg = pg:FindFirstChild("TalentGui")
        local cf = tg and tg:FindFirstChild("ChoiceFrame")
        if cf and cf.Visible then
            for _, c in ipairs(cf:GetChildren()) do
                local cls = c.ClassName
                if cls == "Frame" or cls == "TextButton" or cls == "ImageButton" or cls == "ImageLabel" then
                    local n = cardName(c)
                    if n and n ~= "" then table.insert(cards, { name = n, rect = cardRect(c) }) end
                end
            end
        end
    end)
    pcall(function()
        local cp = pg:FindFirstChild("ChoicePrompt")
        local sf = cp and cp:FindFirstChild("ScrollingFrame", true)
        if sf then
            for _, c in ipairs(sf:GetChildren()) do
                if c:FindFirstChild("CardFrame") then
                    local n = cardName(c)
                    if n and n ~= "" then table.insert(cards, { name = n, rect = cardRect(c) }) end
                end
            end
        end
    end)
    return cards
end

local function cardVerdict(name)
    local c = tclean(name)
    if c == "roll2" or c == "fold" then return "skip?", Color3.fromRGB(180, 180, 180) end
    if trackState.owned[c] then return "OWNED", Color3.fromRGB(150, 150, 150) end
    if buildSet[c] then return "GET", Color3.fromRGB(0, 255, 120) end
    if mantraSet[c] then return "GET (mantra)", Color3.fromRGB(0, 255, 120) end
    return "SKIP", Color3.fromRGB(255, 60, 100)
end

-- Debug: dump what the card GUI looks like if names come out wrong
local function dumpCards()
    task.spawn(function()
        local lines = { "Talent card dump " .. os.date("%H:%M:%S") }
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            for _, gname in ipairs({ "TalentGui", "ChoicePrompt" }) do
                local g = pg:FindFirstChild(gname)
                if g then
                    local desc = {}
                    pcall(function() desc = g:GetDescendants() end)
                    for i, d in ipairs(desc) do
                        if i > 400 then break end
                        local t = ""
                        pcall(function() if d.Text then t = " = " .. tostring(d.Text) end end)
                        local path = d.Name
                        pcall(function() path = d.Parent.Name .. "/" .. d.Name end)
                        table.insert(lines, gname .. ": " .. path .. " [" .. tostring(d.ClassName) .. "]" .. t)
                    end
                else
                    table.insert(lines, gname .. ": not found")
                end
            end
        end
        pcall(function() writefile("dw_cards.txt", table.concat(lines, "\n")) end)
        talentStatus = "Wrote dw_cards.txt (" .. #lines .. " lines)"
    end)
end

-- Drawings
local TROWS = 24
local tdraw = nil
local function makeTalentDraw()
    tdraw = { bg = newSquare(Color3.fromRGB(15, 15, 20), true, 1), rows = {}, boxes = {}, tags = {} }
    pcall(function() tdraw.bg.Transparency = 0.75 end)
    for i = 1, TROWS do tdraw.rows[i] = newText(13, Color3.fromRGB(255, 255, 255), false) end
    for i = 1, 8 do
        tdraw.boxes[i] = newSquare(Color3.fromRGB(0, 255, 120), false, 4)
        pcall(function() tdraw.boxes[i].Thickness = 3 end)
        tdraw.tags[i] = newText(16, Color3.fromRGB(0, 255, 120), true)
    end
end

local function hideTalentDraw()
    if not tdraw then return end
    tdraw.bg.Visible = false
    for i = 1, TROWS do tdraw.rows[i].Visible = false end
    for i = 1, 8 do tdraw.boxes[i].Visible = false; tdraw.tags[i].Visible = false end
end

local function joinShort(list, maxN)
    local out = {}
    for i, n in ipairs(list) do
        if i > maxN then table.insert(out, "+" .. (#list - maxN) .. " more"); break end
        table.insert(out, n)
    end
    return out
end

local function drawTalents()
    local onTracker = V("dw_talenttrack", false)
    local showPanel = onTracker and V("dw_talentpanel", true)
    local showCards = onTracker and V("dw_talentcards", true)
    if not onTracker then hideTalentDraw(); return end
    if not tdraw then makeTalentDraw() end

    local rows = {}
    local function add(text, color) table.insert(rows, { text, color }) end

    -- Card verdicts (shown whenever cards are up)
    local cards = trackState.cards
    if showCards and #cards > 0 then
        add("TALENT CARDS:", Color3.fromRGB(255, 255, 255))
        for _, c in ipairs(cards) do
            local v, col = cardVerdict(c.name)
            add("  " .. v .. "  " .. c.name, col)
        end
    end

    if showPanel then
        local total = #(build.talents or {})
        add(string.format("BUILD: %s  (%d/%d)", tostring(build.name), total - #trackState.need, total), Color3.fromRGB(120, 200, 255))
        if #trackState.need > 0 then
            add("STILL NEED (" .. #trackState.need .. "):", Color3.fromRGB(0, 255, 120))
            for _, n in ipairs(joinShort(trackState.need, 8)) do add("  " .. n, Color3.fromRGB(170, 255, 200)) end
        end
        if #trackState.extra > 0 then
            add("NOT IN BUILD - GET RID OF (" .. #trackState.extra .. "):", Color3.fromRGB(255, 60, 100))
            for _, n in ipairs(joinShort(trackState.extra, 8)) do add("  " .. n, Color3.fromRGB(255, 160, 180)) end
        end
    end

    local x, y = 20, 300
    local n = math.min(#rows, TROWS)
    if n > 0 then
        tdraw.bg.Position = Vector2.new(x - 8, y - 6)
        tdraw.bg.Size = Vector2.new(330, n * 16 + 12)
        tdraw.bg.Visible = true
    else
        tdraw.bg.Visible = false
    end
    for i = 1, TROWS do
        local r = tdraw.rows[i]
        if i <= n then
            r.Text = rows[i][1]
            r.Color = rows[i][2]
            r.Position = Vector2.new(x, y + (i - 1) * 16)
            r.Visible = true
        else
            r.Visible = false
        end
    end

    -- Boxes drawn right on the cards (only if Matcha can read card positions)
    local yoff = V("dw_cardyoff", 36)
    for i = 1, 8 do
        local c = showCards and cards[i] or nil
        local b, t = tdraw.boxes[i], tdraw.tags[i]
        if c and c.rect then
            local v, col = cardVerdict(c.name)
            b.Position = Vector2.new(c.rect.x, c.rect.y + yoff)
            b.Size = Vector2.new(c.rect.w, c.rect.h)
            b.Color = col
            b.Visible = true
            t.Text = v
            t.Color = col
            t.Position = Vector2.new(c.rect.x + c.rect.w / 2, c.rect.y + yoff - 22)
            t.Visible = true
        else
            b.Visible = false; t.Visible = false
        end
    end
end

-- Tracker loop: backpack every 2s, cards every 0.3s
task.spawn(function()
    local tk = 0
    while true do
        if V("dw_talenttrack", false) then
            if tk % 7 == 0 then pcall(scanOwned) end
            local ok, cards = pcall(readCards)
            cards = ok and cards or {}
            trackState.cards = cards
            local names = {}
            for _, c in ipairs(cards) do table.insert(names, c.name) end
            local sig = table.concat(names, "|")
            if sig ~= trackState.lastCardSig then
                trackState.lastCardSig = sig
                if #cards > 0 and V("dw_talentnotify", true) then
                    local get = {}
                    for _, c in ipairs(cards) do
                        local v = cardVerdict(c.name)
                        if v == "GET" or v == "GET (mantra)" then table.insert(get, c.name) end
                    end
                    if #get > 0 then
                        pcall(function() notify(table.concat(get, ", ") .. (#get == 1 and " is" or " are") .. " here - TAKE IT", "IN YOUR BUILD", 10) end)
                    else
                        pcall(function() notify("None of these cards are in your build", "Talent Cards", 5) end)
                    end
                end
            end
            tk = tk + 1
        else
            trackState.cards = {}
            trackState.lastCardSig = ""
        end
        pcall(drawTalents)
        wait(0.3)
    end
end)

TT.loadFromLink = loadBuildFromLink
TT.reload = function() loadBuildFile(); scanOwned() end
TT.dump = dumpCards
TT.status = function() return talentStatus end
TT.buildName = function() return tostring(build.name) .. " (" .. #(build.talents or {}) .. " talents)" end
TT.progress = function()
    local total = #(build.talents or {})
    return string.format("Have %d/%d | need %d | not in build %d", total - #trackState.need, total, #trackState.need, #trackState.extra)
end
TT.resetBuild = function()
    build = DEFAULT_BUILD
    rebuildSets(); saveBuildFile(); scanOwned()
    talentStatus = "Reset to built-in build"
end
end

-------------------------------
-- AGILITY SPOOFER (same idea as Rain/Rice: writes your PassiveAgility value)
-- Don't run this AND Rice's agility spoof at the same time, they'll fight.
-------------------------------

local agi = { was = false, old = nil, status = "Off" }  -- read by the UI
task.spawn(function()
    while true do
        pcall(function()
            local on = V("dw_agispoof", false)
            local live = workspace:FindFirstChild("Live")
            local me = live and live:FindFirstChild(LocalPlayer.Name)
            local passive = me and me:FindFirstChild("PassiveAgility")
            if not passive then
                if on then agi.status = "PassiveAgility not found (dead / loading?)" end
                return
            end
            if on then
                if not agi.was then agi.old = passive.Value; agi.was = true end
                local target = 8 + (V("dw_agiamount", 50) / 10) * 2
                if passive.Value ~= target then passive.Value = target end
                local now = passive.Value
                if math.abs((now or 0) - target) < 0.01 then
                    agi.status = "ON: " .. target
                else
                    agi.status = "Matcha didn't apply it (value " .. tostring(now) .. ")"
                end
            elseif agi.was then
                if agi.old then passive.Value = agi.old end
                agi.was = false
                agi.status = "Off (restored " .. tostring(agi.old) .. ")"
            end
        end)
        wait(0.5)
    end
end)

-------------------------------
-- OPTIMIZATION TEST + LIGHT GRAPHICS
-- Matcha Standard can silently ignore writes, so every write here is READ
-- BACK to check it actually stuck. "Test Optimizations" tells you exactly
-- which kinds of changes your Matcha can do.
-------------------------------

local OPT = { test = "Not run" }
do

local function tryWrite(obj, prop, value)
    local okR, before = pcall(function() return obj[prop] end)
    if not okR then return "can't read" end
    pcall(function() obj[prop] = value end)
    local okA, after = pcall(function() return obj[prop] end)
    local stuck = okA and (after == value or (type(after) == "number" and type(value) == "number" and math.abs(after - value) < 0.01))
    pcall(function() obj[prop] = before end)  -- put it back
    if stuck then return "WORKS" end
    return "IGNORED"
end

local function findOne(root, check, limit)
    local found = nil
    pcall(function()
        for i, d in ipairs(root:GetDescendants()) do
            if i > limit then break end
            if check(d) then found = d; break end
        end
    end)
    return found
end

local function runOptTest()
    task.spawn(function()
        OPT.test = "Testing..."
        local res = {}
        res[#res + 1] = "Shadows: " .. tryWrite(Lighting, "GlobalShadows", false)
        local terrain = workspace:FindFirstChild("Terrain")
        if terrain then
            res[#res + 1] = "Grass: " .. tryWrite(terrain, "Decoration", false)
            res[#res + 1] = "Water: " .. tryWrite(terrain, "WaterWaveSize", 0)
        end
        local part = nil
        for _, top in ipairs(workspace:GetChildren()) do
            local okP, isP = pcall(function() return top:IsA("BasePart") end)
            if okP and isP and top.Name ~= "Terrain" then part = top; break end
        end
        if not part then
            part = findOne(workspace, function(d)
                local ok, isP = pcall(function() return d:IsA("BasePart") end)
                return ok and isP
            end, 3000)
        end
        res[#res + 1] = "Parts: " .. (part and tryWrite(part, "Transparency", 0.37) or "none found")
        local emitter = findOne(workspace, function(d) return d.ClassName == "ParticleEmitter" end, 6000)
        res[#res + 1] = "Particles: " .. (emitter and tryWrite(emitter, "Enabled", not emitter.Enabled) or "none found nearby")
        OPT.test = table.concat(res, " | ")
        OPT.canWrite = string.find(OPT.test, "WORKS", 1, true) ~= nil
        pcall(function() writefile("dw_opttest.txt", OPT.test) end)
        pcall(function() notify(OPT.test, "Optimization Test", 12) end)
        print("[DW opt] " .. OPT.test)
    end)
end

-- Light Graphics: shadows off, bloom/sunrays/depth-of-field off, flat water.
-- Shadows are the biggest real FPS win of anything a script can touch.
local lg = { on = false, saved = {}, status = "Off" }
local POST_FX = { BloomEffect = true, SunRaysEffect = true, DepthOfFieldEffect = true }

local function setSaved(obj, key, prop, value)
    if lg.saved[key] == nil then
        local ok, v = pcall(function() return obj[prop] end)
        if ok then lg.saved[key] = { obj = obj, prop = prop, v = v } end
    end
    pcall(function() obj[prop] = value end)
    local ok2, now = pcall(function() return obj[prop] end)
    return ok2 and now == value
end

local function updateLightGfx()
    local want = V("dw_lightgfx", false)
    if want then
        local okCount, total = 0, 0
        total = total + 1
        if setSaved(Lighting, "shadows", "GlobalShadows", false) then okCount = okCount + 1 end
        for _, fx in ipairs(Lighting:GetChildren()) do
            local cls = fx.ClassName
            if cls and POST_FX[cls] then
                total = total + 1
                if setSaved(fx, "fx:" .. cls .. ":" .. fx.Name, "Enabled", false) then okCount = okCount + 1 end
            end
        end
        local terrain = workspace:FindFirstChild("Terrain")
        if terrain then
            total = total + 2
            if setSaved(terrain, "wave", "WaterWaveSize", 0) then okCount = okCount + 1 end
            if setSaved(terrain, "refl", "WaterReflectance", 0) then okCount = okCount + 1 end
        end
        lg.on = true
        lg.status = okCount .. "/" .. total .. " changes stuck"
    elseif lg.on then
        for _, s in pairs(lg.saved) do
            pcall(function() s.obj[s.prop] = s.v end)
        end
        lg.saved = {}
        lg.on = false
        lg.status = "Off (restored)"
    end
end

task.spawn(function()
    while true do
        pcall(updateLightGfx)
        wait(1)
    end
end)

-- Quick silent check on startup (flip shadows and put them right back)
OPT.canWrite = nil
task.spawn(function()
    wait(2)
    local r1 = tryWrite(Lighting, "GlobalShadows", not Lighting.GlobalShadows)
    local r2 = "IGNORED"
    local terrain = workspace:FindFirstChild("Terrain")
    if terrain then r2 = tryWrite(terrain, "WaterWaveSize", 0.123) end
    OPT.canWrite = (r1 == "WORKS" or r2 == "WORKS")
    if not OPT.canWrite then
        print("[DW] Matcha Standard is ignoring world changes - hiding features that need them")
    end
end)
OPT.blocked = function()
    return OPT.canWrite == false and not V("dw_showblocked", false)
end

OPT.runTest = runOptTest
OPT.updateLightGfx = updateLightGfx
OPT.lgStatus = function() return lg.status end
end

-------------------------------
-- UI (runs every frame)
-------------------------------

-------------------------------
-- OBJECT SCANNER: lists what's near you in the whole map (top-level of
-- workspace, one folder deep, plus workspace.Thrown) so we can find the real
-- name of things like the artifact orbs. Writes dw_objects.txt
-------------------------------

local scanStatus = "Not run"

local function anyPart(obj)
    local p = objPart(obj)
    if p then return p end
    local found = nil
    pcall(function()
        for i, d in ipairs(obj:GetDescendants()) do
            if i > 60 then break end
            if d:IsA("BasePart") then found = d break end
        end
    end)
    return found
end

local function scanNearby()
    task.spawn(function()
        local ok, err = pcall(function()
            scanStatus = "Scanning..."
            local myPos = getMyPos()
            if not myPos then scanStatus = "Can't find your position"; return end

            local SKIP = { Live = true, NPCs = true, Terrain = true, Camera = true }
            local rows = {}
            local n = 0
            local function check(obj, path)
                n = n + 1
                if n % 40 == 0 then wait() end
                local part = anyPart(obj)
                if not part then return end
                local okP, pos = pcall(function() return part.Position end)
                if okP and pos then
                    local d = (pos - myPos).Magnitude
                    if d <= 400 then
                        table.insert(rows, { path = path, cls = obj.ClassName or "?", d = d })
                    end
                end
            end

            for _, top in ipairs(workspace:GetChildren()) do
                local tname = top.Name or "?"
                if not SKIP[tname] then
                    local kids = {}
                    pcall(function() kids = top:GetChildren() end)
                    -- folders/containers: look one level inside
                    if (top.ClassName == "Folder" or tname == "Thrown") and #kids < 3000 then
                        for _, c in ipairs(kids) do
                            check(c, tname .. "/" .. (c.Name or "?"))
                        end
                    else
                        check(top, tname)
                    end
                end
            end

            table.sort(rows, function(x, y) return x.d < y.d end)
            local out = { "Objects within 400m (closest first)  [path | class | distance]" }
            for i, r in ipairs(rows) do
                if i > 80 then break end
                table.insert(out, string.format("%-45s %-12s %dm", r.path, r.cls, math.floor(r.d)))
            end
            pcall(function() writefile("dw_objects.txt", table.concat(out, "\n")) end)
            for i = 1, math.min(#out, 20) do print("[DW scan] " .. out[i]) end
            scanStatus = "Found " .. #rows .. " near you (dw_objects.txt)"
        end)
        if not ok then scanStatus = "Failed"; report("scan", err) end
    end)
end

-------------------------------
-- VFX REMOVAL + SUPER OPTIMIZE
-- These change properties Matcha's docs don't list, so on Standard some
-- may simply do nothing. Status text tells you if Matcha refused.
-------------------------------

local VFX_CLASSES = { ParticleEmitter = true, Beam = true, Trail = true, Smoke = true, Fire = true, Sparkles = true }
local disabledVfx = {}
local vfxStatus = "Idle"
local vfxBusy = false

local function disableVfxIn(root, budget)
    local count, refused = 0, false
    local desc = {}
    pcall(function() desc = root:GetDescendants() end)
    for i, d in ipairs(desc) do
        if budget and i % budget == 0 then wait() end
        local cls = d.ClassName
        if cls and VFX_CLASSES[cls] then
            local okW = pcall(function() d.Enabled = false end)
            if okW then
                table.insert(disabledVfx, d)
                count = count + 1
            else
                refused = true
            end
        end
    end
    return count, refused
end

local function removeAllVfx(done)
    if vfxBusy then return end
    vfxBusy = true
    vfxStatus = "Removing VFX..."
    task.spawn(function()
        local ok, err = pcall(function()
            local total, anyRefused = 0, false
            for _, top in ipairs(workspace:GetChildren()) do
                if top.Name ~= "Live" then
                    local c, r = disableVfxIn(top, 300)
                    total = total + c
                    anyRefused = anyRefused or r
                end
            end
            if total == 0 and anyRefused then
                vfxStatus = "Matcha blocked this on Standard"
            else
                vfxStatus = "Disabled " .. total .. " effects"
            end
        end)
        if not ok then vfxStatus = "Failed"; report("vfx", err) end
        vfxBusy = false
        if done then done() end
    end)
end

local function restoreVfx()
    task.spawn(function()
        for i, d in ipairs(disabledVfx) do
            pcall(function() d.Enabled = true end)
            if i % 300 == 0 then wait() end
        end
        vfxStatus = "Restored " .. #disabledVfx .. " effects"
        disabledVfx = {}
    end)
end

local function superOptimize()
    optStatus = "Super optimizing..."
    pcall(function() UI.SetValue("dw_nograss", true) end)
    removeAllVfx(function()
        hideFoliage()
    end)
end

-- Loop for the toggle-style removals
local campfireDone = {}
task.spawn(function()
    while true do
        pcall(function()
            if V("dw_noblur", false) then
                for _, obj in ipairs(Lighting:GetChildren()) do
                    if obj.ClassName == "BlurEffect" then pcall(function() obj.Size = 0 end) end
                end
            end
            if V("dw_nosanity", false) then
                local pg = LocalPlayer:FindFirstChild("PlayerGui")
                local ov = pg and pg:FindFirstChild("OverlayGui")
                if ov then pcall(function() ov.Enabled = false end) end
            end
            if V("dw_nocampfire", false) then
                for _, folderName in ipairs({ "Thrown", "Destructibles" }) do
                    local f = workspace:FindFirstChild(folderName)
                    if f then
                        for _, obj in ipairs(f:GetChildren()) do
                            if obj.Name == "Campfire" then
                                local k = folderName .. "/" .. tostring(obj)
                                if not campfireDone[k] then
                                    campfireDone[k] = true
                                    disableVfxIn(obj, nil)
                                end
                            end
                        end
                    end
                end
            end
        end)
        wait(1)
    end
end)

-------------------------------
-- CONFIGS (like Matcha's): save as many named configs as you want in the
-- dw_configs folder, pick one from the list to load or delete.
-------------------------------

local HttpService = game:GetService("HttpService")
local CONFIG_DIR = "dw_configs"
local AUTOLOAD_FILE = "dw_configs/_autoload.txt"
local configStatus = "Ready"
local configNames = {}

local CONFIG_IDS = {
    "dw_esp", "dw_mobesp", "dw_showhp", "dw_showdist", "dw_showuser", "dw_hpcolorname",
    "dw_bardist", "dw_playerdist", "dw_mobdist", "dw_maxdraw", "dw_smooth", "dw_smoothamt",
    "dw_artifact", "dw_artdist", "dw_artalert", "dw_chest", "dw_npcesp", "dw_miscobj", "dw_ingred", "dw_objdist",
    "dw_fullbright", "dw_fbintensity", "dw_exposure", "dw_nofog",
    "dw_noblur", "dw_nosanity", "dw_nocampfire",
    "dw_nearby", "dw_prox", "dw_proxdist", "dw_mods", "dw_bigwarn",
    "dw_parry", "dw_parrykey", "dw_parrywin", "dw_parrycd", "dw_parryy", "dw_parryreset", "dw_parryreseton", "dw_rechotkey",
    "dw_nograss", "dw_refresh", "dw_status", "dw_autoload", "dw_camgap",
    "dw_lowimpact", "dw_lightgfx",
    "dw_talenttrack", "dw_talentnotify", "dw_talentcards", "dw_talentpanel", "dw_cardyoff",
    "dw_buildlink", "dw_talentignore",
    "dw_agispoof", "dw_agiamount", "dw_showblocked",
}

local pendingMob = {}   -- mob filter values waiting for that mob type to show up

local function refreshConfigList()
    local names = {}
    pcall(function()
        if not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
        for _, path in ipairs(listfiles(CONFIG_DIR)) do
            local name = string.match(path, "([^/\\]+)%.json$")
            if name then table.insert(names, name) end
        end
    end)
    table.sort(names)
    configNames = names
end

local function cleanName(name)
    name = tostring(name or "")
    name = string.gsub(name, "[^%w%-_ ]", "")
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    return name
end

local function saveConfig(name)
    name = cleanName(name)
    if name == "" then
        configStatus = "Type a config name first"
        return
    end
    local ok, err = pcall(function()
        if not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
        local data = { values = {}, colors = {}, mobs = {} }
        for _, id in ipairs(CONFIG_IDS) do
            local v = V(id, nil)
            if v ~= nil and type(v) ~= "userdata" then data.values[id] = v end
        end
        for cname, c in pairs(COL) do
            data.colors[cname] = { c.R, c.G, c.B }
        end
        for id, v in pairs(savedMobs) do data.mobs[id] = v end
        for _, t in ipairs(mobTypeList) do
            local id = "dw_mt_" .. safeId(t)
            data.mobs[id] = V(id, true)
        end
        writefile(CONFIG_DIR .. "/" .. name .. ".json", HttpService:JSONEncode(data))
    end)
    configStatus = ok and ("Saved '" .. name .. "'") or ("Save failed: " .. tostring(err))
    refreshConfigList()
    pcall(function() notify(configStatus, "DW Config", 3) end)
end

local setPicker  -- defined further down, next to the color pickers
local function loadConfig(name, silent)
    name = cleanName(name)
    if name == "" then configStatus = "Pick a config"; return end
    local ok, err = pcall(function()
        local path = CONFIG_DIR .. "/" .. name .. ".json"
        if not isfile(path) then configStatus = "'" .. name .. "' not found"; return end
        local data = HttpService:JSONDecode(readfile(path))
        if type(data) ~= "table" then configStatus = "Config file broken"; return end
        if type(data.values) == "table" then
            for id, v in pairs(data.values) do
                pcall(function() UI.SetValue(id, v) end)
            end
        end
        if type(data.colors) == "table" then
            for cname, rgb in pairs(data.colors) do
                if COL[cname] and type(rgb) == "table" and #rgb == 3 then
                    COL[cname] = Color3.new(rgb[1], rgb[2], rgb[3])
                    if setPicker then pcall(setPicker, cname, COL[cname]) end
                end
            end
        end
        if type(data.mobs) == "table" then
            for id, v in pairs(data.mobs) do
                pendingMob[id] = v
                savedMobs[id] = v
            end
        end
        configStatus = "Loaded '" .. name .. "'"
    end)
    if not ok then configStatus = "Load failed: " .. tostring(err) end
    if not silent then pcall(function() notify(configStatus, "DW Config", 3) end) end
end

local function deleteConfig(name)
    name = cleanName(name)
    if name == "" then return end
    pcall(function() delfile(CONFIG_DIR .. "/" .. name .. ".json") end)
    configStatus = "Deleted '" .. name .. "'"
    refreshConfigList()
end

local function setAutoload(name)
    name = cleanName(name)
    pcall(function()
        if not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
        writefile(AUTOLOAD_FILE, name)
    end)
    configStatus = name ~= "" and ("'" .. name .. "' loads on execute") or "Autoload off"
end

local function getAutoload()
    local name = ""
    pcall(function()
        if isfile(AUTOLOAD_FILE) then name = readfile(AUTOLOAD_FILE) end
    end)
    return cleanName(name)
end

local function selectedConfig()
    local idx = V("dw_cfgsel", 0) or 0
    return configNames[idx + 1]
end

refreshConfigList()

-- Turn whatever the picker gives back into a Color3 (Matcha may return Color3 or a table)
local function toColor3(v)
    if v == nil then return nil end
    local ok, c = pcall(function()
        if type(v) == "table" then
            local r = v.R or v.r or v[1]
            local g = v.G or v.g or v[2]
            local b = v.B or v.b or v[3]
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                if r > 1 or g > 1 or b > 1 then return Color3.fromRGB(r, g, b) end
                return Color3.new(r, g, b)
            end
            return nil
        end
        if type(v.R) == "number" and type(v.G) == "number" and type(v.B) == "number" then
            return Color3.new(v.R, v.G, v.B)
        end
        return nil
    end)
    if ok then return c end
    return nil
end

local function sameColor(a, b)
    if not a or not b then return false end
    return math.abs(a.R - b.R) < 0.004 and math.abs(a.G - b.G) < 0.004 and math.abs(a.B - b.B) < 0.004
end

local pickerNames = {}
local lastPicker = {}   -- last value we saw from each picker

-- Push a color into the picker widget (used after loading a config)
setPicker = function(name, c)
    local id = "dw_col_" .. name
    local ok = pcall(function() UI.SetValue(id, c) end)
    if not ok then pcall(function() UI.SetValue(id, { c.R, c.G, c.B, 1 }) end) end
    lastPicker[name] = c
end

-- Color picker helper: picker must come right after a toggle
local function colorPicker(sec, name)
    local c = COL[name]
    table.insert(pickerNames, name)
    lastPicker[name] = c
    sec:ColorPicker("dw_col_" .. name, c.R, c.G, c.B, 1, function(color)
        local cc = toColor3(color)
        if cc then COL[name] = cc; lastPicker[name] = cc end
    end)
end

-- Backup in case the picker callback doesn't fire: poll picker values
task.spawn(function()
    while true do
        for _, name in ipairs(pickerNames) do
            local ok, v = pcall(function() return UI.GetValue("dw_col_" .. name) end)
            local cc = ok and toColor3(v) or nil
            if cc and not sameColor(cc, lastPicker[name]) then
                lastPicker[name] = cc
                COL[name] = cc
            end
        end
        wait(0.2)
    end
end)

-------------------------------
-- RESET + REFRESH
-- Every widget registers its default here, so each section gets a
-- "Reset Section" button that puts it back to how the script ships.
-------------------------------

local RS = {}
do
    local defaults = {}     -- [section] = { {id, default}, ... }
    local colorsOf = {}     -- [section] = { colorName, ... }
    local seen = {}
    local COL_DEFAULT = {}
    for k, v in pairs(COL) do COL_DEFAULT[k] = v end

    local function reg(sn, id, def)
        if seen[id] then return end
        seen[id] = true
        defaults[sn] = defaults[sn] or {}
        table.insert(defaults[sn], { id, def })
    end

    function RS.toggle(sec, sn, id, label, def, cb)
        reg(sn, id, def)
        if cb then return sec:Toggle(id, label, def, cb) end
        return sec:Toggle(id, label, def)
    end
    function RS.slider(sec, sn, id, label, mn, mx, def)
        reg(sn, id, def)
        return sec:SliderInt(id, label, mn, mx, def)
    end
    function RS.combo(sec, sn, id, label, items, def)
        reg(sn, id, def)
        return sec:Combo(id, label, items, def)
    end
    function RS.input(sec, sn, id, label, def)
        reg(sn, id, def)
        return sec:InputText(id, label, def)
    end
    function RS.color(sec, sn, name)
        if not seen["col:" .. name] then
            seen["col:" .. name] = true
            colorsOf[sn] = colorsOf[sn] or {}
            table.insert(colorsOf[sn], name)
        end
        colorPicker(sec, name)
    end

    function RS.resetSection(sn, quiet)
        for _, d in ipairs(defaults[sn] or {}) do
            pcall(function() UI.SetValue(d[1], d[2]) end)
        end
        for _, name in ipairs(colorsOf[sn] or {}) do
            COL[name] = COL_DEFAULT[name]
            pcall(setPicker, name, COL[name])
        end
        if not quiet then
            pcall(function() notify(sn .. " reset to default", "Reset", 3) end)
        end
    end

    function RS.resetAll()
        for sn, _ in pairs(defaults) do RS.resetSection(sn, true) end
        for _, t in ipairs(mobTypeList) do
            local id = "dw_mt_" .. safeId(t)
            pcall(function() UI.SetValue(id, true) end)
            savedMobs[id] = true
        end
        pcall(function() notify("Everything reset to default (configs on disk untouched)", "Reset", 4) end)
    end

    -- Throw away all mob/player ESP drawings and re-read workspace.Live now
    function RS.refreshEsp()
        for key, e in pairs(entities) do
            pcall(freeDrawings, e)
            entities[key] = nil
        end
        mobTypeList = {}
        mobTypeCounts = {}
        stats.force = true
        pcall(function() notify("Mob/Player ESP refreshed", "Refresh", 3) end)
    end

    function RS.refreshObjects()
        for key, o in pairs(objects) do
            kill(o.text)
            objects[key] = nil
        end
        stats.forceObj = true
        pcall(function() notify("Object ESP refreshed", "Refresh", 3) end)
    end

    -- Forget who we already warned about and check the server again
    function RS.recheckStaff()
        staffNotified = {}
        staffList = {}
        task.spawn(function()
            local found = {}
            for _, p in ipairs(Players:GetPlayers()) do
                local role = modList[p.UserId]
                if role and p.Name ~= LocalPlayer.Name then
                    table.insert(found, p.Name .. " (" .. role .. ")")
                end
            end
            stats.force = true
            if #found == 0 then
                pcall(function() notify("No known staff in this server (" .. #Players:GetPlayers() .. " players checked)", "Mod Checker", 5) end)
            end
            -- if staff are found, the normal staff notify fires again on the next refresh
        end)
    end
end

-------------------------------
-- RECORDER HOTKEY (so you don't have to open the menu mid-fight)
-------------------------------

local REC_KEYS = { [0] = 0x75, [1] = 0x76, [2] = 0x77, [3] = 0x78, [4] = 0x79 } -- F6..F10
task.spawn(function()
    local wasDown = false
    while true do
        local key = REC_KEYS[V("dw_rechotkey", 2) or 2]
        local down = false
        if key then pcall(function() down = iskeypressed(key) end) end
        if down and not wasDown then
            recorder.armed = true
            pcall(function() notify("Armed - now press parry and land one", "Parry Recorder", 3) end)
        end
        wasDown = down
        wait(0.05)
    end
end)

local autoLoaded = false

logStep("7 building UI")
UI.AddTab("Deepwoken Script", function(tab)
    logStep("8 UI first frame start", true)

    if not autoLoaded then
        autoLoaded = true
        task.spawn(function()
            wait(0.5)
            local name = getAutoload()
            if name ~= "" then
                logStep("A1 auto-loading config " .. name, true)
                loadConfig(name, true)
                logStep("A2 config auto-load done: " .. configStatus, true)
            end
        end)
    end

    local T, S, C, I, P = RS.toggle, RS.slider, RS.combo, RS.input, RS.color

    local esp = tab:Section("ESP", "Left")
    T(esp, "ESP", "dw_esp", "Player ESP", false)
    P(esp, "ESP", "player")
    S(esp, "ESP", "dw_playerdist", "Player Distance", 100, 20000, 5000)
    T(esp, "ESP", "dw_mobesp", "Mob ESP", false)
    P(esp, "ESP", "mob")
    S(esp, "ESP", "dw_mobdist", "Mob Distance", 50, 5000, 1000)
    T(esp, "ESP", "dw_showhp", "Show HP (bar + numbers)", true)
    T(esp, "ESP", "dw_showdist", "Show Distance", true)
    T(esp, "ESP", "dw_showuser", "Show @username", true)
    T(esp, "ESP", "dw_hpcolorname", "Color Name by HP (when hurt)", false)
    S(esp, "ESP", "dw_bardist", "HP Bar Radius", 25, 1000, 200)
    S(esp, "ESP", "dw_maxdraw", "Max ESP Drawn (closest)", 5, 80, 30)
    T(esp, "ESP", "dw_smooth", "Smooth ESP (laggy servers)", true)
    S(esp, "ESP", "dw_smoothamt", "Smoothing Speed", 3, 30, 12)
    esp:Tip("Lower = smoother but trails behind more")
    S(esp, "ESP", "dw_camgap", "Use Camera If Body Is >", 20, 500, 80)
    esp:Tip("If distances look wrong, lower this")
    esp:Button("Refresh Mob / Player ESP", function() RS.refreshEsp() end)
    esp:Button("Reset ESP Section", function() RS.resetSection("ESP") end)

    local obj = tab:Section("Object ESP", "Left")
    T(obj, "Object ESP", "dw_artifact", "Artifact ESP", false)
    P(obj, "Object ESP", "artifact")
    S(obj, "Object ESP", "dw_artdist", "Artifact Distance", 100, 20000, 20000)
    T(obj, "Object ESP", "dw_artalert", "Notify When Artifact Spawns", true)
    T(obj, "Object ESP", "dw_chest", "Chest ESP", false)
    P(obj, "Object ESP", "chest")
    T(obj, "Object ESP", "dw_npcesp", "NPC ESP (shops / quests)", false)
    P(obj, "Object ESP", "npcesp")
    T(obj, "Object ESP", "dw_miscobj", "Campfires / Bags / Meteors", false)
    T(obj, "Object ESP", "dw_ingred", "Ingredient ESP", false)
    P(obj, "Object ESP", "ingred")
    S(obj, "Object ESP", "dw_objdist", "Object Distance", 100, 5000, 1500)
    obj:Button("Refresh Object ESP", function() RS.refreshObjects() end)
    obj:Button("Scan Nearby Objects", function() scanNearby() end)
    obj:Tip("Stand next to the thing, then send dw_objects.txt")
    obj:Text("Scan: " .. scanStatus)
    obj:Button("Reset Object ESP Section", function() RS.resetSection("Object ESP") end)

    local tal = tab:Section("Talent Tracker", "Left")
    T(tal, "Talent Tracker", "dw_talenttrack", "Talent Tracker", false)
    T(tal, "Talent Tracker", "dw_talentnotify", "Notify When Build Cards Show Up", true)
    T(tal, "Talent Tracker", "dw_talentcards", "Mark Cards GET / SKIP", true)
    T(tal, "Talent Tracker", "dw_talentpanel", "Show Need / Get Rid Of List", true)
    S(tal, "Talent Tracker", "dw_cardyoff", "Card Box Y Offset", 0, 80, 36)
    tal:Tip("If the GET/SKIP boxes sit too high/low on cards, move this")
    tal:Text("Build: " .. TT.buildName())
    tal:Text(TT.progress())
    I(tal, "Talent Tracker", "dw_buildlink", "Builder Link", "https://deepwoken.co/builder?id=kWkA0YWx")
    tal:Button("Load Build From Link", function() TT.loadFromLink(V("dw_buildlink", "")) end)
    tal:Button("Reload dw_build.txt", function() TT.reload() end)
    I(tal, "Talent Tracker", "dw_talentignore", "Never flag these (comma sep)", "")
    tal:Tip("Talents from your race/origin/oath you can't remove")
    tal:Button("Dump Card GUI (if names are wrong)", function() TT.dump() end)
    tal:Text(TT.status())
    tal:Button("Reset Talent Tracker Section", function() RS.resetSection("Talent Tracker") end)
    tal:Button("Reset Build To Built-in", function() TT.resetBuild() end)

    local world = tab:Section("World & VFX", "Left")
    if OPT.blocked() then
        world:Text("Your Matcha (Standard) ignores every change")
        world:Text("to the game world, so Fullbright / No Fog /")
        world:Text("VFX removal can't do anything. Not a script bug.")
        world:Tip("Matcha's own World tab may still have fullbright/fog")
    else
        T(world, "World & VFX", "dw_fullbright", "Fullbright", false)
        S(world, "World & VFX", "dw_fbintensity", "Fullbright Intensity", 10, 100, 100)
        S(world, "World & VFX", "dw_exposure", "Exposure Boost", 0, 3, 1)
        T(world, "World & VFX", "dw_nofog", "No Fog", false)
        T(world, "World & VFX", "dw_noblur", "No Blur", false)
        T(world, "World & VFX", "dw_nosanity", "No Sanity Overlay", false)
        T(world, "World & VFX", "dw_nocampfire", "No Campfire VFX", false)
        world:Button("Remove All Particles / VFX", function() removeAllVfx() end)
        world:Button("Restore VFX", function() restoreVfx() end)
        world:Text("VFX: " .. vfxStatus)
        world:Button("Reset World Section", function() RS.resetSection("World & VFX") end)
    end
    T(world, "World & VFX", "dw_showblocked", "Show blocked features anyway", false)

    local cfgSec = tab:Section("Configs", "Left")
    cfgSec:InputText("dw_cfgname", "Config Name", "")
    cfgSec:Button("Save As New / Overwrite", function() saveConfig(V("dw_cfgname", "")) end)
    local list = (#configNames > 0) and configNames or { "(no configs yet)" }
    cfgSec:Combo("dw_cfgsel", "Saved Configs", list, 0)
    cfgSec:Button("Load Selected", function()
        local n = selectedConfig()
        if n then loadConfig(n, false) end
    end)
    cfgSec:Button("Overwrite Selected", function()
        local n = selectedConfig()
        if n then saveConfig(n) end
    end)
    cfgSec:Button("Delete Selected", function()
        local n = selectedConfig()
        if n then deleteConfig(n) end
    end)
    cfgSec:Button("Load Selected On Execute", function()
        local n = selectedConfig()
        if n then setAutoload(n) end
    end)
    cfgSec:Button("Turn Off Autoload", function() setAutoload("") end)
    cfgSec:Button("Refresh List", function() refreshConfigList() end)
    cfgSec:Text(configStatus)
    cfgSec:Button("RESET EVERYTHING TO DEFAULT", function() RS.resetAll() end)
    cfgSec:Tip("Doesn't delete saved configs")

    local alerts = tab:Section("Nearby & Alerts", "Right")
    T(alerts, "Nearby & Alerts", "dw_nearby", "Nearby Players Box", false)
    P(alerts, "Nearby & Alerts", "box")
    T(alerts, "Nearby & Alerts", "dw_prox", "Proximity Notify", false)
    S(alerts, "Nearby & Alerts", "dw_proxdist", "Nearby Distance", 100, 20000, 1000)
    T(alerts, "Nearby & Alerts", "dw_mods", "Mod Checker", true)
    P(alerts, "Nearby & Alerts", "staff")
    T(alerts, "Nearby & Alerts", "dw_bigwarn", "Big Staff Warning (center)", true)
    alerts:Button("Re-check Staff Now", function() RS.recheckStaff() end)
    alerts:Text(#staffList > 0 and ("STAFF HERE: " .. #staffList) or "No known staff right now")
    alerts:Button("Reset Alerts Section", function() RS.resetSection("Nearby & Alerts") end)

    local pr = tab:Section("Parry Timer", "Right")
    T(pr, "Parry Timer", "dw_parry", "Parry Cooldown Bar", false)
    P(pr, "Parry Timer", "parry")
    C(pr, "Parry Timer", "dw_parrykey", "Parry Key", { "F", "Right Mouse", "Q", "E", "R", "G" }, 0)
    S(pr, "Parry Timer", "dw_parrywin", "Parry Window (x0.01s)", 5, 100, 25)
    S(pr, "Parry Timer", "dw_parrycd", "Cooldown (x0.01s)", 10, 400, 100)
    pr:Tip("Tune these to match your weapon")
    S(pr, "Parry Timer", "dw_parryy", "Bar Height on Screen (%)", 5, 90, 25)
    T(pr, "Parry Timer", "dw_parryreseton", "Reset Bar On Landed Parry", true)
    I(pr, "Parry Timer", "dw_parryreset", "Reset on (effect name)", "CLIENT_SOUND_4954186776")
    pr:Tip("Name(s) of the effect a landed parry spawns, comma separated")
    C(pr, "Parry Timer", "dw_rechotkey", "Recorder Hotkey", { "F6", "F7", "F8", "F9", "F10" }, 2)
    pr:Tip("Press it in-game, then land a parry. Writes dw_parrylog.txt")
    pr:Text(recorder.armed and "Recorder: ARMED - press parry" or (recorder.active and "Recorder: recording..." or "Recorder: idle"))
    pr:Button("Reset Parry Section", function() RS.resetSection("Parry Timer") end)

    local sp = tab:Section("Spoofer", "Right")
    if OPT.blocked() then
        sp:Text("Agility spoof needs to change a game value,")
        sp:Text("and your Matcha blocks that. Use Rice's instead.")
    else
        T(sp, "Spoofer", "dw_agispoof", "Agility Spoofer", false)
        S(sp, "Spoofer", "dw_agiamount", "Agility Amount", 0, 100, 50)
        sp:Tip("Don't use this AND Rice's agility spoof at once")
        sp:Text("Agility: " .. agi.status)
    end
    sp:Text("Rice: " .. riceState)
    sp:Button("Don't Load Rice On Execute", function()
        pcall(function() writefile("dw_norice.txt", "delete this file to load Rice again") end)
        riceState = "Off next execute"
    end)
    sp:Button("Load Rice On Execute", function()
        pcall(function() delfile("dw_norice.txt") end)
        riceState = "On next execute"
    end)
    sp:Button("Reset Spoofer Section", function() RS.resetSection("Spoofer") end)

    local filter = tab:Section("Mob Filter", "Right", { "Mobs Nearby" }, 320)
    filter:Text("Uncheck a mob to hide it from Mob ESP")
    filter:Button("Refresh Mob List", function() RS.refreshEsp() end)
    filter:Button("Show All (reset filter)", function()
        for _, t in ipairs(mobTypeList) do
            local id = "dw_mt_" .. safeId(t)
            UI.SetValue(id, true); savedMobs[id] = true
        end
    end)
    filter:Button("Hide All", function()
        for _, t in ipairs(mobTypeList) do
            local id = "dw_mt_" .. safeId(t)
            UI.SetValue(id, false); savedMobs[id] = false
        end
    end)
    if #mobTypeList == 0 then
        filter:Text("No mobs loaded near you - turn on Mob ESP")
    else
        for _, t in ipairs(mobTypeList) do
            local id = "dw_mt_" .. safeId(t)
            local w = filter:Toggle(id, t, true, function(state) savedMobs[id] = state end)
            -- widget.value is the documented way to read a toggle; trust it over UI.GetValue
            local okV, val = pcall(function() return w.value end)
            if okV and type(val) == "boolean" then savedMobs[id] = val end
            if pendingMob[id] ~= nil then
                local v = pendingMob[id]
                pendingMob[id] = nil
                pcall(function() w:SetValue(v) end)
            end
        end
    end

    local opt = tab:Section("Optimization", "Right")
    opt:Button("TEST WHAT WORKS ON MY MATCHA", function() OPT.runTest() end)
    opt:Text("Test: " .. OPT.test)
    opt:Tip("WORKS = that kind of optimization can help. IGNORED = it can't")
    T(opt, "Optimization", "dw_lowimpact", "Low Impact Mode (script uses less CPU)", false)
    opt:Tip("Fewer ESP updates, 15 ESP max, objects 25 max")
    if OPT.blocked() then
        opt:Text("FPS boosts (shadows, grass, particles, foliage)")
        opt:Text("are blocked on Matcha Standard - hidden.")
        opt:Text("Real FPS fixes: Roblox menu > Graphics Quality")
        opt:Text("set to Manual + 1, close Chrome/Discord, plug in.")
    else
        T(opt, "Optimization", "dw_lightgfx", "Light Graphics (no shadows/bloom)", false)
        opt:Text("Light Graphics: " .. OPT.lgStatus())
        T(opt, "Optimization", "dw_nograss", "Disable Terrain Grass", false)
        opt:Button("SUPER OPTIMIZE", function()
            pcall(function() UI.SetValue("dw_lightgfx", true) end)
            pcall(function() UI.SetValue("dw_lowimpact", true) end)
            superOptimize()
        end)
        opt:Tip("Light Graphics + Low Impact + grass/particles/foliage off")
        opt:Button("Hide Foliage / Decor", function() hideFoliage() end)
        opt:Button("Restore Foliage", function() restoreFoliage() end)
        opt:Text("Status: " .. optStatus)
    end
    S(opt, "Optimization", "dw_refresh", "ESP Data Refresh (ms)", 100, 1000, 250)
    opt:Tip("Higher = less lag, HP/labels update slower")
    T(opt, "Optimization", "dw_status", "Show Status Line", true)
    opt:Button("Reset Optimization Section", function()
        RS.resetSection("Optimization")
        restoreFoliage()
        restoreVfx()
    end)
end)

logStep("9 script fully loaded")
