--[[
 KUKIRIN HUB V7.02 | Control System | by Mmss_212 | Correctif vitesse
 Pour KuKirin Life (Roblox) - script local / Xeno (non teste dans ce jeu).
 Modes ECO 55, SPORT 80, RACE 125 + PERSO 0..200 (125 au depart).
 Les vitesses sont des studs/seconde Roblox, PAS des km/h reels.
 Freinage progressif, anti-derapage ON/OFF, wheelies & figures libres en l'air,
 menu flottant reductible et intro de 2,5 secondes. Police Look marque les
 MODELES DE VEHICULES POLICE locaux, jamais les joueurs (portee limitee).
 Les modifications de physique peuvent etre ignorees par le serveur du jeu.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local env = (getgenv and getgenv()) or _G

-- Pas de V5/V6/V7 superposees : evite les boosts simultanes.
if type(env.KuKirinHubCleanup) == "function" then
    pcall(env.KuKirinHubCleanup)
end
for _, key in ipairs({"KL_Boost", "KL_SpeedConn", "KuKirinHubConnection"}) do
    if env[key] then
        pcall(function() env[key]:Disconnect() end)
        env[key] = nil
    end
end
for _, name in ipairs({
    "KuKirinHub", "KuKirinHubV2", "KuKirinHubV3", "KuKirinHubV4",
    "KuKirinHubV5", "KuKirinHubV6", "KuKirinHubV7", "KuKirinHubV7_01", "KuKirinHubV7_02"
}) do
    local old = playerGui:FindFirstChild(name)
    if old then old:Destroy() end
end
for _, name in ipairs({
    "KuKirinHubBlurV5", "KuKirinHubBlurV6", "KuKirinHubBlurV7", "KuKirinHubBlurV7_01", "KuKirinHubBlurV7_02"
}) do
    local old = Lighting:FindFirstChild(name)
    if old then old:Destroy() end
end

local MODE_LIMIT = { ECO = 55, SPORT = 80, RACE = 125 }
local MODE_COLOR = {
    ECO = Color3.fromRGB(54, 200, 139),
    SPORT = Color3.fromRGB(65, 153, 249),
    RACE = Color3.fromRGB(255, 123, 28),
    PERSO = Color3.fromRGB(182, 125, 255)
}
local ORANGE = Color3.fromRGB(255, 123, 28)
local DARK = Color3.fromRGB(16, 19, 27)
local WHITE = Color3.fromRGB(248, 250, 253)
local DIM = Color3.fromRGB(169, 178, 194)
local GREEN = Color3.fromRGB(32, 158, 100)
local GREY = Color3.fromRGB(83, 90, 105)
local RED = Color3.fromRGB(251, 56, 70)

local ACCEL_TIME = 6             -- 0 -> 125 en ~6 s en RACE (sur sol plat)
local FALL_SOFT_LIMIT = 48      -- chute aerienne adoucie (studs/s), pas de gravite globale modifiee
local FALL_SOFT_RESPONSE = 13  -- correction progressive, sans a-coup
local COAST_TIME = 12           -- 125 -> 0 en ~12 s au relachement
local BRAKE_TIME = 2.25       -- frein plus ferme lorsque l'on appuie
local REVERSE_LIMIT = 14       -- marche arriere : 14 studs/s max (pas des km/h)
local INTRO_TIME = 2.5
local GROUND_RAY_LENGTH = 3.6  -- conserve le seuil strict pour les figures
local DRIVE_RAY_LENGTH = 6.4 -- seuil distinct pour les petites bosses en roulant
local DRIVE_GROUND_GRACE = 0.16 -- ne pas couper la vitesse au moindre rebond
local POLICE_MARKER_DISTANCE = 900 -- portee accrue, y compris derriere les montagnes
local POLICE_MARKER_MAX = 48      -- limite pour ne pas saturer les Highlights
local PERSONAL_MAX_SPEED = 200

local mode = "RACE"
local personalLimit = 125
local enabled, gripEnabled, policeLook = true, true, false
local running = true
local connections, activeTweens, policeMarkers = {}, {}, {}
local currentSeat, speedState, lastHeading = nil, nil, nil
local groundContact, previousGround = false, false
local lastDriveContactAt, lastDriveRayAt = -math.huge, -math.huge
local lastDriveRayHit = false
local lastGroundCheck, lastUiRefresh = 0, 0
local introToken, opening = 0, false
local impactBlockUntil, lastCrashAt = 0, 0
local previousVelocity, pendingTrick = nil, nil
local activeTrick = nil
-- Conduite basee sur AssemblyLinearVelocity comme dans le script de reference.
-- Evite de changer VehicleSeat.MaxSpeed : selon le vehicule, cette propriete
-- est re-ecrite par son controleur et peut contredire la vitesse demandee.
local speedLimitedSince = 0
local speedLimitWarning = false
local afterPhysicsAssist = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function speedLimit()
    return mode == "PERSO" and personalLimit or MODE_LIMIT[mode]
end

local function connect(sig, fn)
    local c = sig:Connect(fn)
    table.insert(connections, c)
    return c
end
local function makeCorner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = obj
    return c
end
local function stroke(obj, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 1
    s.Parent = obj
    return s
end
local function text(parent, string, x, y, w, h, size, color, center)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Position = UDim2.fromOffset(x, y)
    t.Size = UDim2.fromOffset(w, h)
    t.Text = string
    t.TextColor3 = color or WHITE
    t.TextSize = size or 14
    t.Font = Enum.Font.GothamBold
    t.TextXAlignment = center and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
    t.TextYAlignment = Enum.TextYAlignment.Center
    t.Parent = parent
    return t
end
local function button(parent, string, x, y, w, h, color)
    local b = Instance.new("TextButton")
    b.Position = UDim2.fromOffset(x, y)
    b.Size = UDim2.fromOffset(w, h)
    b.BackgroundColor3 = color or GREY
    b.Text = string
    b.TextColor3 = WHITE
    b.TextSize = 13
    b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = true
    b.Parent = parent
    makeCorner(b, 9)
    return b
end
local function tween(obj, duration, goals, ease)
    local t = TweenService:Create(obj,
        TweenInfo.new(duration, ease or Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out), goals)
    table.insert(activeTweens, t)
    t:Play()
    return t
end
local function cancelTweens()
    for _, t in ipairs(activeTweens) do
        pcall(function() t:Cancel() end)
    end
    table.clear(activeTweens)
end
local function flat(v)
    return Vector3.new(v.X, 0, v.Z)
end

-- GUI -------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "KuKirinHubV7_02"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 225
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local blur = Instance.new("BlurEffect")
blur.Name = "KuKirinHubBlurV7_02"
blur.Size = 0
blur.Parent = Lighting

local launch = button(gui, "KuKirin", 0, 0, 76, 63, DARK)
launch.Name = "OpenKuKirinHub"
-- Fixe au milieu du bord droit, accessible a la souris et au toucher.
launch.AnchorPoint = Vector2.new(1, 0.5)
launch.Position = UDim2.new(1, -12, 0.5, 0)
launch.Active = true
launch.TextColor3 = ORANGE
launch.TextSize = 15
launch.ZIndex = 80
stroke(launch, ORANGE, 2)

local veil = Instance.new("Frame")
veil.Size = UDim2.fromScale(1, 1)
veil.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
veil.BackgroundTransparency = 1
veil.ZIndex = 20
veil.Visible = false
veil.Parent = gui

local intro = Instance.new("CanvasGroup")
intro.Name = "LogoAnimation"
intro.AnchorPoint = Vector2.new(0.5, 0.5)
intro.Position = UDim2.fromScale(0.5, 0.5)
intro.Size = UDim2.fromOffset(350, 261)
intro.BackgroundTransparency = 1
intro.GroupTransparency = 1
intro.ZIndex = 30
intro.Visible = false
intro.Parent = gui
local introScale = Instance.new("UIScale")
introScale.Scale = 0.65
introScale.Parent = intro
local wordFallback = text(intro, "KuKirin", 18, 5, 314, 112, 45, ORANGE, true)
wordFallback.Font = Enum.Font.GothamBlack
local introLogo = Instance.new("ImageLabel")
introLogo.Position = UDim2.fromOffset(118, 10)
introLogo.Size = UDim2.fromOffset(114, 112)
introLogo.BackgroundTransparency = 1
introLogo.ScaleType = Enum.ScaleType.Fit
introLogo.Visible = false
introLogo.Parent = intro
local introTitle = text(intro, "KUKIRIN HUB", 0, 120, 350, 47, 29, WHITE, true)
introTitle.Font = Enum.Font.GothamBlack
text(intro, "V7.02  •  CONTROL SYSTEM", 0, 168, 350, 22, 13, ORANGE, true)

local credit = Instance.new("Frame")
credit.BackgroundTransparency = 1
credit.Position = UDim2.fromOffset(102, 199)
credit.Size = UDim2.fromOffset(180, 31)
credit.Parent = intro
local creditAvatar = Instance.new("ImageLabel")
creditAvatar.Size = UDim2.fromOffset(24, 24)
creditAvatar.Position = UDim2.fromOffset(0, 3)
creditAvatar.BackgroundColor3 = Color3.fromRGB(66, 68, 81)
creditAvatar.Image = ""
creditAvatar.Parent = credit
makeCorner(creditAvatar, 12)
local avatarFallback = text(creditAvatar, "M", 0, 0, 24, 24, 13, ORANGE, true)
text(credit, "by Mmss_212", 32, 0, 146, 31, 14, WHITE)

-- Image fournie par l'utilisateur, integree dans le script.
-- Aucune recherche de skin / avatar Roblox : c'est la vraie image envoyee.
local AVATAR_BASE64 = [[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]]
local function decodeBase64(input)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local lookup = {}
    for i = 1, #alphabet do
        lookup[alphabet:sub(i, i)] = i - 1
    end
    input = input:gsub("%s", "")
    local output = {}
    for i = 1, #input, 4 do
        local a = lookup[input:sub(i, i)]
        local b = lookup[input:sub(i + 1, i + 1)]
        local c = lookup[input:sub(i + 2, i + 2)]
        local d = lookup[input:sub(i + 3, i + 3)]
        if a and b then
            local n = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
            output[#output + 1] = string.char(math.floor(n / 65536) % 256)
            if c then output[#output + 1] = string.char(math.floor(n / 256) % 256) end
            if d then output[#output + 1] = string.char(n % 256) end
        end
    end
    return table.concat(output)
end
task.spawn(function()
    local success, asset = pcall(function()
        local getAsset = getcustomasset or getsynasset
        if type(writefile) ~= "function" or type(getAsset) ~= "function" then
            return nil
        end
        writefile("kukirin_v702_avatar.jpg", decodeBase64(AVATAR_BASE64))
        return getAsset("kukirin_v702_avatar.jpg")
    end)
    if running and success and type(asset) == "string" and creditAvatar.Parent then
        creditAvatar.Image = asset
        avatarFallback.Visible = false
    end
end)

-- Panel flottant : aucun flou permanent hors animation.
local panel = Instance.new("CanvasGroup")
panel.Name = "FloatingSettings"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(358, 449)
panel.BackgroundColor3 = DARK
panel.BackgroundTransparency = 0.045
panel.GroupTransparency = 1
panel.ZIndex = 40
panel.Visible = false
panel.Active = true
panel.Parent = gui
makeCorner(panel, 15)
stroke(panel, ORANGE, 1.7)
local panelScale = Instance.new("UIScale")
panelScale.Scale = 0.86
panelScale.Parent = panel

local header = Instance.new("Frame")
header.Position = UDim2.fromOffset(0, 0)
header.Size = UDim2.new(1, -91, 0, 43)
header.BackgroundTransparency = 1
header.Active = true
header.Parent = panel
local headerTitle = text(header, "KUKIRIN HUB V7.02", 15, 5, 248, 34, 19, ORANGE)
headerTitle.Font = Enum.Font.GothamBlack
local collapse = button(panel, "-", 279, 10, 30, 30, Color3.fromRGB(65, 67, 78))
collapse.Name = "MinimizeRestore"
local close = button(panel, "X", 316, 10, 30, 30, Color3.fromRGB(65, 67, 78))

text(panel, "MODE DE CONDUITE", 15, 48, 327, 17, 11, DIM)
local modes = {}
for i, name in ipairs({"ECO", "SPORT", "RACE", "PERSO"}) do
    modes[name] = button(panel, name, 14 + (i - 1) * 86, 69, 81, 34,
        Color3.fromRGB(49, 54, 68))
end

text(panel, "VITESSE PERSONNALISEE", 15, 112, 244, 23, 12, DIM)
local customText = text(panel, "125 / 200", 258, 111, 85, 24, 14, ORANGE)
customText.TextXAlignment = Enum.TextXAlignment.Right

local sliderTrack = Instance.new("Frame")
sliderTrack.Name = "SpeedSlider_0_200"
sliderTrack.Position = UDim2.fromOffset(23, 150)
sliderTrack.Size = UDim2.fromOffset(313, 8)
sliderTrack.BackgroundColor3 = Color3.fromRGB(55, 61, 78)
sliderTrack.Active = true
sliderTrack.Parent = panel
makeCorner(sliderTrack, 5)
local sliderFill = Instance.new("Frame")
sliderFill.Size = UDim2.fromScale(125 / PERSONAL_MAX_SPEED, 1)
sliderFill.BackgroundColor3 = ORANGE
sliderFill.Parent = sliderTrack
makeCorner(sliderFill, 5)
local sliderKnob = Instance.new("TextButton")
sliderKnob.Name = "DragSpeed"
sliderKnob.Size = UDim2.fromOffset(23, 23)
sliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
sliderKnob.Position = UDim2.fromScale(125 / PERSONAL_MAX_SPEED, 0.5)
sliderKnob.BackgroundColor3 = WHITE
sliderKnob.Text = ""
sliderKnob.ZIndex = 42
sliderKnob.AutoButtonColor = false
sliderKnob.Parent = sliderTrack
makeCorner(sliderKnob, 12)
stroke(sliderKnob, ORANGE, 2)

text(panel, "VITESSE (UNITES ROBLOX)", 15, 178, 280, 20, 11, DIM)
local speedText = text(panel, "0 / 125", 16, 199, 222, 39, 27, ORANGE)
local unitText = text(panel, "studs/s", 243, 205, 99, 29, 12, DIM)
unitText.TextXAlignment = Enum.TextXAlignment.Right
local meter = Instance.new("Frame")
meter.Position = UDim2.fromOffset(16, 243)
meter.Size = UDim2.fromOffset(326, 7)
meter.BackgroundColor3 = Color3.fromRGB(55, 60, 73)
meter.Parent = panel
makeCorner(meter, 5)
local meterFill = Instance.new("Frame")
meterFill.Size = UDim2.fromScale(0, 1)
meterFill.BackgroundColor3 = ORANGE
meterFill.Parent = meter
makeCorner(meterFill, 5)

local gripButton = button(panel, "ANTI-DERAPAGE : ON", 16, 267, 326, 36,
    Color3.fromRGB(39, 113, 180))
local boostButton = button(panel, "BOOST : ON", 16, 310, 326, 36, GREEN)
local policeButton = button(panel, "POLICE LOOK : OFF", 16, 353, 326, 36, GREY)
local status = text(panel, "Pret - choisis un mode", 16, 392, 325, 17, 11, DIM)
status.Font = Enum.Font.GothamMedium
local advice = text(panel,
    "Tip: Over 140 km/h, enable anti-skid.",
    12, 414, 334, 27, 13, Color3.fromRGB(237, 197, 126), true)
advice.Font = Enum.Font.GothamMedium
advice.TextWrapped = true
-- Simple conseil affiche, SANS activation automatique.

-- Chargement optionnel du logo officiel ; fallback texte si Xeno ne le permet pas.
task.spawn(function()
    local success, asset = pcall(function()
        local getAsset = getcustomasset or getsynasset
        if type(writefile) ~= "function" or type(getAsset) ~= "function" then
            return nil
        end
        local url = "https://cdn.shopify.com/s/files/1/0721/5743/0039/files/LOGO1_d67ee12b-a043-49c2-b46e-ae67196b922f.png?v=1687489869&width=1308"
        local bytes = game:HttpGet(url)
        if type(bytes) ~= "string" or bytes:sub(2, 4) ~= "PNG" then
            return nil
        end
        writefile("kukirin_hub_v702_logo.png", bytes)
        return getAsset("kukirin_hub_v702_logo.png")
    end)
    if not (running and success and asset and gui.Parent) then return end
    local small = Instance.new("ImageLabel")
    small.BackgroundTransparency = 1
    small.Position = UDim2.fromOffset(5, 5)
    small.Size = UDim2.new(1, -10, 1, -10)
    small.ScaleType = Enum.ScaleType.Fit
    small.Image = asset
    small.ZIndex = 81
    small.Parent = launch
    launch.Text = ""
    introLogo.Image = asset
    introLogo.Visible = true
    wordFallback.Visible = false
end)

local function redrawModes()
    for name, b in pairs(modes) do
        b.BackgroundColor3 = name == mode and MODE_COLOR[name]
            or Color3.fromRGB(49, 54, 68)
    end
    local c = MODE_COLOR[mode]
    speedText.TextColor3 = c
    meterFill.BackgroundColor3 = c
    sliderFill.BackgroundColor3 = mode == "PERSO" and c or ORANGE
end
local function redrawSlider()
    local alpha = personalLimit / PERSONAL_MAX_SPEED
    sliderFill.Size = UDim2.fromScale(alpha, 1)
    sliderKnob.Position = UDim2.fromScale(alpha, 0.5)
    customText.Text = tostring(personalLimit) .. " / " .. PERSONAL_MAX_SPEED
end
redrawModes()
redrawSlider()
for name, b in pairs(modes) do
    connect(b.MouseButton1Click, function()
        mode = name
        redrawModes()
    end)
end

-- Curseur tactile et souris : le glisser passe directement en mode PERSO.
local sliding = false
local slidingType = nil
local function setSliderAt(screenX)
    local width = sliderTrack.AbsoluteSize.X
    if width <= 0 then return end
    local alpha = math.clamp(
        (screenX - sliderTrack.AbsolutePosition.X) / width, 0, 1)
    personalLimit = math.clamp(math.floor(alpha * PERSONAL_MAX_SPEED + 0.5), 0, PERSONAL_MAX_SPEED)
    mode = "PERSO"
    redrawSlider()
    redrawModes()
end
local function startSlide(input)
    if input.UserInputType ~= Enum.UserInputType.Touch
        and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
        return
    end
    sliding = true
    slidingType = input.UserInputType
    setSliderAt(input.Position.X)
end
connect(sliderTrack.InputBegan, startSlide)
connect(sliderKnob.InputBegan, startSlide)
connect(UIS.InputChanged, function(input)
    if not sliding then return end
    if slidingType == Enum.UserInputType.Touch then
        if input.UserInputType == Enum.UserInputType.Touch then
            setSliderAt(input.Position.X)
        end
    elseif input.UserInputType == Enum.UserInputType.MouseMovement then
        setSliderAt(input.Position.X)
    end
end)
connect(UIS.InputEnded, function(input)
    if sliding and input.UserInputType == slidingType then
        sliding = false
        slidingType = nil
    end
end)

connect(gripButton.MouseButton1Click, function()
    gripEnabled = not gripEnabled
    gripButton.Text = gripEnabled and "ANTI-DERAPAGE : ON"
        or "ANTI-DERAPAGE : OFF (GRIP LEGER)"
    gripButton.BackgroundColor3 = gripEnabled
        and Color3.fromRGB(39, 113, 180) or GREY
end)
connect(boostButton.MouseButton1Click, function()
    enabled = not enabled
    speedState = nil
    speedLimitedSince, speedLimitWarning = 0, false
    afterPhysicsAssist = nil
    boostButton.Text = enabled and "BOOST : ON" or "BOOST : OFF"
    boostButton.BackgroundColor3 = enabled and GREEN or GREY
end)

-- POLICE LOOK V7.02 : silhouettes rouges, aucun texte ou symbole.
-- Toujours mis a jour, meme quand le joueur conduit une trottinette.
-- AlwaysOnTop traverse les obstacles seulement pour les modeles charges
-- sur ce client (Roblox StreamingEnabled peut cacher les modeles lointains).
local function isPoliceName(name)
    local n = string.lower(tostring(name or ""))
    for _, word in ipairs({"police", "sheriff", "gendarme", "gendarmerie",
        "officer", "policier", "patrol", "copcar", "cop car", "law enforcement"}) do
        if n:find(word, 1, true) then return true end
    end
    return false
end

local function getPolicePerson(model)
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    local person = Players:GetPlayerFromCharacter(model)
    if person then
        if person == player or not person.Team
           or not isPoliceName(person.Team.Name) then return nil end
    elseif not isPoliceName(model.Name)
        and not (model.Parent and isPoliceName(model.Parent.Name)) then
        return nil
    end
    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChildWhichIsA("BasePart", true)
end

local function getPoliceVehicle(model)
    if model:FindFirstChildOfClass("Humanoid") then return nil end
    local nameOk = isPoliceName(model.Name)
        or (model.Parent and isPoliceName(model.Parent.Name))
    local vehicleSeat = model:FindFirstChildWhichIsA("VehicleSeat", true)
    -- Ignore tout de suite les gros modeles decoratifs sans signature police
    -- ni systeme de conduite : reduit fortement les scans inutiles.
    if not nameOk and not vehicleSeat then return nil end
    local ordinarySeat = model:FindFirstChildWhichIsA("Seat", true)
    local wheel, chassis, fallback
    -- Identifie aussi les modeles aux noms neutres qui portent des pieces
    -- ou inscriptions "Police", sans confondre avec les autres voitures.
    for _, child in ipairs(model:GetDescendants()) do
        if child:IsA("BasePart") then
            fallback = fallback or child
            local n = child.Name:lower()
            if n:find("wheel", 1, true) or n:find("roue", 1, true)
                or n:find("tire", 1, true) then
                wheel = wheel or child
            elseif n:find("chassis", 1, true) or n:find("body", 1, true) then
                chassis = chassis or child
            end
            if isPoliceName(child.Name) then nameOk = true end
        elseif child:IsA("Decal") or child:IsA("Texture") then
            if isPoliceName(child.Name) then nameOk = true end
        elseif child:IsA("TextLabel") then
            if isPoliceName(child.Text) then nameOk = true end
        end
    end
    if not nameOk or not (vehicleSeat or ordinarySeat or (wheel and chassis)) then
        return nil
    end
    return model.PrimaryPart or chassis or vehicleSeat or ordinarySeat
        or wheel or fallback
end

local function policeCandidate(model)
    if not model:IsA("Model") or model == player.Character then return nil end
    local a = model.Parent
    while a and a ~= Workspace do
        if policeMarkers[a] then return nil end
        if a:IsA("Model") and a:FindFirstChildOfClass("Humanoid") then
            return nil
        end
        a = a.Parent
    end
    return getPolicePerson(model) or getPoliceVehicle(model)
end

local function viewerPosition()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root and root:IsDescendantOf(Workspace) then return root.Position end
    local camera = Workspace.CurrentCamera
    return camera and camera.CFrame.Position or nil
end

local function removePoliceMarker(model)
    local entry = policeMarkers[model]
    if not entry then return end
    pcall(function() entry.highlight:Destroy() end)
    policeMarkers[model] = nil
end

local function createPoliceOutline(model, part)
    if not running or not policeLook or policeMarkers[model] then return false end
    local here = viewerPosition()
    if not here or not part or not part:IsDescendantOf(model)
       or (part.Position - here).Magnitude > POLICE_MARKER_DISTANCE then
        return false
    end
    local h = Instance.new("Highlight")
    h.Name = "KuKirinPoliceOutlineOnly"
    h.Adornee = model
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.OutlineColor = RED
    h.OutlineTransparency = 0
    h.FillTransparency = 1
    h.Enabled = true
    h.Parent = Workspace
    policeMarkers[model] = {highlight = h, part = part}
    return true
end
local function clearPoliceMarkers()
    for model in pairs(policeMarkers) do removePoliceMarker(model) end
end

local function refreshPoliceRange()
    if not running or not policeLook then return end
    local here = viewerPosition()
    for model, entry in pairs(policeMarkers) do
        local part = entry.part
        if not model:IsDescendantOf(Workspace) or not part
            or not part:IsDescendantOf(model) then
            removePoliceMarker(model)
        else
            local dist = here and (part.Position - here).Magnitude or math.huge
            -- Cachage instantane sans destruction/recreation du contour.
            entry.highlight.Enabled = dist <= POLICE_MARKER_DISTANCE
            if dist > POLICE_MARKER_DISTANCE + 100 then
                removePoliceMarker(model)
            end
        end
    end
end

local scanning = false
local function scanPolice()
    if scanning or not running or not policeLook then return end
    scanning = true
    local here = viewerPosition()
    if not here then scanning = false; return end

    -- Reprioriser chaque scan : les policiers les PLUS PROCHES sont marques
    -- avant les autres, pas les premiers modeles dans la hierarchie Roblox.
    local candidates = {}
    local nodes = Workspace:GetDescendants()
    for i, obj in ipairs(nodes) do
        if not running or not policeLook then break end
        if obj:IsA("Model") then
            local part = policeCandidate(obj)
            if part and part:IsDescendantOf(obj) then
                local dist = (part.Position - here).Magnitude
                if dist <= POLICE_MARKER_DISTANCE then
                    candidates[#candidates + 1] = {
                        model = obj, part = part, distance = dist
                    }
                end
            end
        end
        if i % 450 == 0 then task.wait() end
    end
    if running and policeLook then
        table.sort(candidates, function(a, b)
            return a.distance < b.distance
        end)
        local retained = {}
        local count = 0
        for _, entry in ipairs(candidates) do
            if count >= POLICE_MARKER_MAX then break end
            local model = entry.model
            local insideMarkedParent = false
            local p = model.Parent
            while p and p ~= Workspace do
                if retained[p] or policeMarkers[p] then
                    insideMarkedParent = true
                    break
                end
                p = p.Parent
            end
            if not insideMarkedParent then
                retained[model] = true
                count = count + 1
                if not policeMarkers[model] then
                    createPoliceOutline(model, entry.part)
                end
            end
        end
        for model in pairs(policeMarkers) do
            if not retained[model] then removePoliceMarker(model) end
        end
        refreshPoliceRange()
    end
    scanning = false
end

connect(policeButton.MouseButton1Click, function()
    policeLook = not policeLook
    policeButton.Text = policeLook and "POLICE LOOK : ON" or "POLICE LOOK : OFF"
    policeButton.BackgroundColor3 = policeLook and RED or GREY
    if policeLook then
        task.spawn(scanPolice)
    else
        clearPoliceMarkers()
    end
end)

-- Les modeles du monde peuvent se charger progressivement ; rescanner
-- sans obligation de descendre / remonter sur la trottinette.
local scanQueued = false
connect(Workspace.DescendantAdded, function(obj)
    if not running or not policeLook or scanQueued then return end
    if obj:IsA("Model")
       or (obj:IsA("BasePart") and isPoliceName(obj.Name))
       or obj:IsA("VehicleSeat") then
        scanQueued = true
        task.delay(0.25, function()
            scanQueued = false
            if running and policeLook then task.spawn(scanPolice) end
        end)
    end
end)
task.spawn(function()
    while running do
        task.wait(1.0)
        if policeLook then scanPolice() end
    end
end)
task.spawn(function()
    while running do
        task.wait(0.14)
        if policeLook then refreshPoliceRange() end
    end
end)

-- Bouton KuKirin volontairement fixe : pas d'evenement de glissement.
-- La fenetre des parametres reste, elle, deplacable.

-- Fenetre deplacable a la souris et au toucher, sans bouger le curseur.
local moving = false
local moveType, moveStart, panelStart = nil, nil, nil
connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        moving = true
        moveType = input.UserInputType
        moveStart = input.Position
        panelStart = panel.Position
    end
end)
connect(UIS.InputChanged, function(input)
    if not moving then return end
    if moveType == Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    if moveType == Enum.UserInputType.Touch
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local delta = input.Position - moveStart
    panel.Position = UDim2.new(
        panelStart.X.Scale, panelStart.X.Offset + delta.X,
        panelStart.Y.Scale, panelStart.Y.Offset + delta.Y)
end)
connect(UIS.InputEnded, function(input)
    if moving and input.UserInputType == moveType then moving = false end
end)

-- BARRE REDUITE : conserver titre, reduction et fermeture accessibles.
local minimized = false
local minimizeToken = 0
local function showSettings(show)
    for _, child in ipairs(panel:GetChildren()) do
        if child:IsA("GuiObject") and child ~= header
            and child ~= close and child ~= collapse then
            child.Visible = show
        end
    end
end
connect(collapse.MouseButton1Click, function()
    minimized = not minimized
    minimizeToken = minimizeToken + 1
    local token = minimizeToken
    if minimized then
        sliding = false
        moving = false
        showSettings(false)
        collapse.Text = "+"
        tween(panel, 0.22, {Size = UDim2.fromOffset(358, 48)})
    else
        collapse.Text = "-"
        tween(panel, 0.24, {Size = UDim2.fromOffset(358, 449)})
        task.delay(0.23, function()
            if running and token == minimizeToken and not minimized then
                showSettings(true)
            end
        end)
    end
end)

-- OUVERTURE : 2,5 s logo -> disparition -> fenetre flottante.
local function closeMenu()
    -- Conserver la position choisie par glisser-deposer, meme apres fermeture.
    introToken = introToken + 1
    opening = false
    cancelTweens()
    tween(panel, 0.18, {GroupTransparency = 1})
    tween(panelScale, 0.18, {Scale = 0.94})
    local token = introToken
    task.delay(0.19, function()
        if running and token == introToken then panel.Visible = false end
    end)
end
local function openMenu()
    if opening then return end
    if panel.Visible then closeMenu(); return end
    opening = true
    introToken = introToken + 1
    local token = introToken
    cancelTweens()
    launch.Visible = false
    veil.Visible = true
    intro.Visible = true
    veil.BackgroundTransparency = 1
    intro.GroupTransparency = 1
    introScale.Scale = 0.66
    blur.Size = 0
    tween(veil, 0.43, {BackgroundTransparency = 0.32})
    tween(blur, 0.5, {Size = 15})
    tween(intro, 0.43, {GroupTransparency = 0})
    tween(introScale, 0.66, {Scale = 1}, Enum.EasingStyle.Back)
    task.delay(INTRO_TIME - 0.45, function()
        if not running or token ~= introToken then return end
        tween(intro, 0.40, {GroupTransparency = 1})
        tween(introScale, 0.4, {Scale = 1.09})
        tween(veil, 0.4, {BackgroundTransparency = 1})
        tween(blur, 0.4, {Size = 0})
    end)
    task.delay(INTRO_TIME, function()
        if not running or token ~= introToken then return end
        intro.Visible = false
        veil.Visible = false
        launch.Visible = true
        -- Bouton fixe a droite, aucun repositionnement au clic.
        minimized = false
        minimizeToken = minimizeToken + 1
        collapse.Text = "-"
        panel.Size = UDim2.fromOffset(358, 449)
        showSettings(true)
        panel.Visible = true
        panel.GroupTransparency = 1
        panelScale.Scale = 0.86
        tween(panel, 0.26, {GroupTransparency = 0})
        tween(panelScale, 0.31, {Scale = 1}, Enum.EasingStyle.Back)
        opening = false
    end)
end
-- Activated gere souris, tactile et manette, sans filtrage intempestif.
connect(launch.Activated, openMenu)
connect(close.MouseButton1Click, closeMenu)

-- VEHICULE & PHYSIQUE --------------------------------------------------
local function vehicleModel(seat)
    local model = seat:FindFirstAncestorOfClass("Model")
    while model and model.Parent and model.Parent:IsA("Model")
        and model.Parent ~= player.Character do
        model = model.Parent
    end
    return model
end
local function setupGroundRay(seat, char)
    local filter = {char}
    local model = vehicleModel(seat)
    table.insert(filter, model or seat)
    rayParams.FilterDescendantsInstances = filter
end
local function isGrounded(seat, now)
    if now - lastGroundCheck < 0.068 then return groundContact end
    lastGroundCheck = now
    local start = seat.Position + Vector3.new(0, 0.65, 0)
    local f = flat(seat.CFrame.LookVector)
    f = f.Magnitude > 0.01 and f.Unit or Vector3.zero
    groundContact = false
    -- Centre, roue avant, roue arriere : une roue levee != vol.
    for _, offset in ipairs({Vector3.zero, f * 2, -f * 2}) do
        local ray = Workspace:Raycast(start + offset,
            Vector3.new(0, -GROUND_RAY_LENGTH, 0), rayParams)
        if ray and ray.Normal.Y > 0.35 then
            groundContact = true
            break
        end
    end
    return groundContact
end

-- La detection stricte du sol sert aux figures. Pour la vitesse, une seconde
-- sonde un peu plus longue evite qu'une roue levee ou une bosse fasse retomber
-- la consigne a la vitesse native du jeu. La marge est tres courte et ne
-- s'applique pas aux vrais sauts / fortes chutes.
local function driveHasSupport(seat, now, verticalSpeed, strictGrounded)
    if strictGrounded then
        lastDriveContactAt = now
        return true
    end
    if verticalSpeed > 7 or verticalSpeed < -13 then return false end
    if now - lastDriveRayAt >= 0.09 then
        lastDriveRayAt = now
        lastDriveRayHit = false
        local forward = flat(seat.CFrame.LookVector)
        forward = forward.Magnitude > 0.05 and forward.Unit or Vector3.zero
        local origin = seat.Position + Vector3.new(0, 0.65, 0)
        for _, offset in ipairs({Vector3.zero, forward * 2, -forward * 2}) do
            local hit = Workspace:Raycast(origin + offset,
                Vector3.new(0, -DRIVE_RAY_LENGTH, 0), rayParams)
            if hit and hit.Normal.Y > 0.35 then
                lastDriveRayHit = true
                break
            end
        end
    end
    if lastDriveRayHit then
        lastDriveContactAt = now
        return true
    end
    return now - lastDriveContactAt < DRIVE_GROUND_GRACE
end

-- Les figures restent accessibles par T/Y/U/B/N mais n'occupent plus le panneau.
-- Un backflip applique une rotation EN L'AIR seulement, sans auto-redressement.
local TRICKS = {
    [Enum.KeyCode.T] = {yaw = true, deg = 180, duration = 0.9},
    [Enum.KeyCode.Y] = {yaw = true, deg = 360, duration = 1.3},
    [Enum.KeyCode.U] = {yaw = true, deg = 720, duration = 2.0},
    [Enum.KeyCode.B] = {yaw = false, deg = -360, duration = 1.4},
    [Enum.KeyCode.N] = {yaw = false, deg = 360, duration = 1.4}
}
local inAir = false
connect(UIS.InputBegan, function(input, processed)
    if processed or UIS:GetFocusedTextBox() then return end
    local cfg = TRICKS[input.KeyCode]
    if not cfg or not enabled or not currentSeat or activeTrick then return end
    -- Pression un peu avant de quitter le sol : figure lancee au decollage.
    pendingTrick = {cfg = cfg, expires = os.clock() + 1.15}
end)
local function beginTrick(cfg)
    activeTrick = {
        yaw = cfg.yaw,
        direction = cfg.deg >= 0 and 1 or -1,
        total = math.rad(math.abs(cfg.deg)),
        duration = cfg.duration,
        elapsed = 0,
        rotated = 0
    }
end
local function updateTrick(root, seat, dt)
    if not activeTrick then return end
    local t = activeTrick
    t.elapsed = t.elapsed + dt
    -- Orientation verticale uniquement pour les 180/360, axe local pour flips.
    local axis = t.yaw and Vector3.yAxis or seat.CFrame.RightVector
    axis = axis * t.direction
    local angular = root.AssemblyAngularVelocity
    t.rotated = t.rotated + math.max(0, angular:Dot(axis)) * dt
    local remaining = t.total - t.rotated
    if remaining < 0.08 or t.elapsed > t.duration + 0.7 then
        -- Retire seulement la rotation qui avait ete ajoutee, sans snap.
        local component = math.max(0, angular:Dot(axis))
        root.AssemblyAngularVelocity = angular - axis * component * 0.65
        activeTrick = nil
        return
    end
    local baseRate = t.total / t.duration
    local targetRate = math.min(9.2, baseRate)
    if remaining < 1.3 then
        targetRate = math.min(targetRate, math.max(0.6, remaining / 0.24))
    end
    local current = angular:Dot(axis)
    local smooth = 1 - math.exp(-12 * dt)
    local nextRate = current + (targetRate - current) * smooth
    root.AssemblyAngularVelocity = angular + axis * (nextRate - current)
end

connect(RunService.PreSimulation, function(rawDt)
    if not running then return end
    afterPhysicsAssist = nil
    local dt = math.clamp(rawDt, 0, 0.05)
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart
    if seat ~= currentSeat then
        afterPhysicsAssist = nil
        speedLimitedSince, speedLimitWarning = 0, false
        currentSeat, speedState, lastHeading, activeTrick = seat, nil, nil, nil
        previousVelocity, pendingTrick, impactBlockUntil = nil, nil, 0
        groundContact, previousGround, inAir = false, false, false
        lastDriveContactAt, lastDriveRayAt, lastDriveRayHit = -math.huge, -math.huge, false
        lastGroundCheck = 0
        if seat then setupGroundRay(seat, char) end
    end
    local now = os.clock()
    if not seat then
        if now - lastUiRefresh > 0.15 then
            local limit = speedLimit()
            speedText.Text = "0 / " .. limit
            meterFill.Size = UDim2.fromScale(0, 1)
            status.Text = "Monte sur une trottinette compatible"
            lastUiRefresh = now
        end
        return
    end

    local root = seat.AssemblyRootPart or seat
    if root.Anchored or root:IsDescendantOf(char) then
        if now - lastUiRefresh > 0.15 then
            status.Text = "Vehicule incompatible"
            lastUiRefresh = now
        end
        return
    end

    local velocity = root.AssemblyLinearVelocity
    local horizontal = flat(velocity)
    local actual = horizontal.Magnitude
    local limit = speedLimit()

    -- Collision frontale reelle : ne plus confondre un freinage ou un
    -- virage pres d'un mur avec un choc. Les gros impacts restent possibles.
    local brakingOrSteering = UIS:IsKeyDown(Enum.KeyCode.Space)
        or UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.Down)
        or UIS:IsKeyDown(Enum.KeyCode.A) or UIS:IsKeyDown(Enum.KeyCode.D)
        or UIS:IsKeyDown(Enum.KeyCode.Left) or UIS:IsKeyDown(Enum.KeyCode.Right)
    if seat:IsA("VehicleSeat") then
        brakingOrSteering = brakingOrSteering
            or seat.ThrottleFloat < -0.1 or math.abs(seat.SteerFloat) > 0.16
    end
    if enabled and not activeTrick and not brakingOrSteering
        and now >= impactBlockUntil and now - lastCrashAt > 1.7
        and previousVelocity and previousVelocity.Magnitude > 115
        and actual < previousVelocity.Magnitude * 0.14 then
        local direction = previousVelocity.Unit
        local probe = Workspace:Raycast(seat.Position,
            direction * 5 + Vector3.new(0, 0.2, 0), rayParams)
        if probe and probe.Normal.Y < 0.50 and probe.Distance < 4.5 then
            speedState = 0
            activeTrick, pendingTrick = nil, nil
            lastCrashAt = now
            impactBlockUntil = now + 0.9
            root.AssemblyAngularVelocity = root.AssemblyAngularVelocity * 0.28
            -- Le serveur du jeu peut refuser / inverser cette action.
            hum.Sit = false
            hum.Jump = true
            status.Text = "Impact detecte - boost suspendu"
        end
    end
    previousVelocity = horizontal
    if now < impactBlockUntil then return end

    local grounded = isGrounded(seat, now)
    local driveSupported = driveHasSupport(seat, now, velocity.Y, grounded)
    local landed = grounded and not previousGround
    previousGround, inAir = grounded, not grounded

    if now - lastUiRefresh > 0.13 then
        speedText.Text = string.format("%d / %d",
            math.floor(actual + 0.5), limit)
        meterFill.Size = UDim2.fromScale(
            limit > 0 and math.clamp(actual / limit, 0, 1) or 0, 1)
        lastUiRefresh = now
    end
    if not enabled then
        activeTrick, pendingTrick = nil, nil
        speedState = nil
        return
    end
    if pendingTrick and now > pendingTrick.expires then
        pendingTrick = nil
    end
    -- Ne pas confondre la portee du rayon avec la realite du saut :
    -- une impulsion verticale confirme le decollage meme si le raycast
    -- touche encore une pente ou le bord d'une plateforme.
    local airborneForTricks = not grounded or velocity.Y > 7
    if pendingTrick and not activeTrick and airborneForTricks then
        beginTrick(pendingTrick.cfg)
        pendingTrick = nil
    end
    -- Correction douce uniquement de la vitesse VERTICALE en descente.
    -- Ne touche pas a la vitesse horizontale, aux sauts montants ni au pitch.
    -- Efficace aussi pendant une figure, sans reduire sa rotation.
    if not grounded and velocity.Y < -FALL_SOFT_LIMIT then
        local blend = 1 - math.exp(-FALL_SOFT_RESPONSE * dt)
        local softenedY = velocity.Y + (-FALL_SOFT_LIMIT - velocity.Y) * blend
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, softenedY, velocity.Z)
    end
    -- Les flips sont prioritaires : jamais de grip, frein ou force de cap
    -- pendant une rotation lancee, meme si le rayon touche a nouveau le sol.
    if activeTrick then
        updateTrick(root, seat, dt)
        return
    end
    if not driveSupported then
        -- En plein saut, conserver la physique naturelle et les rotations.
        return
    end

    -- Le cap ne doit JAMAIS etre gele pendant un wheeling :
    -- cela empechait de tourner avec ANTI-DERAPAGE sur OFF.
    -- Au moment ou la roue avant se leve, LookVector devient surtout
    -- vertical ; on reconstruit donc le cap horizontal depuis RightVector.
    local isWheelie = math.abs(seat.CFrame.LookVector.Y) > 0.28
    local forward = flat(seat.CFrame.LookVector)
    if isWheelie then
        local horizontalRight = flat(seat.CFrame.RightVector)
        if horizontalRight.Magnitude > 0.03 then
            forward = Vector3.yAxis:Cross(horizontalRight.Unit)
        end
    end
    if forward.Magnitude > 0.03 then
        local wantedHeading = forward.Unit
        if isWheelie and lastHeading then
            -- ON amortit davantage, OFF laisse reorienter rapidement.
            local response = gripEnabled and 5.5 or 13.0
            local blend = 1 - math.exp(-response * dt)
            local blended = lastHeading:Lerp(wantedHeading, blend)
            forward = blended.Magnitude > 0.03 and blended.Unit or wantedHeading
        else
            forward = wantedHeading
        end
        lastHeading = forward
    elseif lastHeading then
        forward = lastHeading
    else
        return
    end

    local along = horizontal:Dot(forward)
    if speedState == nil then
        speedState = math.clamp(along, -REVERSE_LIMIT, PERSONAL_MAX_SPEED)
    end
    -- Ne plus remettre speedState a la vitesse reelle a chaque contact sol :
    -- le jeu la ramenait parfois a ~97 lors des petites bosses/atterrissages.

    local throttle = UIS:IsKeyDown(Enum.KeyCode.W)
        or UIS:IsKeyDown(Enum.KeyCode.Z)
        or UIS:IsKeyDown(Enum.KeyCode.Up)
    local reverse = UIS:IsKeyDown(Enum.KeyCode.S)
        or UIS:IsKeyDown(Enum.KeyCode.Down)
    local handbrake = UIS:IsKeyDown(Enum.KeyCode.Space)
    if seat:IsA("VehicleSeat") then
        throttle = throttle or seat.ThrottleFloat > 0.1
        reverse = reverse or seat.ThrottleFloat < -0.1
    end

    -- Au relachement ou au freinage, repartir de la vitesse reelle et non
    -- de la consigne virtuelle (evite de continuer a accelerer au-dessus de 97).
    if not throttle and speedState > 0 then
        speedState = math.min(speedState, math.max(0, along))
    end

    if handbrake or reverse then
        if speedState > 0 then
            local brakeRate = math.max(36, 125 / BRAKE_TIME)
            speedState = math.max(0, speedState - brakeRate * dt)
        elseif reverse and not handbrake then
            speedState = math.max(-REVERSE_LIMIT,
                speedState - REVERSE_LIMIT / 1.3 * dt)
        else
            speedState = math.min(0, speedState + 35 * dt)
        end
    elseif throttle then
        if speedState < 0 then
            speedState = math.min(0, speedState + 42 * dt)
        elseif speedState > limit then
            -- Reduire en douceur si on abaisse le curseur ou change de mode.
            speedState = math.max(limit, speedState - 55 * dt)
        else
            speedState = math.min(limit,
                speedState + (limit / ACCEL_TIME) * dt)
        end
    else
        local rate = speedState >= 0 and (125 / COAST_TIME)
            or (REVERSE_LIMIT / 2.5)
        local sign = speedState >= 0 and 1 or -1
        speedState = sign * math.max(0, math.abs(speedState) - rate * dt)
    end
    if speedState > limit then
        speedState = math.max(limit, speedState - 55 * dt)
    end

    -- Diagnostic : la consigne monte mais le vehicule reste limite par le jeu.
    if throttle and grounded and limit >= 100 and speedState > actual + 13
        and actual > 55 then
        if speedLimitedSince == 0 then speedLimitedSince = now end
        if now - speedLimitedSince > 2.4 then speedLimitWarning = true end
    else
        speedLimitedSince, speedLimitWarning = 0, false
    end
    if speedLimitWarning and now - lastUiRefresh < 0.15 then
        status.Text = "Vitesse limitee par le jeu (~" .. math.floor(actual) .. ")"
    elseif not speedLimitWarning
        and status.Text:find("Vitesse limitee par le jeu", 1, true) then
        status.Text = "BOOST actif - vitesse reelle affichee"
    end

    local angular = root.AssemblyAngularVelocity
    -- La correction de virage ne s'applique pas pendant wheelie ou en l'air.
    if speedState > 0 and not isWheelie then
        -- Le facteur fixe 106 limitait meme de petits virages a ~106.
        -- Desormais aucune reduction avant une rotation vraiment brusque.
        local yaw = math.abs(angular.Y)
        local sharpTurnThreshold = gripEnabled and 2.0 or 2.35
        if yaw > sharpTurnThreshold then
            local excess = yaw - sharpTurnThreshold
            local slowdown = gripEnabled and 0.45 or 0.28
            local floorSpeed = gripEnabled and 37 or 58
            local turnLimit = math.clamp(limit / (1 + excess * slowdown),
                math.min(floorSpeed, limit), math.max(limit, 1))
            if speedState > turnLimit then
                speedState = math.max(turnLimit,
                    speedState - (gripEnabled and 44 or 25) * dt)
            end
        end
    end

    local lateral = horizontal - forward * along
    local friction = gripEnabled and 10.3 or (actual > 85 and 5.2 or 3.4)
    if handbrake or reverse then friction = friction + 1.6 end
    local side = lateral * math.exp(-friction * dt)
    if limit == 0 and speedState >= 0 then
        speedState = math.max(0, speedState - 85 * dt)
        side = side * math.exp(-8 * dt)
    end
    local nextFlat = forward * speedState + side
    if limit > 0 and nextFlat.Magnitude > math.max(limit, speedState)
        and speedState >= 0 then
        nextFlat = nextFlat.Unit * math.max(limit, speedState)
    end
    -- Methode du script fourni : consigne de vitesse directement sur
    -- l'assemblage du vehicule, sans modifier VehicleSeat.MaxSpeed.
    root.AssemblyLinearVelocity = Vector3.new(nextFlat.X, velocity.Y, nextFlat.Z)

    -- Certains controleurs ecrasent cette vitesse pendant la simulation.
    -- La correction post-physique ne s'active qu'en acceleration au sol.
    -- Jamais en freinage, en marche arriere ou pendant des figures.
    if throttle and not reverse and not handbrake and speedState > 0
        and not isWheelie and now >= impactBlockUntil then
        afterPhysicsAssist = {
            root = root,
            seat = seat,
            heading = forward,
            speed = math.min(speedState, limit),
            t = now
        }
    end

    -- Petite aide au braquage pendant wheeling lorsque grip OFF.
    -- Conserve le pitch naturel (pas de frein ni d'auto-redressement).
    if isWheelie and not gripEnabled then
        local steer = 0
        if UIS:IsKeyDown(Enum.KeyCode.A) or UIS:IsKeyDown(Enum.KeyCode.Left) then
            steer = steer - 1
        end
        if UIS:IsKeyDown(Enum.KeyCode.D) or UIS:IsKeyDown(Enum.KeyCode.Right) then
            steer = steer + 1
        end
        if seat:IsA("VehicleSeat") then
            local controllerSteer = seat.SteerFloat
            if math.abs(controllerSteer) > 0.05 then
                steer = controllerSteer
            end
        end
        if steer ~= 0 then
            local yawNow = root.AssemblyAngularVelocity
            local maxYaw = 0.45 + 0.7 * math.clamp(math.abs(speedState) / 125, 0, 1)
            local desired = steer * maxYaw
            local nextY = yawNow.Y + (desired - yawNow.Y)
                * (1 - math.exp(-2.8 * dt))
            root.AssemblyAngularVelocity = Vector3.new(
                yawNow.X, nextY, yawNow.Z)
        end
    end

    -- Un tout petit peu plus de maintien en virage / freinage : uniquement
    -- du roulis au sol. On conserve le pitch pour wheelings / backflips.
    if grounded and not isWheelie then
        local bodyForward = seat.CFrame.LookVector
        local roll = bodyForward * angular:Dot(bodyForward)
        local rollResponse = gripEnabled and 4.2 or 0.75
        local yawBlend = 1 - math.exp(-(gripEnabled and 1.0 or 0.22) * dt)
        local steering = UIS:IsKeyDown(Enum.KeyCode.A)
            or UIS:IsKeyDown(Enum.KeyCode.D)
            or UIS:IsKeyDown(Enum.KeyCode.Left)
            or UIS:IsKeyDown(Enum.KeyCode.Right)
        if seat:IsA("VehicleSeat") then
            steering = steering or math.abs(seat.SteerFloat) > 0.1
        end
        if steering then yawBlend = yawBlend * 0.15 end
        -- +12 % de correction sur le roulis, pas d'immunite aux chutes.
        if steering or handbrake or reverse then
            rollResponse = rollResponse * 1.12
        end
        local rollBlend = 1 - math.exp(-rollResponse * dt)
        root.AssemblyAngularVelocity = angular
            - roll * rollBlend - Vector3.yAxis * angular.Y * yawBlend
    end
end)

-- Synchronisation legere APRES la physique. C'est une confirmation de la
-- consigne de la frame, pas une seconde acceleration (le timer n'avance pas).
-- Elle permet de compenser un controleur local qui redescend vers 97.
connect(RunService.PostSimulation, function(rawDt)
    local assist = afterPhysicsAssist
    afterPhysicsAssist = nil
    if not running or not enabled or not assist or activeTrick then return end
    local root, seat = assist.root, assist.seat
    if not root or not root.Parent or root.Anchored or currentSeat ~= seat then return end
    if os.clock() < impactBlockUntil then return end
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.SeatPart ~= seat then return end
    local heading = assist.heading
    local v = root.AssemblyLinearVelocity
    local horizontal = flat(v)
    local projected = horizontal:Dot(heading)
    if projected >= assist.speed - 1 or assist.speed <= 0 then return end

    -- Un obstacle devant la trottinette n'est jamais une raison de continuer
    -- a pousser le vehicule : desactiver la correction pres d'un mur.
    local obstacle = Workspace:Raycast(seat.Position,
        heading * math.clamp(2 + horizontal.Magnitude * math.clamp(rawDt, 0, 0.05), 3, 9),
        rayParams)
    if obstacle and obstacle.Normal.Y < 0.55 then return end

    -- On restaure au maximum la CONSIGNE progressive calculee avant la
    -- simulation. Pas de teleportation ni de changement de vitesse verticale.
    local lateral = horizontal - heading * projected
    local corrected = heading * assist.speed + lateral * 0.93
    root.AssemblyLinearVelocity = Vector3.new(corrected.X, v.Y, corrected.Z)
end)

env.KuKirinHubCleanup = function()
    running = false
    afterPhysicsAssist = nil
    introToken = introToken + 1
    cancelTweens()
    clearPoliceMarkers()
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    pcall(function() blur:Destroy() end)
    pcall(function() gui:Destroy() end)
end

print("KuKirin Hub V7.02 | support route ameliore, roulis adouci et impacts ajustes; vitesses en studs/s")
