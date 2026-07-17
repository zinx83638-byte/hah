if not hookmetamethod or not hookfunction then
    warn("[TPS Assist] executor sin hookmetamethod/hookfunction")
    return
end

if _G.TPSReach and _G.TPSReach.cleanup then
    pcall(_G.TPSReach.cleanup)
end

local REACH_MAX = 10

local REACT_RANGE = 5.5
local REACH_WINDOW = 0.9
local REACH_MIN = 0

local KICK_REMOTE_BURST = 3

local AC_WATCH_INTERVAL = 1.5
local AC_KICK_MESSAGE = "Anticheat actualizado"

local Config = {
    reachEnabled = false,
    reactEnabled = false,
    reactV2Enabled = false,
    bypassEnabled = true,
    reach        = REACH_MAX,
    kickActive   = false,
    kickFired    = false,
    passActive   = false,
    actionActive = false,
    reactShot    = false,
    reactForceTouch = false,
    kickRemoteCount = 0,
    chargeStart  = 0,
    reachUntil   = 0,
    acWatchEnabled = true,
}

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local CoreGui           = game:GetService("CoreGui")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local Hooks = {}
local UI = {
    window = nil,
    gui    = nil,
}

local function parentGui(gui)
    local ok = pcall(function()
        if typeof(gethui) == "function" then
            gui.Parent = gethui()
            return
        end
        if syn and syn.protect_gui then
            syn.protect_gui(gui)
        end
        gui.Parent = CoreGui
    end)
    if not ok or not gui.Parent then
        pcall(function()
            gui.Parent = PlayerGui
        end)
    end
end

local NotifyGui = Instance.new("ScreenGui")
NotifyGui.Name = "TPSAssistNotify"
NotifyGui.ResetOnSpawn = false
NotifyGui.DisplayOrder = 200
NotifyGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
parentGui(NotifyGui)

print("[TPS Assist] loading...")

local function notify(text, color)
    local toast = Instance.new("Frame")
    toast.Name = "Toast"
    toast.AnchorPoint = Vector2.new(1, 0)
    toast.Position = UDim2.new(1, -16, 0, 16)
    toast.Size = UDim2.new(0, 260, 0, 36)
    toast.BackgroundColor3 = Color3.fromRGB(32, 35, 42)
    toast.BorderSizePixel = 0
    toast.Parent = NotifyGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = toast

    local stroke = Instance.new("UIStroke")
    stroke.Color = color or Color3.fromRGB(70, 140, 100)
    stroke.Thickness = 1
    stroke.Parent = toast

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, -16, 1, 0)
    label.Position = UDim2.new(0, 8, 0, 0)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextColor3 = Color3.fromRGB(235, 238, 245)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = text
    label.Parent = toast

    toast.Position = UDim2.new(1, 40, 0, 16)
    TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Position = UDim2.new(1, -16, 0, 16),
    }):Play()

    task.delay(2.5, function()
        if not toast.Parent then return end
        local out = TweenService:Create(toast, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
            Position = UDim2.new(1, 40, 0, 16),
        })
        out:Play()
        out.Completed:Wait()
        toast:Destroy()
    end)
end

local LIMB_NAMES = {
    RightLowerLeg = true, RightUpperLeg = true, RightFoot = true,
    LeftLowerLeg = true, LeftUpperLeg = true, LeftFoot = true,
    RightLowerArm = true, RightUpperArm = true, RightHand = true,
    LeftLowerArm = true, LeftUpperArm = true, LeftHand = true,
    Torso = true, UpperTorso = true, LowerTorso = true,
    HumanoidRootPart = true,
    ["Right Leg"] = true, ["Left Leg"] = true,
    ["Right Arm"] = true, ["Left Arm"] = true,
}

local function getBackpack()
    return LocalPlayer:FindFirstChild("Backpack")
end

local BALL_NAMES = {
    TPS = true,
    PSoccerBall = true,
    Bomb = true,
}

local function isBallName(name)
    return BALL_NAMES[name] == true
end

local function getTPSBall()
    local sys = Workspace:FindFirstChild("TPSSystem")
    if sys then
        local tps = sys:FindFirstChild("TPS")
        if tps and tps:IsA("BasePart") then
            return tps
        end
        for _, child in ipairs(sys:GetChildren()) do
            if child:IsA("BasePart") and isBallName(child.Name) then
                return child
            end
        end
    end


    for _, name in ipairs({ "TPS", "PSoccerBall", "Bomb" }) do
        local ball = Workspace:FindFirstChild(name, true)
        if ball and ball:IsA("BasePart") then
            return ball
        end
    end
    return nil
end

local function getDistanceToBall(ball)
    ball = ball or getTPSBall()
    local char = LocalPlayer.Character
    if not (ball and char) then return math.huge end

    local best = math.huge
    for _, name in ipairs({
        "RightFoot", "LeftFoot", "RightLowerLeg", "LeftLowerLeg",
        "RightUpperLeg", "LeftUpperLeg", "HumanoidRootPart",
        "RightLowerArm", "LeftLowerArm", "RightUpperArm", "LeftUpperArm",
        "RightHand", "LeftHand",
        "Right Leg", "Left Leg", "Right Arm", "Left Arm",
        "Torso", "UpperTorso", "LowerTorso",
    }) do
        local part = char:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            local d = (ball.Position - part.Position).Magnitude
            if d < best then best = d end
        end
    end
    return best
end

local function isReachWindowOpen()
    return tick() <= (Config.reachUntil or 0)
end

local function openReachWindow(secs)
    local untilAt = tick() + (type(secs) == "number" and secs or REACH_WINDOW)
    if untilAt > (Config.reachUntil or 0) then
        Config.reachUntil = untilAt
    end
end

local function isLocalGk()
    local red = PlayerGui:FindFirstChild("RedGK")
    if red and red.Value then return true end
    local blue = PlayerGui:FindFirstChild("BlueGK")
    if blue and blue.Value then return true end
    return false
end

local function canPlay()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("Humanoid") then return false end
    if char.Humanoid.Health <= 0 then return false end
    local activate = PlayerGui:FindFirstChild("Activate")
    if activate and activate.Value == false then return false end
    -- GK allowed: Save/Dive reach needs canPlay/canHit while RedGK/BlueGK is true
    return true
end

local function canHitBall()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("Humanoid") then return false end
    if char.Humanoid.Health <= 0 then return false end
    -- Do NOT block GK here. Field-only kick remotes are gated in fireKick via isLocalGk.
    return true
end

local function resultsHaveTPS(results)
    for _, part in ipairs(results) do
        if isBallName(part.Name) then
            return true
        end
    end
    return false
end

local function isValidBall(ball)
    if not ball or not ball:IsA("BasePart") then return false end
    if not isBallName(ball.Name) then return false end
    if ball.Anchored then return false end
    local parent = ball.Parent
    if parent and parent:FindFirstChildOfClass("Humanoid") then return false end
    if parent and parent:IsA("Accessory") then return false end

    if ball.Locked == false then return false end
    return true
end

local function isInReachRange(dist)
    return dist >= REACH_MIN and dist <= Config.reach
end

local function isAnyReactOn()
    return Config.reactEnabled == true or Config.reactV2Enabled == true
end

local function getHitRange()
    if Config.reachEnabled then
        return Config.reach
    end
    if isAnyReactOn() or Config.reactShot then
        return REACT_RANGE
    end
    return 0
end

local function isInHitRange(dist)
    local maxR = getHitRange()
    if maxR <= 0 then return false end
    return dist >= REACH_MIN and dist <= maxR
end

local function isHitAssistActive()
    if not (Config.kickActive or Config.passActive or Config.actionActive or isReachWindowOpen()) then
        return false
    end
    return Config.reachEnabled or isAnyReactOn() or Config.reactShot
end

local function applyReactTouch()
    local backpack = getBackpack()
    if not backpack then return end
    local speed = backpack:FindFirstChild("Speed")
    local angle = backpack:FindFirstChild("Angle")

    if speed then speed.Value = 30 end
    if angle then angle.Value = Vector3.new(4000000, 350, 4000000) end
    local ground = backpack:FindFirstChild("Ground")
    if ground then ground.Value = false end
end

local function isKickFireRemote(inst)
    if typeof(inst) ~= "Instance" then return false end
    local parent = inst.Parent
    if not parent then return false end

    if parent.Name == "Kick" and parent.Parent and parent.Parent.Name == "FE" then
        return true
    end

    if inst.Name == "Kick" and parent.Name == "System" and parent.Parent and parent.Parent.Name == "FE" then
        return true
    end
    return false
end

local function beginShotWindow()
    Config.kickFired = false
    Config.kickRemoteCount = 0
end

local function fireKick(ball)
    if Config.kickFired then return false end
    -- Kick remotes are field-only; GK uses Module Save/Dive + GetTouchingParts inject
    if isLocalGk() then return false end
    if not isValidBall(ball) or not canHitBall() then return false end

    local backpack = getBackpack()
    if not backpack then return false end

    local fe = Workspace:FindFirstChild("FE")
    if not fe then return false end

    local system = fe:FindFirstChild("System")
    local kickFolder = fe:FindFirstChild("Kick")
    if not (system and kickFolder) then return false end

    local kickRemote = kickFolder:FindFirstChild("RemoteEvent")
    local systemKick = system:FindFirstChild("Kick")
    if not (kickRemote and systemKick) then return false end

    local altName = system:FindFirstChild("ALTNameA")
    local speed = backpack:FindFirstChild("Speed")
    local angle = backpack:FindFirstChild("Angle")
    if not (speed and angle) then return false end

    local powerActive = backpack:FindFirstChild("PowerActive")
    local ground = backpack:FindFirstChild("Ground")
    local curving = backpack:FindFirstChild("Curving")
    local particle = backpack:FindFirstChild("Particle")
    local fvalue = backpack:FindFirstChild("FValue")

    if particle then particle.Disabled = false end


    local ok = pcall(function()
        kickRemote:FireServer(ball)
        systemKick:FireServer(
            LocalPlayer.UserId,
            ball,
            speed.Value,
            angle.Value,
            powerActive and powerActive.Value or false,
            ground and ground.Value or false,
            curving and curving.Value or false,
            "Rock'n'roll Star",
            altName and altName.Value or "",
            "power=95/100"
        )

        if powerActive and powerActive.Value == true then
            if ball.Name ~= "Bomb" then
                powerActive.Value = false
                local start = PlayerGui:FindFirstChild("Start")
                if start and start:FindFirstChild("PowerShot") then
                    local timer = start.PowerShot:FindFirstChild("Timer")
                    if timer then timer.Disabled = false end
                end
            end
            if fvalue and kickFolder:FindFirstChild("RemoteEvent1") then
                kickFolder.RemoteEvent1:FireServer(ball, fvalue.Value)
            end
        end
    end)

    if not ok then
        Config.kickFired = false
        Config.kickRemoteCount = 0
        return false
    end

    Config.kickFired = true
    Config.kickRemoteCount = KICK_REMOTE_BURST
    return true
end

local function tryInstantReactHit()
    if not canHitBall() then return false end
    local ball = getTPSBall()
    if not isValidBall(ball) then return false end
    local dist = getDistanceToBall(ball)
    if not isInHitRange(dist) then return false end
    return fireKick(ball)
end

local function markKickFiredFromRemote(remote)
    if not remote then return end
    if not isKickFireRemote(remote) then return end
    Config.kickRemoteCount = (Config.kickRemoteCount or 0) + 1
    Config.kickFired = true
end

local KNOWN_AC_PING_REMOTES = {
    ["p290i35s"] = true,
    ["w392p389s"] = true,
    ["x-996d-685y"] = true,
    ["z-68n809t"] = true,
}

local function isAcClientRemote(inst)
    if typeof(inst) ~= "Instance" then return false end
    if not (inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent")) then
        return false
    end

    if inst.Parent ~= game:GetService("ReplicatedStorage") then
        return false
    end
    local name = inst.Name
    if KNOWN_AC_PING_REMOTES[name] then return true end

    if name == "PSAdminMsg" or name == "GetSubscriptionStatus" then
        return false
    end

    if string.match(name, "%d") and #name <= 24 then
        if inst:FindFirstChildWhichIsA("Script")
            or inst:FindFirstChildWhichIsA("LocalScript")
            or string.find(name, "-", 1, true)
        then
            return true
        end
    end
    return false
end

local function findAcPingRemotes()
    local rs = game:GetService("ReplicatedStorage")
    local list = {}
    for _, child in ipairs(rs:GetChildren()) do
        if isAcClientRemote(child) then
            list[#list + 1] = child
        end
    end
    return list
end

local function setPingBypass(enabled)
    if not getconnections then return false end
    local okAny = false
    for _, pingRemote in ipairs(findAcPingRemotes()) do
        local ok = pcall(function()
            for _, conn in ipairs(getconnections(pingRemote.OnClientEvent)) do
                if enabled then
                    if conn.Disable then conn:Disable() end
                else
                    if conn.Enable then conn:Enable() end
                end
            end
        end)
        if ok then okAny = true end
    end
    Hooks.pingBypassEnabled = enabled and okAny
    return okAny
end

local function isHelloWorldRemote(inst)


    if typeof(inst) ~= "Instance" then return false end
    if inst.ClassName ~= "RemoteEvent" then return false end
    if inst.Name ~= "HelloWorld" then return false end
    local system = inst.Parent
    if not system or system.Name ~= "System" then return false end
    local fe = system.Parent
    return fe ~= nil and fe.Name == "FE"
end

local function shouldBlockAcBanCode(code)
    return code == 2 or code == 3 or code == 4
end

local function djb2Hash(str)
    if type(str) ~= "string" then return "0" end
    local hash = 5381
    for i = 1, #str do
        hash = bit32.bxor((hash * 33) % 4294967296, string.byte(str, i))
    end
    return string.format("%08x", hash)
end

local function getScriptSig(scriptInst)
    if typeof(scriptInst) ~= "Instance" then return nil end
    if not (scriptInst:IsA("LocalScript") or scriptInst:IsA("ModuleScript")) then
        return nil
    end
    if type(getscriptbytecode) == "function" then
        local ok, bytecode = pcall(getscriptbytecode, scriptInst)
        if ok and type(bytecode) == "string" and #bytecode > 0 then
            return #bytecode .. ":" .. djb2Hash(bytecode)
        end
    end
    return scriptInst.ClassName .. ":" .. scriptInst.Name
end

local function collectNamedChildren(parent)
    if not parent then return "" end
    local names = {}
    for _, child in ipairs(parent:GetChildren()) do
        names[#names + 1] = child.Name .. ":" .. child.ClassName
    end
    table.sort(names)
    return table.concat(names, ",")
end

local function collectAcScriptFingerprint()

    local roots = {
        Workspace:FindFirstChild("Holder"),
        Workspace:FindFirstChild("Walls"),
        Workspace:FindFirstChild("Sounds"),
        Workspace:FindFirstChild("FixersBall"),
        Workspace:FindFirstChild("GiftReward"),
        Workspace:FindFirstChild("Leaderboards"),
        Workspace:FindFirstChild("WLeaderboards"),
        Workspace:FindFirstChild("FE"),
    }

    local entries = {}
    for _, root in ipairs(roots) do
        if root then
            local okDesc, descendants = pcall(function()
                return root:GetDescendants()
            end)
            if okDesc and type(descendants) == "table" then
                for _, inst in ipairs(descendants) do
                    if inst:IsA("LocalScript") or inst:IsA("ModuleScript") then
                        local sig = getScriptSig(inst)
                        if sig then
                            entries[#entries + 1] = inst:GetFullName() .. "=" .. sig
                        end
                    end
                end
            end
        end
    end
    table.sort(entries)
    return table.concat(entries, "|")
end

local function collectRemoteFingerprint()
    local rs = game:GetService("ReplicatedStorage")
    local names = {}
    for _, child in ipairs(rs:GetChildren()) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") or child:IsA("UnreliableRemoteEvent") then

            if isAcClientRemote(child) or string.match(child.Name, "%d") or #child.Name <= 4 then
                names[#names + 1] = child.Name .. ":" .. child.ClassName
            end
        end
    end
    table.sort(names)
    return table.concat(names, ",")
end

local function buildAcFingerprint()
    local fe = Workspace:FindFirstChild("FE")
    local system = fe and fe:FindFirstChild("System")
    local hello = system and system:FindFirstChild("HelloWorld")

    return table.concat({
        "pv=" .. tostring(game.PlaceVersion),
        "hello=" .. (hello and (hello.ClassName .. ":" .. tostring(hello)) or "missing"),
        "system=" .. collectNamedChildren(system),
        "remotes=" .. collectRemoteFingerprint(),
        "scripts=" .. collectAcScriptFingerprint(),
    }, "||")
end

local function kickForAcUpdate(reason)
    if Hooks.acTripped then return end
    Hooks.acTripped = true
    Config.acWatchEnabled = false


    Hooks.acUpdateReason = reason
    pcall(function()
        notify(AC_KICK_MESSAGE .. " · re-ejecuta el script", Color3.fromRGB(220, 90, 90))
    end)
end

local function installAcUpdateWatch()
    if Hooks.acWatchInstalled then return end
    Hooks.acWatchInstalled = true
    Hooks.acTripped = false

    local okBaseline, baseline = pcall(buildAcFingerprint)
    if not okBaseline or type(baseline) ~= "string" or baseline == "" then
        baseline = "pv=" .. tostring(game.PlaceVersion)
    end
    Hooks.acBaseline = baseline
    Hooks.acHelloRef = nil

    local fe = Workspace:FindFirstChild("FE")
    local system = fe and fe:FindFirstChild("System")
    if system then
        Hooks.acHelloRef = system:FindFirstChild("HelloWorld")
    end

    local function checkAc(reasonHint)
        if not Config.acWatchEnabled or Hooks.acTripped then return end

        local feNow = Workspace:FindFirstChild("FE")
        local systemNow = feNow and feNow:FindFirstChild("System")
        local helloNow = systemNow and systemNow:FindFirstChild("HelloWorld")


        if not systemNow then
            kickForAcUpdate(reasonHint or "FE.System missing")
            return
        end
        if not helloNow or not helloNow:IsA("RemoteEvent") then
            kickForAcUpdate(reasonHint or "HelloWorld missing/changed")
            return
        end
        if Hooks.acHelloRef and helloNow ~= Hooks.acHelloRef then
            kickForAcUpdate(reasonHint or "HelloWorld replaced")
            return
        end

        local okNow, current = pcall(buildAcFingerprint)
        if not okNow or type(current) ~= "string" then return end
        if current ~= Hooks.acBaseline then
            kickForAcUpdate(reasonHint or "fingerprint mismatch")
        end
    end

    Hooks.acCheck = checkAc


    if system then
        Hooks.acSystemChildConn = system.ChildAdded:Connect(function()
            task.defer(function()
                checkAc("FE.System ChildAdded")
            end)
        end)
        Hooks.acSystemRemoveConn = system.ChildRemoved:Connect(function(child)
            if child.Name == "HelloWorld" or (Hooks.acHelloRef and child == Hooks.acHelloRef) then
                kickForAcUpdate("HelloWorld removed")
            else
                task.defer(function()
                    checkAc("FE.System ChildRemoved")
                end)
            end
        end)
    end

    local rs = game:GetService("ReplicatedStorage")
    Hooks.acRsConn = rs.ChildAdded:Connect(function(child)
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") or child:IsA("UnreliableRemoteEvent") then
            if isAcClientRemote(child) or string.match(child.Name, "%d") or #child.Name <= 4 then

                if Config.bypassEnabled then
                    task.defer(function()
                        setPingBypass(true)
                    end)
                end
                task.defer(function()
                    checkAc("ReplicatedStorage remote added")
                end)
            end
        end
    end)

    Hooks.acWatchConn = task.spawn(function()
        while Config.acWatchEnabled and not Hooks.acTripped do
            task.wait(AC_WATCH_INTERVAL)
            if not Config.acWatchEnabled or Hooks.acTripped then break end
            checkAc("periodic scan")
        end
    end)
end

local function installBypassHook()




    local ok, helloWorld = pcall(function()
        local fe = Workspace:FindFirstChild("FE") or Workspace:WaitForChild("FE", 5)
        if not fe then return nil end
        local system = fe:FindFirstChild("System") or fe:WaitForChild("System", 5)
        if not system then return nil end
        return system:FindFirstChild("HelloWorld") or system:WaitForChild("HelloWorld", 5)
    end)
    if ok and helloWorld then
        Hooks.acHelloRef = helloWorld
    end




end

local taskWaitOk, taskWaitErr = pcall(function()
    Hooks.oldTaskWait = hookfunction(task.wait, newcclosure(function(duration)
        if Config.reactShot and Config.kickActive and duration == 0.7 then

            return Hooks.oldTaskWait(0)
        end
        return Hooks.oldTaskWait(duration)
    end))
end)
if not taskWaitOk then
    warn("[TPS Assist] task.wait hook failed: ", taskWaitErr)
end

local namecallOk, namecallErr = pcall(function()
    Hooks.oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()


        if method == "FireServer" then
            if Config.bypassEnabled and isHelloWorldRemote(self) then
                local code = ...
                if shouldBlockAcBanCode(code) then
                    return
                end
            end


            if isKickFireRemote(self) then
                if (Config.kickRemoteCount or 0) >= KICK_REMOTE_BURST then
                    return
                end
                markKickFiredFromRemote(self)
            end

            return Hooks.oldNamecall(self, ...)
        end

        if method == "GetTouchingParts" and isHitAssistActive() then
            local results = Hooks.oldNamecall(self, ...)

            -- Limbs always; during Save/Dive/Tackle also allow hitbox-style BaseParts
            -- (GK Detect often queries non-limb parts, not only R15 limbs).
            local allowPart = typeof(self) == "Instance"
                and self:IsA("BasePart")
                and (
                    LIMB_NAMES[self.Name]
                    or Config.actionActive
                    or isLocalGk()
                )

            if allowPart then
                if not resultsHaveTPS(results) then
                    local ball = getTPSBall()
                    if isValidBall(ball) then
                        local dist = getDistanceToBall(ball)
                        if isInHitRange(dist) then
                            local extended = table.create(#results + 1)
                            for i = 1, #results do
                                extended[i] = results[i]
                            end
                            extended[#results + 1] = ball
                            return extended
                        end
                    end
                end
            end

            return results
        end

        -- Spatial queries used by newer Touch/Save paths (same inject rules).
        if (method == "GetPartsInPart" or method == "GetPartBoundsInBox" or method == "GetPartBoundsInRadius")
            and isHitAssistActive()
        then
            local results = Hooks.oldNamecall(self, ...)
            if type(results) == "table" and not resultsHaveTPS(results) then
                local ball = getTPSBall()
                if isValidBall(ball) then
                    local dist = getDistanceToBall(ball)
                    if isInHitRange(dist) then
                        local extended = table.create(#results + 1)
                        for i = 1, #results do
                            extended[i] = results[i]
                        end
                        extended[#results + 1] = ball
                        return extended
                    end
                end
            end
            return results
        end

        return Hooks.oldNamecall(self, ...)
    end))
end)
if not namecallOk then
    warn("[TPS Assist] namecall hook failed: ", namecallErr)
end

local function wrapModuleFunction(mod, key, oldKey, wrapperFactory)
    local current = mod[key]
    if type(current) ~= "function" then return false end


    if Hooks[oldKey] and current ~= Hooks[oldKey] and Hooks["wrapped" .. key] == current then
        return true
    end


    Hooks[oldKey] = current
    local wrapped = wrapperFactory(Hooks[oldKey])
    Hooks["wrapped" .. key] = wrapped
    mod[key] = wrapped
    return true
end

local function hookGameModule()
    local backpack = LocalPlayer:FindFirstChild("Backpack") or LocalPlayer:WaitForChild("Backpack", 5)
    if not backpack then return false end

    local moduleScript = backpack:FindFirstChild("Module") or backpack:WaitForChild("Module", 5)
    if not moduleScript then return false end

    local okRequire, mod = pcall(require, moduleScript)
    if not okRequire or type(mod) ~= "table" then return false end


    if Hooks.hookedModule ~= mod then
        Hooks.oldKick = nil
        Hooks.oldKick2 = nil
        Hooks.oldPass = nil
        Hooks.oldTackle = nil
        Hooks.oldSave = nil
        Hooks.oldDive = nil
        Hooks.oldSpecialKick = nil
        Hooks.wrappedKick = nil
        Hooks.wrappedKick2 = nil
        Hooks.wrappedPass = nil
        Hooks.wrappedTackle = nil
        Hooks.wrappedSave = nil
        Hooks.wrappedDive = nil
        Hooks.wrappedSpecialKick = nil
        Hooks.hookedModule = mod
    end

    local function wrapActionReach(key, oldKey, windowSecs)
        wrapModuleFunction(mod, key, oldKey, function(old)
            return function(...)
                local win = windowSecs or REACH_WINDOW
                Config.actionActive = true
                -- Always open window for Save/Dive/Tackle when reach is on (incl. GK)
                if Config.reachEnabled then
                    openReachWindow(win)
                end

                local ok, err = pcall(old, ...)

                task.delay(win, function()
                    Config.actionActive = false
                end)

                if not ok then
                    warn("[TPS Assist] " .. key .. " error: ", err)
                end
            end
        end)
    end

    wrapModuleFunction(mod, "Kick", "oldKick", function(old)
        return function(...)
            Config.chargeStart = tick()
            return old(...)
        end
    end)

    wrapModuleFunction(mod, "Kick2", "oldKick2", function(old)
        return function(...)
            beginShotWindow()
            Config.kickActive = true


            local useV1 = Config.reactEnabled == true
            local useV2 = (not useV1) and Config.reactV2Enabled == true
            Config.reactShot = useV1 or useV2
            Config.reactForceTouch = useV1

            if Config.reactShot then
                if Config.reactForceTouch then

                    applyReactTouch()
                end

                openReachWindow()
                tryInstantReactHit()
            elseif Config.reachEnabled then
                openReachWindow()
            end


            local ok, err = pcall(old, ...)

            task.delay(REACH_WINDOW, function()
                Config.kickActive = false
                Config.reactShot = false
                Config.reactForceTouch = false
            end)

            if not ok then
                warn("[TPS Assist] Kick2 error: ", err)
            end
        end
    end)

    wrapModuleFunction(mod, "Pass", "oldPass", function(old)
        return function(...)
            beginShotWindow()
            Config.passActive = true
            Config.reactShot = false
            if Config.reachEnabled then
                openReachWindow()
            end

            local ok, err = pcall(old, ...)

            task.delay(REACH_WINDOW, function()
                Config.passActive = false
            end)

            if not ok then
                warn("[TPS Assist] Pass error: ", err)
            end
        end
    end)

    -- Match Module hit windows: Tackle ~1s, Save/Dive ~0.7s, SpecialKick anim longer.
    -- Studs unchanged; only inject window + limb coverage for these actions.
    wrapActionReach("Tackle", "oldTackle", 1.15)
    wrapActionReach("Save", "oldSave", 1.0)
    wrapActionReach("Dive", "oldDive", 1.0)
    wrapActionReach("SpecialKick", "oldSpecialKick", 1.5)

    return true
end

Hooks.reachConn = RunService.Heartbeat:Connect(function()
    if Config.kickFired then return end
    if not Config.kickActive then return end
    if not (Config.reachEnabled or isAnyReactOn() or Config.reactShot) then return end
    if not canHitBall() then return end

    local ball = getTPSBall()
    if not isValidBall(ball) then return end

    local dist = getDistanceToBall(ball)
    if not isInHitRange(dist) then return end


    if Config.reactForceTouch or Config.reactEnabled then
        applyReactTouch()
    end
    fireKick(ball)
end)

Hooks.charConn = LocalPlayer.CharacterAdded:Connect(function()
    Config.kickActive = false
    Config.passActive = false
    Config.actionActive = false
    Config.kickFired = false
    Config.reactShot = false
    Config.reactForceTouch = false
    Config.kickRemoteCount = 0
    Config.reachUntil = 0
    task.delay(0.5, function()
        hookGameModule()
    end)
    task.delay(2, function()
        hookGameModule()
    end)
end)

local backpack = LocalPlayer:FindFirstChild("Backpack")
if backpack then
    Hooks.backpackConn = backpack.ChildAdded:Connect(function(child)
        if child.Name == "Module" then
            task.defer(hookGameModule)
        end
    end)
end

local pingOk = false
pcall(installBypassHook)
pcall(function()
    pingOk = setPingBypass(true) and true or false
end)
pcall(hookGameModule)
pcall(installAcUpdateWatch)
pcall(function()
    Hooks.acPingRemotes = findAcPingRemotes()
end)
Hooks.placeVersionAtLoad = game.PlaceVersion

_G.TPSReach = {
    config = Config,
    hooks = Hooks,
    cleanup = function() end,
    notify = notify,
    findAcPingRemotes = findAcPingRemotes,
    setPingBypass = setPingBypass,
}

local function destroyKairoGui()
    if UI.minimizeConn then
        pcall(function()
            UI.minimizeConn:Disconnect()
        end)
        UI.minimizeConn = nil
    end
    if UI.gui and UI.gui.Parent then
        UI.gui:Destroy()
    else
        for _, parent in ipairs({ CoreGui, PlayerGui }) do
            local gui = parent:FindFirstChild("KairoUI")
            if gui then
                gui:Destroy()
            end
        end
    end
    UI.window = nil
    UI.gui = nil
end

local function cleanup()
    Config.acWatchEnabled = false
    Hooks.acTripped = true
    Config.reachEnabled = false
    Config.reactEnabled = false
    Config.kickActive = false
    Config.passActive = false
    Config.actionActive = false

    if Hooks.reachConn then Hooks.reachConn:Disconnect() end
    if Hooks.charConn then Hooks.charConn:Disconnect() end
    if Hooks.backpackConn then Hooks.backpackConn:Disconnect() end
    if Hooks.acSystemChildConn then Hooks.acSystemChildConn:Disconnect() end
    if Hooks.acSystemRemoveConn then Hooks.acSystemRemoveConn:Disconnect() end
    if Hooks.acRsConn then Hooks.acRsConn:Disconnect() end

    if Hooks.oldNamecall then
        pcall(function()
            hookmetamethod(game, "__namecall", Hooks.oldNamecall)
        end)
        Hooks.oldNamecall = nil
    end

    if Hooks.oldTaskWait then
        pcall(function()
            hookfunction(task.wait, Hooks.oldTaskWait)
        end)
        Hooks.oldTaskWait = nil
    end

    setPingBypass(false)

    local backpack = getBackpack()
    if backpack and backpack:FindFirstChild("Module") then
        local ok, mod = pcall(require, backpack.Module)
        if ok and type(mod) == "table" then
            if Hooks.oldKick then mod.Kick = Hooks.oldKick end
            if Hooks.oldKick2 then mod.Kick2 = Hooks.oldKick2 end
            if Hooks.oldPass then mod.Pass = Hooks.oldPass end
            if Hooks.oldTackle then mod.Tackle = Hooks.oldTackle end
            if Hooks.oldSave then mod.Save = Hooks.oldSave end
            if Hooks.oldDive then mod.Dive = Hooks.oldDive end
            if Hooks.oldSpecialKick then mod.SpecialKick = Hooks.oldSpecialKick end
        end
    end

    destroyKairoGui()
    if CoreGui:FindFirstChild("NotifyGui") then
        pcall(function() CoreGui.NotifyGui:Destroy() end)
    end
    if NotifyGui.Parent then NotifyGui:Destroy() end

    _G.TPSReach = nil
end

_G.TPSReach = {
    config = Config,
    cleanup = cleanup,
    notify = notify,
    ui = UI,
    hooks = Hooks,
    findAcPingRemotes = findAcPingRemotes,
    setPingBypass = setPingBypass,
}

local pingNames = {}
for _, r in ipairs(Hooks.acPingRemotes or {}) do
    pingNames[#pingNames + 1] = r.Name
end
local pv = tostring(Hooks.placeVersionAtLoad or game.PlaceVersion)

local remotesOk = pcall(function()
    local re = Workspace.FE.Kick.RemoteEvent
    assert(type(re.FireServer) == "function")
    assert(type(Workspace.FE.System.Kick.FireServer) == "function")
end)

if not remotesOk then
    notify("Remotes rotos · REENTRA al juego y re-ejecuta", Color3.fromRGB(220, 90, 90))
elseif not namecallOk then
    notify("Namecall falló · rejoin + re-ejecuta", Color3.fromRGB(220, 90, 90))
elseif pingOk then
    notify("Bypass OK · AC " .. (pingNames[1] or "ok") .. " · v" .. pv, Color3.fromRGB(70, 180, 110))
else
    notify("Bypass OK · ping AC no hallado · v" .. pv, Color3.fromRGB(220, 140, 60))
end
print("[TPS Assist] hooks listos · cargando UI (Kairo)…")

task.spawn(function()
    local uiOk, uiErr = pcall(function()
        destroyKairoGui()

        local KAIRO_URL = "https://raw.githubusercontent.com/Itzzavi335/Kairo-Ui-Library/refs/heads/main/source.luau"
        local src
        if typeof(game.HttpGet) == "function" then
            src = game:HttpGet(KAIRO_URL)
        elseif typeof(http_request) == "function" or typeof(request) == "function" then
            local req = http_request or request
            local res = req({
                Url = KAIRO_URL,
                Method = "GET",
            })
            src = res and (res.Body or res.body)
        else
            error("no HttpGet/request")
        end
        assert(type(src) == "string" and #src > 100, "Kairo empty")

        local Kairo = loadstring(src)()

        local isMobile = UserInputService.TouchEnabled
            and (not UserInputService.KeyboardEnabled or not UserInputService.MouseEnabled)
        local winSize = isMobile and UDim2.fromOffset(360, 340) or UDim2.fromOffset(520, 420)

        local Window = Kairo:CreateWindow({
            Title = "sec assist",
            Theme = "Crimson",
            Size = winSize,
            Center = true,
            Draggable = true,
            Resize = not isMobile,
            Badges = {},
            MinimizeKey = Enum.KeyCode.RightShift,
            MinimizeButton = isMobile,
            Config = {
                Enabled = true,
                Folder = "TPSAssist_Kairo",
                AutoLoad = true,
            },
        })

        UI.window = Window
        UI.gui = CoreGui:FindFirstChild("KairoUI") or PlayerGui:FindFirstChild("KairoUI")

        if UI.gui and not isMobile then
            local floatBtn = UI.gui:FindFirstChild("MobileMinimizeButton")
            if floatBtn then
                floatBtn:Destroy()
            end
        end

        if UI.minimizeConn then
            pcall(function()
                UI.minimizeConn:Disconnect()
            end)
            UI.minimizeConn = nil
        end
        UI.minimizeConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end
            if input.KeyCode ~= Enum.KeyCode.K then
                return
            end
            if gameProcessed then
                return
            end
            if UserInputService:GetFocusedTextBox() then
                return
            end
            local gui = UI.gui
            if not gui or not gui.Parent then
                return
            end
            local holder = gui:FindFirstChild("DropShadowHolder")
            if holder then
                holder.Visible = not holder.Visible
            end
        end)

        local icon = "rbxassetid://16932740082"
        local AssistTab = Window:CreateTab("Assist", icon)
        local ReactTab = Window:CreateTab("React", icon)


        local function compactEmptyDescriptions(tab)
            if not tab then return end
            for _, child in ipairs(tab:GetChildren()) do
                if child:IsA("Frame") then
                    for _, name in ipairs({ "ToggleContent", "SliderContent", "ButtonContent", "ParagraphContent", "InputContent" }) do
                        local label = child:FindFirstChild(name)
                        if label and label:IsA("TextLabel") and (label.Text == "" or label.Text == " ") then
                            label.Visible = false
                            child.Size = UDim2.new(1, 0, 0, 36)
                            local title = child:FindFirstChild("ToggleTitle")
                                or child:FindFirstChild("SliderTitle")
                                or child:FindFirstChild("ButtonTitle")
                                or child:FindFirstChild("InputTitle")
                            if title then
                                title.Position = UDim2.new(0, 10, 0, 0)
                                title.Size = UDim2.new(1, -100, 1, 0)
                                title.TextYAlignment = Enum.TextYAlignment.Center
                            end
                        end
                    end
                end
            end
        end

        Window:AddToggle(AssistTab, "Reach", "", false, function(on)
            Config.reachEnabled = on
        end, "ReachToggle")

        Window:AddSlider(AssistTab, "Studs", "", 1, REACH_MAX, REACH_MAX, function(value)
            Config.reach = math.floor(value)
        end, "ReachStuds")

        local reactToggle
        local reactV2Toggle
        local syncingReact = false

        local function setToggleOff(toggle)
            if not toggle or type(toggle.Set) ~= "function" then return end
            syncingReact = true
            pcall(function()
                toggle.Set(false)
            end)
            syncingReact = false
        end

        reactToggle = Window:AddToggle(ReactTab, "React", "", false, function(on)
            if syncingReact then
                Config.reactEnabled = on == true
                return
            end
            Config.reactEnabled = on == true
            if on == true then
                Config.reactV2Enabled = false
                setToggleOff(reactV2Toggle)
            end
        end, "ReactV1Toggle")

        reactV2Toggle = Window:AddToggle(ReactTab, "React V2", "", false, function(on)
            if syncingReact then
                Config.reactV2Enabled = on == true
                return
            end
            Config.reactV2Enabled = on == true
            if on == true then
                Config.reactEnabled = false
                setToggleOff(reactToggle)
            end
        end, "ReactV2Toggle")

        compactEmptyDescriptions(AssistTab)
        compactEmptyDescriptions(ReactTab)
    end)

    if uiOk then
        print("[sec assist] UI OK (Kairo)")
    else
        warn("[sec assist] UI failed: ", uiErr)
        notify("UI falló · hooks OK", Color3.fromRGB(220, 140, 60))
    end
end)
