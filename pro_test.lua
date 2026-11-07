-- Matcha capability test (for deciding what the Pro version of the
-- Deepwoken script can do). Run it once in Deepwoken, standing still near
-- another player or mob if possible. It only READS and tries harmless
-- things (a test part it deletes again); it never fires a game remote.
-- Results: dw_protest.txt in the Matcha workspace folder + the console.

local out = {}
local function line(s) table.insert(out, s); print("[DW pro] " .. s) end
local function try(label, fn)
    local ok, res = pcall(fn)
    line(string.format("%-34s %s", label, ok and ("OK  " .. tostring(res)) or ("FAIL  " .. tostring(res))))
    return ok, res
end
local function has(name)
    local v = nil
    pcall(function() v = getfenv()[name] end)
    if v == nil then pcall(function() v = _G[name] end) end
    return type(v)
end

line("DW capability test " .. tostring(os.date()))
try("executor", function()
    if identifyexecutor then return table.concat({ identifyexecutor() }, " ") end
    return "identifyexecutor missing"
end)

local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local live = workspace:FindFirstChild("Live")
local me = live and live:FindFirstChild(lp.Name)
local hum = me and me:FindFirstChild("Humanoid")
local root = me and me:FindFirstChild("HumanoidRootPart")
line("character found: " .. tostring(me ~= nil))

line("")
line("== 1. AUTO PARRY: reading animations ==")
try("Humanoid:GetPlayingAnimationTracks", function()
    local t = hum:GetPlayingAnimationTracks()
    local ids = {}
    for i, tr in ipairs(t) do
        if i > 4 then break end
        local id = "?"
        pcall(function() id = tr.Animation.AnimationId end)
        local tp = "?"
        pcall(function() tp = string.format("%.2f", tr.TimePosition) end)
        table.insert(ids, id .. " @" .. tp)
    end
    return #t .. " tracks: " .. table.concat(ids, ", ")
end)
try("Animator:GetPlayingAnimationTracks", function()
    return #hum:FindFirstChild("Animator"):GetPlayingAnimationTracks() .. " tracks"
end)
try("AnimationPlayed event", function()
    local c = hum:FindFirstChild("Animator").AnimationPlayed:Connect(function() end)
    c:Disconnect()
    return "can connect"
end)
-- someone else, if close
pcall(function()
    local best, bd = nil, 80
    for _, m in ipairs(live:GetChildren()) do
        if m ~= me then
            local ok, p = pcall(function() return m.HumanoidRootPart.Position end)
            if ok and p and root then
                local d = (p - root.Position).Magnitude
                if d < bd then best, bd = m, d end
            end
        end
    end
    if best then
        try("other (" .. best.Name .. ") tracks", function()
            return #best.Humanoid:GetPlayingAnimationTracks() .. " tracks"
        end)
    else
        line("other character tracks             (nobody within 80 studs - optional)")
    end
end)

line("")
line("== 2. NOCLIP: collision ==")
try("read CanCollide on your Torso", function() return tostring(me.Torso.CanCollide) end)
try("read CanCollide on a map part", function()
    for _, d in ipairs(workspace:FindFirstChild("Map"):GetDescendants()) do
        if d.ClassName == "Part" then return d:GetFullName() .. " = " .. tostring(d.CanCollide) end
    end
    return "no Part found in Map"
end)
try("write + read back CanCollide", function()
    local p = me.HumanoidRootPart
    local old = p.CanCollide
    p.CanCollide = not old
    local back = p.CanCollide
    p.CanCollide = old
    return "wrote " .. tostring(not old) .. ", read back " .. tostring(back)
end)
try("ControllerManager.ActiveController", function()
    local cm = me:FindFirstChild("ControllerManager")
    return tostring(cm.ActiveController)
end)
try("Humanoid.Sit / SeatPart (boat)", function()
    return "Sit=" .. tostring(hum.Sit) .. " SeatPart=" .. tostring(hum.SeatPart)
end)
try("Anchored read", function() return tostring(root.Anchored) end)

line("")
line("== 3. CREATING THINGS ==")
try("Instance.new Part (deleted again)", function()
    local p = Instance.new("Part")
    p.Name = "DWTestPart"
    p.Transparency = 1
    p.CanCollide = false
    p.Parent = workspace
    local ok = workspace:FindFirstChild("DWTestPart") ~= nil
    p:Destroy()
    return "made and found: " .. tostring(ok)
end)
try("Instance.new Highlight", function()
    local h = Instance.new("Highlight")
    h:Destroy()
    return "ok"
end)

line("")
line("== 4. GAME MODULES / REMOTES (nothing is fired) ==")
try("require(RealmInfo) (data only)", function()
    local m = require(game:GetService("ReplicatedStorage").Info.RealmInfo)
    return type(m) .. " CurrentWorld=" .. tostring(m.CurrentWorld)
end)
try("Requests folder", function()
    local r = game:GetService("ReplicatedStorage"):FindFirstChild("Requests")
    return r and (#r:GetChildren() .. " remotes") or "missing"
end)
try("RemoteEvent has FireServer", function()
    for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
        if d.ClassName == "RemoteEvent" then return d.Name .. ": " .. typeof(d.FireServer) end
    end
    return "no RemoteEvent found"
end)

line("")
line("== 5. WORLD ==")
try("workspace.Gravity", function() return tostring(workspace.Gravity) end)
try("workspace:Raycast down", function()
    local r = workspace:Raycast(root.Position, Vector3.new(0, -50, 0))
    return r and (r.Instance:GetFullName()) or "nil (no hit)"
end)
try("IsA works", function() return tostring(root:IsA("BasePart")) end)
try("FindFirstChildWhichIsA works", function() return tostring(me:FindFirstChildWhichIsA("Humanoid")) end)

line("")
line("== 6. EXECUTOR FUNCTIONS (type = function means available) ==")
for _, n in ipairs({ "hookfunction", "hookmetamethod", "getrawmetatable", "setreadonly", "newcclosure",
    "getgenv", "getsenv", "getgc", "getconnections", "firesignal", "fireproximityprompt",
    "firetouchinterest", "getnilinstances", "getscripts", "decompile", "setthreadidentity",
    "keypress", "keyrelease", "mouse1click", "mouse1press", "mousemoverel", "memory_read",
    "memory_write", "request", "http_request", "httpget", "writefile", "Drawing" }) do
    line(string.format("%-34s %s", n, has(n)))
end
try("VirtualInputManager", function() return tostring(game:GetService("VirtualInputManager")) end)

line("")
line("== 7. HYBRID: hooking (tested on a dummy function only) ==")
for _, n in ipairs({ "getnamecallmethod", "checkcaller", "cloneref", "hookfunction", "hookmetamethod",
    "getrawmetatable", "replaceclosure", "detour_function", "getcallingscript", "islclosure" }) do
    line(string.format("%-34s %s", n, has(n)))
end
try("hookfunction on a test function", function()
    local function original() return "original" end
    local old = hookfunction(original, function() return "hooked" end)
    local got = original()
    if old then hookfunction(original, old) end
    return "call returned " .. tostring(got)
end)
try("game __namecall metamethod", function()
    local mt = getrawmetatable(game)
    return "type " .. type(mt.__namecall)
end)
try("Humanoid.AnimationPlayed event", function()
    local c = hum.AnimationPlayed:Connect(function() end)
    c:Disconnect()
    return "can connect"
end)
try("FallDamage remote exists", function()
    local r = game:GetService("ReplicatedStorage"):FindFirstChild("Requests")
    local f = r and r:FindFirstChild("FallDamage")
    return f and (f.ClassName .. " (not fired)") or "not found by that name"
end)

pcall(function() writefile("dw_protest.txt", table.concat(out, "\n")) end)
pcall(function() notify("Wrote dw_protest.txt - send it over", "DW capability test", 8) end)
line("done - send dw_protest.txt")
