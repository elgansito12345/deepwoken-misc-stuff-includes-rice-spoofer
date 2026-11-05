-- Deepwoken Script for Matcha (Standard)
-- Player/Mob/NPC/Artifact ESP, Mob Filter, Nearby Box + Staff Warning,
-- Proximity Notify, Parry Timer, Talent Tracker, Movement Speed

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

-- Wait for the game. Executing at the Roblox menu (or before the place has
-- finished loading) used to die here with "attempt to index nil with
-- 'LocalPlayer'", because game:GetService returns nil until you're in a server.
local Players, Lighting, RunService, LocalPlayer

do
    local waited, told = 0, false
    while true do
        pcall(function()
            Players = game:GetService("Players")
            Lighting = game:GetService("Lighting")
            RunService = game:GetService("RunService")
        end)
        if Players then
            pcall(function() LocalPlayer = Players.LocalPlayer end)
        end
        if LocalPlayer then break end
        if not told then
            told = true
            logStep("1a waiting for the game (not in a server yet)")
            pcall(function()
                notify("Join a Deepwoken server - the script starts by itself once you're in.",
                       "Waiting for the game", 8)
            end)
        end
        wait(0.5)
        waited = waited + 0.5
        if waited >= 120 then
            logStep("1a GAVE UP: still not in a game after 2 minutes")
            pcall(function()
                notify("Still not in a game. Join a server, then execute the script again.",
                       "Deepwoken Script", 12)
            end)
            return
        end
    end
    local who = "?"
    pcall(function() who = tostring(LocalPlayer.Name) end)
    logStep(string.format("1b game ready after %.1fs (%s)", waited, who))
end

-------------------------------
-- BASIC HELPERS
-------------------------------

logStep("2 services ok")
local FONT = nil
-- Monospace (JetBrains) for the cyberpunk look; falls back to System
pcall(function() FONT = Drawing.Fonts.Monospace or Drawing.Fonts.System end)

-- Values from a loaded config that the menu hasn't taken yet. Matcha's menu
-- widgets only exist once the tab has been drawn, so a config loaded on
-- execute couldn't be pushed into them and was silently lost. Until the
-- menu accepts a value, the script reads it from here instead.
local PENDING = {}
local pendingTries = {}

-- Config files store every number as a decimal (25.0). Matcha's sliders
-- rejected those and dropped to 0 - that's why Parry Window, Speed and
-- Agility Step all showed 0. Shape values the way the setting expects.
local function fixValue(v, like)
    if type(like) == "number" then
        if type(v) == "string" then v = tonumber(v) end
        if type(v) == "number" and v == math.floor(v) then v = math.floor(v) end
        return v
    elseif type(like) == "boolean" then
        if type(v) == "string" then return v == "true" end
        return v
    end
    if type(v) == "number" and v == math.floor(v) then return math.floor(v) end
    return v
end

-- Since v16 the script has its OWN menu, so PENDING is simply the settings
-- store: every setting lives here, set by the menu, configs and keybinds.
-- No Matcha widgets are involved any more, so nothing can reset your
-- settings behind your back, and reading a setting is just a table lookup
-- (no call into Matcha 800+ times a second).
local function V(id, default)
    local p = PENDING[id]
    if p ~= nil then
        local fixed = fixValue(p, default)
        if fixed ~= nil then return fixed end
    end
    return default
end

local function SetV(id, v)
    PENDING[id] = v
    pendingTries[id] = nil
end

-------------------------------
-- KEYBINDS YOU CAN SET TO ANY KEY
-- The key's name is kept in a text box (so it saves with configs). The "Set"
-- button waits for the next key you press and fills it in for you.
-------------------------------
local KB = {}
do
    local names = {}
    for c = 0x41, 0x5A do names[c] = string.char(c) end           -- A-Z
    for c = 0x30, 0x39 do names[c] = string.char(c) end           -- 0-9
    for i = 1, 12 do names[0x6F + i] = "F" .. i end               -- F1-F12
    for i = 0, 9 do names[0x60 + i] = "NUM" .. i end              -- numpad
    local extra = {
        [0x04] = "MOUSE3", [0x05] = "MOUSE4", [0x06] = "MOUSE5", [0x02] = "MOUSE2",
        [0x20] = "SPACE", [0x09] = "TAB", [0x14] = "CAPS", [0x10] = "SHIFT", [0x11] = "CTRL",
        [0x12] = "ALT", [0x0D] = "ENTER", [0x08] = "BACKSPACE", [0x2D] = "INSERT",
        [0x2E] = "DELETE", [0x24] = "HOME", [0x23] = "END", [0x21] = "PAGEUP", [0x22] = "PAGEDOWN",
        [0x26] = "UP", [0x28] = "DOWN", [0x25] = "LEFT", [0x27] = "RIGHT",
        [0xDB] = "[", [0xDD] = "]", [0xBA] = ";", [0xDE] = "'", [0xBC] = ",", [0xBE] = ".",
        [0xBF] = "/", [0xBD] = "-", [0xBB] = "=", [0xC0] = "`",
    }
    for k, v in pairs(extra) do names[k] = v end
    local byName = {}
    for vk, n in pairs(names) do byName[n] = vk end

    function KB.vk(name)
        if type(name) ~= "string" or name == "" then return nil end
        return byName[string.upper((string.gsub(name, "%s", "")))]
    end

    -- true once per press, never while held, never while you're setting a key
    local was = {}
    function KB.pressed(id, name)
        local vk = KB.vk(name)
        if not vk or KB.capturing then was[id] = true; return false end
        local down = false
        pcall(function() down = iskeypressed(vk) end)
        local edge = down and not was[id]
        was[id] = down
        return edge
    end

    KB.capturing = nil
    function KB.capture(id)
        if KB.capturing then return end
        KB.capturing = id
        pcall(function() notify("Press the key you want (Esc cancels)", "Set keybind", 4) end)
        task.spawn(function()
            wait(0.4)   -- let go of the click that pressed "Set"
            local deadline, got = tick() + 8, nil
            while tick() < deadline and not got do
                for vk, n in pairs(names) do
                    local d = false
                    pcall(function() d = iskeypressed(vk) end)
                    if d then got = n; break end
                end
                if not got then
                    local esc = false
                    pcall(function() esc = iskeypressed(0x1B) end)
                    if esc then break end
                    wait(0.02)
                end
            end
            if got then
                SetV(id, got)
                pcall(function() notify("Bound to " .. got, "Set keybind", 2) end)
                was[id] = true   -- the key is still down; don't fire it straight away
            end
            KB.capturing = nil
        end)
    end
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
    custom   = Color3.fromRGB(255, 120, 255),
}

-- CYBERPUNK THEME: neon cyan / hot pink / yellow on near-black - the same
-- look as the Party HP overlay. With "Cyberpunk Theme" off, the colours
-- you picked above are used instead. (CYBER.on is set by the settings read.)
local CYBER = {
    on     = true,
    cyan   = Color3.fromRGB(0, 229, 255),
    pink   = Color3.fromRGB(255, 42, 109),
    yellow = Color3.fromRGB(252, 238, 10),
    orange = Color3.fromRGB(255, 140, 40),
    red    = Color3.fromRGB(255, 40, 70),
    dim    = Color3.fromRGB(105, 125, 150),
    bg     = Color3.fromRGB(8, 12, 22),
    track  = Color3.fromRGB(22, 36, 54),
}

local function hpColor(pct)
    if CYBER.on then
        if pct > 0.60 then return CYBER.cyan end
        if pct > 0.35 then return CYBER.yellow end
        if pct > 0.15 then return CYBER.orange end
        return CYBER.red
    end
    if pct > 0.75 then return C_GREEN end
    if pct > 0.50 then return C_YELLOW end
    if pct > 0.25 then return C_ORANGE end
    return C_RED
end

-- Who is it? Players cyan, mobs pink, staff yellow (theme on)
local function entColor(e)
    if not CYBER.on then return e.color end
    if e.role then return CYBER.yellow end
    if e.isMob then return CYBER.pink end
    if e.player then return CYBER.cyan end
    return CYBER.dim
end

local OBJ_CYBER = {
    artifact = CYBER.yellow, chest = CYBER.yellow, npcesp = CYBER.cyan,
    ingred = CYBER.cyan, custom = CYBER.pink, misc = CYBER.orange,
}

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
    -- extra staff from Rain's group_members list
    [633527] = "Admin", [32915494] = "Admin", [80804680] = "Admin",
    [20010882] = "Mod", [175717585] = "Mod", [489934750] = "Mod",
    [145985756] = "Jr Mod", [387785503] = "Jr Mod", [835990871] = "Jr Mod", [2471186291] = "Jr Mod",
    [106693864] = "Observer", [2590254462] = "Observer",
}

-------------------------------
-- INSTANT MOD CHECK: runs right here, before anything else loads, and
-- ALWAYS tells you the result (staff found or "all clear").
-------------------------------

logStep("2a instant mod check")
local executeStaff = {}
do
    local total = 0
    local ok, err = pcall(function()
        for _, p in ipairs(Players:GetPlayers()) do
            total = total + 1
            local uid = p.UserId
            if p.Name ~= LocalPlayer.Name and modList[uid] then
                table.insert(executeStaff, { id = uid, name = p.Name, role = modList[uid] })
            end
        end
    end)
    if not ok then
        pcall(function() notify("Mod check failed: " .. tostring(err), "MOD CHECK", 10) end)
        logStep("2a mod check FAILED: " .. tostring(err))
    elseif #executeStaff > 0 then
        local names = {}
        for _, s in ipairs(executeStaff) do
            table.insert(names, s.name .. " (" .. s.role .. ")")
            pcall(function() notify(s.name .. " (" .. s.role .. ") IS IN YOUR SERVER", "!! STAFF WARNING !!", 30) end)
        end
        warn("[DW] !! STAFF DETECTED ON EXECUTE: " .. table.concat(names, ", "))
        logStep("2a STAFF ON EXECUTE: " .. table.concat(names, ", "))
    else
        pcall(function() notify("Checked " .. total .. " players - no known staff", "MOD CHECK", 6) end)
        logStep("2a no staff (" .. total .. " players)")
    end
end

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
local staffList = executeStaff   -- staff in server (seeded by the instant check)
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
    cfg.customNames = V("dw_customnames", "")
    cfg.custom    = V("dw_customesp", false) and cfg.customNames ~= ""
    cfg.playerdist = V("dw_playerdist", 5000)
    cfg.mobdist   = V("dw_mobdist", 1000)
    cfg.espdist   = math.max(cfg.playerdist, cfg.mobdist)
    -- new id on purpose: old configs saved smoothing ON, which made the ESP
    -- trail behind targets. It now starts OFF = drawn where they really are.
    cfg.smooth    = V("dw_smooth2", false)
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
    cfg.parry     = false   -- parry timer removed
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
    CYBER.on      = V("dw_cyber", true) and true or false
    cfg.boxes     = V("dw_boxes", false)
    cfg.showHpNum = V("dw_showhpnum", false)
    cfg.hpPctOnly = V("dw_hppctonly", false)   -- just "92%", no bar / numbers
    cfg.nofall    = V("dw_nofall", false)
    cfg.nofallCap = V("dw_nofallsink", 30)   -- glide-down speed (new id: old one meant something else)
    cfg.nofallMode  = V("dw_nofallmode", 2)   -- 0 = Glide, 1 = Speed Cap (old), 2 = Fall reset only
    cfg.nofallMax   = V("dw_nofallcap2", 40)  -- Speed Cap mode: max fall speed
    cfg.nofallDelay = V("dw_nofalldelay2", 0)  -- ms of real falling before it steps in (0 = safest)
    cfg.nofallCatch = V("dw_nofallcatch", 20)  -- catch drops faster than this (studs/s)
    cfg.nofallBreak = V("dw_nofallbreak", 12)  -- reset the game's fall count every N studs
    cfg.tpSpeed   = V("dw_tpspeed", 120)
    cfg.tpStopKey = V("dw_tpstopkey", "")
    cfg.nofallKey = V("dw_nofallkey", "")
    cfg.boatOn    = V("dw_boat", false)
    cfg.boatMult  = V("dw_boatmult", 20)   -- x0.1
    cfg.boatKey   = V("dw_boatkey", "")
    cfg.exphp     = V("dw_exphp", false)
    cfg.friends   = V("dw_friends", "")
    cfg.exphpms   = V("dw_exphpms", 250)
    -- Movement: read here (10x/sec) instead of every frame in the speed loop
    cfg.speedOn   = V("dw_speed", false)
    cfg.speedKey  = V("dw_speedkey", 0)
    cfg.speedKeyName = V("dw_speedkeyname", "")
    cfg.stunKeyName  = V("dw_stunkeyname", "")
    cfg.speedMode = V("dw_speedmode", 0)
    cfg.speedMult = V("dw_speedmult", 20)
    cfg.spdStep   = V("dw_spdstep", 1)
    cfg.spdUp     = V("dw_spdupkey", "")
    cfg.spdDown   = V("dw_spddownkey", "")
    cfg.agiAmt    = V("dw_agiamt", 10)
    cfg.agiCustom = V("dw_agicustom", "")
    cfg.agiStep   = V("dw_agistep", 5)
    cfg.agiUp     = V("dw_agiupkey", "")
    cfg.agiDown   = V("dw_agidownkey", "")
    cfg.stunOn    = V("dw_stunmove", false)
    cfg.stunKey   = V("dw_stunkey", 0)
    cfg.stunSpeed = V("dw_stunspeed", 14)
    -- Talent tracker
    cfg.talTrack  = V("dw_talenttrack", false)
    cfg.talPanel  = V("dw_talentpanel", true)
    cfg.talCards  = V("dw_talentcards", true)
    cfg.talNotify = V("dw_talentnotify", true)
    cfg.cardYoff  = V("dw_cardyoff", 36)
    cfg.talKey    = V("dw_talhlkey", "")
    cfg.status    = V("dw_status", true)
    cfg.noclip    = V("dw_noclip", false)
    cfg.ncspeed   = V("dw_ncspeed", 30)
    cfg.ncaccel   = V("dw_ncaccel", 10)
    cfg.ncblink   = V("dw_ncblink", 12)
    cfg.ncblinkkey = V("dw_ncblinkkey", 1)
    cfg.ncblinkcd = V("dw_ncblinkcd", 30)
    cfg.nckey     = V("dw_nckey", 0)
    cfg.lowimpact = false
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
        -- one outline box (was 8 separate corner lines per target, which
        -- was up to 240 extra drawing updates every frame = lag)
        box   = newSquare(CYBER.cyan, false, 2),
        last  = {},
    }
    for i = 1, 4 do e.d.lines[i] = newLine(Color3.fromRGB(0, 0, 0)) end
end

local function hideBar(d)
    d.barBg.Visible = false
    d.bar.Visible = false
    for i = 1, 4 do d.lines[i].Visible = false end
end

local function hideCorners(d)
    if d.boxShown then
        d.box.Visible = false
        d.boxShown = false
    end
end

local function hideDrawings(e)
    local d = e.d
    if not d or not d.shown then return end
    d.name.Visible = false
    d.info.Visible = false
    hideBar(d)
    hideCorners(d)
    d.last.barOn = false
    d.shown = false
end

local function freeDrawings(e)
    local d = e.d
    if not d then return end
    kill(d.name); kill(d.info); kill(d.barBg); kill(d.bar)
    for i = 1, 4 do kill(d.lines[i]) end
    kill(d.box)
    e.d = nil
end

-------------------------------
-- REFRESH: heavy lookups, ~4x per second
-------------------------------

local proxAlerted = {}
local staffNotified = {}
for _, s in ipairs(executeStaff) do staffNotified[s.id] = true end

-- Staff joining mid-session: warn the instant they join, not on the next refresh
pcall(function()
    Players.PlayerAdded:Connect(function(p)
        local uid, name = nil, "?"
        pcall(function() uid = p.UserId; name = p.Name end)
        local role = uid and modList[uid]
        if role and not staffNotified[uid] then
            staffNotified[uid] = true
            pcall(function() notify(name .. " (" .. role .. ") JUST JOINED", "!! STAFF WARNING !!", 30) end)
            stats.force = true
        end
    end)
end)

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

            -- Re-find the parts EVERY refresh. They used to be found once and
            -- kept: when the game unloads a far mob and loads it back (or a
            -- player respawns), the old part is dead and the label stuck to
            -- where it used to be.
            -- (about once a second per target, or right away if it's missing,
            -- so a full server doesn't cost thousands of lookups a second)
            e.model = model
            e.reres = (e.reres or 0) + 1
            if not e.anchor or e.reres >= 4 then
                e.reres = 0
                e.anchor = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("Head")
                e.hum = nil
            end
            if not e.hum then
                e.hum = model:FindFirstChild("Humanoid")
            end

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
                    table.insert(nearby, { name = mname, char = e.charName, dist = e.dist,
                                           role = e.role, pct = e.pct })
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

-- v24: Matcha doesn't answer IsA / FindFirstChildWhichIsA, so a model like
-- BigArtifact (Model > BigArtifact > Meshes) never got a part to put the
-- label on: "objects 2" on the status line, but nothing drawn. Now parts are
-- recognised by ClassName and must actually give a Position.
local PART_CLASS = { Part = true, MeshPart = true, UnionOperation = true, WedgePart = true,
    CornerWedgePart = true, TrussPart = true, Seat = true, SpawnLocation = true }
local function usablePart(inst)
    local cls = nil
    pcall(function() cls = inst.ClassName end)
    if not PART_CLASS[cls] then return false end
    local ok, pos = pcall(function() return inst.Position end)
    return ok and pos ~= nil
end
local function objPart(obj)
    if usablePart(obj) then return obj end
    local p = nil
    pcall(function() p = obj.PrimaryPart end)
    if p and usablePart(p) then return p end
    -- children first, then a little deeper
    local queue, qi = { obj }, 1
    while qi <= #queue and qi <= 80 do
        local kids = {}
        pcall(function() kids = queue[qi]:GetChildren() end)
        qi = qi + 1
        for _, k in ipairs(kids) do
            if usablePart(k) then return k end
            table.insert(queue, k)
        end
    end
    return nil
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
        local okP, p = pcall(objPart, obj)
        if okP then o.part = p end
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

    -- A picked-up / carried artifact sits right in workspace as
    -- "BigArtifact" (your Close Scan: "6m BigArtifact"), not in Thrown
    if cfg.artifact then
        local kids = {}
        pcall(function() kids = workspace:GetChildren() end)
        for _, obj in ipairs(kids) do
            if obj.Name == "BigArtifact" then
                local s = OBJ_STYLE.BigArtifact
                addObject(found, obj, s.label, s.color, s.size, s.flag)
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

    -- CUSTOM ESP: any model names you type (comma separated). Looks in
    -- Thrown, the top of workspace, and up to 4 folders deep.
    if cfg.custom then
        local want = {}
        for part in string.gmatch(cfg.customNames, "[^,]+") do
            local n = string.lower((string.gsub(part, "^%s*(.-)%s*$", "%1")))
            if n ~= "" then want[n] = true end
        end
        local SKIPC = { Live = true, Terrain = true, Camera = true }
        local queue = {}
        for _, c in ipairs(workspace:GetChildren()) do
            if not SKIPC[c.Name or ""] then table.insert(queue, { c, 1 }) end
        end
        local qi, budget = 1, 20000
        while qi <= #queue and budget > 0 do
            local inst, depth = queue[qi][1], queue[qi][2]
            qi = qi + 1
            budget = budget - 1
            if budget % 300 == 0 then wait() end
            local nm = inst.Name
            if nm and want[string.lower(nm)] then
                addObject(found, inst, nm, COL.custom, 13, "custom")
            elseif depth < 5 then
                local cls = inst.ClassName
                if cls == "Folder" or cls == "Model" then
                    local kids = {}
                    pcall(function() kids = inst:GetChildren() end)
                    if #kids < 4000 then
                        for _, k in ipairs(kids) do table.insert(queue, { k, depth + 1 }) end
                    end
                end
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
local BOX_W = 350   -- a bit wider now that each row carries a health percent
local ROW_H = 18
local MAX_ROWS = 15

local function makeBox()
    box = {
        bg      = newSquare(CYBER.on and CYBER.bg or Color3.fromRGB(14, 14, 18), true, 1),
        border  = newSquare(Color3.fromRGB(90, 90, 110), false, 2),
        title   = newText(14, CYBER.on and CYBER.yellow or Color3.fromRGB(255, 255, 255), false),
        warnBg  = newSquare(CYBER.on and Color3.fromRGB(70, 6, 30) or Color3.fromRGB(170, 0, 0), true, 2),
        warn    = newText(15, CYBER.on and CYBER.yellow or Color3.fromRGB(255, 255, 255), false),
        rows    = {},
    }
    pcall(function() box.bg.Transparency = CYBER.on and 0.85 or 0.75 end)
    for i = 1, MAX_ROWS do
        box.rows[i] = newText(14, Color3.fromRGB(255, 255, 255), false)
    end
end

-- Big center-screen warning
local bigWarn = nil
local function makeBigWarn()
    bigWarn = {
        bg   = newSquare(CYBER.on and Color3.fromRGB(70, 6, 30) or Color3.fromRGB(160, 0, 0), true, 5),
        text = newText(20, CYBER.on and CYBER.yellow or Color3.fromRGB(255, 255, 255), true),
        sub  = newText(14, CYBER.on and CYBER.pink or Color3.fromRGB(255, 220, 220), true),
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
        bigWarn.text.Text = CYBER.on and "// WARNING :: STAFF IN SERVER //" or "/!\\  STAFF IN YOUR SERVER  /!\\"
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
    box.border.Color = hasStaff and (CYBER.on and CYBER.pink or C_RED) or (CYBER.on and CYBER.cyan or COL.box)
    box.border.Visible = true

    if hasStaff then
        box.warnBg.Position = Vector2.new(x + 1, cursor - 4)
        box.warnBg.Size = Vector2.new(BOX_W - 2, warnH)
        box.warnBg.Visible = true
        box.warn.Text = CYBER.on and ("// STAFF IN SERVER [" .. #staffList .. "]")
            or ("/!\\ STAFF IN SERVER (" .. #staffList .. ") /!\\")
        box.warn.Position = Vector2.new(x + 10, cursor)
        box.warn.Visible = true
        cursor = cursor + 24
        for i = 1, math.min(#staffList, 4) do
            rowsUsed = rowsUsed + 1
            local s = staffList[i]
            local r = box.rows[rowsUsed]
            r.Text = s.role .. ": " .. s.name .. (s.char and (" | " .. s.char) or "")
            r.Color = CYBER.on and CYBER.pink or Color3.fromRGB(255, 255, 255)
            r.Position = Vector2.new(x + 14, cursor)
            r.Visible = true
            cursor = cursor + ROW_H
        end
        cursor = cursor + 6
    else
        box.warnBg.Visible = false
        box.warn.Visible = false
    end

    box.title.Text = CYBER.on and ("// NEARBY.SCAN  [" .. #nearbyList .. "]  " .. cfg.proxdist .. "m")
        or ("NEARBY PLAYERS (" .. #nearbyList .. ")  -  " .. cfg.proxdist .. "m")
    box.title.Position = Vector2.new(x + 10, cursor)
    box.title.Visible = true
    cursor = cursor + ROW_H + 2

    if #nearbyList == 0 then
        rowsUsed = rowsUsed + 1
        local r = box.rows[rowsUsed]
        r.Text = CYBER.on and "NO SIGNAL" or "No one nearby"
        r.Color = CYBER.on and CYBER.dim or Color3.fromRGB(150, 150, 150)
        r.Position = Vector2.new(x + 14, cursor)
        r.Visible = true
    else
        for i = 1, shown do
            rowsUsed = rowsUsed + 1
            if rowsUsed > MAX_ROWS then break end
            local n = nearbyList[i]
            local r = box.rows[rowsUsed]
            local cy = CYBER.on
            local sep = cy and "  //  " or "  -  "
            local label = n.name
            if n.char and n.char ~= "" then label = label .. " | " .. n.char end
            label = label .. sep .. math.floor(n.dist) .. "m"
            -- health as a percent, for everyone in the box
            if n.pct then
                label = label .. sep .. math.floor(n.pct * 100 + 0.5) .. "%"
            end
            local color = cy and CYBER.cyan or Color3.fromRGB(120, 255, 140)
            if n.role then
                label = "[" .. n.role .. "] " .. label
                color = cy and CYBER.yellow or C_ORANGE
            elseif n.pct and n.pct <= 0.75 then
                -- hurt players stand out: the row takes their health colour
                color = hpColor(n.pct)
            elseif n.dist < 150 then
                color = cy and CYBER.pink or C_RED
            elseif n.dist < 400 then
                color = cy and CYBER.yellow or C_YELLOW
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

-- Labels already placed this frame. Mobs in a group stood in the same spot,
-- so their labels were drawn right on top of each other
-- ("[829n][833m] mudskipper..."). Each new label moves up until it's clear.
local LABELS = {}
local function placeLabel(cx, y, w, h)
    for _ = 1, 8 do
        local hit = false
        for _, p in ipairs(LABELS) do
            if math.abs(cx - p.x) < (w + p.w) / 2 and math.abs(y - p.y) < h then
                y = p.y - h
                hit = true
            end
        end
        if not hit then break end
    end
    table.insert(LABELS, { x = cx, y = y, w = w })
    return y
end

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

    -- Default: draw exactly where the target is, like Matcha's own ESP.
    -- The old "prediction" guessed where targets were heading; positions
    -- arrive in jumps over the network, so the guess overshot and labels
    -- floated off the target. Optional smoothing now only eases toward the
    -- REAL position - it can lag a touch but never overshoots.
    if cfg.smooth then
        local sm = e.sm
        if not sm or (pos - sm).Magnitude > 25 then
            sm = pos
        else
            sm = sm:Lerp(pos, 1 - math.exp(-(cfg.smoothAmt or 12) * 2 * frameDt))
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

    -- Line 1 (short): SUMMER THUG  92%      [+ 643/700 if HP numbers on]
    -- Line 2 (small):  95m  //  @username
    local pct = e.pct
    local cyber = CYBER.on
    local col = entColor(e)
    local line1 = cyber and string.upper(e.label) or e.label
    if cfg.showHp and pct then
        line1 = line1 .. "  " .. math.floor(pct * 100 + 0.5) .. "%"
        if cfg.showHpNum and not cfg.hpPctOnly and e.hp and e.maxhp then
            line1 = line1 .. "  " .. math.floor(e.hp + 0.5) .. "/" .. math.floor(e.maxhp + 0.5)
        end
    end
    local parts = {}
    if cfg.showDist then table.insert(parts, fmtDist(dist)) end
    if not e.isMob and cfg.showUser and e.username and e.username ~= e.label then
        table.insert(parts, "@" .. e.username)
    end
    local line2 = table.concat(parts, cyber and "  //  " or "  ")

    -- name keeps its colour until hurt, then takes the health colour
    local nameColor = col
    if cfg.hpColorName and pct and pct <= 0.75 and not e.role then nameColor = hpColor(pct) end
    local infoColor = cyber and CYBER.dim or Color3.fromRGB(200, 200, 200)

    -- Every drawing write is a call into Matcha, so nothing is written
    -- unless it changed: positions are rounded to whole pixels and compared
    -- to last frame, and Visible is only flipped when it actually changes.
    local wasShown = d.shown
    if last.l1 ~= line1 then d.name.Text = line1; last.l1 = line1 end
    if last.c1 ~= nameColor then d.name.Color = nameColor; last.c1 = nameColor end
    if last.ic ~= infoColor then d.info.Color = infoColor; last.ic = infoColor end
    local blockH = (line2 ~= "") and 28 or 15
    local nameY = placeLabel(cx, top - blockH - 2, #line1 * 7, blockH)
    local nx, ny = math.floor(cx + 0.5), math.floor(nameY + 0.5)
    if last.nx ~= nx or last.ny ~= ny then
        d.name.Position = Vector2.new(nx, ny)
        d.info.Position = Vector2.new(nx, ny + 14)
        last.nx, last.ny = nx, ny
    end
    if not wasShown then d.name.Visible = true end

    local wantInfo = line2 ~= ""
    if wantInfo and last.l2 ~= line2 then d.info.Text = line2; last.l2 = line2 end
    if not wasShown or last.iv ~= wantInfo then
        d.info.Visible = wantInfo
        last.iv = wantInfo
    end

    -- Optional outline box (one drawing, theme on, off by default)
    if cyber and cfg.boxes == true and charH >= 10 then
        local w = math.floor(charH * 0.55 + 0.5)
        local bx, by, bh = math.floor(cx - w / 2 + 0.5), math.floor(top + 0.5), math.floor(charH + 0.5)
        if last.bx ~= bx or last.by ~= by or last.bw ~= w or last.bh ~= bh then
            d.box.Position = Vector2.new(bx, by)
            d.box.Size = Vector2.new(w, bh)
            last.bx, last.by, last.bw, last.bh = bx, by, w, bh
        end
        if last.boxc ~= col then d.box.Color = col; last.boxc = col end
        if not d.boxShown then d.box.Visible = true; d.boxShown = true end
    else
        hideCorners(d)
    end

    -- Health bar: only inside the bar radius, left side, character height
    if pct and cfg.showHp and not cfg.hpPctOnly and dist <= cfg.barDist and charH >= 8 then
        local barW = (charH > 80) and 3 or 2
        local bx = math.floor(cx - charH * 0.275 - barW - 4 + 0.5)
        local by = math.floor(top + 0.5)
        local h = math.floor(charH + 0.5)
        local fill = math.floor(h * pct + 0.5)

        local trackC = cyber and CYBER.track or Color3.fromRGB(0, 0, 0)
        if last.tc ~= trackC then
            d.barBg.Color = trackC
            for i = 1, 4 do d.lines[i].Color = cyber and CYBER.bg or Color3.fromRGB(0, 0, 0) end
            last.tc = trackC
        end
        if last.hx ~= bx or last.hy ~= by or last.hh ~= h or last.hf ~= fill then
            d.barBg.Position = Vector2.new(bx - 1, by - 1)
            d.barBg.Size = Vector2.new(barW + 2, h + 2)
            d.bar.Position = Vector2.new(bx, by + (h - fill))
            d.bar.Size = Vector2.new(barW, fill)
            local segs = h >= 40
            for i = 1, 4 do
                if segs then
                    local ly = by + h * (1 - i * 0.2)
                    d.lines[i].From = Vector2.new(bx, ly)
                    d.lines[i].To = Vector2.new(bx + barW, ly)
                end
            end
            if last.segs ~= segs then
                for i = 1, 4 do d.lines[i].Visible = segs end
                last.segs = segs
            end
            last.hx, last.hy, last.hh, last.hf = bx, by, h, fill
        end
        local bc = hpColor(pct)
        if last.bc ~= bc then d.bar.Color = bc; last.bc = bc end
        if not last.barOn then
            d.barBg.Visible = true
            d.bar.Visible = true
            if last.segs then for i = 1, 4 do d.lines[i].Visible = true end end
            last.barOn = true
        end
    elseif last.barOn then
        hideBar(d)
        last.barOn = false
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
    local txt
    if CYBER.on then
        txt = string.upper(o.label) .. (dist and ("  //  " .. math.floor(dist) .. "m") or "")
    else
        txt = o.label .. (dist and (" [" .. math.floor(dist) .. "m]") or "")
    end
    if o.lastText ~= txt then o.text.Text = txt; o.lastText = txt end
    o.text.Color = (CYBER.on and OBJ_CYBER[o.flag]) or COL[o.flag] or o.color
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

    -- nearest first, so the closest target keeps its label spot and the
    -- ones behind it move out of the way
    LABELS = {}
    local list = {}
    for _, e in pairs(entities) do
        if e.want then
            table.insert(list, e)
        elseif e.d and e.d.shown then
            hideDrawings(e)
        end
    end
    table.sort(list, function(a, b) return (a.dist or 1e9) < (b.dist or 1e9) end)
    local drawn = 0
    for _, e in ipairs(list) do
        if renderEntity(e, myPos) then drawn = drawn + 1 end
    end
    for _, o in pairs(objects) do
        renderObject(o, myPos)
    end
    stats.drawn = drawn
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
-- NOCLIP v7 - Deepwoken's anticheat yanks you back when you move too far too
-- fast (big teleports). The GC scan proved CanCollide=false STICKS on Matcha,
-- so we lean on that instead of teleporting:
--   WALK  (default): only turn collision off, you run through walls normally
--   FLOAT : collision off + tiny per-frame nudges (<=1.2 studs) so the move
--           looks like normal walking, never a teleport. Space=up, Shift=down
-- TPSafe (Rain's bypass) needs the game's EffectReplicator:CreateEffect, which
-- Matcha (external VM) can't call - the scan confirmed it exists but it's the
-- game's own function. TURN OFF Matcha's own Flight / No-Clip while using this.
-------------------------------

local NOCLIP = { on = false, status = "Off" }
do
    local NC_KEYS = { [1] = 0x4E, [2] = 0x48, [3] = 0x4A, [4] = 0x55, [5] = 0x59 } -- N H J U Y
    local K_W, K_A, K_S, K_D = 0x57, 0x41, 0x53, 0x44
    local K_SPACE, K_LSHIFT = 0x20, 0xA0
    local ZERO = Vector3.new(0, 0, 0)

    local keyWas = false
    local lastT = tick()
    local vpos = nil
    local setbacks = 0
    local myParts, partsAt, curChar = {}, 0, nil
    local hud = nil

    local function kd(k)
        local d = false
        pcall(function() d = iskeypressed(k) end)
        return d
    end

    local function myChar()
        local live = workspace:FindFirstChild("Live")
        local me = live and live:FindFirstChild(LocalPlayer.Name)
        local root = me and (me:FindFirstChild("HumanoidRootPart") or me:FindFirstChild("Torso"))
        return me, root
    end

    local function refreshParts(me)
        local now = tick()
        if me == curChar and now < partsAt then return end
        curChar, partsAt = me, now + 1
        local list = {}
        pcall(function()
            for _, p in ipairs(me:GetChildren()) do
                local isPart = false
                pcall(function() isPart = p:IsA("BasePart") end)
                if isPart then table.insert(list, p) end
            end
        end)
        myParts = list
    end

    local function collideOff()
        for _, p in ipairs(myParts) do
            pcall(function() p.CanCollide = false end)
        end
    end

    pcall(function()
        RunService.Stepped:Connect(function()
            if NOCLIP.on then collideOff() end
        end)
    end)

    local function setVel(root, v)
        pcall(function() root.AssemblyLinearVelocity = v end)
        pcall(function() root.Velocity = v end)
    end

    local function showHud(text, color)
        if not hud then
            hud = newText(15, Color3.fromRGB(0, 220, 255), true)
            pcall(function() hud.ZIndex = 9 end)
        end
        hud.Text = text
        hud.Color = color or Color3.fromRGB(0, 220, 255)
        hud.Position = Vector2.new(camInfo.vx / 2, 92)
        hud.Visible = true
    end

    local function hideHud()
        if hud then hud.Visible = false end
    end

    -- WHAT MATCHA ACTUALLY ALLOWS (proven by the v8 self-test on your PC):
    --   Position write .......... WORKS
    --   Velocity write .......... WORKS
    --   Anchored ................ "Unknown property" - NOT SUPPORTED
    --   PlatformStand ........... NOT SUPPORTED
    --   CanCollide .............. writable, but your HumanoidRootPart was
    --                             ALREADY false and walls still blocked you,
    --                             so the collision comes from the Humanoid /
    --                             ControllerManager hull we cannot reach
    --   Raycast ................. always returns nil (broken)
    -- So the ONLY way through a wall is to move far enough in ONE position
    -- write to land past it before physics resolves = a short teleport.
    -- That is BLINK. Small blinks (8-15 studs) clear normal walls and stay
    -- well under the distance that made the server rubber-band you.
    local blinkWas, blinkAt, blinks = false, 0, 0
    local curVel = Vector3.new(0, 0, 0)

    local function enable(root)
        vpos = nil
        setbacks = 0
        blinkWas, blinkAt, blinks = false, 0, 0
        curVel = Vector3.new(0, 0, 0)
    end

    local function disable(root)
        if root then setVel(root, ZERO) end
        vpos = nil
        for _, p in ipairs(myParts) do
            local n = ""
            pcall(function() n = p.Name end)
            if n == "Torso" or n == "Head" or n == "HumanoidRootPart" then
                pcall(function() p.CanCollide = true end)
            end
        end
        hideHud()
    end

    -- Shared: camera-relative WASD + Space/Shift -> unit direction (or nil)
    local function inputDir()
        local fx, fz, rx, rz = 0, 0, 0, 0
        pcall(function()
            local lv = workspace.CurrentCamera.CFrame.LookVector
            local l = math.sqrt(lv.X * lv.X + lv.Z * lv.Z)
            if l > 0.01 then fx, fz = lv.X / l, lv.Z / l end
            rx, rz = -fz, fx
        end)
        local dx, dy, dz = 0, 0, 0
        if kd(K_W) then dx = dx + fx; dz = dz + fz end
        if kd(K_S) then dx = dx - fx; dz = dz - fz end
        if kd(K_D) then dx = dx + rx; dz = dz + rz end
        if kd(K_A) then dx = dx - rx; dz = dz - rz end
        if kd(K_SPACE) then dy = dy + 1 end
        if kd(K_LSHIFT) then dy = dy - 1 end
        local l = math.sqrt(dx * dx + dy * dy + dz * dz)
        if l < 0.1 then return nil end
        return Vector3.new(dx / l, dy / l, dz / l)
    end

    -- FLY: hover + move by Position writes (physics is still on, so this gets
    --      you OVER and AROUND things, not through them).
    -- BLINK: one key = jump forward N studs in a single write. That single
    --      jump is what actually crosses a wall. Hold it to blink repeatedly.
    local BLINK_KEYS = { [1] = 0x47, [2] = 0x56, [3] = 0x43, [4] = 0x58, [5] = 0x52 } -- G V C X R

    local function move(dt, me, root)
        local speed = clamp(cfg.ncspeed or 30, 8, 120)
        collideOff()   -- harmless, and free if your build ever honors it

        local pos = nil
        pcall(function() pos = root.Position end)
        if not pos then NOCLIP.status = "NOCLIP: can't read your position"; return end
        if not vpos then vpos = pos end

        -- the game yanked us far (anticheat / respawn): resync
        if (pos - vpos).Magnitude > 25 then
            vpos = pos
            setbacks = setbacks + 1
        end

        local d = inputDir()
        local moving = d ~= nil

        -- ---- BLINK -------------------------------------------------------
        local bk = BLINK_KEYS[cfg.ncblinkkey or 0]
        local blinkNow = false
        if bk then
            local down = kd(bk)
            local dist = clamp(cfg.ncblink or 12, 3, 40)
            local now = tick()
            -- fires on press, then repeats while held (with a cooldown)
            if down and (not blinkWas or now - blinkAt >= (cfg.ncblinkcd or 30) / 100) then
                -- blink the way you're steering; if idle, straight ahead
                local bd = d
                if not bd then
                    local lv = nil
                    pcall(function() lv = workspace.CurrentCamera.CFrame.LookVector end)
                    if lv then bd = lv end
                end
                if bd then
                    vpos = pos + bd * dist
                    pcall(function() root.Position = vpos end)
                    -- carry velocity THROUGH the blink instead of zeroing it,
                    -- so the jump reads as a fast dash rather than "teleported
                    -- while standing still"
                    curVel = bd * speed
                    setVel(root, curVel)
                    blinkAt = now
                    blinks = blinks + 1
                    blinkNow = true
                end
            end
            blinkWas = down
        end

        -- ---- FLY (velocity-driven, NOT position) --------------------------
        -- This is what stops you getting shot down. Writing Position every
        -- frame while reporting velocity 0 tells the server "I am standing
        -- still" and then moves you anyway - that mismatch IS the teleport
        -- flag. Driving with velocity makes the engine move you itself, so
        -- your position and your reported velocity always agree and it reads
        -- as ordinary physics. Gravity is cancelled because we rewrite the
        -- velocity every frame before it can build up.
        if not blinkNow then
            local want = ZERO
            if moving then want = d * speed end
            -- ease in/out so speed never jumps in a single frame
            local a = clamp(dt * (cfg.ncaccel or 10), 0, 1)
            curVel = curVel + (want - curVel) * a
            if curVel.Magnitude < 0.05 then curVel = ZERO end
            setVel(root, curVel)
            vpos = pos          -- keep blink's anchor in sync; never written
        end

        local parts = { string.format("NOCLIP: FLY %d studs/s (velocity)", speed) }
        table.insert(parts, moving and "moving" or "hovering")
        if bk then
            table.insert(parts, string.format("BLINK %d studs x%d", clamp(cfg.ncblink or 12, 3, 40), blinks))
        else
            table.insert(parts, "BLINK key not set (walls need it)")
        end
        if setbacks > 0 then table.insert(parts, "pulled back x" .. setbacks) end
        NOCLIP.status = table.concat(parts, " | ")
    end

    NOCLIP.frame = function()
        local now = tick()
        local dt = clamp(now - lastT, 0, 0.1)
        lastT = now

        local on = cfg.noclip and true or false
        local k = NC_KEYS[cfg.nckey or 0]
        if k then
            local down = kd(k)
            if down and not keyWas then
                on = not on
                cfg.noclip = on
                pcall(function() UI.SetValue("dw_noclip", on) end)
                pcall(function() notify(on and "Noclip ON" or "Noclip OFF", "Movement", 2) end)
            end
            keyWas = down
        end

        local me, root = myChar()
        if on and not NOCLIP.on then
            NOCLIP.on = true
            NOCLIP.status = "starting..."
            enable(root)
        elseif not on and NOCLIP.on then
            NOCLIP.on = false
            disable(root)
            NOCLIP.status = "Off"
        end
        if not NOCLIP.on then return end
        if not root then
            NOCLIP.status = "NOCLIP ON - no character found in workspace.Live"
            vpos = nil
        else
            refreshParts(me)
            local ok, err = pcall(move, dt, me, root)
            if not ok then NOCLIP.status = "NOCLIP ERROR: " .. tostring(err) end
        end
        showHud(NOCLIP.status, string.find(NOCLIP.status, "FAIL") and C_ORANGE or nil)
    end

    -- Tests each method once and writes the answers to dw_noclip.txt
    -- Looks inside the game's Lua memory (getgc) for Deepwoken's effect data and
    -- anticheat values, to see if TPSafe (Rain's anticheat bypass) can be faked
    NOCLIP.acScan = function()
        task.spawn(function()
            local out = { "DW anticheat/effect GC scan " .. os.date("%H:%M:%S"),
                "Run this with noclip OFF, standing still, then again right after a wall snap-back." }
            -- rare names first, very common ones (Class, Tags, Domain) LAST because
            -- those can return huge lists and stall the scan
            local keys = {
                "TPSafe", "EffectReplicator", "CreateEffect", "FindEffect", "DebrisTime",
                "SafePosition", "LastSafePosition", "LastSafe", "SafeCFrame", "LastPosition",
                "LastPos", "LastCFrame", "PreviousPosition", "OldPosition",
                "NoClip", "Noclip", "NoclipCheck", "AntiCheat", "Anticheat", "Teleport", "Teleported",
                "Flagged", "Violations", "Strikes", "Knocked", "Effects",
                "Domain", "Tags", "Class",
            }
            local listValues = { Class = true, Domain = true }
            -- write the header now, then append after EVERY key, so a stall still
            -- leaves a usable file on disk
            pcall(function() writefile("dw_acscan.txt", table.concat(out, "\n") .. "\n") end)
            local written = #out
            for ki, key in ipairs(keys) do
                pcall(function() notify("Scanning " .. key .. " (" .. ki .. "/" .. #keys .. ")", "Anticheat Scan", 2) end)
                local ok, res = pcall(function() return getgc(key) end)
                if not ok then
                    table.insert(out, "== " .. key .. ": getgc ERROR " .. tostring(res))
                elseif type(res) ~= "table" or #res == 0 then
                    table.insert(out, "== " .. key .. ": none")
                else
                    local types = {}
                    for _, e in ipairs(res) do
                        local t = tostring(e.type)
                        types[t] = (types[t] or 0) + 1
                    end
                    local tl = {}
                    for t, n in pairs(types) do table.insert(tl, t .. "=" .. n) end
                    table.insert(out, "== " .. key .. ": " .. #res .. " found (" .. table.concat(tl, ", ") .. ")")
                    if listValues[key] then
                        local counts = {}
                        for _, e in ipairs(res) do
                            if e.type == "string" then
                                local v = tostring(e.value)
                                counts[v] = (counts[v] or 0) + 1
                            end
                        end
                        local cl = {}
                        for v, n in pairs(counts) do table.insert(cl, { v, n }) end
                        table.sort(cl, function(a, b) return a[2] > b[2] end)
                        for i, c in ipairs(cl) do
                            if i > 150 then break end
                            table.insert(out, string.format("    %q x%d", c[1], c[2]))
                        end
                    else
                        for i, e in ipairs(res) do
                            if i > 40 then break end
                            table.insert(out, string.format("    %s = %s  @%s", tostring(e.type), tostring(e.value), tostring(e.addr)))
                        end
                    end
                end
                -- flush this key's lines to disk before moving to the next
                if #out > written then
                    pcall(function() appendfile("dw_acscan.txt", table.concat(out, "\n", written + 1) .. "\n") end)
                    written = #out
                end
                wait()
            end
            pcall(function() appendfile("dw_acscan.txt", "== DONE ==\n") end)
            pcall(function() notify("Wrote dw_acscan.txt - send it to me", "Anticheat Scan", 6) end)
        end)
    end

    NOCLIP.selfTest = function()
        task.spawn(function()
            local out = { "DW noclip self-test " .. os.date("%H:%M:%S") }
            local function line(s) table.insert(out, s); print("[DW nc] " .. s) end
            pcall(function()
                local n, v = identifyexecutor()
                line("executor: " .. tostring(n) .. " " .. tostring(v))
            end)
            local me, root = myChar()
            line("character: " .. tostring(me ~= nil) .. "  root: " .. tostring(root ~= nil))
            if not root then
                pcall(function() writefile("dw_noclip.txt", table.concat(out, "\n")) end)
                pcall(function() notify("No character - test stopped", "Noclip Test", 5) end)
                return
            end
            local p0 = nil
            pcall(function() p0 = root.Position end)
            line("read Position: " .. tostring(p0))

            -- position write: lift 1 stud, read back, put back
            if p0 then
                local up = p0 + Vector3.new(0, 1, 0)
                local okW, errW = pcall(function() root.Position = up end)
                local p1 = nil
                pcall(function() p1 = root.Position end)
                line(string.format("write Position: ok=%s err=%s readback dy=%.2f",
                    tostring(okW), tostring(errW), p1 and (p1.Y - p0.Y) or -999))
                pcall(function() root.Position = p0 end)
            end

            -- velocity write
            local okV = pcall(function() root.AssemblyLinearVelocity = Vector3.new(0, 5, 0) end)
            local v1 = nil
            pcall(function() v1 = root.AssemblyLinearVelocity end)
            line("write Velocity: ok=" .. tostring(okV) .. " readback=" .. tostring(v1))
            pcall(function() root.AssemblyLinearVelocity = ZERO end)

            -- CanCollide on Torso: write, read now, read after a moment
            local torso = me:FindFirstChild("Torso") or root
            local c0 = nil
            pcall(function() c0 = torso.CanCollide end)
            local okC, errC = pcall(function() torso.CanCollide = false end)
            local c1, c2 = nil, nil
            pcall(function() c1 = torso.CanCollide end)
            wait(0.1)
            pcall(function() c2 = torso.CanCollide end)
            line(string.format("CanCollide (%s): before=%s write ok=%s err=%s right after=%s 0.1s later=%s",
                tostring(torso.Name), tostring(c0), tostring(okC), tostring(errC), tostring(c1), tostring(c2)))

            -- raycast straight down from you
            if p0 then
                local okR, hit = pcall(function() return workspace:Raycast(p0, Vector3.new(0, -50, 0)) end)
                local what = "nil"
                if okR and hit then
                    pcall(function() what = tostring(hit.Instance and hit.Instance:GetFullName()) .. " at " .. tostring(hit.Position) end)
                elseif not okR then
                    what = "ERROR " .. tostring(hit)
                end
                line("raycast down: ok=" .. tostring(okR) .. " hit=" .. what)
            end

            local okS = pcall(function() return RunService.Stepped end)
            line("RunService.Stepped available: " .. tostring(okS))

            -- Does Stepped actually FIRE? (available ~= fires)
            local fired = 0
            pcall(function()
                RunService.Stepped:Connect(function() fired = fired + 1 end)
            end)
            wait(1)
            line("Stepped FIRED " .. fired .. " times in 1s  (0 = collision-off can never work)")

            -- ANCHOR: the thing noclip v8 relies on
            local a0 = nil
            pcall(function() a0 = root.Anchored end)
            local okA, errA = pcall(function() root.Anchored = true end)
            local a1 = nil
            pcall(function() a1 = root.Anchored end)
            wait(0.2)
            local a2 = nil
            pcall(function() a2 = root.Anchored end)
            pcall(function() root.Anchored = (a0 == true) end)
            line(string.format("Anchored: before=%s write ok=%s err=%s after=%s 0.2s later=%s",
                tostring(a0), tostring(okA), tostring(errA), tostring(a1), tostring(a2)))

            -- Does anchoring actually stop gravity? (proof physics respects it)
            if a1 == true or a2 == true then
                pcall(function() root.Anchored = true end)
                local p1 = nil
                pcall(function() p1 = root.Position end)
                wait(0.4)
                local p2 = nil
                pcall(function() p2 = root.Position end)
                pcall(function() root.Anchored = (a0 == true) end)
                if p1 and p2 then
                    line(string.format("anchored drift over 0.4s = %.3f studs (0 = physics really is ignoring you)",
                        (p2 - p1).Magnitude))
                end
            end

            -- PlatformStand: backup way to shut the Humanoid controller up
            local hum = me and me:FindFirstChild("Humanoid")
            if hum then
                local s0 = nil
                pcall(function() s0 = hum.PlatformStand end)
                local okP = pcall(function() hum.PlatformStand = true end)
                local s1 = nil
                pcall(function() s1 = hum.PlatformStand end)
                pcall(function() hum.PlatformStand = (s0 == true) end)
                line("PlatformStand: before=" .. tostring(s0) .. " write ok=" .. tostring(okP) .. " after=" .. tostring(s1))
            else
                line("PlatformStand: no Humanoid found")
            end

            -- HumanoidRootPart specifically (the part that actually collides)
            local hrp = me and me:FindFirstChild("HumanoidRootPart")
            if hrp then
                local c0 = nil
                pcall(function() c0 = hrp.CanCollide end)
                pcall(function() hrp.CanCollide = false end)
                local c1 = nil
                pcall(function() c1 = hrp.CanCollide end)
                wait(0.5)
                local c2 = nil
                pcall(function() c2 = hrp.CanCollide end)
                line("HRP CanCollide: before=" .. tostring(c0) .. " after write=" .. tostring(c1) .. " 0.5s later=" .. tostring(c2))
            else
                line("HRP CanCollide: no HumanoidRootPart")
            end

            -- what parts does the character actually have?
            local names = {}
            pcall(function()
                for _, p in ipairs(me:GetChildren()) do
                    local isPart = false
                    pcall(function() isPart = p:IsA("BasePart") end)
                    if isPart then table.insert(names, p.Name) end
                end
            end)
            line("character BaseParts (" .. #names .. "): " .. table.concat(names, ", "))

            pcall(function() writefile("dw_noclip.txt", table.concat(out, "\n")) end)
            pcall(function() notify("Wrote dw_noclip.txt - send it to me", "Noclip Test", 6) end)
        end)
    end
end

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

-------------------------------
-- FRIENDS HP EXPORT
-- Writes dw_party.txt in your Matcha workspace folder, one line per player:
--     Name|0.73
-- Screen Macro reads that file and shows it as a percent, so it never has to
-- read anything off the screen and works with no party panel showing.
-------------------------------
task.spawn(function()
    local lastText = nil
    while true do
        if cfg.exphp then
            local ok, err = pcall(function()
                -- optional filter: only these names
                local want, filtering = {}, false
                for part in string.gmatch(cfg.friends or "", "[^,]+") do
                    local n = string.lower((string.gsub(part, "^%s*(.-)%s*$", "%1")))
                    if n ~= "" then want[n] = true; filtering = true end
                end
                local rows = {}
                for _, e in pairs(entities) do
                    if e.player and e.pct and not e.isMob then
                        local uname = e.username or e.name or ""
                        if uname ~= "" and (not filtering or want[string.lower(uname)]) then
                            table.insert(rows, { name = uname, pct = e.pct, dist = e.dist or 1e9 })
                        end
                    end
                end
                table.sort(rows, function(a, b) return a.dist < b.dist end)
                local out = {}
                for i, r in ipairs(rows) do
                    if i > 12 then break end
                    table.insert(out, string.format("%s|%.3f", r.name, r.pct))
                end
                local text = table.concat(out, "\n") .. "\n"
                -- only touch the disk when something actually changed
                if text ~= lastText then
                    lastText = text
                    writefile("dw_party.txt", text)
                end
            end)
            if not ok then report("friends hp export", err) end
        elseif lastText ~= nil then
            lastText = nil
            pcall(function() writefile("dw_party.txt", "") end)
        end
        wait(math.max(cfg.exphpms or 250, 100) / 1000)
    end
end)

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

    -- Noclip / fly are NOT run from this script any more. Matcha has its own
    -- No-Clip and Flight under Character > Movement, and those are built into
    -- the executor so they can do things a Lua script cannot. When both ran at
    -- once they each wrote your velocity every frame and fought each other.

    frameCount = frameCount + 1
    if status and frameCount % 30 == 0 then
        if cfg.status then
            status.Position = Vector2.new(camInfo.vx / 2, 70)
            if lastErr then
                status.Color = C_RED
                status.Text = "DW ERROR: " .. string.sub(lastErr, 1, 90)
            else
                status.Color = CYBER.on and CYBER.cyan or Color3.fromRGB(0, 255, 120)
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
-- (render hook done)
-------------------------------

logStep("6 render hooked (RenderStepped=" .. tostring(connected) .. ")")

-------------------------------
-- RICE (Exly78/Rice-Public) - loads alongside this script for its extras
-- like removing kill bricks. Rice is a whole second script, so you can skip
-- it with "Don't Load Rice On Execute" (makes dw_norice.txt) to save CPU.
-------------------------------
local RICE = { state = "Loading...", url = "https://raw.githubusercontent.com/Exly78/Rice-Public/main/main.lua" }
function RICE.load()
    RICE.state = "Loading..."
    task.spawn(function()
        local src = nil
        pcall(function() src = game:HttpGet(RICE.url) end)
        if type(src) ~= "string" or src == "" then
            pcall(function() src = httpget(RICE.url) end)   -- Matcha's own HTTP, if game:HttpGet isn't there
        end
        if type(src) ~= "string" or src == "" then
            RICE.state = "Failed to download"
            pcall(function() notify("Couldn't download Rice", "Rice", 5) end)
            return
        end
        local ok, err = pcall(function() loadstring(src)() end)
        if ok then
            RICE.state = "Loaded"
            logStep("6a Rice loaded")
        else
            RICE.state = "Failed to start"
            report("Rice load", err)
        end
    end)
end
do
    local skip = false
    pcall(function() skip = isfile("dw_norice.txt") end)
    if skip then RICE.state = "Not loaded (turned off)" else RICE.load() end
end
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

-- Read the talent / mantra cards on screen right now.
-- Matcha only supports some properties, and reading one it doesn't know
-- throws an error. The old reader checked ChoiceFrame.Visible (not on
-- Matcha's list), so the error made it return NO cards every time - that's
-- why nothing was ever highlighted. This only uses Name, ClassName, Text,
-- AbsolutePosition, AbsoluteSize, GetChildren and GetDescendants.
local SKIP_CLASS = {
    UIListLayout = true, UIGridLayout = true, UIAspectRatioConstraint = true, UIScale = true,
    UIPadding = true, UICorner = true, UIStroke = true, UIGradient = true, UISizeConstraint = true,
    UITextSizeConstraint = true, Sound = true, LocalScript = true, Script = true, ModuleScript = true,
}
local TITLE_NAMES = { title = true, name = true, talentname = true, cardname = true, header = true }

-- every non-empty text inside a card, in tree order
local function textsIn(card)
    local out = {}
    local ok, desc = pcall(function() return card:GetDescendants() end)
    if not ok or type(desc) ~= "table" then return out end
    for i, d in ipairs(desc) do
        if i > 150 then break end
        local cls = nil
        pcall(function() cls = d.ClassName end)
        if cls == "TextLabel" or cls == "TextButton" then
            local t, n = nil, nil
            pcall(function() t = d.Text end)
            pcall(function() n = d.Name end)
            if type(t) == "string" then
                t = string.gsub(t, "<.->", "")
                t = string.gsub(string.gsub(t, "^%s+", ""), "%s+$", "")
                if t ~= "" then table.insert(out, { text = t, name = tostring(n or "") }) end
            end
        end
    end
    return out
end

local function cardName(card)
    local texts = textsIn(card)
    -- 1) any text that is a talent/mantra in your build (or one you own)
    for _, t in ipairs(texts) do
        local c = tclean(t.text)
        if buildSet[c] or mantraSet[c] or trackState.owned[c] then return t.text end
    end
    -- 2) a label named like a title
    for _, t in ipairs(texts) do
        if TITLE_NAMES[string.lower(t.name)] then return t.text end
    end
    -- 3) the first short text that isn't a sentence (descriptions are)
    for _, t in ipairs(texts) do
        if #t.text <= 32 and not string.find(t.text, "[%.!?]") then return t.text end
    end
    return nil
end

local function rectOf(g)
    local r = nil
    pcall(function()
        local p, s = g.AbsolutePosition, g.AbsoluteSize
        if p and s and s.X > 40 and s.Y > 40 then r = { x = p.X, y = p.Y, w = s.X, h = s.Y } end
    end)
    return r
end

-- the card's box on screen; falls back to its biggest piece
local function cardRect(card)
    local r = rectOf(card)
    if r then return r end
    local best = nil
    pcall(function()
        for i, d in ipairs(card:GetDescendants()) do
            if i > 80 then break end
            local rr = rectOf(d)
            if rr and (not best or rr.w * rr.h > best.w * best.h) then best = rr end
        end
    end)
    return best
end

local function addCardsFrom(holder, cards)
    local kids = {}
    pcall(function() kids = holder:GetChildren() end)
    for _, c in ipairs(kids) do
        local cls = nil
        pcall(function() cls = c.ClassName end)
        if cls and not SKIP_CLASS[cls] then
            local n = cardName(c)
            if n and n ~= "" then table.insert(cards, { name = n, rect = cardRect(c) }) end
        end
    end
end

local function readCards()
    local cards = {}
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return cards end
    -- talent cards: PlayerGui.TalentGui.ChoiceFrame (from your dw_cards.txt)
    local tg = pg:FindFirstChild("TalentGui")
    local cf = tg and tg:FindFirstChild("ChoiceFrame")
    if cf then addCardsFrom(cf, cards) end
    -- mantra / other picks
    if #cards == 0 then
        local cp = pg:FindFirstChild("ChoicePrompt")
        local holder = cp and (cp:FindFirstChild("ScrollingFrame") or cp:FindFirstChild("ChoiceFrame"))
        if holder then addCardsFrom(holder, cards) end
    end
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

-- The highlight keybind turns the overlay on for a while even if the
-- tracker toggle is off, so you can check a card pick on demand.
local function talentActive()
    return cfg.talTrack or tick() < (trackState.flashUntil or 0)
end

local function drawTalents()
    local flashing = tick() < (trackState.flashUntil or 0)
    local onTracker = talentActive()
    local showPanel = onTracker and (cfg.talPanel ~= false or flashing)
    local showCards = onTracker and (cfg.talCards ~= false or flashing)
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
    local yoff = cfg.cardYoff or 36
    for i = 1, 8 do
        local c = showCards and cards[i] or nil
        local b, t = tdraw.boxes[i], tdraw.tags[i]
        if c and c.rect then
            local v, col = cardVerdict(c.name)
            b.Position = Vector2.new(c.rect.x, c.rect.y + yoff)
            b.Size = Vector2.new(c.rect.w, c.rect.h)
            b.Color = col
            -- cards you need get a thick border, the rest a thin one
            pcall(function() b.Thickness = (string.sub(v, 1, 3) == "GET") and 5 or 2 end)
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

-- Highlight keybind: read the cards on screen right now, tell you which to
-- take, and keep the boxes + "still need" list up for 12 seconds.
TT.highlight = function()
    trackState.flashUntil = tick() + 12
    pcall(scanOwned)
    local ok, cards = pcall(readCards)
    cards = ok and cards or {}
    trackState.cards = cards
    trackState.lastCardSig = ""          -- let the tracker loop re-announce too
    local get = {}
    for _, c in ipairs(cards) do
        local v = cardVerdict(c.name)
        if v == "GET" or v == "GET (mantra)" then table.insert(get, c.name) end
    end
    local msg
    if #cards == 0 then
        local need = joinShort(trackState.need, 6)
        msg = (#need > 0) and ("No cards up. Still need: " .. table.concat(need, ", "))
            or "No cards up, and you have everything in your build."
    elseif #get > 0 then
        msg = "TAKE: " .. table.concat(get, ", ")
    else
        msg = "None of these " .. #cards .. " cards are in your build"
    end
    pcall(function() notify(msg, "Talent Highlight", 8) end)
    pcall(drawTalents)
end

-- Tracker loop: backpack every 2s, cards every 0.3s
task.spawn(function()
    local tk = 0
    while true do
        if talentActive() then
            if tk % 7 == 0 then pcall(scanOwned) end
            local ok, cards = pcall(readCards)
            cards = ok and cards or {}
            trackState.cards = cards
            local names = {}
            for _, c in ipairs(cards) do table.insert(names, c.name) end
            local sig = table.concat(names, "|")
            if sig ~= trackState.lastCardSig then
                trackState.lastCardSig = sig
                if #cards > 0 and cfg.talNotify ~= false and cfg.talTrack then
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
-- MEMORY WRITES (memory_write + Instance.Address)
-- Normal "obj.Prop = x" is ignored on your Matcha, but raw memory writes
-- aren't. We don't hardcode offsets (they change every Roblox update):
-- we FIND them each session by scanning the object's memory for the value
-- the property currently has, then prove it by writing a test value and
-- reading the property back. Only a proven offset is ever used.
-------------------------------

local MEM = { status = "Not used yet", fb = "Off", agi = "Off" }
do
    local found = {}        -- ["Class.Prop"] = { off = n, kind = "float"/"double", scale = 1 }
    local failed = {}       -- ["Class.Prop"] = true (don't rescan every frame)
    local why = {}          -- ["Class.Prop"] = reason text for the debug file
    local SCAN_BYTES = 0x1400

    local function addrOf(inst)
        local a = nil
        pcall(function() a = inst.Address end)
        if type(a) == "number" and a > 0 then return a end
        return nil
    end

    local function rd(kind, a)
        local ok, v = pcall(function() return memory_read(kind, a) end)
        if ok and type(v) == "number" then return v end
        return nil
    end

    local function wr(kind, a, v)
        return pcall(function() memory_write(kind, a, v) end)
    end

    local function near(a, b, tol) return a and b and math.abs(a - b) < (tol or 1e-3) end

    -- getter(inst) returns the property's current number (via Matcha read)
    -- scales: memory might store hours as hours (1) or as seconds (3600)
    local function findOffset(inst, key, getter, scales)
        if found[key] then return found[key] end
        if failed[key] then return nil end
        local base = addrOf(inst)
        if not base then why[key] = "no Address"; return nil end
        local cur = getter(inst)
        if type(cur) ~= "number" then failed[key] = true; why[key] = "Matcha can't read it (" .. type(cur) .. ")"; return nil end
        if math.abs(cur) < 1e-6 then why[key] = "value is 0 right now, waiting"; return nil end

        local tries = 0
        for _, scale in ipairs(scales or { 1 }) do
            for off = 0, SCAN_BYTES, 4 do
                -- IntValue-style whole numbers may be stored as ints, not floats
                local kinds = (cur == math.floor(cur) and scale == 1) and { "float", "double", "int" } or { "float", "double" }
                for _, kind in ipairs(kinds) do
                    if kind ~= "double" or off % 8 == 0 then
                        local v = rd(kind, base + off)
                        local tol = math.max(kind == "float" and 1e-3 or 1e-6, math.abs(cur * scale) * 2e-4)
                        if kind == "int" then tol = 0.5 end
                        if near(v, cur * scale, tol) then
                            -- prove it: write a test value, read the property back
                            tries = tries + 1
                            local test = (kind == "int") and (cur + 1) or (cur + 0.731)
                            wr(kind, base + off, test * scale)
                            local back = getter(inst)
                            wr(kind, base + off, v)            -- put the original back
                            if near(back, test, 0.01) then
                                found[key] = { off = off, kind = kind, scale = scale }
                                print(string.format("[DW mem] %s -> offset 0x%X (%s x%d)", key, off, kind, scale))
                                return found[key]
                            end
                            if tries > 12 then
                                failed[key] = true
                                why[key] = "12 matches for " .. tostring(cur) .. ", none proved"
                                return nil
                            end
                        end
                    end
                end
            end
        end
        failed[key] = true
        why[key] = (tries == 0) and ("value " .. tostring(cur) .. " not found in memory") or (tries .. " matches, none proved")
        return nil
    end

    -- Color3 property (Ambient etc): 3 floats in a row
    local foundC = {}
    local function findColor(inst, key, prop)
        if foundC[key] then return foundC[key] end
        if failed[key] then return nil end
        local base = addrOf(inst)
        if not base then why[key] = "no Address"; return nil end
        local c = nil
        pcall(function() c = inst[prop] end)
        if not (c and type(c.R) == "number") then failed[key] = true; why[key] = "can't read color"; return nil end
        if c.R + c.G + c.B < 0.02 then why[key] = "color is black right now, waiting"; return nil end
        local tries = 0
        for off = 0, SCAN_BYTES, 4 do
            local r = rd("float", base + off)
            if near(r, c.R, 1e-3) and near(rd("float", base + off + 4), c.G, 1e-3) and near(rd("float", base + off + 8), c.B, 1e-3) then
                tries = tries + 1
                local test = (c.R > 0.5) and (c.R - 0.31) or (c.R + 0.31)
                wr("float", base + off, test)
                local back = nil
                pcall(function() back = inst[prop].R end)
                wr("float", base + off, r)
                if near(back, test, 0.01) then
                    foundC[key] = off
                    print(string.format("[DW mem] %s -> offset 0x%X (color)", key, off))
                    return off
                end
                if tries > 8 then break end
            end
        end
        failed[key] = true
        why[key] = (tries == 0) and "color not found in memory" or (tries .. " matches, none proved")
        return nil
    end
    local function memSetColor(inst, key, prop, r, g, b)
        local off = findColor(inst, key, prop)
        local base = addrOf(inst)
        if not (off and base) then return false end
        wr("float", base + off, r); wr("float", base + off + 4, g); wr("float", base + off + 8, b)
        local c = nil
        pcall(function() c = inst[prop] end)
        return c and near(c.R, r, 0.02) or false
    end

    -- write a number property through memory. returns true if it stuck
    local function memSet(inst, key, getter, value, scales)
        local f = findOffset(inst, key, getter, scales)
        if not f then return false end
        local base = addrOf(inst)
        if not base then return false end
        local v = value * f.scale
        if f.kind == "int" then v = math.floor(v + 0.5) end
        wr(f.kind, base + f.off, v)
        return near(getter(inst), (f.kind == "int") and math.floor(value + 0.5) or value, 0.05)
    end
    MEM.set = memSet

    MEM.resetScan = function()
        found, failed, why, foundC = {}, {}, {}, {}
        MEM.status = "Offsets cleared - will rescan"
    end

    MEM.dump = function()
        local lines = { "DW memory debug " .. os.date("%H:%M:%S") }
        for k, f in pairs(found) do table.insert(lines, string.format("OK   %s offset 0x%X %s x%d", k, f.off, f.kind, f.scale)) end
        for k, off in pairs(foundC) do table.insert(lines, string.format("OK   %s offset 0x%X color", k, off)) end
        for k, r in pairs(why) do
            if not found[k] and not foundC[k] then table.insert(lines, "FAIL " .. k .. ": " .. r) end
        end
        table.insert(lines, "World status: " .. tostring(MEM.fb))
        table.insert(lines, "Agility status: " .. tostring(MEM.agi))
        pcall(function() writefile("dw_memdebug.txt", table.concat(lines, "\n")) end)
        for _, l in ipairs(lines) do print("[DW mem] " .. l) end
    end

    MEM.report = function()
        local parts = {}
        for k, f in pairs(found) do table.insert(parts, k .. "=ok") end
        for k, _ in pairs(foundC) do table.insert(parts, k .. "=ok") end
        for k, _ in pairs(failed) do table.insert(parts, k .. "=FAIL") end
        if #parts == 0 then return "nothing scanned yet" end
        table.sort(parts)
        return table.concat(parts, ", ")
    end

    ---------------------------------------------------------------
    -- FULLBRIGHT + NO FOG (memory). Deepwoken keeps re-tweening its
    -- lighting, so we re-apply every 0.25s while it's on.
    ---------------------------------------------------------------
    local function g(prop) return function(inst) local v = nil; pcall(function() v = inst[prop] end); return v end end
    local saved = {}

    task.spawn(function()
        while true do
            pcall(function()
                local fbOn = V("dw_mfullbright", false)
                local fogOn = V("dw_mnofog", false)
                local results = {}

                if fbOn then
                    local lvl = V("dw_mfbbright", 3)
                    local okC = memSet(Lighting, "Lighting.ClockTime", g("ClockTime"), 14, { 1, 3600 })
                    local okB = memSet(Lighting, "Lighting.Brightness", g("Brightness"), lvl)
                    local okE = memSet(Lighting, "Lighting.ExposureCompensation", g("ExposureCompensation"), V("dw_mfbexpo", 1) * 0.5)
                    table.insert(results, "time " .. (okC and "ok" or "x"))
                    table.insert(results, "bright " .. (okB and "ok" or "x"))
                    table.insert(results, "expo " .. (okE and "ok" or "x"))
                    local a = V("dw_mfbambient", 70) / 100
                    local okAm = memSetColor(Lighting, "Lighting.Ambient", "Ambient", a, a, a)
                    local okOA = memSetColor(Lighting, "Lighting.OutdoorAmbient", "OutdoorAmbient", a, a, a)
                    table.insert(results, "ambient " .. ((okAm or okOA) and "ok" or "x"))
                    -- Deepwoken darkens areas with ColorCorrection: neutralize it
                    for _, fx in ipairs(Lighting:GetChildren()) do
                        if fx.ClassName == "ColorCorrectionEffect" then
                            local br = nil
                            pcall(function() br = fx.Brightness end)
                            if type(br) == "number" and br < 0 then
                                memSet(fx, "ColorCorrectionEffect.Brightness", g("Brightness"), 0)
                            end
                        end
                    end
                    saved.fb = true
                end

                if fogOn then
                    local okF = memSet(Lighting, "Lighting.FogEnd", g("FogEnd"), 100000)
                    local atmo = Lighting:FindFirstChild("Atmosphere")
                    local okA = false
                    if atmo then okA = memSet(atmo, "Atmosphere.Density", g("Density"), 0) end
                    table.insert(results, "fog " .. (okF and "ok" or "x"))
                    table.insert(results, "atmo " .. ((atmo and (okA and "ok" or "x")) or "none"))
                end

                if #results > 0 then
                    MEM.fb = table.concat(results, " | ")
                else
                    MEM.fb = "Off"
                end
            end)
            wait(0.25)
        end
    end)

    ---------------------------------------------------------------
    -- AGILITY (memory): PassiveAgility.Value via memory_write
    ---------------------------------------------------------------
    local agiOld = nil
    local agiOn = false
    -- `target` is the agility value you want outright, not a multiplier.
    MEM.agilityStep = function(me, target)
        local passive = me and me:FindFirstChild("PassiveAgility")
        if not passive then MEM.agi = "PassiveAgility not found"; return MEM.agi end
        local cur = nil
        pcall(function() cur = passive.Value end)
        if not agiOn then agiOld = cur; agiOn = true end
        local ok = memSet(passive, "NumberValue.Value", g("Value"), target)
        if ok then
            MEM.agi = string.format("ON (memory): agility %s -> %g",
                (type(agiOld) == "number") and string.format("%.1f", agiOld) or "?", target)
        else
            MEM.agi = "Value offset not found - press Memory Debug and send me dw_memdebug.txt"
        end
        return MEM.agi
    end
    MEM.agilityRestore = function(me)
        if not agiOn then return end
        agiOn = false
        local passive = me and me:FindFirstChild("PassiveAgility")
        if passive and agiOld then
            pcall(memSet, passive, "NumberValue.Value", g("Value"), agiOld)
        end
    end
end

-------------------------------
-- MOVEMENT SPOOF (our own, no Rice)
-- "Velocity" mode (default): sets your speed instead of moving your
-- position, so Roblox physics still stops you at walls (no clipping) and it
-- looks smooth. Speed = the game's own WalkSpeed x your multiplier, so when
-- the game slows/stuns you (lowers WalkSpeed), the boost drops with it.
-- "Push" mode: every frame it reads how fast the GAME is moving you right
-- now and pushes you a bit further the same way. It multiplies the game's
-- own movement, so stuns / parry slows / jump slows still hit you:
-- stunned = 0 speed x 3 = still 0. Uses root.Position, which is what
-- Matcha's own teleport example writes.
-- "PassiveAgility" mode: writes the PassiveAgility value like Rain does.
-- Your Matcha may ignore that one; the status line tells you.
-------------------------------

-- Teleports (filled in further down; declared here so No Fall can see it)
local TP = { status = "Idle", running = false, areas = {}, spots = {} }

local SPD = { status = "Off" }
do
    local SPEED_KEYS = { [1] = 0x58, [2] = 0x43, [3] = 0x56, [4] = 0x42, [5] = 0x5A } -- X C V B Z
    local lastT = tick()
    local lastPos = nil
    local keyWas = false
    local fails = 0
    local guardUntil = 0          -- wall guard: pause pushing until this time
    local lastHs = nil
    local lastPush = nil          -- { dx, dz } unit direction of last push
    local learnedBase = 16        -- your normal speed, learned while not boosting
    local agiOld, agiWas = nil, false

    local function myParts()
        local live = workspace:FindFirstChild("Live")
        local me = live and live:FindFirstChild(LocalPlayer.Name)
        return me, me and me:FindFirstChild("HumanoidRootPart"), me and me:FindFirstChild("Humanoid")
    end

    local function readVel(root)
        local vel = nil
        pcall(function() vel = root.AssemblyLinearVelocity end)
        if not (vel and type(vel.X) == "number") then
            vel = nil
            pcall(function() vel = root.Velocity end)
        end
        if vel and type(vel.X) == "number" then return vel end
        return nil
    end

    local function writeVel(root, v)
        local ok = pcall(function() root.AssemblyLinearVelocity = v end)
        if not ok then pcall(function() root.Velocity = v end) end
    end

    -------------------------------------------------------------------
    -- NO FALL DAMAGE (glide)
    -- v13 capped fall speed at 40, but you still landed INJURED: the game
    -- isn't judging how hard you hit, it's judging the fall itself. Flying
    -- never got you hurt, because while flying your downward speed is ~0
    -- and the game never sees a fall start. So this does the same: the
    -- moment you start dropping, your fall speed is set back to 0 and you
    -- sink by being MOVED down instead of by falling. (Rain's real no-fall
    -- needs the game's EffectReplicator, which Standard Matcha can't call.)
    -------------------------------------------------------------------
    SPD.fallStatus = "Off"
    local nfLast = tick()
    SPD.noFall = function()
        local now = tick()
        local dt = clamp(now - nfLast, 0, 0.1)
        nfLast = now
        if KB.pressed("dw_nofallkey", cfg.nofallKey) then
            cfg.nofall = not cfg.nofall
            SetV("dw_nofall", cfg.nofall)
            pcall(function() notify(cfg.nofall and "No Fall ON" or "No Fall OFF", "No Fall", 2) end)
        end
        if not cfg.nofall then SPD.fallStatus = "Off"; SPD.gliding, SPD.prevVY = false, nil; return end
        if TP and TP.running then SPD.fallStatus = "paused (teleport moving you)"; SPD.gliding, SPD.prevVY = false, nil; return end
        local _, root = myParts()
        if not root then SPD.fallStatus = "ON (no character)"; return end
        local vel = readVel(root)
        if not vel then SPD.fallStatus = "ON - can't read your velocity"; return end

        -- v21: FALL BREAKER - from the game's own fall code (dw_fallcode.txt,
        -- WorldClient fall()). While you're in the air it adds up how far you
        -- drop each frame. The moment you go UP even a little for one frame,
        -- that fall is over and a new one starts from 0. Damage only happens
        -- when one unbroken fall goes past ~20-40 studs. So every few studs
        -- of drop we lift you a hair: every fall the game measures stays tiny.
        local y = nil
        pcall(function() y = root.Position.Y end)
        local brk = SPD.brk or {}
        SPD.brk = brk
        if y then
            if not brk.top or not brk.prev or y > brk.prev + 0.01 or now - (brk.t or 0) > 0.5 then
                brk.top = y   -- went up (or first frame): the game started a new fall too
            end
            local limit = clamp(tonumber(cfg.nofallBreak) or 12, 4, 30)
            if brk.top - y >= limit then
                -- more than one frame of falling, so the game sees Y go up
                local lift = math.max(0.6, math.abs(vel.Y) * 0.05 + 0.3)
                local p = nil
                pcall(function() p = root.Position end)
                if p and pcall(function() root.Position = p + Vector3.new(0, lift, 0) end) then
                    y = y + lift
                    brk.top = y
                    brk.count = (brk.count or 0) + 1
                end
            end
            brk.prev, brk.t = y, now
        end
        local mode = tonumber(cfg.nofallMode) or 0
        if mode == 2 then
            SPD.gliding = false
            SPD.fallStatus = string.format("ON - fall reset every %d studs (%d resets)",
                clamp(tonumber(cfg.nofallBreak) or 12, 4, 30), brk.count or 0)
            return
        end

        -- v20: only REAL falling counts. Gravity speeds you up a little
        -- every frame; Matcha's Flight (or a teleport) sets your speed
        -- directly and it barely changes frame to frame. v14-v19 grabbed
        -- anything moving down faster than 8, so flying down/straight got
        -- yanked back and forth between Flight and the glide = the lag.
        -- (Matcha hands back nil for workspace.Gravity - that nil crashed v20
        -- every frame, so No Fall did nothing at all)
        local g = nil
        pcall(function() g = tonumber(workspace.Gravity) end)
        if not g or g <= 0 then g = 196.2 end
        local base = SPD.wrote or SPD.prevVY or vel.Y   -- what the speed was after last frame
        local dv = vel.Y - base
        local pull = g * dt
        local gravityLike = dv < -0.5 and dv > -(pull * 2.5 + 2)
        SPD.prevVY, SPD.wrote = vel.Y, nil

        local catch = clamp(tonumber(cfg.nofallCatch) or 20, 8, 60)
        local delay = clamp(tonumber(cfg.nofallDelay) or 0, 0, 2000) / 1000
        if not SPD.gliding then
            if vel.Y < -1 and gravityLike then
                SPD.fallFrames = (SPD.fallFrames or 0) + 1
                SPD.fallSince = SPD.fallSince or now
            elseif dv > 1 or vel.Y > -1 then
                SPD.fallFrames, SPD.fallSince = 0, nil   -- going up / standing: not a fall
            end
            -- (frames where the speed didn't change are ignored: Flight)
            if vel.Y < -catch and (SPD.fallFrames or 0) >= 2 and now - (SPD.fallSince or now) >= delay then
                SPD.gliding, SPD.calmSince = true, nil
            else
                SPD.fallStatus = (vel.Y < -catch and (SPD.fallFrames or 0) < 2)
                    and "ON - not a real fall (flying?), left alone" or "ON - waiting for a drop"
                return
            end
        else
            -- what we set last frame plus one frame of gravity is expected.
            -- Anything else means Flight / a jump / a teleport took over.
            if dv > 2 or dv < -(pull * 2.5 + 4) then
                SPD.gliding, SPD.fallFrames, SPD.fallSince = false, 0, nil
                SPD.fallStatus = "ON - let go (something else is moving you)"
                return
            end
            if vel.Y > -0.5 and dv > -0.5 then
                -- no gravity since last frame: standing on something
                SPD.calmSince = SPD.calmSince or now
                if now - SPD.calmSince > 0.08 then
                    SPD.gliding, SPD.fallFrames, SPD.fallSince = false, 0, nil
                    SPD.fallStatus = "ON - landed"
                    return
                end
            else
                SPD.calmSince = nil
            end
        end

        if mode == 1 then
            -- SPEED CAP (the old one): fall, but never faster than the cap
            local cap = clamp(tonumber(cfg.nofallMax) or 40, 5, 200)
            if vel.Y < -cap then
                writeVel(root, Vector3.new(vel.X, -cap, vel.Z))
                SPD.wrote = -cap
            end
            SPD.fallStatus = string.format("ON - speed cap %d", cap)
        else
            -- GLIDE: fall speed held at 0, you're moved down instead.
            -- Stops moving you down the moment nothing is pulling you any more,
            -- so it never shoves you into the floor once you've landed.
            local sink = clamp(tonumber(cfg.nofallCap) or 30, 5, 120)
            writeVel(root, Vector3.new(vel.X, 0, vel.Z))
            SPD.wrote = 0
            if not SPD.calmSince or now - SPD.calmSince < 0.02 then
                local p = nil
                pcall(function() p = root.Position end)
                if p then pcall(function() root.Position = p - Vector3.new(0, sink * dt, 0) end) end
            end
            SPD.fallStatus = string.format("ON - gliding down (%d studs/s)", sink)
        end
    end

    -- Saves the game's own fall-damage script as text (Matcha can decompile
    -- local scripts). If glide still lets damage through, send me this file
    -- and I can see exactly what the game checks.
    SPD.dumpFallCode = function()
        task.spawn(function()
            local found = {}
            pcall(function()
                local pg = LocalPlayer:FindFirstChild("PlayerGui")
                local wc = pg and pg:FindFirstChild("WorldClient")
                if wc then table.insert(found, wc) end
            end)
            if #found == 0 then
                pcall(function()
                    for _, s in ipairs(getscripts()) do
                        local n = ""
                        pcall(function() n = s.Name end)
                        local l = string.lower(n)
                        if string.find(l, "world") or string.find(l, "fall") then table.insert(found, s) end
                        if #found >= 4 then break end
                    end
                end)
            end
            if #found == 0 then
                pcall(function() notify("Couldn't find the game's fall script", "Fall Debug", 5) end)
                return
            end
            local out = {}
            for _, s in ipairs(found) do
                local name = "?"
                pcall(function() name = s:GetFullName() end)
                local src = nil
                pcall(function() src = decompile(s) end)
                table.insert(out, "==== " .. name .. " ====")
                table.insert(out, type(src) == "string" and src or "(decompile failed)")
            end
            pcall(function() writefile("dw_fallcode.txt", table.concat(out, "\n")) end)
            pcall(function() notify("Wrote dw_fallcode.txt - send it to me", "Fall Debug", 6) end)
        end)
    end

    -- Velocity mode: speed comes from WalkSpeed (never from our own boosted
    -- speed), so it can't snowball out of control
    local function velocityStep(root, hum, mult)
        if not hum then return "No Humanoid found" end
        local ws, md = nil, nil
        pcall(function() ws = hum.WalkSpeed end)
        pcall(function() md = hum.MoveDirection end)
        local vel = readVel(root)
        if not vel then return "Matcha can't read your velocity - try Push mode" end
        local usingLearned = false
        if type(ws) ~= "number" then ws = learnedBase; usingLearned = true end

        -- which way you're trying to go: your WASD direction, or failing that
        -- the way you're already moving
        local dx, dz = 0, 0
        if md and type(md.X) == "number" then
            dx, dz = md.X, md.Z
        else
            local hs = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
            if hs > 2 then dx, dz = vel.X / hs, vel.Z / hs end
        end
        local len = math.sqrt(dx * dx + dz * dz)
        if len < 0.1 or ws < 1 then
            return string.format("ON %.1fx (standing still / slowed to 0)", mult)
        end
        dx, dz = dx / len, dz / len

        local target = ws * mult
        local tx, tz = dx * target, dz * target
        writeVel(root, Vector3.new(tx, vel.Y, tz))

        local after = readVel(root)
        if after and math.abs(after.X - tx) < 0.5 and math.abs(after.Z - tz) < 0.5 then
            fails = 0
            return string.format("ON %.1fx (%s %d -> %d)%s", mult, usingLearned and "base" or "walkspeed",
                math.floor(ws), math.floor(target), usingLearned and " - ignores slows" or "")
        end
        fails = fails + 1
        if fails > 30 then return "Matcha ignored the speed write - try Push mode" end
        return string.format("ON %.1fx", mult)
    end

    local function restoreAgility(me)
        pcall(MEM.agilityRestore, me)
        if not agiWas then return end
        pcall(function()
            local passive = me and me:FindFirstChild("PassiveAgility")
            if passive and agiOld then passive.Value = agiOld end
        end)
        agiWas = false
    end

    -- Game's current horizontal speed: velocity if Matcha can read it,
    -- otherwise how far you moved since last frame (after our push)
    local function gameVelocity(root, pos, dt)
        local vel = nil
        pcall(function() vel = root.AssemblyLinearVelocity end)
        if not (vel and type(vel.X) == "number") then
            pcall(function() vel = root.Velocity end)
        end
        if vel and type(vel.X) == "number" then return vel.X, vel.Z end
        if lastPos and dt > 0 then
            return (pos.X - lastPos.X) / dt, (pos.Z - lastPos.Z) / dt
        end
        return 0, 0
    end

    -- Agility "amount": the custom box wins when it holds a number (1-100000),
    -- otherwise the 1-1000 slider. Same formula as Project Rain:
    --     agility = 8 + (amount / 10) * 2
    local function agiAmount()
        local n = tonumber(cfg.agiCustom)
        if n then return clamp(math.floor(n + 0.5), 1, 100000) end
        return clamp(math.floor((cfg.agiAmt or 10) + 0.5), 1, 1000)
    end
    local function agiFromAmount(amount) return 8 + (amount / 10) * 2 end
    SPD.agiAmount, SPD.agiFromAmount = agiAmount, agiFromAmount

    -- Step keys. Agility and speed each have their own interval.
    local function stepKeys()
        local up = KB.pressed("dw_agiupkey", cfg.agiUp)
        local down = KB.pressed("dw_agidownkey", cfg.agiDown)
        if up or down then
            -- a step of 0 (what the zeroed slider gave you) would do nothing
            local s = math.max(math.floor(tonumber(cfg.agiStep) or 5), 1)
            local amt = clamp(agiAmount() + (up and s or -s), 1, 100000)
            cfg.agiCustom = tostring(amt)
            SetV("dw_agicustom", cfg.agiCustom)
            pcall(function()
                notify(string.format("amount %d  ->  agility %g", amt, agiFromAmount(amt)), "Agility", 1.5)
            end)
        end
        if KB.pressed("dw_talhlkey", cfg.talKey) and TT.highlight then pcall(TT.highlight) end
    end

    local function step(dt)
        pcall(stepKeys)
        local on = cfg.speedOn and true or false

        if KB.pressed("dw_speedkeyname", cfg.speedKeyName) then
            on = not on
            cfg.speedOn = on
            SetV("dw_speed", on)
            pcall(function() notify(on and "Agility Spoof ON" or "Agility Spoof OFF", "Agility", 2) end)
        end

        -- PassiveAgility is the only spoof now (Push / Velocity removed)
        local mode = 2
        local mult = 1
        local me, root, hum = myParts()
        if not root then
            SPD.status = on and "No character (dead / loading?)" or "Off"
            lastPos = nil
            return
        end

        if not on or mode ~= 2 then restoreAgility(me) end
        if not on then
            SPD.status = "Off"
            lastPos = nil
            return
        end
        if NOCLIP.on then
            SPD.status = "Paused (noclip is on)"
            lastPos = nil
            return
        end

        -- PassiveAgility value mode
        if mode == 1 then
            SPD.status = velocityStep(root, hum, mult)
            return
        end

        if mode == 2 then
            local passive = me:FindFirstChild("PassiveAgility")
            if not passive then SPD.status = "PassiveAgility not found"; return end
            if not agiWas then
                agiOld = passive.Value
                agiWas = true
            end
            local amount = agiAmount()
            local target = agiFromAmount(amount)
            pcall(function() if passive.Value ~= target then passive.Value = target end end)
            local now = nil
            pcall(function() now = passive.Value end)
            if type(now) == "number" and math.abs(now - target) < 0.05 then
                SPD.status = string.format("ON: amount %d -> agility %g (was %s)", amount, target,
                    (type(agiOld) == "number") and string.format("%.1f", agiOld) or "?")
            else
                -- normal write ignored on Standard -> go through memory
                SPD.status = MEM.agilityStep(me, target)
            end
            return
        end

        -- Push mode (default)
        local pos = nil
        pcall(function() pos = root.Position end)
        if not pos then return end
        local vx, vz = gameVelocity(root, pos, dt)
        local hs = math.sqrt(vx * vx + vz * vz)
        local now = tick()

        -- WALL GUARD 1: last frame we pushed you, but this frame physics (a wall)
        -- or the server shoved you backwards -> stop pushing for a moment
        if lastPush and lastPos then
            local back = (pos.X - lastPos.X) * lastPush[1] + (pos.Z - lastPos.Z) * lastPush[2]
            if back < -0.15 then guardUntil = now + 0.4 end
        end
        -- WALL GUARD 2: your speed suddenly dropped by half (ran into something)
        if lastHs and lastHs > 6 and hs < lastHs * 0.5 then guardUntil = now + 0.3 end
        lastHs = hs
        lastPush = nil

        -- standing still / stunned: nothing to multiply
        -- crazy fast (knockback, fling, Matcha fly): leave it alone
        if hs < 2 or hs > 90 then
            lastPos = pos
            SPD.status = string.format("ON %.1fx (waiting for you to move)", mult)
            return
        end
        if now < guardUntil then
            lastPos = pos
            SPD.status = string.format("ON %.1fx (paused - wall / server pushback)", mult)
            return
        end

        learnedBase = learnedBase * 0.98 + math.min(hs, 40) * 0.02

        -- small steps only (max 1.5 studs a frame) so you can't tunnel into walls
        local step = math.min(hs * (mult - 1) * dt, 1.5)
        local ux, uz = vx / hs, vz / hs
        local tx = pos.X + ux * step
        local tz = pos.Z + uz * step
        pcall(function() root.Position = Vector3.new(tx, pos.Y, tz) end)

        local after = nil
        pcall(function() after = root.Position end)
        if after and math.abs(after.X - tx) < 0.1 and math.abs(after.Z - tz) < 0.1 then
            fails = 0
            lastPush = { ux, uz }
            SPD.status = string.format("ON %.1fx (%d -> %d studs/s)", mult, math.floor(hs), math.floor(hs * mult))
        else
            fails = fails + 1
            if fails > 30 then SPD.status = "Matcha ignored the move - doesn't work on yours" end
        end
        lastPos = after or pos
    end

    -------------------------------
    -- MOVE WHILE STUNNED: if you're holding WASD but the game has you stuck
    -- (stun / endlag), push you the way you're steering. Movement only - it
    -- can't make you attack or parry sooner.
    -------------------------------
    local K_W, K_A, K_S, K_D = 0x57, 0x41, 0x53, 0x44
    local sm = { lastPos = nil, lastDir = nil, guard = 0, keyWas = false, status = "Off" }
    SPD.stunStatus = function() return sm.status end

    local function keyDown(k)
        local d = false
        pcall(function() d = iskeypressed(k) end)
        return d
    end

    -- camera forward/right flattened to the ground
    local function camAxes(rootPos)
        local fx, fz = nil, nil
        pcall(function()
            local lv = workspace.CurrentCamera.CFrame.LookVector
            fx, fz = lv.X, lv.Z
        end)
        if not fx then
            -- no LookVector: camera is behind you, so "forward" = camera -> you
            pcall(function()
                local cp = workspace.CurrentCamera.CFrame.Position
                fx, fz = rootPos.X - cp.X, rootPos.Z - cp.Z
            end)
        end
        if not fx then return nil end
        local len = math.sqrt(fx * fx + fz * fz)
        if len < 0.01 then return nil end
        fx, fz = fx / len, fz / len
        return fx, fz, -fz, fx   -- forward x,z  right x,z
    end

    local SM_KEYS = { [1] = 0x4E, [2] = 0x4D, [3] = 0x4A, [4] = 0x4B, [5] = 0x4C } -- N M J K L
    SPD.stunStep = function(dt)
        local on = cfg.stunOn and true or false
        local k = nil   -- quick-pick keys removed; only the key you set
        local custom = KB.vk(cfg.stunKeyName) ~= nil
        if custom or k then
            local down, edge
            if custom then
                edge = KB.pressed("dw_stunkeyname", cfg.stunKeyName)
                down = edge
            else
                down = keyDown(k)
                edge = down and not sm.keyWas
            end
            if edge then
                on = not on
                cfg.stunOn = on
                SetV("dw_stunmove", on)
                pcall(function() notify(on and "Move While Stunned ON" or "Move While Stunned OFF", "Movement", 2) end)
            end
            sm.keyWas = down
        end
        if not on then sm.status = "Off"; sm.lastPos = nil; return end
        if NOCLIP.on then sm.status = "Paused (noclip is on)"; sm.lastPos = nil; return end

        local _, root = myParts()
        if not root then sm.status = "No character"; return end
        local pos = nil
        pcall(function() pos = root.Position end)
        if not pos then return end

        -- which way you're steering
        local ix, iz = 0, 0
        local fx, fz, rx, rz = camAxes(pos)
        if not fx then sm.status = "Can't read camera"; return end
        if keyDown(K_W) then ix, iz = ix + fx, iz + fz end
        if keyDown(K_S) then ix, iz = ix - fx, iz - fz end
        if keyDown(K_D) then ix, iz = ix + rx, iz + rz end
        if keyDown(K_A) then ix, iz = ix - rx, iz - rz end
        local il = math.sqrt(ix * ix + iz * iz)

        local vx, vz = gameVelocity(root, pos, dt)
        local hs = math.sqrt(vx * vx + vz * vz)
        local now = tick()

        -- wall guard: last push got shoved back -> wall or server, back off
        if sm.lastDir and sm.lastPos then
            local back = (pos.X - sm.lastPos.X) * sm.lastDir[1] + (pos.Z - sm.lastPos.Z) * sm.lastDir[2]
            if back < -0.15 then sm.guard = now + 0.5 end
        end
        sm.lastDir = nil

        if il < 0.1 then
            sm.status = "ON (not steering)"; sm.lastPos = pos; return
        end
        -- the game is already moving you normally: not stunned, do nothing
        if hs > 4 then
            sm.status = "ON (you can move normally)"; sm.lastPos = pos; return
        end
        if now < sm.guard then
            sm.status = "ON (paused - wall / server pushback)"; sm.lastPos = pos; return
        end

        local speed = cfg.stunSpeed or 14
        local stepLen = math.min(speed * dt, 1.5)
        local ux, uz = ix / il, iz / il
        local tx, tz = pos.X + ux * stepLen, pos.Z + uz * stepLen
        pcall(function() root.Position = Vector3.new(tx, pos.Y, tz) end)
        local after = nil
        pcall(function() after = root.Position end)
        if after and math.abs(after.X - tx) < 0.1 and math.abs(after.Z - tz) < 0.1 then
            sm.lastDir = { ux, uz }
            sm.status = "ON - moving you while stuck (" .. speed .. " studs/s)"
        else
            sm.status = "Matcha ignored the move"
        end
        sm.lastPos = after or pos
    end

    task.spawn(function()
        while true do
            local now = tick()
            local dt = clamp(now - lastT, 0, 0.1)
            lastT = now
            local ok, err = pcall(step, dt)
            if not ok then report("speed", err) end
            local ok2, err2 = pcall(SPD.stunStep, dt)
            if not ok2 then report("stunmove", err2) end
            local ok3, err3 = pcall(SPD.noFall)
            if not ok3 then report("nofall", err3) end
            task.wait()
        end
    end)
end

-------------------------------
-- BOAT SPEED
-- Pushes you (and the boat you're sitting on) a bit further every frame in
-- the direction the boat is ALREADY going. The game's own speed is never
-- touched, so it can't snowball: no sail = no speed = no push.
-------------------------------
local BOAT = { status = "Off", partName = nil }
do
    local lastT = tick()
    local lastPos, lastDir, guard = nil, nil, 0
    local boatPart, nextSearch, searching = nil, 0, false
    local PARTC = { Part = true, MeshPart = true, UnionOperation = true, WedgePart = true,
        Seat = true, VehicleSeat = true, CornerWedgePart = true, TrussPart = true }
    local SKIP = { Terrain = true, Camera = true }

    local function parts()
        local live = workspace:FindFirstChild("Live")
        local me = live and live:FindFirstChild(LocalPlayer.Name)
        return me, me and me:FindFirstChild("HumanoidRootPart")
    end

    local function velOf(p)
        local v = nil
        pcall(function() v = p.AssemblyLinearVelocity end)
        if not (v and type(v.X) == "number") then
            v = nil
            pcall(function() v = p.Velocity end)
        end
        if v and type(v.X) == "number" then return v end
        return nil
    end

    -- Walk workspace (Matcha can't tell us SeatPart / Sit) and call fn for
    -- every part within `radius` of `center` that isn't part of you.
    local function nearParts(center, radius, me, fn)
        local queue, qi, budget = {}, 1, 12000
        for _, c in ipairs(workspace:GetChildren()) do
            local n = ""
            pcall(function() n = c.Name end)
            if not SKIP[n] then table.insert(queue, { c, 1, n }) end
        end
        while qi <= #queue and budget > 0 do
            local inst, depth, path = queue[qi][1], queue[qi][2], queue[qi][3]
            qi = qi + 1
            budget = budget - 1
            if budget % 400 == 0 then task.wait() end
            if inst ~= me then
                local cls = ""
                pcall(function() cls = inst.ClassName end)
                if PARTC[cls] then
                    local pos = nil
                    pcall(function() pos = inst.Position end)
                    if pos and (pos - center).Magnitude <= radius then fn(inst, path, cls, pos) end
                end
                if depth < 6 and (cls == "Folder" or cls == "Model" or PARTC[cls]) then
                    local kids = {}
                    pcall(function() kids = inst:GetChildren() end)
                    if #kids < 3000 then
                        for _, k in ipairs(kids) do
                            local kn = "?"
                            pcall(function() kn = k.Name end)
                            table.insert(queue, { k, depth + 1, path .. "/" .. kn })
                        end
                    end
                end
            end
        end
    end

    -- the boat = a part near you moving the same way you are
    local function findBoat(me, rpos, rvel)
        local best, bestScore = nil, 1e9
        nearParts(rpos, 25, me, function(p, path, cls, pos)
            local v = velOf(p)
            if v then
                local d = math.abs(v.X - rvel.X) + math.abs(v.Z - rvel.Z)
                local score = d + (pos - rpos).Magnitude * 0.05
                if d < 4 and score < bestScore then best, bestScore = p, score; BOAT.partName = path end
            end
        end)
        return best
    end

    local function step(dt)
        if KB.pressed("dw_boatkey", cfg.boatKey) then
            cfg.boatOn = not cfg.boatOn
            SetV("dw_boat", cfg.boatOn)
            pcall(function() notify(cfg.boatOn and "Boat Speed ON" or "Boat Speed OFF", "Boat", 2) end)
        end
        if not cfg.boatOn then BOAT.status = "Off"; lastPos = nil; boatPart = nil; return end
        local me, root = parts()
        if not root then BOAT.status = "ON (no character)"; lastPos = nil; return end

        local pos = nil
        pcall(function() pos = root.Position end)
        if not pos then return end
        local vel = velOf(root)
        local vx, vz = 0, 0
        if vel then
            vx, vz = vel.X, vel.Z
        elseif lastPos and dt > 0 then
            vx, vz = (pos.X - lastPos.X) / dt, (pos.Z - lastPos.Z) / dt
        end
        local hs = math.sqrt(vx * vx + vz * vz)
        local now = tick()

        if lastDir and lastPos then
            local back = (pos.X - lastPos.X) * lastDir[1] + (pos.Z - lastPos.Z) * lastDir[2]
            if back < -0.2 then guard = now + 0.5 end
        end
        lastDir = nil
        if hs < 2 then
            BOAT.status = "ON - waiting for the boat to move"
            lastPos = pos
            return
        end
        if now < guard then
            BOAT.status = "ON - paused (hit something / pulled back)"
            lastPos = pos
            return
        end

        -- look for the boat in the background while you sail
        if not boatPart and not searching and now > nextSearch and vel then
            searching, nextSearch = true, now + 3
            task.spawn(function()
                local ok, p = pcall(findBoat, me, pos, vel)
                if ok and p then boatPart = p end
                searching = false
            end)
        end

        local mult = clamp((tonumber(cfg.boatMult) or 20) / 10, 1, 10)
        local push = math.min(hs * (mult - 1) * dt, 4)
        local ux, uz = vx / hs, vz / hs
        local off = Vector3.new(ux * push, 0, uz * push)
        local onBoat = false
        if boatPart then
            local bp = nil
            pcall(function() bp = boatPart.Position end)
            if bp and (bp - pos).Magnitude < 40 then
                onBoat = pcall(function() boatPart.Position = bp + off end)
            else
                boatPart = nil   -- got off / boat gone
            end
        end
        pcall(function() root.Position = pos + off end)
        lastDir = { ux, uz }
        lastPos = pos + off
        BOAT.status = string.format("ON %.1fx (%d -> ~%d studs/s) %s", mult, math.floor(hs), math.floor(hs * mult),
            onBoat and ("boat: " .. tostring(BOAT.partName)) or (searching and "[looking for the boat]" or "[moving you only]"))
    end

    -- Boat Scan: every part within 30 studs, with how fast it's moving.
    -- Sail, then press it: the boat is the stuff moving at your speed.
    function BOAT.scan()
        task.spawn(function()
            local out = { "DW boat scan v2 " .. os.date() }
            local me, root = parts()
            local rpos = nil
            pcall(function() rpos = root.Position end)
            if not rpos then table.insert(out, "no character") else
                local rv = velOf(root)
                table.insert(out, "you: speed " .. (rv and string.format("%.1f", Vector3.new(rv.X, 0, rv.Z).Magnitude) or "?"))
                local rows = {}
                nearParts(rpos, 30, me, function(p, path, cls, pos)
                    local v = velOf(p)
                    local sp = v and Vector3.new(v.X, 0, v.Z).Magnitude or -1
                    table.insert(rows, { d = (pos - rpos).Magnitude, line = string.format("%5.1fm  speed %6.1f  %s  (%s)",
                        (pos - rpos).Magnitude, sp, path, cls) })
                end)
                table.sort(rows, function(a, b) return a.d < b.d end)
                table.insert(out, "-- parts within 30 studs (closest first): " .. #rows .. " --")
                for i, r in ipairs(rows) do
                    if i > 120 then break end
                    table.insert(out, r.line)
                end
            end
            pcall(function() writefile("dw_boat.txt", table.concat(out, "\n")) end)
            for i, l in ipairs(out) do
                if i > 30 then break end
                print("[DW boat] " .. l)
            end
            pcall(function() notify("Wrote dw_boat.txt - send it to me", "Boat Scan", 5) end)
        end)
    end

    task.spawn(function()
        while true do
            local now = tick()
            local dt = clamp(now - lastT, 0, 0.1)
            lastT = now
            local ok, err = pcall(step, dt)
            if not ok then report("boat", err) end
            task.wait()
        end
    end)
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

-- CLOSE SCAN: finds the real name of the thing you're standing next to.
-- Lists every "press E" prompt within 80m (chests, loot, doors) with its
-- full path, plus every part within 25m. Writes dw_closescan.txt
local function closeScan()
    task.spawn(function()
        local ok, err = pcall(function()
            scanStatus = "Close scan running..."
            local myPos = getMyPos()
            if not myPos then scanStatus = "Can't find your position"; return end
            local SKIP = { Live = true, Terrain = true, Camera = true }
            local prompts, parts, seenPath = {}, {}, {}
            local queue = {}
            for _, c in ipairs(workspace:GetChildren()) do
                local n = c.Name or "?"
                if not SKIP[n] then table.insert(queue, { c, n, 1 }) end
            end
            local qi, budget = 1, 80000
            while qi <= #queue and budget > 0 do
                local inst, path, depth = queue[qi][1], queue[qi][2], queue[qi][3]
                qi = qi + 1
                budget = budget - 1
                if budget % 400 == 0 then
                    scanStatus = "Close scan... " .. (80000 - budget) .. " checked"
                    wait()
                end
                local cls = inst.ClassName or "?"
                if cls == "ProximityPrompt" then
                    local pp = nil
                    pcall(function() pp = inst.Parent.Position end)
                    local d = pp and (pp - myPos).Magnitude or nil
                    if d and d <= 80 then
                        local act, objt = "", ""
                        pcall(function() act = tostring(inst.ActionText or "") end)
                        pcall(function() objt = tostring(inst.ObjectText or "") end)
                        table.insert(prompts, { path = path, d = d, txt = act .. (objt ~= "" and (" / " .. objt) or "") })
                    end
                else
                    local isPart = false
                    pcall(function() isPart = inst:IsA("BasePart") end)
                    if isPart then
                        local pp = nil
                        pcall(function() pp = inst.Position end)
                        local d = pp and (pp - myPos).Magnitude or nil
                        if d and d <= 25 then
                            -- report the model it belongs to, not every little part
                            local owner = string.match(path, "^(.*)/[^/]+$") or path
                            if not seenPath[owner] then
                                seenPath[owner] = true
                                table.insert(parts, { path = owner, d = d })
                            end
                        end
                    end
                    if depth < 8 then
                        local kids = {}
                        pcall(function() kids = inst:GetChildren() end)
                        if #kids < 4000 then
                            for _, k in ipairs(kids) do
                                table.insert(queue, { k, path .. "/" .. (k.Name or "?"), depth + 1 })
                            end
                        end
                    end
                end
            end
            table.sort(prompts, function(a, b) return a.d < b.d end)
            table.sort(parts, function(a, b) return a.d < b.d end)
            local out = { "=== PROMPTS (press-E things) within 80m ===" }
            for i, r in ipairs(prompts) do
                if i > 40 then break end
                table.insert(out, string.format("%dm  %s  [%s]", math.floor(r.d), r.path, r.txt))
            end
            table.insert(out, "=== MODELS with parts within 25m ===")
            for i, r in ipairs(parts) do
                if i > 60 then break end
                table.insert(out, string.format("%dm  %s", math.floor(r.d), r.path))
            end
            pcall(function() writefile("dw_closescan.txt", table.concat(out, "\n")) end)
            for i = 1, math.min(#out, 25) do print("[DW close] " .. out[i]) end
            scanStatus = "Close scan: " .. #prompts .. " prompts, " .. #parts .. " models (dw_closescan.txt)"
        end)
        if not ok then scanStatus = "Close scan failed"; report("closescan", err) end
    end)
end

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
    "dw_bardist", "dw_playerdist", "dw_mobdist", "dw_maxdraw", "dw_smooth2", "dw_smoothamt",
    "dw_artifact", "dw_artdist", "dw_artalert", "dw_chest", "dw_npcesp", "dw_miscobj", "dw_ingred", "dw_objdist",
    "dw_nearby", "dw_prox", "dw_proxdist", "dw_mods", "dw_bigwarn",
    "dw_exphp", "dw_friends", "dw_exphpms",
    "dw_cyber", "dw_boxes", "dw_showhpnum", "dw_hppctonly", "dw_nofall", "dw_nofallsink", "dw_nofallkey",
    "dw_tpspeed", "dw_tpstopkey",
    "dw_nofallmode", "dw_nofallcap2", "dw_nofalldelay2", "dw_nofallcatch", "dw_nofallbreak", "dw_boat", "dw_boatmult", "dw_boatkey", "dw_menukey",
    "dw_parry", "dw_parrykey", "dw_parrywin", "dw_parrycd", "dw_parryy", "dw_parryreset", "dw_parryreseton", "dw_rechotkey",
    "dw_refresh", "dw_status", "dw_autoload", "dw_camgap",
    "dw_talenttrack", "dw_talentnotify", "dw_talentcards", "dw_talentpanel", "dw_cardyoff",
    "dw_buildlink", "dw_talentignore",
    "dw_speed", "dw_speedmode", "dw_speedmult", "dw_speedkey", "dw_speedkeyname", "dw_stunkeyname",
    "dw_spdstep", "dw_spdupkey", "dw_spddownkey",
    "dw_agiamt", "dw_agicustom", "dw_agistep", "dw_agiupkey", "dw_agidownkey", "dw_talhlkey",
    "dw_stunmove", "dw_stunspeed", "dw_stunkey",
    "dw_customesp", "dw_customnames", "dw_mfullbright", "dw_mfbbright", "dw_mfbexpo", "dw_mnofog", "dw_mfbambient",
    "dw_noclip", "dw_ncspeed", "dw_nckey", "dw_ncaccel", "dw_ncblink", "dw_ncblinkkey", "dw_ncblinkcd",
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
        -- the config you saved last is the one that comes back on execute
        writefile(AUTOLOAD_FILE, name)
    end)
    configStatus = ok and ("Saved '" .. name .. "' - loads on execute") or ("Save failed: " .. tostring(err))
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
        local count = 0
        if type(data.values) == "table" then
            for id, v in pairs(data.values) do
                -- the script uses it right away; the menu catches up when drawn
                PENDING[id] = fixValue(v, nil)
                pendingTries[id] = nil
                pcall(function() UI.SetValue(id, PENDING[id]) end)
                count = count + 1
            end
        end
        -- configs saved on v16-v18 kept INSERT, which is Matcha's own menu key
        if PENDING.dw_menukey == "INSERT" then PENDING.dw_menukey = "END" end
        pcall(readSettings)
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
                PENDING[id] = v   -- the custom menu reads mob toggles from here
            end
        end
        configStatus = "Loaded '" .. name .. "' (" .. count .. " settings)"
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

-- What the Saved Configs dropdown shows right now (set by the menu each
-- frame). Matching by name means a new save can't shift you onto the
-- wrong config the way picking by position could.
local cfgPicked = nil
local function selectedConfig()
    if cfgPicked then
        for _, n in ipairs(configNames) do
            if n == cfgPicked then return n end
        end
    end
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

    -- every widget object, by id - setting a slider through its own
    -- :SetValue is the documented way; UI.SetValue left sliders at 0
    RS.widgets = {}
    local function keep(id, w)
        if w ~= nil then RS.widgets[id] = w end
        return w
    end

    function RS.toggle(sec, sn, id, label, def, cb)
        reg(sn, id, def)
        if cb then return keep(id, sec:Toggle(id, label, def, cb)) end
        return keep(id, sec:Toggle(id, label, def))
    end
    function RS.slider(sec, sn, id, label, mn, mx, def)
        reg(sn, id, def)
        return keep(id, sec:SliderInt(id, label, mn, mx, def))
    end
    function RS.combo(sec, sn, id, label, items, def)
        reg(sn, id, def)
        return keep(id, sec:Combo(id, label, items, def))
    end
    function RS.input(sec, sn, id, label, def)
        reg(sn, id, def)
        return keep(id, sec:InputText(id, label, def))
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
            SetV(d[1], d[2])
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
            SetV(id, true)
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

-- (parry recorder hotkey removed along with the parry timer)

-- Auto-load the last saved config right away on execute - no need to open
-- the menu first. The values sit in PENDING, so everything runs with them
-- immediately and the menu shows them once it's drawn.
do
    local name = getAutoload()
    if name ~= "" then
        logStep("A1 auto-loading config " .. name)
        loadConfig(name, true)
        logStep("A2 " .. configStatus)
        if string.find(configStatus, "^Loaded") then
            pcall(function() notify(configStatus, "DW Config", 4) end)
        end
    end
end

-- Push waiting config values into the menu.
-- v14 gave up after 30 tries and then trusted the widget - but Matcha was
-- refusing UI.SetValue on sliders, so they all sat at 0 and the script
-- started using 0 (Player Distance 0 = no ESP, Max Drawn 0 = nobody).
-- Now: push through the widget's own :SetValue too, and if the menu still
-- won't take it, KEEP using the config value. It only hands over to the
-- menu once the widget shows the value, or once YOU move that widget.
local function getUI(id)
    local ok, v = pcall(function() return UI.GetValue(id) end)
    if ok then return v end
    return nil
end

local function pushValue(id, v)
    pcall(function() UI.SetValue(id, v) end)
    local w = RS.widgets and RS.widgets[id]
    if w then pcall(function() w:SetValue(v) end) end
end

local function flushPending()
    for id, v in pairs(PENDING) do
        local cur = getUI(id)
        if cur ~= nil then v = fixValue(v, cur) end
        local seen = pendingTries[id]
        if seen == nil then
            -- first look: push it in and remember what the widget shows now
            pushValue(id, v)
            local got = getUI(id)
            if got == v then
                PENDING[id] = nil
            else
                pendingTries[id] = { shown = got, frames = 0 }
            end
        else
            local got = getUI(id)
            if got == v then
                PENDING[id] = nil                  -- the menu finally took it
                pendingTries[id] = nil
            elseif got ~= seen.shown then
                PENDING[id] = nil                  -- you changed it: menu wins
                pendingTries[id] = nil
            else
                seen.frames = seen.frames + 1
                if seen.frames % 60 == 0 then pushValue(id, v) end   -- retry now and then
            end
        end
    end
end

-------------------------------
-- TELEPORTS
-- Two ways to get somewhere on Standard Matcha:
--  TRAVEL  - fly up high, cross over, come down at a believable speed.
--            One long jump gets you pulled back by the anticheat; steady
--            flying doesn't. This is why Rice says Mod Office "takes 10-15
--            mins": it's ~68,000 studs away.
--  INSTANT - Project Rain's method: put you ON the destination every frame.
--            For realm/depths teleports that means standing on the game's
--            own portal part, so the game's own touch sends you through.
--            Riskier: a long instant jump may get pulled back.
-- Destinations come from Rain's source, the game's own area markers
-- (ReplicatedStorage.MarkerWorkspace.AreaMarkers), and spots you save.
-------------------------------
do
    local function childPath(...)
        local cur = workspace
        for _, n in ipairs({ ... }) do
            if not cur then return nil end
            cur = cur:FindFirstChild(n)
        end
        return cur
    end

    TP.presets = {
        { name = "Mod Office", pos = Vector3.new(39911.37, 39980.94, 39708.32),
          part = function() return childPath("ModOffice", "OfficePit") end },
        { name = "Depths (whirlpool)", pos = Vector3.new(-11771.12, 0, 2849.19),
          part = function() return childPath("DepthsWhirlpool", "Part") end },
        { name = "Etrean Luminant (realm exit)", pos = Vector3.new(-528.43, 704.67, -4760.43),
          part = function() return childPath("ValleyExit", "RealmTeleport") end },
        { name = "Eastern Luminant (realm exit)", pos = Vector3.new(-2637.46, 721.63, -6722.52),
          part = function() return childPath("ValleyExit", "RealmTeleport") end },
        { name = "Trial of One", pos = Vector3.new(-959.79, 147.0, -6659.63),
          part = function() return childPath("OneEntrance") end },
    }

    local function myRoot()
        local live = workspace:FindFirstChild("Live")
        local me = live and live:FindFirstChild(LocalPlayer.Name)
        return me and me:FindFirstChild("HumanoidRootPart")
    end

    local function posOf(inst)
        local p = nil
        pcall(function() p = inst.Position end)
        return p
    end

    -- every named area the game itself knows about
    function TP.scanAreas()
        local out = {}
        pcall(function()
            local rs = game:GetService("ReplicatedStorage")
            local mw = rs:FindFirstChild("MarkerWorkspace")
            local am = mw and mw:FindFirstChild("AreaMarkers")
            if not am then return end
            for _, a in ipairs(am:GetChildren()) do
                local m = a:FindFirstChild("AreaMarker") or a
                local p = posOf(m)
                if p then table.insert(out, { name = tostring(a.Name), pos = p }) end
            end
        end)
        table.sort(out, function(x, y) return x.name < y.name end)
        TP.areas = out
        TP.status = (#out > 0) and ("Found " .. #out .. " areas") or "No area markers loaded here"
        return out
    end

    -- saved spots (dw_spots.json)
    local SPOTS_FILE = "dw_spots.json"
    local function loadSpots()
        local list = {}
        pcall(function()
            if isfile(SPOTS_FILE) then
                local data = game:GetService("HttpService"):JSONDecode(readfile(SPOTS_FILE))
                for _, s in ipairs(data) do
                    if s.name and s.x and s.y and s.z then
                        table.insert(list, { name = s.name, pos = Vector3.new(s.x, s.y, s.z) })
                    end
                end
            end
        end)
        TP.spots = list
    end
    local function saveSpots()
        local raw = {}
        for _, s in ipairs(TP.spots) do
            table.insert(raw, { name = s.name, x = s.pos.X, y = s.pos.Y, z = s.pos.Z })
        end
        pcall(function() writefile(SPOTS_FILE, game:GetService("HttpService"):JSONEncode(raw)) end)
    end
    loadSpots()

    function TP.saveSpot(name)
        name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then TP.status = "Type a name for the spot first"; return end
        local root = myRoot()
        local p = root and posOf(root)
        if not p then TP.status = "Can't read your position"; return end
        for i, s in ipairs(TP.spots) do
            if s.name == name then table.remove(TP.spots, i) break end
        end
        table.insert(TP.spots, { name = name, pos = p })
        saveSpots()
        TP.status = "Saved '" .. name .. "'"
        pcall(function() notify("Saved spot '" .. name .. "'", "Teleports", 3) end)
    end

    function TP.deleteSpot(name)
        for i, s in ipairs(TP.spots) do
            if s.name == name then table.remove(TP.spots, i); saveSpots(); TP.status = "Deleted '" .. name .. "'"; return end
        end
    end

    function TP.stop(why)
        TP.cancel = true
        TP.status = why or "Stopped"
    end

    local function fmtTime(s)
        s = math.max(math.floor(s), 0)
        if s >= 60 then return string.format("%dm %02ds", math.floor(s / 60), s % 60) end
        return s .. "s"
    end

    -- mode "travel" or "instant"; getPart (optional) returns the real
    -- destination part once that area has loaded in around you
    function TP.go(name, dest, getPart, mode)
        -- each run gets its own number; starting a new one retires the old
        -- one without the old one's cleanup cancelling the new one
        TP.gen = (TP.gen or 0) + 1
        local myGen = TP.gen
        TP.cancel = false
        TP.running = true
        TP.status = "Starting: " .. name
        task.spawn(function()
            local ok, err = pcall(function()
                local zero = Vector3.new(0, 0, 0)
                local cruiseY = nil
                local holdUntil = nil
                local sawPart = false
                local lastT = tick()
                while not TP.cancel and myGen == TP.gen do
                    if KB.pressed("dw_tpstopkey", cfg.tpStopKey) then TP.stop("Stopped (key)") break end
                    local now = tick()
                    local dt = clamp(now - lastT, 0, 0.1)
                    lastT = now
                    local root = myRoot()
                    if not root then
                        -- character gone: you probably went through the portal
                        TP.status = name .. ": character gone (portal worked?)"
                        if holdUntil then break end
                        wait(0.3)
                    else
                        local pos = posOf(root)
                        local part = getPart and getPart()
                        local target = (part and posOf(part)) or dest
                        if pos and target then
                            local speed = clamp(tonumber(cfg.tpSpeed) or 120, 20, 600)
                            local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
                            local flatD = flat.Magnitude
                            local fullD = (target - pos).Magnitude

                            if mode == "instant" or fullD < 6 then
                                -- on target: keep putting you there (touches portals).
                                -- Give a portal time to load in around you first.
                                holdUntil = holdUntil or (now + (getPart and 8 or 2))
                                if part and not sawPart then
                                    sawPart = true
                                    holdUntil = now + 15
                                end
                                local jitter = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 0.02
                                pcall(function() root.Position = target + Vector3.new(0, part and 1 or 3, 0) + jitter end)
                                pcall(function() root.AssemblyLinearVelocity = zero end)
                                TP.status = string.format("%s: holding on target (%s)", name,
                                    part and "touching portal" or "arrived")
                                if now > holdUntil then
                                    TP.status = name .. ": done"
                                    break
                                end
                            else
                                cruiseY = cruiseY or (math.max(pos.Y, target.Y) + 250)
                                local vel
                                if flatD > 8 and pos.Y < cruiseY - 6 then
                                    vel = Vector3.new(0, speed, 0)                         -- climb
                                    TP.status = string.format("%s: climbing (%d left)", name, math.floor(cruiseY - pos.Y))
                                elseif flatD > 8 then
                                    local u = flat / flatD
                                    local hold = clamp((cruiseY - pos.Y) * 2, -speed, speed)
                                    vel = Vector3.new(u.X * speed, hold, u.Z * speed)       -- cruise
                                    TP.status = string.format("%s: flying %dm, ~%s left", name,
                                        math.floor(flatD), fmtTime(flatD / speed + (cruiseY - target.Y) / speed))
                                else
                                    local dir = (target - pos).Unit
                                    vel = dir * math.min(speed, fullD * 4)                  -- descend
                                    TP.status = string.format("%s: landing (%dm)", name, math.floor(fullD))
                                end
                                pcall(function() root.AssemblyLinearVelocity = vel end)
                            end
                        end
                    end
                    task.wait()
                end
            end)
            if not ok then TP.status = "Teleport error: " .. tostring(err); report("teleport", err) end
            if myGen == TP.gen then
                TP.running = false
                TP.cancel = false
            end
        end)
    end
end

logStep("7 building UI")
-- The old Matcha tab, kept only for reference - it's no longer shown.
-- Everything lives in the custom menu below instead.
local function oldMatchaTab(tab)
    logStep("8 UI first frame start", true)

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
    T(esp, "ESP", "dw_cyber", "Cyberpunk Theme", true)
    T(esp, "ESP", "dw_boxes", "Outline Box (theme on)", false)
    T(esp, "ESP", "dw_showhpnum", "Show HP Numbers (e.g. 643/700)", false)
    T(esp, "ESP", "dw_hppctonly", "HP % Only (no bar, no numbers)", false)
    esp:Tip("Turn OFF Matcha's own ESP (Visuals tab) or both draw on top of each other")
    S(esp, "ESP", "dw_bardist", "HP Bar Radius", 25, 1000, 200)
    S(esp, "ESP", "dw_maxdraw", "Max ESP Drawn (closest)", 5, 80, 30)
    T(esp, "ESP", "dw_smooth2", "Smooth ESP (adds a little delay)", false)
    S(esp, "ESP", "dw_smoothamt", "Smoothing Speed", 3, 30, 12)
    esp:Tip("Leave OFF for labels that stick to targets. Higher speed = less delay")
    S(esp, "ESP", "dw_camgap", "Use Camera If Body Is >", 20, 500, 80)
    esp:Tip("If distances look wrong, lower this")
    S(esp, "ESP", "dw_refresh", "ESP Data Refresh (ms)", 100, 1000, 250)
    esp:Tip("Higher = less lag, HP/labels update slower")
    T(esp, "ESP", "dw_status", "Show Status Line", true)
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
    T(obj, "Object ESP", "dw_customesp", "Custom ESP (names below)", false)
    P(obj, "Object ESP", "custom")
    I(obj, "Object ESP", "dw_customnames", "Model names (comma separated)", "")
    obj:Tip("Get the name from Close Scan, paste it here")
    obj:Button("CLOSE SCAN (stand next to it)", function() closeScan() end)
    obj:Tip("Prints press-E prompts within 80m + their real names")
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
    I(tal, "Talent Tracker", "dw_talhlkey", "Highlight Cards Key", "")
    tal:Button("Set: Highlight Cards Key", function() KB.capture("dw_talhlkey") end)
    tal:Button("Highlight Cards Now", function() if TT.highlight then TT.highlight() end end)
    tal:Tip("Press it when cards are up: GET cards get a thick green box for 12s")
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

    local wm = tab:Section("World (memory)", "Left")
    T(wm, "World (memory)", "dw_mfullbright", "Fullbright", false)
    S(wm, "World (memory)", "dw_mfbbright", "Brightness", 1, 10, 3)
    S(wm, "World (memory)", "dw_mfbexpo", "Exposure (x0.5)", 0, 6, 1)
    T(wm, "World (memory)", "dw_mnofog", "No Fog", false)
    wm:Text("Status: " .. MEM.fb)
    wm:Text("Offsets: " .. MEM.report())
    S(wm, "World (memory)", "dw_mfbambient", "Ambient Light (%)", 10, 100, 70)
    wm:Button("Rescan Offsets (after Roblox update)", function() MEM.resetScan() end)
    wm:Button("Memory Debug (writes dw_memdebug.txt)", function() MEM.dump() end)
    wm:Tip("Uses memory_write - finds offsets itself each session")
    wm:Button("Reset World Section", function() RS.resetSection("World (memory)") end)

    local cfgSec = tab:Section("Configs", "Left")
    cfgSec:InputText("dw_cfgname", "Config Name", "")
    cfgSec:Button("Save As New / Overwrite", function() saveConfig(V("dw_cfgname", "")) end)
    local list = (#configNames > 0) and configNames or { "(no configs yet)" }
    local cfgCombo = cfgSec:Combo("dw_cfgsel", "Saved Configs", list, 0)
    -- A combo keeps the items it was made with, so a config saved after
    -- execute never showed up. Re-fill it whenever the list changes.
    pcall(function()
        local items = cfgCombo:GetItems()
        if type(items) == "table" and table.concat(items, "\n") ~= table.concat(list, "\n") then
            cfgCombo:Clear()
            for _, n in ipairs(list) do cfgCombo:Add(n) end
        end
    end)
    pcall(function() cfgPicked = cfgCombo:GetText() end)
    cfgSec:Button("Load By Name (box above)", function() loadConfig(V("dw_cfgname", ""), false) end)
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
    T(alerts, "Nearby & Alerts", "dw_exphp", "Export Friends HP (dw_party.txt)", false)
    I(alerts, "Nearby & Alerts", "dw_friends", "Only these names (comma sep)", "")
    alerts:Tip("Leave empty for everyone loaded nearby")
    S(alerts, "Nearby & Alerts", "dw_exphpms", "Export Every (ms)", 100, 2000, 250)
    alerts:Tip("Screen Macro's Party HP tab reads this file and shows it as a %")
    alerts:Text(#staffList > 0 and ("STAFF HERE: " .. #staffList) or "No known staff right now")
    alerts:Button("Reset Alerts Section", function() RS.resetSection("Nearby & Alerts") end)

    -- A key you can set to anything: a text box holding its name + "Set"
    local function keyRow(sec, sn, id, label)
        I(sec, sn, id, label, "")
        sec:Button("Set " .. label, function() KB.capture(id) end)
    end

    local sp = tab:Section("Agility Spoof", "Right")
    T(sp, "Agility Spoof", "dw_speed", "Agility Spoof", false)
    keyRow(sp, "Agility Spoof", "dw_speedkeyname", "Agility Toggle Key")
    sp:Text("Status: " .. SPD.status)
    S(sp, "Agility Spoof", "dw_agiamt", "Amount (slider)", 1, 1000, 10)
    I(sp, "Agility Spoof", "dw_agicustom", "Custom Amount (up to 100000)", "")
    sp:Button("Clear Custom - use slider", function()
        cfg.agiCustom = ""
        SetV("dw_agicustom", "")
    end)
    do
        local amt = SPD.agiAmount and SPD.agiAmount() or 10
        local src = tonumber(cfg.agiCustom) and "custom" or "slider"
        sp:Text(string.format("Using amount %d (%s) = agility %g", amt, src, 8 + (amt / 10) * 2))
    end
    S(sp, "Agility Spoof", "dw_agistep", "Step Per Key Press", 1, 1000, 5)
    keyRow(sp, "Agility Spoof", "dw_agiupkey", "Agility Up Key")
    keyRow(sp, "Agility Spoof", "dw_agidownkey", "Agility Down Key")
    sp:Button("Reset Agility Spoof", function() RS.resetSection("Agility Spoof") end)

    local sm = tab:Section("Move While Stunned", "Right")
    T(sm, "Move While Stunned", "dw_stunmove", "Move While Stunned / Endlag", false)
    keyRow(sm, "Move While Stunned", "dw_stunkeyname", "Stun Toggle Key")
    S(sm, "Move While Stunned", "dw_stunspeed", "Speed (studs/s)", 4, 30, 14)
    sm:Text("Status: " .. SPD.stunStatus())

    local nf = tab:Section("No Fall Damage", "Right")
    T(nf, "No Fall Damage", "dw_nofall", "No Fall Damage", false)
    keyRow(nf, "No Fall Damage", "dw_nofallkey", "No Fall Toggle Key")
    S(nf, "No Fall Damage", "dw_nofallsink", "Glide Down Speed (studs/s)", 5, 120, 30)
    nf:Tip("Drops become a slow glide, like flying down - the game never sees a fall")
    nf:Text("Status: " .. (SPD.fallStatus or "Off"))
    nf:Button("Fall Debug: save game's fall code", function() SPD.dumpFallCode() end)
    nf:Tip("Still getting hurt? Press this, then send me dw_fallcode.txt")

    -- ---- TELEPORTS ----
    local tp = tab:Section("Teleports", "Right")
    tp:Text("Teleport: " .. TP.status)
    S(tp, "Teleports", "dw_tpspeed", "Travel Speed (studs/s)", 20, 600, 120)
    tp:Tip("Faster = sooner but likelier to be pulled back. 120 is safe-ish")
    keyRow(tp, "Teleports", "dw_tpstopkey", "Stop Teleport Key")
    tp:Button("STOP TELEPORT", function() TP.stop("Stopped") end)
    tp:Text("-- Travel (flies there, slow but safe) --")
    for _, p in ipairs(TP.presets) do
        tp:Button("Travel: " .. p.name, function() TP.go(p.name, p.pos, p.part, "travel") end)
    end
    tp:Text("-- Instant (Rain method, may get pulled back) --")
    for _, p in ipairs(TP.presets) do
        tp:Button("Instant: " .. p.name, function() TP.go(p.name, p.pos, p.part, "instant") end)
    end

    local ar = tab:Section("Areas & Saved Spots", "Right")
    ar:Button("Scan Game Areas", function() TP.scanAreas() end)
    ar:Tip("Lists every named area the game has (towns, bosses, Boatman's Watch...)")
    do
        local names = {}
        for _, a in ipairs(TP.areas) do table.insert(names, a.name) end
        if #names == 0 then names = { "(press Scan Game Areas)" } end
        local cb = ar:Combo("dw_tparea", "Area", names, 0)
        pcall(function()
            local items = cb:GetItems()
            if type(items) == "table" and table.concat(items, "\n") ~= table.concat(names, "\n") then
                cb:Clear()
                for _, n in ipairs(names) do cb:Add(n) end
            end
        end)
        pcall(function() TP.pickArea = cb:GetText() end)
    end
    local function pickedArea()
        for _, a in ipairs(TP.areas) do if a.name == TP.pickArea then return a end end
        return nil
    end
    ar:Button("Travel to Area", function()
        local a = pickedArea()
        if a then TP.go(a.name, a.pos, nil, "travel") else TP.status = "Scan and pick an area first" end
    end)
    ar:Button("Instant to Area", function()
        local a = pickedArea()
        if a then TP.go(a.name, a.pos, nil, "instant") else TP.status = "Scan and pick an area first" end
    end)

    ar:Text("-- Your saved spots --")
    ar:InputText("dw_spotname", "Spot Name", "")
    ar:Button("Save Spot Here", function() TP.saveSpot(V("dw_spotname", "")) end)
    ar:Tip("Stand somewhere (Primadon, Hive, Ferryman...), name it, save it")
    do
        local names = {}
        for _, s in ipairs(TP.spots) do table.insert(names, s.name) end
        if #names == 0 then names = { "(no saved spots)" } end
        local cb = ar:Combo("dw_tpspot", "Saved Spot", names, 0)
        pcall(function()
            local items = cb:GetItems()
            if type(items) == "table" and table.concat(items, "\n") ~= table.concat(names, "\n") then
                cb:Clear()
                for _, n in ipairs(names) do cb:Add(n) end
            end
        end)
        pcall(function() TP.pickSpot = cb:GetText() end)
    end
    local function pickedSpot()
        for _, s in ipairs(TP.spots) do if s.name == TP.pickSpot then return s end end
        return nil
    end
    ar:Button("Travel to Spot", function()
        local s = pickedSpot()
        if s then TP.go(s.name, s.pos, nil, "travel") else TP.status = "Save or pick a spot first" end
    end)
    ar:Button("Instant to Spot", function()
        local s = pickedSpot()
        if s then TP.go(s.name, s.pos, nil, "instant") else TP.status = "Save or pick a spot first" end
    end)
    ar:Button("Delete Spot", function()
        local s = pickedSpot()
        if s then TP.deleteSpot(s.name) end
    end)

    local rc = tab:Section("Rice", "Right")
    rc:Text("Rice: " .. RICE.state)
    rc:Tip("Exly78/Rice-Public - its own tab has Remove Kill Bricks etc.")
    rc:Button("Load Rice Now", function() RICE.load() end)
    rc:Button("Don't Load Rice On Execute", function()
        pcall(function() writefile("dw_norice.txt", "delete this file to load Rice again") end)
        RICE.state = "Off next execute"
    end)
    rc:Button("Load Rice On Execute", function()
        pcall(function() delfile("dw_norice.txt") end)
        RICE.state = "On next execute"
    end)
    rc:Tip("Don't run Rice's agility spoof AND this one - they'll fight")

    local nc = tab:Section("Noclip & Fly", "Right")
    nc:Text("Use MATCHA'S own, not this script.")
    nc:Text("Character > Movement:  No-Clip (Z),  Flight (F1)")
    nc:Tip("Matcha's are built into the executor, so they can do what a Lua script can't")
    nc:Text("")
    nc:Text("TURN THE SPEEDS DOWN - that is what")
    nc:Text("gets you yanked back by the anticheat:")
    nc:Text("   Fly Amount    848  ->  try 50-60")
    nc:Text("   Speed Amount  902  ->  try 30-40")
    nc:Tip("Normal walk speed is about 16. 848 is 50x that, and trivially detected")
    nc:Text("")
    nc:Text("Set Fly Method / Speed Method to Velocity.")
    nc:Tip("Velocity moves you like real physics. Position jumps look like teleports")
    nc:Text("")
    nc:Text("This script no longer touches your movement,")
    nc:Text("so it can't fight Matcha's any more.")
    nc:Button("Diagnostics: what Matcha allows (dw_noclip.txt)", function() NOCLIP.selfTest() end)
    nc:Button("Diagnostics: game memory scan (dw_acscan.txt)", function() NOCLIP.acScan() end)

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

    -- last, so this frame's widgets already exist
    flushPending()
end

-------------------------------
-- CUSTOM MENU  -  DEMOLISHER //DW
-- Its own window, styled after the DEMOLISHER //V2 app: yellow title
-- block, numbered sidebar, big TITLE_ headers, cyan section headings.
-- Drag it by the header. END (or your own key - INSERT is Matcha's) hides/shows it.
-- Every drawing is reused frame to frame and only written when something
-- changed, so an open menu stays light.
-------------------------------
local GUI = { open = true, page = 1, x = 120, y = 90, w = 860, h = 600, scroll = {}, sel = {}, buf = "" }
do
    local C = {
        bg = Color3.fromRGB(9, 13, 22), panel = Color3.fromRGB(14, 20, 33), side = Color3.fromRGB(6, 9, 16),
        line = Color3.fromRGB(34, 50, 72), yellow = Color3.fromRGB(252, 238, 10), cyan = Color3.fromRGB(0, 229, 255),
        pink = Color3.fromRGB(255, 42, 109), text = Color3.fromRGB(222, 230, 240), dim = Color3.fromRGB(112, 130, 152),
        black = Color3.fromRGB(0, 0, 0), track = Color3.fromRGB(24, 36, 54),
    }
    local P, N = { sq = {}, tx = {} }, { sq = 0, tx = 0 }
    local CW = 7.8   -- monospace character width at size 13

    local function get(kind)
        N[kind] = N[kind] + 1
        local o = P[kind][N[kind]]
        if not o then
            local d
            if kind == "sq" then
                d = Drawing.new("Square")
            else
                d = Drawing.new("Text")
                pcall(function() d.Outline = false end)
                if FONT then pcall(function() d.Font = FONT end) end
            end
            o = { d = d, c = {} }
            P[kind][N[kind]] = o
        end
        return o
    end
    local function sp(o, k, v)
        if o.c[k] ~= v then
            o.c[k] = v
            pcall(function() o.d[k] = v end)
        end
    end
    local function v2(o, k, x, y)
        x, y = math.floor(x + 0.5), math.floor(y + 0.5)
        if o.c[k .. "X"] ~= x or o.c[k .. "Y"] ~= y then
            o.c[k .. "X"], o.c[k .. "Y"] = x, y
            pcall(function() o.d[k] = Vector2.new(x, y) end)
        end
    end
    local function box(x, y, w, h, col, filled, alpha, z)
        local o = get("sq")
        v2(o, "Position", x, y)
        v2(o, "Size", math.max(w, 1), math.max(h, 1))
        sp(o, "Color", col)
        sp(o, "Filled", filled ~= false)
        sp(o, "Transparency", alpha or 1)
        sp(o, "ZIndex", z or 60)
        sp(o, "Visible", true)
    end
    local function text(x, y, s, col, size, center)
        local o = get("tx")
        sp(o, "Text", tostring(s))
        sp(o, "Color", col or C.text)
        sp(o, "Size", size or 13)
        sp(o, "FontSize", size or 13)
        sp(o, "Center", center == true)
        sp(o, "ZIndex", 62)
        v2(o, "Position", x, y)
        sp(o, "Visible", true)
    end
    local function finish()
        for kind, list in pairs(P) do
            for i = N[kind] + 1, #list do sp(list[i], "Visible", false) end
            N[kind] = 0
        end
    end

    -- ---- input ----
    local mouse = nil
    pcall(function() mouse = LocalPlayer:GetMouse() end)
    local mx, my, down, click, wasDown = 0, 0, false, false, false
    local dragging, dragWin, dragBar = nil, nil, nil
    local function readInput()
        local x, y = 0, 0
        pcall(function() x, y = mouse.X, mouse.Y end)
        mx, my = x, y
        local d = false
        pcall(function() d = ismouse1pressed() end)
        click = d and not wasDown
        down = d
        wasDown = d
    end
    local function over(x, y, w, h) return mx >= x and mx <= x + w and my >= y and my <= y + h end

    -- ---- typing into a text box ----
    local CHARS = {}
    for c = 0x41, 0x5A do CHARS[c] = { string.lower(string.char(c)), string.char(c) } end
    local SHIFTED = ")!@#$%^&*("
    for i = 0, 9 do CHARS[0x30 + i] = { tostring(i), string.sub(SHIFTED, i + 1, i + 1) } end
    for i = 0, 9 do CHARS[0x60 + i] = { tostring(i), tostring(i) } end
    local more = { [0x20] = { " ", " " }, [0xBE] = { ".", ">" }, [0xBC] = { ",", "<" }, [0xBD] = { "-", "_" },
        [0xBB] = { "=", "+" }, [0xBF] = { "/", "?" }, [0xBA] = { ";", ":" }, [0xDB] = { "[", "{" },
        [0xDD] = { "]", "}" }, [0xDE] = { "'", "\"" }, [0xC0] = { "`", "~" }, [0x6E] = { ".", "." }, [0x6D] = { "-", "-" } }
    for k, v in pairs(more) do CHARS[k] = v end
    local held, bsAt = {}, 0

    local function commit()
        if GUI.focus then
            local val = GUI.buf
            if GUI.numeric and val ~= "" and not tonumber(val) then val = "" end
            SetV(GUI.focus, val)
        end
        GUI.focus = nil
        if KB.capturing == "typing" then KB.capturing = nil end
    end
    local function focusOn(id, cur, numeric)
        commit()
        GUI.focus, GUI.buf, GUI.numeric = id, cur, numeric
        KB.capturing = "typing"   -- your hotkeys don't fire while you type
    end
    local function typeKeys()
        local shift = false
        pcall(function() shift = iskeypressed(0x10) end)
        for vk, pair in pairs(CHARS) do
            local d = false
            pcall(function() d = iskeypressed(vk) end)
            if d and not held[vk] then
                local ch = shift and pair[2] or pair[1]
                if not GUI.numeric or string.find(ch, "^[%d%.%-]$") then GUI.buf = GUI.buf .. ch end
            end
            held[vk] = d
        end
        local bs = false
        pcall(function() bs = iskeypressed(0x08) end)
        if bs and (not held[0x08] or tick() > bsAt) then
            GUI.buf = string.sub(GUI.buf, 1, -2)
            bsAt = tick() + (held[0x08] and 0.04 or 0.4)
        end
        held[0x08] = bs
        local enter, esc = false, false
        pcall(function() enter = iskeypressed(0x0D) end)
        pcall(function() esc = iskeypressed(0x1B) end)
        if enter and not held[0x0D] then commit() end
        if esc and not held[0x1B] then GUI.focus = nil; KB.capturing = nil end
        held[0x0D], held[0x1B] = enter, esc
    end

    -- ---- widgets (laid out top to bottom in the content area) ----
    local L = { x = 0, y = 0, w = 0, top = 0, bottom = 0 }
    local function vis(h) return L.y >= L.top and L.y + h <= L.bottom end
    local function store(id, def)
        local v = PENDING[id]
        if v == nil then return def end
        return v
    end

    local W = {}
    function W.section(t)
        L.y = L.y + 6
        if vis(24) then
            text(L.x, L.y, string.upper(t), C.cyan, 13)
            box(L.x, L.y + 19, L.w, 1, C.line, true)
        end
        L.y = L.y + 28
    end
    function W.label(t, col)
        if vis(18) then text(L.x, L.y, t, col or C.dim, 12) end
        L.y = L.y + 18
    end
    function W.toggle(id, label, def)
        local on = store(id, def) == true
        if vis(24) then
            box(L.x, L.y + 3, 16, 16, on and C.yellow or C.track, true)
            if not on then box(L.x, L.y + 3, 16, 16, C.line, false) end
            text(L.x + 26, L.y + 4, label, on and C.text or C.dim, 13)
            if click and over(L.x, L.y, L.w, 22) then
                click = false
                on = not on
                SetV(id, on)
            end
        end
        L.y = L.y + 26
        return on
    end
    function W.slider(id, label, lo, hi, def, step, suffix)
        step = step or 1
        local v = tonumber(store(id, def)) or def
        if vis(40) then
            text(L.x, L.y, label, C.text, 13)
            local s = tostring(v) .. (suffix or "")
            text(L.x + L.w - #s * CW, L.y, s, C.yellow, 13)
            local tx, ty, tw = L.x, L.y + 22, L.w
            local f = clamp((v - lo) / math.max(hi - lo, 1), 0, 1)
            box(tx, ty, tw, 6, C.track, true)
            box(tx, ty, tw * f, 6, C.cyan, true)
            box(tx + tw * f - 3, ty - 4, 6, 14, C.yellow, true)
            if click and over(tx - 6, ty - 10, tw + 12, 26) then dragging = id; click = false end
            if dragging == id then
                if down then
                    local nv = lo + clamp((mx - tx) / tw, 0, 1) * (hi - lo)
                    nv = clamp(math.floor(nv / step + 0.5) * step, lo, hi)
                    if nv ~= v then SetV(id, nv) end
                else
                    dragging = nil
                end
            end
        end
        L.y = L.y + 42
    end
    -- a row of buttons sharing the width: { {"Label", fn, primary}, ... }
    function W.buttons(list)
        if vis(28) then
            local gap = 8
            local bw = (L.w - gap * (#list - 1)) / #list
            for i, b in ipairs(list) do
                local bx = L.x + (i - 1) * (bw + gap)
                local hov = over(bx, L.y, bw, 26)
                if b[3] then
                    box(bx, L.y, bw, 26, hov and C.text or C.yellow, true)
                else
                    box(bx, L.y, bw, 26, hov and C.track or C.panel, true)
                    box(bx, L.y, bw, 26, hov and C.cyan or C.line, false)
                end
                text(bx + bw / 2, L.y + 6, b[1], b[3] and C.black or C.text, 13, true)
                if click and hov then click = false; pcall(b[2]) end
            end
        end
        L.y = L.y + 34
    end
    function W.button(label, fn, primary) W.buttons({ { label, fn, primary } }) end
    function W.key(id, label, def)
        local k = tostring(store(id, def or "") or "")
        if vis(26) then
            text(L.x, L.y + 5, label, C.text, 13)
            local bw = 150
            local bx = L.x + L.w - bw
            local waiting = KB.capturing == id
            local hov = over(bx, L.y, bw, 24)
            box(bx, L.y, bw, 24, C.panel, true)
            box(bx, L.y, bw, 24, waiting and C.yellow or (hov and C.cyan or C.line), false)
            text(bx + bw / 2, L.y + 5, waiting and "PRESS A KEY" or (k ~= "" and k or "NONE"),
                waiting and C.yellow or C.cyan, 13, true)
            -- small x to clear it
            local cx = bx - 30
            local hovx = over(cx, L.y, 24, 24)
            box(cx, L.y, 24, 24, hovx and C.pink or C.panel, true)
            text(cx + 12, L.y + 5, "x", hovx and C.black or C.dim, 13, true)
            if click and hov then click = false; KB.capture(id) end
            if click and hovx then click = false; SetV(id, "") end
        end
        L.y = L.y + 30
    end
    function W.input(id, label, def, numeric)
        local cur = tostring(store(id, def) or "")
        local focused = GUI.focus == id
        if vis(46) then
            text(L.x, L.y, label, C.text, 13)
            local by = L.y + 19
            local hov = over(L.x, by, L.w, 24)
            box(L.x, by, L.w, 24, C.panel, true)
            box(L.x, by, L.w, 24, focused and C.yellow or (hov and C.cyan or C.line), false)
            local shown = focused and (GUI.buf .. ((math.floor(tick() * 2) % 2 == 0) and "_" or " ")) or cur
            local maxc = math.floor((L.w - 16) / CW)
            if #shown > maxc then shown = string.sub(shown, -maxc) end
            if shown == "" then shown = "click to type" end
            text(L.x + 8, by + 5, shown, focused and C.yellow or (cur == "" and C.dim or C.cyan), 13)
            if focused then GUI.focusRect = { L.x, by, L.w, 24 } end
            if click and hov and not focused then click = false; focusOn(id, cur, numeric) end
        end
        L.y = L.y + 48
    end
    -- "< item >" picker; returns the picked index
    function W.pick(key, label, items)
        local n = #items
        local i = clamp(GUI.sel[key] or 1, 1, math.max(n, 1))
        if vis(26) then
            text(L.x, L.y + 5, label, C.text, 13)
            local bw = math.min(L.w * 0.62, 340)
            local bx = L.x + L.w - bw
            box(bx, L.y, bw, 24, C.panel, true)
            box(bx, L.y, bw, 24, C.line, false)
            local hl, hr = over(bx, L.y, 26, 24), over(bx + bw - 26, L.y, 26, 24)
            text(bx + 13, L.y + 5, "<", hl and C.yellow or C.cyan, 13, true)
            text(bx + bw - 13, L.y + 5, ">", hr and C.yellow or C.cyan, 13, true)
            local s = (n > 0) and tostring(items[i]) or "-"
            local maxc = math.floor((bw - 60) / CW)
            if #s > maxc then s = string.sub(s, 1, maxc - 1) .. "~" end
            text(bx + bw / 2, L.y + 5, s, C.text, 13, true)
            if n > 0 and click and hl then click = false; i = (i - 2) % n + 1 end
            if n > 0 and click and hr then click = false; i = i % n + 1 end
        end
        GUI.sel[key] = i
        L.y = L.y + 30
        return i
    end
    GUI.W = W

    -- ---- pages ----
    local PAGES = {}
    local function page(name, fn) table.insert(PAGES, { name = name, fn = fn }) end

    page("ESP", function()
        W.section("Players & mobs")
        W.toggle("dw_esp", "Player ESP", false)
        W.slider("dw_playerdist", "Player Distance", 100, 20000, 5000, 100, "m")
        W.toggle("dw_mobesp", "Mob ESP", false)
        W.slider("dw_mobdist", "Mob Distance", 50, 5000, 1000, 50, "m")
        W.slider("dw_maxdraw", "Max Drawn (closest)", 5, 80, 30)
        W.section("Labels")
        W.toggle("dw_showhp", "Show HP (bar + %)", true)
        W.toggle("dw_showhpnum", "Show HP numbers (643/700)", false)
        W.toggle("dw_hppctonly", "HP % only (no bar, no numbers)", false)
        W.toggle("dw_showdist", "Show distance", true)
        W.toggle("dw_showuser", "Show @username", true)
        W.toggle("dw_hpcolorname", "Colour name by HP when hurt", false)
        W.slider("dw_bardist", "HP Bar Radius", 25, 1000, 200, 25, "m")
        W.section("Look")
        W.toggle("dw_cyber", "Cyberpunk theme", true)
        W.toggle("dw_boxes", "Outline box", false)
        W.toggle("dw_status", "Status line (top)", true)
        W.section("Tracking")
        W.toggle("dw_smooth2", "Smooth ESP (adds a little delay)", false)
        W.slider("dw_smoothamt", "Smoothing Speed", 3, 30, 12)
        W.slider("dw_camgap", "Use camera if body is further than", 20, 500, 80, 10, "m")
        W.slider("dw_refresh", "Data refresh", 100, 1000, 250, 50, "ms")
        W.button("Refresh Mob / Player ESP", function() RS.refreshEsp() end)
        W.label("Turn OFF Matcha's own ESP (Visuals tab) or both draw at once")
    end)

    page("OBJECTS", function()
        W.section("Objects")
        W.toggle("dw_artifact", "Artifact ESP", false)
        W.slider("dw_artdist", "Artifact Distance", 100, 20000, 20000, 100, "m")
        W.toggle("dw_artalert", "Notify when an artifact spawns", true)
        W.toggle("dw_chest", "Chest ESP", false)
        W.toggle("dw_npcesp", "NPC ESP (shops / quests)", false)
        W.toggle("dw_miscobj", "Campfires / bags / meteors", false)
        W.toggle("dw_ingred", "Ingredient ESP", false)
        W.slider("dw_objdist", "Object Distance", 100, 5000, 1500, 50, "m")
        W.button("Refresh Object ESP", function() RS.refreshObjects() end)
        W.section("Custom ESP")
        W.toggle("dw_customesp", "Custom ESP (names below)", false)
        W.input("dw_customnames", "Model names (comma separated)", "")
        W.buttons({ { "Close Scan", function() closeScan() end }, { "Scan Nearby", function() scanNearby() end } })
        W.label("Scan: " .. tostring(scanStatus))
    end)

    page("MOB FILTER", function()
        W.section("Mobs near you")
        W.buttons({
            { "Show all", function()
                for _, t in ipairs(mobTypeList) do local id = "dw_mt_" .. safeId(t); SetV(id, true); savedMobs[id] = true end
            end },
            { "Hide all", function()
                for _, t in ipairs(mobTypeList) do local id = "dw_mt_" .. safeId(t); SetV(id, false); savedMobs[id] = false end
            end },
            { "Refresh", function() RS.refreshEsp() end },
        })
        if #mobTypeList == 0 then W.label("No mobs loaded - turn on Mob ESP first") end
        for _, t in ipairs(mobTypeList) do
            local id = "dw_mt_" .. safeId(t)
            local on = W.toggle(id, t .. "  (" .. tostring(mobTypeCounts[t] or 0) .. ")", true)
            savedMobs[id] = on
        end
    end)

    page("ALERTS", function()
        W.section("Staff")
        W.toggle("dw_mods", "Mod checker", true)
        W.toggle("dw_bigwarn", "Big staff warning (centre)", true)
        W.button("Re-check staff now", function() RS.recheckStaff() end)
        W.label(#staffList > 0 and ("STAFF HERE: " .. #staffList) or "No known staff right now",
            #staffList > 0 and C.pink or C.dim)
        W.section("Nearby")
        W.toggle("dw_nearby", "Nearby players box", false)
        W.toggle("dw_prox", "Proximity notify", false)
        W.slider("dw_proxdist", "Nearby Distance", 100, 20000, 1000, 100, "m")
        W.section("Friends HP export (for Screen Macro)")
        W.toggle("dw_exphp", "Export friends HP (dw_party.txt)", false)
        W.input("dw_friends", "Only these names (comma separated, empty = all)", "")
        W.slider("dw_exphpms", "Export every", 100, 2000, 250, 50, "ms")
    end)

    page("AGILITY", function()
        W.section("Agility spoof")
        W.toggle("dw_speed", "Agility spoof", false)
        W.key("dw_speedkeyname", "Toggle key")
        W.label("Status: " .. tostring(SPD.status), C.cyan)
        W.section("Amount")
        W.slider("dw_agiamt", "Amount (slider)", 1, 1000, 10)
        W.input("dw_agicustom", "Custom amount (up to 100000, overrides slider)", "", true)
        local amt = SPD.agiAmount and SPD.agiAmount() or 10
        W.label(string.format("Using amount %d = agility %g", amt, 8 + (amt / 10) * 2), C.yellow)
        W.button("Clear custom - use slider", function() SetV("dw_agicustom", ""); cfg.agiCustom = "" end)
        W.section("Step keys")
        W.slider("dw_agistep", "Step per key press", 1, 1000, 5)
        W.key("dw_agiupkey", "Up key")
        W.key("dw_agidownkey", "Down key")
    end)

    page("MOVEMENT", function()
        W.section("No fall damage")
        W.toggle("dw_nofall", "No fall damage", false)
        W.key("dw_nofallkey", "Toggle key")
        local modes = { "Glide (slow fall)", "Speed cap (the old one)", "Fall reset (normal falling)" }
        GUI.sel.nfmode = (tonumber(store("dw_nofallmode", 2)) or 2) + 1
        local m = W.pick("nfmode", "Mode", modes)
        if m - 1 ~= (tonumber(store("dw_nofallmode", 2)) or 2) then SetV("dw_nofallmode", m - 1) end
        W.slider("dw_nofallbreak", "Reset the fall every", 4, 30, 12, 1, " studs")
        W.label("Every mode does this: the game only hurts falls over ~20 studs")
        if m == 1 then
            W.slider("dw_nofallsink", "Glide down speed", 5, 120, 30, 1, "/s")
        elseif m == 2 then
            W.slider("dw_nofallcap2", "Max fall speed", 5, 200, 40, 1, "/s")
        end
        if m ~= 3 then
            W.slider("dw_nofallcatch", "Catch drops faster than", 8, 60, 20, 1, "/s")
            W.label("Higher = small jumps / dodges left alone")
            W.slider("dw_nofalldelay2", "Extra wait before catching", 0, 500, 0, 25, "ms")
        end
        W.label("Flight (F1) isn't fought any more", C.dim)
        W.label("Status: " .. tostring(SPD.fallStatus), C.cyan)
        W.button("Fall debug: save game's fall code", function() SPD.dumpFallCode() end)
        W.section("Boat speed")
        W.toggle("dw_boat", "Boat speed", false)
        W.key("dw_boatkey", "Toggle key")
        W.slider("dw_boatmult", "Speed (x0.1)", 10, 60, 20, 1, "")
        W.label("20 = 2x as fast. Sail first - it only adds to the boat's own speed")
        W.label("Status: " .. tostring(BOAT.status), C.cyan)
        W.button("Boat scan (if it doesn't work, send dw_boat.txt)", function() BOAT.scan() end)
        W.section("Move while stunned")
        W.toggle("dw_stunmove", "Move while stunned / endlag", false)
        W.key("dw_stunkeyname", "Toggle key")
        W.slider("dw_stunspeed", "Speed", 4, 30, 14, 1, "/s")
        W.label("Status: " .. tostring(SPD.stunStatus and SPD.stunStatus() or "Off"), C.cyan)
    end)

    page("TELEPORTS", function()
        W.label("Teleport: " .. tostring(TP.status), C.yellow)
        W.button("STOP TELEPORT", function() TP.stop("Stopped") end, true)
        W.slider("dw_tpspeed", "Travel speed", 20, 600, 120, 10, "/s")
        W.key("dw_tpstopkey", "Stop key")
        W.section("Places")
        for _, p in ipairs(TP.presets) do
            W.buttons({
                { "Travel: " .. p.name, function() TP.go(p.name, p.pos, p.part, "travel") end },
                { "Instant", function() TP.go(p.name, p.pos, p.part, "instant") end },
            })
        end
        W.section("Game areas")
        W.button("Scan game areas", function() TP.scanAreas() end)
        local an = {}
        for _, a in ipairs(TP.areas) do table.insert(an, a.name) end
        local ai = W.pick("area", "Area", an)
        local area = TP.areas[ai]
        W.buttons({
            { "Travel", function() if area then TP.go(area.name, area.pos, nil, "travel") end end },
            { "Instant", function() if area then TP.go(area.name, area.pos, nil, "instant") end end },
        })
        W.section("Saved spots")
        W.input("dw_spotname", "Spot name", "")
        W.button("Save spot here", function() TP.saveSpot(store("dw_spotname", "")) end)
        local sn = {}
        for _, s in ipairs(TP.spots) do table.insert(sn, s.name) end
        local si = W.pick("spot", "Spot", sn)
        local spot = TP.spots[si]
        W.buttons({
            { "Travel", function() if spot then TP.go(spot.name, spot.pos, nil, "travel") end end },
            { "Instant", function() if spot then TP.go(spot.name, spot.pos, nil, "instant") end end },
            { "Delete", function() if spot then TP.deleteSpot(spot.name) end end },
        })
    end)

    page("TALENTS", function()
        W.section("Tracker")
        W.toggle("dw_talenttrack", "Talent tracker", false)
        W.toggle("dw_talentnotify", "Notify when build cards show up", true)
        W.toggle("dw_talentcards", "Mark cards GET / SKIP", true)
        W.toggle("dw_talentpanel", "Show need / get rid of list", true)
        W.slider("dw_cardyoff", "Card box Y offset", 0, 80, 36)
        W.key("dw_talhlkey", "Highlight cards key")
        W.button("Highlight cards now", function() if TT.highlight then TT.highlight() end end, true)
        W.section("Build")
        W.label(TT.buildName(), C.cyan)
        W.label(TT.progress())
        W.input("dw_buildlink", "Builder link", "https://deepwoken.co/builder?id=kWkA0YWx")
        W.buttons({
            { "Load from link", function() TT.loadFromLink(store("dw_buildlink", "")) end },
            { "Reload dw_build.txt", function() TT.reload() end },
        })
        W.input("dw_talentignore", "Never flag these (comma separated)", "")
        W.buttons({
            { "Dump card GUI", function() TT.dump() end },
            { "Reset to built-in", function() TT.resetBuild() end },
        })
        W.label(TT.status())
    end)

    page("WORLD", function()
        W.section("Lighting (memory)")
        W.toggle("dw_mfullbright", "Fullbright", false)
        W.slider("dw_mfbbright", "Brightness", 1, 10, 3)
        W.slider("dw_mfbexpo", "Exposure (x0.5)", 0, 6, 1)
        W.slider("dw_mfbambient", "Ambient light", 10, 100, 70, 1, "%")
        W.toggle("dw_mnofog", "No fog", false)
        W.label("Status: " .. tostring(MEM.fb), C.cyan)
        W.buttons({
            { "Rescan offsets", function() MEM.resetScan() end },
            { "Memory debug", function() MEM.dump() end },
        })
        W.section("Rice")
        W.label("Rice: " .. tostring(RICE.state), C.cyan)
        W.label("Rice's own tab has Remove Kill Bricks etc.")
        W.buttons({
            { "Load Rice now", function() RICE.load() end },
            { "Load on execute", function()
                pcall(function() delfile("dw_norice.txt") end); RICE.state = "On next execute"
            end },
            { "Don't load", function()
                pcall(function() writefile("dw_norice.txt", "delete this file to load Rice again") end)
                RICE.state = "Off next execute"
            end },
        })
    end)

    page("CONFIG", function()
        W.section("Configs")
        W.input("dw_cfgname", "Config name", "")
        W.buttons({
            { "Save", function() saveConfig(store("dw_cfgname", "")) end, true },
            { "Load by name", function() loadConfig(store("dw_cfgname", ""), false) end },
        })
        local ci = W.pick("cfg", "Saved", configNames)
        local picked = configNames[ci]
        W.buttons({
            { "Load", function() if picked then loadConfig(picked, false) end end },
            { "Overwrite", function() if picked then saveConfig(picked) end end },
            { "Delete", function() if picked then deleteConfig(picked) end end },
        })
        W.buttons({
            { "Load on execute", function() if picked then setAutoload(picked) end end },
            { "Autoload off", function() setAutoload("") end },
            { "Refresh", function() refreshConfigList() end },
        })
        W.label(tostring(configStatus), C.cyan)
        W.label("Saving also makes that config load next time you execute")
        W.section("Menu")
        W.key("dw_menukey", "Hide / show menu key", "END")
        W.button("RESET EVERYTHING TO DEFAULT", function()
            for k in pairs(PENDING) do PENDING[k] = nil end
            pcall(readSettings)
            pcall(function() notify("All settings back to default (saved configs untouched)", "Reset", 4) end)
        end)
    end)

    -- ---- the window ----

    function GUI.frame()
        if KB.pressed("dw_menukey", V("dw_menukey", "END")) then GUI.open = not GUI.open end
        if not GUI.open then
            if GUI.focus then commit() end
            finish()
            return
        end
        readInput()
        if GUI.focus then typeKeys() end
        -- a click anywhere other than the box you're typing in finishes typing
        if click and GUI.focus and GUI.focusRect then
            local r = GUI.focusRect
            if not over(r[1], r[2], r[3], r[4]) then commit() end
        end
        GUI.focusRect = nil

        local x, y, w, h = GUI.x, GUI.y, GUI.w, GUI.h
        box(x, y, w, h, C.bg, true, 0.96, 55)
        box(x, y, w, h, C.line, false, 1, 56)

        -- header
        box(x, y, w, 42, C.side, true, 1, 57)
        box(x, y, 210, 42, C.yellow, true, 1, 58)
        text(x + 16, y + 12, "DEMOLISHER //DW", C.black, 16)
        local who = "?"
        pcall(function() who = string.upper(LocalPlayer.Name) end)
        text(x + 226, y + 14, "NET_LINK::" .. who .. "  //  SYS_OK", C.dim, 12)
        local hk = tostring(V("dw_menukey", "END"))
        local hideW = 110
        local hx = x + w - hideW - 10
        local hovHide = over(hx, y + 9, hideW, 24)
        box(hx, y + 9, hideW, 24, hovHide and C.pink or C.panel, true, 1, 58)
        text(hx + hideW / 2, y + 14, "HIDE [" .. hk .. "]", hovHide and C.black or C.text, 12, true)
        if click and hovHide then click = false; GUI.open = false end
        if click and over(x + 210, y, w - 210 - hideW - 20, 42) then
            click = false
            dragWin = { mx - x, my - y }
        end
        if dragWin then
            if down then GUI.x, GUI.y = mx - dragWin[1], my - dragWin[2] else dragWin = nil end
        end

        -- sidebar
        box(x, y + 42, 210, h - 42, C.side, true, 1, 57)
        text(x + 18, y + 60, who, C.text, 15)
        text(x + 18, y + 80, "EDGERUNNER // DEEPWOKEN", C.cyan, 11)
        for i, pg in ipairs(PAGES) do
            local iy = y + 112 + (i - 1) * 34
            local active = GUI.page == i
            local hov = over(x + 12, iy, 186, 28)
            if active then box(x + 12, iy, 186, 28, C.yellow, true, 1, 58) end
            text(x + 24, iy + 7, string.format("%02d", i), active and C.black or C.dim, 13)
            text(x + 60, iy + 7, pg.name, active and C.black or (hov and C.cyan or C.text), 13)
            if click and hov then click = false; GUI.page = i end
        end
        text(x + 18, y + h - 52, "// PROFILE", C.dim, 11)
        text(x + 18, y + h - 34, string.sub(tostring(configStatus), 1, 24), C.cyan, 11)

        -- content
        local pg = PAGES[GUI.page] or PAGES[1]
        local cx, cw = x + 234, w - 234 - 38
        text(cx, y + 56, string.format("%02d // %s", GUI.page, pg.name), C.pink, 12)
        text(cx, y + 72, pg.name, C.text, 26)
        text(cx + #pg.name * 15.5 + 4, y + 72, "_", C.yellow, 26)
        L.x, L.w, L.top, L.bottom = cx, cw, y + 114, y + h - 12
        local sc = GUI.scroll[GUI.page] or 0
        L.y = L.top - sc
        local ok, err = pcall(pg.fn)
        if not ok then
            text(cx, L.top, "page error: " .. tostring(err), C.pink, 12)
            report("menu " .. pg.name, err)
        end
        local contentH = (L.y + sc) - L.top
        local viewH = L.bottom - L.top

        -- scrollbar
        if contentH > viewH then
            local bx = x + w - 22
            box(bx, L.top, 6, viewH, C.track, true, 1, 58)
            local thumbH = math.max(viewH * viewH / contentH, 30)
            local maxSc = contentH - viewH
            local ty = L.top + (viewH - thumbH) * (sc / maxSc)
            box(bx - 2, ty, 10, thumbH, dragBar and C.yellow or C.cyan, true, 1, 59)
            if click and over(bx - 8, L.top, 22, viewH) then click = false; dragBar = { my, sc } end
            if dragBar then
                if down then
                    local nsc = dragBar[2] + (my - dragBar[1]) * (contentH / viewH)
                    GUI.scroll[GUI.page] = clamp(nsc, 0, maxSc)
                else
                    dragBar = nil
                end
            end
        else
            GUI.scroll[GUI.page] = 0
        end

        finish()
    end

    task.spawn(function()
        while true do
            local ok, err = pcall(GUI.frame)
            if not ok then report("menu", err) end
            task.wait()
        end
    end)
end

-- Matcha's own tab now just opens/hides the custom menu
UI.AddTab("Deepwoken Script", function(tab)
    logStep("8 UI first frame start", true)
    local s = tab:Section("Deepwoken Script", "Left")
    s:Text("Everything is in the DEMOLISHER //DW window.")
    s:Button(GUI.open and "Hide the menu" or "Show the menu", function() GUI.open = not GUI.open end)
    s:Text("Hide / show key: " .. tostring(V("dw_menukey", "END")))
    s:Text("Drag it by the header.")
end)

logStep("9 script fully loaded")
