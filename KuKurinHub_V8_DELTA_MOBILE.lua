-- KuKurinHub V7 DESIGN TEST / DELTA_MOBILE
-- Design inspire de la maquette orange, fonctions client non garanties par le serveur.
-- KuKurinHub UNIFIE V2 TEST | by Mmss_212 | script unique, sans GitHub.
-- Tout ce fichier est du Lua lisible. Colle-le en entier dans l'editeur Lua.
-- Le moteur Boost / Anti-derapage / Police Look V7.02 est conserve.
-- Wheelie et Money Maker Figures sont reconstruits selon tes anciens reglages.
-- Teleporteur : recherche d'abord les reperes de la carte, puis positions
-- sauvegardees manuellement si les modeles ne portent pas ces noms.
-- Money Maker Pizza : mode experimental dependant des ProximityPrompts locaux.
-- N'execute aucun script distant; n'assure pas de gain en jeu.
local _khEnv=(getgenv and getgenv()) or _G
if type(_khEnv.KuKirinUnifiedCleanup)=="function" then
    pcall(_khEnv.KuKirinUnifiedCleanup)
end

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
    SPORT = Color3.fromRGB(234, 65, 75),
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

local ACCEL_TIME = 4.5             -- 0 -> 125 en ~6 s en RACE (sur sol plat)
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
local AVATAR_BASE64 = [[/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAkGBwgHBgkIBwgKCgkLDRYPDQwMDRsUFRAWIB0iIiAdHx8kKDQsJCYxJx8fLT0tMTU3Ojo6Iys/RD84QzQ5Ojf/2wBDAQoKCg0MDRoPDxo3JR8lNzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzf/wAARCABkAGQDASIAAhEBAxEB/8QAGwAAAQUBAQAAAAAAAAAAAAAAAAMEBQYHAQL/xAA1EAACAQMDAgYABQIFBQAAAAABAgMABBEFEiExQQYTIlFhcRQygZGxI6EHU8Hh8CQlQmLR/8QAGQEAAwEBAQAAAAAAAAAAAAAAAAEDAgQF/8QAIREAAgMAAQQDAQAAAAAAAAAAAAECAxEhBBIxMhMiUUH/2gAMAwEAAhEDEQA/ANAoooNMDmTXC20ZYgD3NRmp6k8JENoAZWGQShYnr+RR+Y578AZ61RdduVYzPqEyJK3HlS/15h2JOCEj+hzxSA0qO4ilj8yOaN48E7lYEY+6YXOtQLDK9q8c4jOHk8wLGh+W/wBBk1jAm8lGMEpTIIbBP5e4+q83E7mJNzZOMImOgrWAXQ+Mbt7t5ZbpWiQZSGJDGMngc8k465OOvSm8XjK9UMZpLmeR1ZREHCIg98gZJ/WqduKL6kyc+o56Uoj7IwxcAFuQ/Uj470+ALLeeMddlhZEnt4IiuwpHHuIXGPzE5zUxpHjif8KsVzYmdowqg2rEMQPcH65qi+YkikAHAGTuGKI5X2hywBYcKBjijEI1zRfFWn6s6wpvhnPSOTHP0e9TwXJxWAtJuz6W3qf0A/mrJ4X8Savb30ERvS9uSEKXL7o1B4GWPK8nrWWhmvUVFW2v2LB0vJ47S5icxywyuMqw9j3HcGikBJVE+JtWXRtN/EEje8ixoOvXqcd8DNPZ762hZkaaPzQdoj3gMzYzgZ+Dmsd8Xa/Jq+pyzbgEiPlxKDwq9z9k0Ae9e8QXU1xK9tdNFFIMGOJyCQTnDHvj9vaq2Z95O4ZHyaRdsnk0Jy6r7nFNAPPSICMcsO9I+YTIrOSVAJxnvXJn/qMuOnH1SeCw4IptgKC4cZAwBjsKVSYQQrgguR+33TZm6BR0pW3UJ6iAzfNJAKRhlQvI3ozkhv8AyP8AztSq3sag4i3H+aT83cx3qoKjjvj968brhQZUlDA8Ee36U9A9PciSTeYsHGD6qVtruCG5R54GkhDAuivtLD77U0kl35JADfXWuR7RhnAKZwwzzj3pMC8QwaFfhp7XVLyOMtjbLbMzA/JHWiqtFZKyZSaROSCoPf8A5iikBof+Jfh5LmNdVgkVLhRsdGBxIACcjA4IA/astYHOCuO9bd4n1O+0u1lll09LrTxGfMlin2SITx+XHyOQaxaeSN5GKQsuTwCeQKAGpOK6COMgj5FAjJPPX2qetrC2g/Cz3aq0MibcE/lbORn7rMpqPk3CDn4INvWSwOSeTxSkcMjAiOKR8d1WrDe2cFvtubS2UNEctGeQy9+KV0iRV3NZzq0Lc7GHqX7qbu41FVQ+7GV+Gxu7iNZIrOR16bl6HFKPpt6sZZrSRAoySewq1EbHZ7d/LZjlhjKt+nv8imOoXFzMy2iGNmPLHGBjsT7Af3rKubZp0RSKs7E8nrXr+pAAXRhk45GMjvVht7CK32eqNpRyxbk5+vvpTTW1MixQ4VBDGzk5zn/cmqK1N4ibpajrIU8scdu/xXFYp6hjj3717RcKw6lgAPYV6WBmOEG5j0A7CqER8t/d2iiGPywgGQNgPXnqaK2DwD4fig8OQrqmnWd1IzF45mw26NsEdRnueDRQBYDz1qpeOfDT6vElzZwwtcQoRg5UsOvGByfg1baOrCgDAvwRjndZUK7TjHz91PeWGiTHGEAXA6cVY/FUMUWr3MUaKEV+ABwOOagX4risnrw9CmCjHSAlZyGuBeXQjycsI+nam9v5LeiK9ucDkhRip02sO5j5Y56jtXYreKLmONVJ9hTViSE623oRIq2wjBZl24yTyagrhLa3fH/Uc9Mk4/irFXkqrdVB+xWYyw3KOlejiDESNGShPAZyC3xThIGkVNyosUrjjJY4Hb6HWpK6xhY0VfMk4Xjp7mkmSMS4C4ht13Eju3t+1UUxOCfkRay/Eu6whRGrFVJ+AKsXgvwut/qqQTMWt4lEs+FIB54UH5/+1HWS4t0JGC3qI+TzWi+DJWi0hgmBmU5OOvArVUm5YQvgktLgoCqAoAA4AAwBRUb+Kl9x+1FdOHKeaF/OPuu7v/Vf2oDYIIVc/VAFA8SMW1e7LHJ81h/eoGeRYwCx6nAqY15v+5XJP+Y381B3CeYQQ7Ljpg/3rzX7M9SPqhKS4ClQFJ3HC5GK7/WfoVQe45JFIXMTCMsCztnJ7H9KRtrgqclyQwA2t2+q2lxwNx0fhH/zOM+3avOJwOGRj7kYrpmQdXUfZFeZZoimHcBWOM9j8ZoTf4YaX6IiQgNcvGDJ+RAM8j/f+K60RdEgIQM53yD9ecUoFBk8xuAowo9qIEUOZedzKAM+1Gmh2vWr94Uj2aOhzne7N9dv9Kz9G5rRfDIK6Lb7gRnJ59s1Xp/Y5+of1JOiu0V1nGe6KKKQFC8TwGLU5/SQGO4Z75qvSA1p2s6WmpQBchZV/K5H9qoGvWjaMN18pRC21XAyGPxXFZXJS1HfXbFxxkQ4LKVOcHg0xcQW8ojUEOee5wK9z6zaK2Iw7j3ximV3c293NG8O5WwVJcHAB74FOEJf1CnZHOGSK3jx9LkKNpbg9q6Naur2zkt5LyVrZuschBBwfrioWCzkMsYLRdcn1ZAx0q06X4U1D8MjS2s+2VseZ5ZC/GB7VVxa8Eoyi39kMIndjtGGA7/FOVBNWSXw1Y2UgivtesopSu7ywpLYqI1U6fpskSpeG5D9dsRBUe5FSdUyvzQOWFpLczpFEpLucCtOtIRb20UK4xGgXimOi6TBp8fmRsXkdRlyMcdeBUmK6Kq+1cnPbZ3Pg7RRRVSJ7ooopAB4BPxWNeL9cu9auTbXgiEdtMfLEa4PPBzzz0oooArbxpG2AoP3zXmImRwrE4z0FFFAFz8BW8DeIYY5YUkQRs2H55AyDVi1i8uNXvHsLqVhA0nRDgqR0I9qKKbAm7TwVoljaG88iW4uPKLeZcSsxzj9KzixlW+10SXFvCyruIj2+n0jgY9qKKbSwDV7BzJZwsRjKD+KXoopAdooooA//9k=]]
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

-- Ancien chargement de logo retire (interface V7 masquee; aucun telechargement requis).
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


-- Interface bridge added after the unmodified V7.02 physics engine.
-- All V7.02 speed, brake, stability and Police Look routines remain as-is.
env.KuKirinLegacyAPI = {
    getState = function()
        return {enabled=enabled, grip=gripEnabled, police=policeLook,
                mode=mode, personal=personalLimit, limit=speedLimit()}
    end,
    setBoost = function(value)
        enabled = not not value
        speedState = nil
        speedLimitedSince, speedLimitWarning = 0, false
        if not enabled then
            -- VehicleSeat speeds were not modified in this particular revision.
            afterPhysicsAssist = nil
        end
        boostButton.Text=enabled and "BOOST : ON" or "BOOST : OFF"
        boostButton.BackgroundColor3=enabled and GREEN or GREY
    end,
    setGrip = function(value)
        gripEnabled=not not value
        gripButton.Text=gripEnabled and "ANTI-DERAPAGE : ON" or "ANTI-DERAPAGE : OFF (GRIP LEGER)"
        gripButton.BackgroundColor3=gripEnabled and Color3.fromRGB(39,113,180) or GREY
    end,
    setMode = function(m)
        if m=="ECO" or m=="SPORT" or m=="RACE" or m=="PERSO" then
            mode=m
            redrawModes()
        end
    end,
    setPersonal = function(value)
        personalLimit=math.clamp(math.floor(tonumber(value) or 125),0,200)
        mode="PERSO"
        redrawModes()
        redrawSlider()
    end,
    setPolice = function(value)
        value=not not value
        if policeLook == value then return end
        policeLook=value
        policeButton.Text=policeLook and "POLICE LOOK : ON" or "POLICE LOOK : OFF"
        policeButton.BackgroundColor3=policeLook and RED or GREY
        if policeLook then task.spawn(scanPolice) else clearPoliceMarkers() end
    end,
    stop = env.KuKirinHubCleanup
}
gui.Enabled=false -- Hide V7 UI only, preserving V7 engine & cleanup.

-- ================================================================
-- KUKURINHUB UNIFIED -- interface & orchestration, 100% local
-- No external script or GitHub dependency, no remote control.
-- V7.02 speed and Police Look engine above is kept as sourced.
-- ================================================================

(function()
local Players2 = game:GetService("Players")
local RunService2 = game:GetService("RunService")
local UIS2 = game:GetService("UserInputService")
local Tween2 = game:GetService("TweenService")
local Workspace2 = game:GetService("Workspace")
local player2 = Players2.LocalPlayer
local env2 = (getgenv and getgenv()) or _G
local api = env2.KuKirinLegacyAPI
if not api then warn("KuKirin Unified: moteur V7.02 introuvable") return end
local pg = player2:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("KuKurinHubUnified")
if old then old:Destroy() end

local BG = Color3.fromRGB(19, 20, 29)
local SURFACE = Color3.fromRGB(27, 29, 41)
local SURFACE2 = Color3.fromRGB(37, 40, 55)
local BORDER = Color3.fromRGB(66, 68, 86)
local WHITE2 = Color3.fromRGB(244, 245, 251)
local MUTED = Color3.fromRGB(157, 163, 180)
local ACCENT = Color3.fromRGB(255, 115, 67)
local PINK = Color3.fromRGB(241, 85, 149)
local GREEN2 = Color3.fromRGB(74, 207, 149)
local RED2 = Color3.fromRGB(245, 94, 106)
local connections2 = {}
local alive = true
local lastRefresh = 0
local openedOnce = false
local currentTab = "Accueil"
local pizza = {enabled=false, phase="pickup", status="Pret", iteration=0}
local waypoints = {}
local wheelie = {enabled=false, angle=40, sense=1, seat=nil, root=nil,
                attach=nil, align=nil, yaw=0}
local flight = {phase="idle", root=nil, seat=nil, startY=nil,
                targetY=nil, elapsed=0, spin=nil, spinActuator=nil, spinT=0}

local function listen(sig, fn)
    local c = sig:Connect(fn)
    table.insert(connections2,c)
    return c
end
local function corner(gui, radius)
    local c=Instance.new("UICorner")
    c.CornerRadius=UDim.new(0,radius or 10)
    c.Parent=gui
    return c
end
local function outline(gui, color, thickness, transparency)
    local s=Instance.new("UIStroke")
    s.Color=color or BORDER
    s.Thickness=thickness or 1
    s.Transparency=transparency or 0
    s.Parent=gui
    return s
end
local function create(class, props, parent)
    local item=Instance.new(class)
    for k,v in pairs(props) do item[k]=v end
    item.Parent=parent
    return item
end
local function label(parent, contents, size, color, bold)
    return create("TextLabel", {BackgroundTransparency=1, Text=tostring(contents),
        TextColor3=color or WHITE2, TextSize=size or 14,
        Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center, TextWrapped=true}, parent)
end
local function btn(parent, caption, color, borderColor)
    local b=create("TextButton", {AutoButtonColor=true, Text=caption,
        TextSize=14, Font=Enum.Font.GothamBold, TextColor3=WHITE2,
        BackgroundColor3=color or SURFACE2, BorderSizePixel=0}, parent)
    corner(b,10)
    if borderColor then outline(b,borderColor,1) end
    return b
end
local function tween(obj, duration, goal, style)
    if not alive or not obj or not obj.Parent then return end
    local ok,t=pcall(function()
        return Tween2:Create(obj,TweenInfo.new(duration,style or Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out),goal)
    end)
    if ok then t:Play() end
end
local function vehicle()
    local character=player2.Character
    local hum=character and character:FindFirstChildOfClass("Humanoid")
    local seat=hum and hum.SeatPart
    if not (seat and seat:IsA("BasePart")) then return nil,nil end
    local root=seat.AssemblyRootPart or seat
    if not root or root.Anchored then return nil,nil end
    return seat,root
end
local function removeWheelieConstraint()
    if wheelie.align then pcall(function() wheelie.align:Destroy() end) end
    if wheelie.attach then pcall(function() wheelie.attach:Destroy() end) end
    wheelie.align,wheelie.attach,wheelie.seat,wheelie.root=nil,nil,nil,nil
end
local function setWheelie(value)
    wheelie.enabled=not not value
    if not wheelie.enabled then removeWheelieConstraint() end
end
local function makeWheelieConstraint(seat,root)
    removeWheelieConstraint()
    local att=Instance.new("Attachment")
    att.Name="KH_Wheelie_Attachment"
    -- Align the scooter seat orientation, even if the assembly root is rotated.
    att.CFrame=root.CFrame:ToObjectSpace(seat.CFrame)
    att.Parent=root
    local a=Instance.new("AlignOrientation")
    a.Name="KH_SmoothWheelie"
    a.Mode=Enum.OrientationAlignmentMode.OneAttachment
    a.Attachment0=att
    a.RigidityEnabled=false
    a.ReactionTorqueEnabled=false
    a.Responsiveness=7
    a.MaxAngularVelocity=4.5
    a.MaxTorque=math.clamp(root.AssemblyMass*2600,9000,155000)
    a.Parent=root
    wheelie.attach,wheelie.align,wheelie.seat,wheelie.root=att,a,seat,root
    local f=seat.CFrame.LookVector
    wheelie.yaw=math.atan2(f.X,-f.Z)
end
local function updateWheelie(dt)
    if not wheelie.enabled then return end
    if flight.phase~="idle" then return end
    local seat,root=vehicle()
    if not seat then removeWheelieConstraint(); return end
    if not wheelie.align or root~=wheelie.root then
        makeWheelieConstraint(seat,root)
    end
    local steer=0
    if seat:IsA("VehicleSeat") then
        steer=seat.SteerFloat
    end
    if math.abs(steer)<0.08 then
        if UIS2:IsKeyDown(Enum.KeyCode.A) or UIS2:IsKeyDown(Enum.KeyCode.Left) then steer=steer-1 end
        if UIS2:IsKeyDown(Enum.KeyCode.D) or UIS2:IsKeyDown(Enum.KeyCode.Right) then steer=steer+1 end
    end
    if math.abs(steer)>0.05 then
        local v=root.AssemblyLinearVelocity
        local horizontal=Vector3.new(v.X,0,v.Z).Magnitude
        wheelie.yaw=wheelie.yaw+steer*dt*(0.65+math.clamp(horizontal*0.012,0,1.4))
    end
    -- Stable pitch. Vehicle throttle/speed are untouched: the rider drives.
    local forward=Vector3.new(math.sin(wheelie.yaw),0,-math.cos(wheelie.yaw))
    local base=CFrame.lookAt(Vector3.zero,forward,Vector3.yAxis)
    wheelie.align.CFrame=base*CFrame.Angles(math.rad(wheelie.angle*wheelie.sense),0,0)
end

local function flightRay(maxDistance)
    if not flight.root or not flight.root.Parent then return nil end
    local rp=RaycastParams.new()
    rp.FilterType=Enum.RaycastFilterType.Exclude
    local list={}
    if player2.Character then table.insert(list,player2.Character) end
    if flight.seat then
        local m=flight.seat:FindFirstAncestorOfClass("Model")
        if m then table.insert(list,m) end
    end
    rp.FilterDescendantsInstances=list
    rp.IgnoreWater=true
    return Workspace2:Raycast(flight.root.Position,Vector3.new(0,-maxDistance,0),rp)
end
local function clearSpin()
    if flight.spinActuator then pcall(function() flight.spinActuator:Destroy() end) end
    if flight.spin then pcall(function() flight.spin:Destroy() end) end
    flight.spin=nil
    flight.spinActuator=nil
end
local function endFlight()
    clearSpin()
    flight.phase="idle"
    flight.root,flight.seat,flight.startY,flight.targetY=nil,nil,nil,nil
    flight.elapsed=0
end
local function startFlight()
    if flight.phase~="idle" then
        -- Releasing ascent restores the game's natural free fall.
        if flight.phase=="ascend" then flight.phase="fall" end
        return true
    end
    local seat,root=vehicle()
    if not seat then return false end
    setWheelie(false) -- Avoid simultaneous orientation controllers.
    flight.seat,flight.root=seat,root
    flight.startY=root.Position.Y
    local height=220 -- Preserved target from the latest Money Maker V2.
    local rp=RaycastParams.new()
    rp.FilterType=Enum.RaycastFilterType.Exclude
    local excludes={}
    if player2.Character then table.insert(excludes,player2.Character) end
    local model=seat:FindFirstAncestorOfClass("Model")
    if model then table.insert(excludes,model) end
    rp.FilterDescendantsInstances=excludes
    local obstacle=Workspace2:Raycast(root.Position,Vector3.new(0,240,0),rp)
    if obstacle then height=math.max(0,math.min(height,obstacle.Distance-15)) end
    if height<30 then endFlight(); return false end
    flight.targetY=flight.startY+height
    flight.phase="ascend"
    flight.elapsed=0
    return true
end
local function startSpin(kind)
    if flight.phase~="fall" and flight.phase~="ascend" then return false end
    local root=flight.root
    if not root or not root.Parent then return false end
    clearSpin()
    local att=Instance.new("Attachment")
    att.Name="KH_Spin_Attachment"
    att.Parent=root
    local av=Instance.new("AngularVelocity")
    av.Name="KH_Flight_Trick"
    av.Attachment0=att
    av.RelativeTo=Enum.ActuatorRelativeTo.World
    av.MaxTorque=math.clamp(root.AssemblyMass*3200,10000,230000)
    local right=root.CFrame.RightVector
    if kind=="Backflip" then
        av.AngularVelocity=right*7.8
    elseif kind=="Frontflip" then
        av.AngularVelocity=-right*7.8
    else
        av.AngularVelocity=Vector3.yAxis*7.8
    end
    av.Parent=root
    flight.spin=att
    flight.spinActuator=av
    flight.spinT=os.clock()+0.8
    -- Destroy attachment and actuator together using explicit reference.
    local token=att
    task.delay(0.82,function()
        if token and token.Parent then token:Destroy() end
        if av and av.Parent then av:Destroy() end
        if flight.spin==token then flight.spin=nil; flight.spinActuator=nil end
    end)
    return true
end
local function updateFlight(dt)
    if flight.phase=="idle" then return end
    local seat,root=vehicle()
    if not root or root~=flight.root then endFlight();return end
    flight.elapsed=flight.elapsed+dt
    if flight.elapsed>24 then endFlight();return end
    local v=root.AssemblyLinearVelocity
    if flight.phase=="ascend" then
        local remaining=flight.targetY-root.Position.Y
        if remaining<=2 then
            flight.phase="fall"
            return
        end
        local desired=math.clamp(remaining*0.70,5,66)
        local blend=1-math.exp(-7*dt)
        root.AssemblyLinearVelocity=Vector3.new(v.X,v.Y+(desired-v.Y)*blend,v.Z)
    elseif flight.phase=="fall" then
        -- True gravity while high up; only soften the final approach.
        local ground=flightRay(35)
        if ground then
            local distance=ground.Distance
            if distance<27 and v.Y < -14 then
                local allowed=-math.clamp(9+distance*0.40,11,20)
                local blend=1-math.exp(-8*dt)
                root.AssemblyLinearVelocity=Vector3.new(v.X,v.Y+(allowed-v.Y)*blend,v.Z)
            end
            if distance<5 and v.Y>-30 and flight.elapsed>1.4 then
                endFlight()
            end
        end
    end
end

-- ========================= TELEPORTATIONS =========================
-- Pas de coordonnees inventees : points reconnus dans Workspace ou
-- memorises par le joueur. Les positions manuelles sont locales a la session.
local teleportTargets = {
    {id="lobby", name="1  •  Lobby", keywords={"lobby", "mainspawn", "main spawn", "spawnpoint"}},
    {id="pizza", name="2  •  Pizza Delivery", keywords={"pizza delivery", "pizzeria", "pizza shop", "pizza"}},
    {id="skate1", name="3  •  Skate Park", keywords={"skatepark", "skate park", "skate_park"}},
    {id="skate2", name="4  •  Deuxieme skate park / rampe", keywords={"mega ramp", "big ramp", "skatepark2", "skate park 2", "ramp"}},
    {id="races", name="5  •  Courses moto / casque", keywords={"race track", "racing", "motorcycle race", "rideout", "circuit", "race"}},
    {id="airport", name="6  •  Aeroport", keywords={"airport", "aeroport", "airfield", "airstrip"}},
}
local function playerAnchor()
    local seat,root=vehicle()
    if seat and root then return root,seat end
    local ch=player2.Character
    return ch and ch:FindFirstChild("HumanoidRootPart"),nil
end
local function currentPlayerPosition()
    local root=playerAnchor()
    return root and root.Position or nil
end
local function findLandmark(def)
    local origin=currentPlayerPosition() or Vector3.zero
    local best,bestScore=nil,-math.huge
    -- Une recherche sur demande, pas a chaque frame. Pas de faux coordinates.
    for _,inst in ipairs(Workspace2:GetDescendants()) do
        if inst:IsA("Model") or inst:IsA("BasePart") then
            local name=inst.Name:lower()
            local score=0
            for _,word in ipairs(def.keywords) do
                if name==word then
                    score=math.max(score,100+#word)
                elseif name:find(word,1,true) and #name<50 then
                    score=math.max(score,35+#word)
                end
            end
            if score>0 then
                -- Favoriser les pieces accessibles; ignorer les gros decors
                -- dont le pivot est trop haut ou deconnecte de la zone.
                local cf
                if inst:IsA("BasePart") then cf=inst.CFrame
                else
                    local ok,pivot=pcall(function()return inst:GetPivot()end)
                    if ok then cf=pivot end
                end
                if cf and math.abs(cf.Position.Y)<50000 then
                    score=score-math.min((cf.Position-origin).Magnitude/2500,16)
                    if score>bestScore then best,bestScore=cf,score end
                end
            end
        end
    end
    if best then return best end
    if def.id=="lobby" then
        local spawn=Workspace2:FindFirstChildWhichIsA("SpawnLocation",true)
        if spawn then return spawn.CFrame end
    end
    return nil
end
local function teleportTo(cf)
    if not cf then return false,"Destination introuvable" end
    local root,seat=playerAnchor()
    if not root then return false,"Ton personnage n'est pas encore charge" end
    if not root:IsA("BasePart") or root.Anchored then
        return false,"Ton vehicule est ancre : deplacement impossible"
    end
    -- Ne pas laisser wheelie et figures se battre contre la teleportation.
    setWheelie(false)
    endFlight()
    local destination=CFrame.new(cf.Position+Vector3.new(0,5.5,0))
    local ok=pcall(function()
        if seat then
            -- Deplace l'assembly de la trottinette plutot qu'un decor entier.
            local heading=seat.CFrame.LookVector
            local flat=Vector3.new(heading.X,0,heading.Z)
            if flat.Magnitude>.05 then destination=CFrame.lookAt(destination.Position,destination.Position+flat.Unit) end
            root.AssemblyLinearVelocity=Vector3.zero
            root.AssemblyAngularVelocity=Vector3.zero
            root.CFrame=destination
        elseif player2.Character then
            player2.Character:PivotTo(destination)
        else
            root.CFrame=destination
        end
    end)
    return ok,(ok and "Teleportation lancee" or "Deplacement refuse par le jeu")
end
local function saveWaypoint(def)
    local position=currentPlayerPosition()
    if not position then return false end
    waypoints[def.id]=CFrame.new(position)
    return true
end
local function gotoWaypoint(def)
    local cf=waypoints[def.id] or findLandmark(def)
    if cf then return teleportTo(cf) end
    return false,"Lieu non reconnu. Va sur place et utilise ENREGISTRER ICI."
end

-- ====================== MONEY MAKER PIZZA =========================
-- Aucune commande d'argent / RemoteEvent inconnue n'est inventee.
-- Le mode ci-dessous utilise UNIQUEMENT les prompts existant sur le client,
-- quand l'executant prend en charge fireproximityprompt. Le jeu peut refuser.
local function promptActivator()
    if type(fireproximityprompt)=="function" then return fireproximityprompt end
    local envFn=env2 and env2.fireproximityprompt
    if type(envFn)=="function" then return envFn end
    return nil
end
local function pizzaPrompt(kind)
    local chosen,scoreMax=nil,-9999
    local visited=0
    for _,d in ipairs(Workspace2:GetDescendants()) do
        visited=visited+1
        if visited>24000 then break end
        if d:IsA("ProximityPrompt") and d.Enabled then
            local p=d.Parent
            local grand=p and p.Parent
            local desc=(d.Name.." "..d.ActionText.." "..d.ObjectText.." "..
              (p and p.Name or "").." "..(grand and grand.Name or "")):lower()
            local hasPizza=desc:find("pizza",1,true) or desc:find("pizzeria",1,true)
            local hasDelivery=desc:find("deliver",1,true) or desc:find("customer",1,true)
                or desc:find("client",1,true) or desc:find("dropoff",1,true)
                or desc:find("livrai",1,true)
            local hasPickup=desc:find("pickup",1,true) or desc:find("pick up",1,true)
                or desc:find("collect",1,true) or desc:find("order",1,true)
                or desc:find("recuper",1,true) or desc:find("prendre",1,true)
            local score=0
            if kind=="pickup" then
                if hasPizza then score=score+10 end
                if hasPickup then score=score+6 end
                if hasDelivery and not hasPizza then score=score-8 end
            else
                if hasDelivery then score=score+12 end
                if hasPizza then score=score+2 end
                if hasPickup then score=score-7 end
            end
            if score>=10 and score>scoreMax then chosen,scoreMax=d,score end
        end
    end
    return chosen
end
local function promptPosition(prompt)
    if not prompt then return nil end
    local parent=prompt.Parent
    if parent:IsA("BasePart") then return parent.Position end
    if parent:IsA("Attachment") then return parent.WorldPosition end
    if parent:IsA("Model") then return parent:GetPivot().Position end
    return nil
end
local function pizzaTargetPosition(target)
    if not target then return nil end
    if target:IsA("BasePart") then return target.Position end
    if target:IsA("Model") then return target:GetPivot().Position end
    return nil
end
local function pizzaPressE()
    local success=false
    if type(keypress)=="function" and type(keyrelease)=="function" then
        success=pcall(function() keypress(0x45);task.wait(.12);keyrelease(0x45) end)
    end
    if not success then
        success=pcall(function()
            local vim=game:GetService("VirtualInputManager")
            vim:SendKeyEvent(true,Enum.KeyCode.E,false,game)
            task.wait(.12)
            vim:SendKeyEvent(false,Enum.KeyCode.E,false,game)
        end)
    end
    return success
end
local function setPizza(value)
    pizza.enabled=not not value
    pizza.iteration=pizza.iteration+1
    pizza.phase="pickup"
    if not pizza.enabled then pizza.status="Arrete";return end
    local ticket=pizza.iteration
    pizza.status="Recherche du PNJ NPCs.Test..."
    task.spawn(function()
        local function valid() return alive and pizza.enabled and ticket==pizza.iteration end
        local function waitValid(seconds)
            local start=os.clock()
            while os.clock()-start<seconds do
                if not valid() then return false end
                task.wait(.2)
            end
            return valid()
        end
        while valid() do
            local folder=Workspace2:FindFirstChild("NPCs")
            local npc=folder and folder:FindFirstChild("Test")
            if not npc then
                pizza.status="PNJ NPCs.Test introuvable (jeu/streaming)"
                if not waitValid(2) then break end
            else
                local pos=pizzaTargetPosition(npc)
                if not pos then pizza.status="Position du PNJ inconnue";break end
                pizza.status="Teleportation a la pizzeria..."
                local ok=teleportTo(CFrame.lookAt(pos+Vector3.new(0,2,4),pos))
                if not ok then pizza.status="Teleportation pizzeria refusee";break end
                if not waitValid(.5) then break end
                if not pizzaPressE() then pizza.status="Touche E indisponible";break end
                pizza.status="Attente du client..."
                local customer
                for i=1,30 do
                    if not valid() then break end
                    customer=Workspace2:FindFirstChild("DeliveryCustomer")
                    if customer then break end
                    task.wait(.5)
                end
                if not valid() then break end
                if not customer then
                    pizza.status="Client DeliveryCustomer introuvable"
                    if not waitValid(2) then break end
                else
                    pizza.status="Commande prise - attente de livraison"
                    if not waitValid(9) then break end
                    local cpos=pizzaTargetPosition(customer)
                    if cpos and customer.Parent then
                        pizza.status="Teleportation au client..."
                        local delivered=teleportTo(CFrame.lookAt(cpos+Vector3.new(0,2,4),cpos))
                        if delivered then
                            if not waitValid(.5) then break end
                            pizzaPressE()
                            pizza.status="Livraison envoyee - validation du jeu..."
                            if not waitValid(7) then break end
                        else pizza.status="Teleportation client refusee" end
                    else pizza.status="Client disparu" end
                end
            end
            if not waitValid(1) then break end
        end
        if ticket==pizza.iteration then pizza.enabled=false end
    end)
end

-- ============================= GUI ================================
local ui=Instance.new("ScreenGui")
ui.Name="KuKurinHubUnified"
ui.ResetOnSpawn=false
ui.IgnoreGuiInset=true
ui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
ui.DisplayOrder=600
ui.Parent=pg

local shade=create("Frame",{Name="Backdrop", BackgroundColor3=Color3.fromRGB(0,0,0),
    BackgroundTransparency=0.55,Size=UDim2.fromScale(1,1),Visible=false, BorderSizePixel=0},ui)
local main=create("CanvasGroup",{Name="MainPanel", BackgroundColor3=BG,
    Size=UDim2.fromOffset(790,475),AnchorPoint=Vector2.new(.5,.5),
    Position=UDim2.fromScale(.5,.5), GroupTransparency=1,Visible=false,
    BorderSizePixel=0},ui)
corner(main,18)
outline(main,ACCENT,2,0.05)
local scale=Instance.new("UIScale")
scale.Parent=main
local function adaptScale()
    local camera=Workspace2.CurrentCamera
    local vp=camera and camera.ViewportSize or Vector2.new(1280,720)
    local w,h=main.Size.X.Offset,main.Size.Y.Offset
    scale.Scale=math.clamp(math.min((vp.X-76)/w,(vp.Y-125)/h),0.30,0.68)
end
adaptScale()
listen(Workspace2:GetPropertyChangedSignal("CurrentCamera"),adaptScale)
if Workspace2.CurrentCamera then
    listen(Workspace2.CurrentCamera:GetPropertyChangedSignal("ViewportSize"),adaptScale)
end

local top=create("Frame",{Name="TitleBar",BackgroundTransparency=1,
    Position=UDim2.fromOffset(0,0),Size=UDim2.new(1,0,0,60), Active=true},main)
label(top,"KuKurin",25,ACCENT,true).Position=UDim2.fromOffset(22,12)
local titleAccent=top:FindFirstChildOfClass("TextLabel")
titleAccent.Size=UDim2.fromOffset(175,36)
local hubText=label(top,"HUB",12,ACCENT,true)
hubText.Size=UDim2.fromOffset(42,28)
hubText.Position=UDim2.fromOffset(158,16)
local version=label(top,"UNIFIED  •  by Mmss_212",11,MUTED,false)
version.Size=UDim2.fromOffset(220,27)
version.Position=UDim2.fromOffset(224,16)
local xbtn=btn(top,"×",SURFACE2)
xbtn.Size=UDim2.fromOffset(36,33)
xbtn.Position=UDim2.new(1,-51,0,14)
xbtn.TextSize=24
local minimizeMain=btn(top,"−",SURFACE2)
minimizeMain.Name="ReduireEnBarre"
minimizeMain.Size=UDim2.fromOffset(36,33)
minimizeMain.Position=UDim2.new(1,-94,0,14)
minimizeMain.TextSize=24
local horizontalBar=create("Frame",{Name="KuKurinHorizontalBar",BackgroundColor3=BG,
    AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,22),
    Size=UDim2.fromOffset(290,49),Visible=false,Active=true,BorderSizePixel=0},ui)
corner(horizontalBar,12)
outline(horizontalBar,ACCENT,2)
local barText=label(horizontalBar,"KuKurinHub  |  by Mmss_212",16,ACCENT,true)
barText.Position=UDim2.fromOffset(15,8)
barText.Size=UDim2.new(1,-115,0,32)
local barRestore=btn(horizontalBar,"+",Color3.fromRGB(151,66,22))
barRestore.Position=UDim2.new(1,-46,0,7)
barRestore.Size=UDim2.fromOffset(36,34)
local barClose=btn(horizontalBar,"×",SURFACE2)
barClose.Position=UDim2.new(1,-87,0,7)
barClose.Size=UDim2.fromOffset(35,34)
local line=create("Frame",{BackgroundColor3=ACCENT,BackgroundTransparency=.15,
    BorderSizePixel=0,Size=UDim2.new(1,-32,0,1),Position=UDim2.fromOffset(16,59)},main)

local side=create("ScrollingFrame",{BackgroundColor3=Color3.fromRGB(22,24,34),BorderSizePixel=0,
    ScrollBarThickness=0,CanvasSize=UDim2.fromOffset(0,0),
    Position=UDim2.fromOffset(12,73), Size=UDim2.fromOffset(185,388)},main)
corner(side,12)
local pagesArea=create("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(209,72),
    Size=UDim2.fromOffset(563,390),ClipsDescendants=true},main)
local menuNames={"Accueil","Teleport","Wheelie","Money Maker","Boost","Police Look"}
local navButtons={}
local pages={}
local pageSwitch
for i,name in ipairs(menuNames) do
    local n=btn(side,name, i==1 and Color3.fromRGB(150,70,28) or Color3.fromRGB(34,30,28))
    n.TextXAlignment=Enum.TextXAlignment.Left
    n.Position=UDim2.fromOffset(11,12+(i-1)*49)
    n.Size=UDim2.fromOffset(161,43)
    n.TextSize=13
    local pad=Instance.new("UIPadding")
    pad.PaddingLeft=UDim.new(0,13)
    pad.Parent=n
    navButtons[name]=n
    local page=create("ScrollingFrame",{Name=name, BackgroundTransparency=1,
        ScrollBarThickness=3,ScrollBarImageColor3=ACCENT,
        CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,
        Size=UDim2.fromScale(1,1), Visible=i==1,BorderSizePixel=0},pagesArea)
    local layout=Instance.new("UIListLayout")
    layout.FillDirection=Enum.FillDirection.Vertical
    layout.SortOrder=Enum.SortOrder.LayoutOrder
    layout.Padding=UDim.new(0,10)
    layout.Parent=page
    local pad2=Instance.new("UIPadding")
    pad2.PaddingRight=UDim.new(0,8)
    pad2.PaddingBottom=UDim.new(0,12)
    pad2.Parent=page
    pages[name]=page
    listen(n.Activated,function() pageSwitch(name) end)
end
pageSwitch=function(name)
    if not pages[name] then return end
    currentTab=name
    for k,p in pairs(pages) do
        p.Visible=(k==name) or (p.Parent~=pagesArea)
        navButtons[k].BackgroundColor3=(k==name) and Color3.fromRGB(150,70,28) or Color3.fromRGB(34,30,28)
        navButtons[k].TextColor3=(k==name) and WHITE2 or MUTED
    end
end

local function section(page,titleText,height)
    local f=create("Frame",{BackgroundColor3=SURFACE,BorderSizePixel=0,
        Size=UDim2.new(1,-2,0,height)},page)
    corner(f,12)
    outline(f,BORDER,1,.47)
    if titleText then
        local h=label(f,titleText,15,WHITE2,true)
        h.Position=UDim2.fromOffset(17,12)
        h.Size=UDim2.new(1,-30,0,25)
    end
    return f
end
local function caption(p,msg,y)
    local l=label(p,msg,12,MUTED)
    l.Position=UDim2.fromOffset(17,y)
    l.Size=UDim2.new(1,-34,0,30)
    return l
end
local function twoButtons(p,t1,t2,y,callback1,callback2)
    local l=btn(p,t1,SURFACE2)
    local r=btn(p,t2,SURFACE2)
    l.Position=UDim2.new(0,17,0,y)
    l.Size=UDim2.new(.5,-23,0,37)
    r.Position=UDim2.new(.5,6,0,y)
    r.Size=UDim2.new(.5,-23,0,37)
    listen(l.Activated,callback1)
    listen(r.Activated,callback2)
    return l,r
end

-- HOME
local home=pages["Accueil"]
local hero=section(home,nil,137)
local heroGradient=Instance.new("UIGradient")
heroGradient.Color=ColorSequence.new(Color3.fromRGB(85,42,18),Color3.fromRGB(30,23,24))
heroGradient.Rotation=15
heroGradient.Parent=hero
local welcome=label(hero,"BIENVENUE SUR  KuKurinHub",23,WHITE2,true)
welcome.Position=UDim2.fromOffset(19,20)
welcome.Size=UDim2.fromOffset(330,34)
local by=label(hero,"Tous tes modules  •  by Mmss_212",12,Color3.fromRGB(238,185,179))
by.Position=UDim2.fromOffset(20,66)
by.Size=UDim2.fromOffset(360,23)
local avatar=create("ImageLabel",{Name="PlayerAvatar",BackgroundColor3=SURFACE2,
    Image="",Size=UDim2.fromOffset(82,82),Position=UDim2.new(1,-105,0,18),
    ScaleType=Enum.ScaleType.Crop},hero)
corner(avatar,41)
outline(avatar,ACCENT,2)
local avatarFallback=label(avatar,"M",35,ACCENT,true)
avatarFallback.Size=UDim2.fromScale(1,1)
avatarFallback.TextXAlignment=Enum.TextXAlignment.Center
local stateCard=section(home,"⚡  ETAT DES MODULES",120)
local overview=caption(stateCard,"Boost actif  •  Wheelie en attente  •  Money Maker pret",45)
overview.TextWrapped=true
local shortcut=section(home,"⚡  ACCES RAPIDE",94)
local quick1,quick2=twoButtons(shortcut,"Teleport","Money Maker",42,function()pageSwitch("Teleport")end,
    function()pageSwitch("Money Maker")end)

-- Cartes de statut comme la maquette de reference.
local statusTiles={}
local tileInfo={{"Boost","⚡"},{"Wheelie","W"},{"Money Maker","$"},{"Police","P"},{"Pizza","◈"}}
for i,entry in ipairs(tileInfo) do
    local tile=create("Frame",{Name="Etat_"..entry[1],BackgroundColor3=Color3.fromRGB(24,27,36),
        Position=UDim2.new((i-1)/5,5,0,43),Size=UDim2.new(.2,-10,0,63),BorderSizePixel=0},stateCard)
    corner(tile,9);outline(tile,Color3.fromRGB(65,70,82),1,.3)
    local title=label(tile,entry[2].."  "..entry[1],11,WHITE2,true)
    title.Position=UDim2.fromOffset(8,9);title.Size=UDim2.new(1,-12,0,20)
    local value=label(tile,"OFF",12,MUTED,true)
    value.Position=UDim2.fromOffset(8,31);value.Size=UDim2.new(1,-14,0,22)
    statusTiles[entry[1]]=value
end

-- TELEPORTS : 6 lieux, chercher automatiquement ou memoriser ta position.
local tpage=pages["Teleport"]
local tIntro=section(tpage,"TELEPORTATION  •  MAP",102)
local tStatus=caption(tIntro,"Choisis un lieu. Si la carte ne le reconnait pas, enregistre-le une fois.",44)
tStatus.Size=UDim2.new(1,-32,0,50)
for _,target in ipairs(teleportTargets) do
    local row=section(tpage,target.name,101)
    local go,remember=twoButtons(row,"TELEPORTER","ENREGISTRER ICI",48,
        function()
            local ok,msg=gotoWaypoint(target)
            tStatus.Text=(ok and "OK : " or "INFO : ")..msg
        end,
        function()
            local ok=saveWaypoint(target)
            tStatus.Text=ok and (target.name.." : position memorisee jusqu'au DISABLE")
                or "Personnage introuvable : impossible d'enregistrer"
        end)
    go.TextSize=12
    remember.TextSize=11
end

-- WHEELIE
local wpage=pages["Wheelie"]
local wcard=section(wpage,"AUTO WHEELIE",161)
caption(wcard,"Avance toi-meme ; direction au guidon ou A / D.",46)
local wheelToggle=btn(wcard,"ACTIVER LE WHEELIE",ACCENT)
wheelToggle.Position=UDim2.fromOffset(17,91)
wheelToggle.Size=UDim2.new(1,-34,0,47)
listen(wheelToggle.Activated,function()
    setWheelie(not wheelie.enabled)
end)
local wangleCard=section(wpage,"ANGLE ET SENS",136)
local angleLabel=label(wangleCard,"40°",33,ACCENT,true)
angleLabel.TextXAlignment=Enum.TextXAlignment.Center
angleLabel.Position=UDim2.new(.5,-43,0,37)
angleLabel.Size=UDim2.fromOffset(86,43)
local dec=btn(wangleCard,"− 1°",SURFACE2)
dec.Position=UDim2.fromOffset(17,43)
dec.Size=UDim2.fromOffset(106,37)
local inc=btn(wangleCard,"+ 1°",SURFACE2)
inc.Position=UDim2.new(1,-123,0,43)
inc.Size=UDim2.fromOffset(106,37)
listen(dec.Activated,function()wheelie.angle=math.max(0,wheelie.angle-1)end)
listen(inc.Activated,function()wheelie.angle=math.min(80,wheelie.angle+1)end)
local sens=btn(wangleCard,"SENS : NORMAL",SURFACE2)
sens.Position=UDim2.fromOffset(17,88)
sens.Size=UDim2.new(1,-34,0,34)
listen(sens.Activated,function()wheelie.sense=-wheelie.sense end)

-- MONEY MAKER
local mpage=pages["Money Maker"]
local mcard=section(mpage,"MS13 MONEY MAKER",164)
caption(mcard,"Montee limitee a 220 studs, puis chute libre.",42)
local flyState=caption(mcard,"Statut : pret",72)
local flyToggle=btn(mcard,"MONTER AVEC LA TROTTINETTE",ACCENT)
flyToggle.Position=UDim2.fromOffset(17,107)
flyToggle.Size=UDim2.new(1,-34,0,42)
listen(flyToggle.Activated,function()
    if not startFlight() then
        flyState.Text="Assieds-toi sur la trottinette / pas de plafond libre."
    end
end)
local tricks=section(mpage,"FIGURES EN L'AIR",103)
local names={"BACKFLIP","FRONTFLIP","360°"}
for i,v in ipairs(names) do
    local b=btn(tricks,v,SURFACE2)
    b.Size=UDim2.new(1/3,-15,0,41)
    b.Position=UDim2.new((i-1)/3,17-(i-1)*2/3,0,47)
    listen(b.Activated,function()
        if not startSpin(v=="360°" and "360" or (v=="BACKFLIP" and "Backflip" or "Frontflip")) then
            flyState.Text="Lance d'abord la montee pour faire une figure."
        end
    end)
end

local pizzaCard=section(mpage,"MONEY MAKER 2  •  PIZZA DELIVERY (BETA)",157)
local pizzaInfo=caption(pizzaCard,"Tentative de commandes et livraisons via les interactions du jeu.",36)
pizzaInfo.Size=UDim2.new(1,-34,0,42)
local pizzaState=caption(pizzaCard,"Statut : pret",77)
pizzaState.Size=UDim2.new(1,-34,0,21)
local pizzaButton=btn(pizzaCard,"DEMARRER AUTO PIZZA",SURFACE2)
pizzaButton.Position=UDim2.fromOffset(17,108)
pizzaButton.Size=UDim2.new(1,-34,0,37)
listen(pizzaButton.Activated,function() setPizza(not pizza.enabled) end)

-- BOOST : V7 source unchanged, new controls call API.
local bpage=pages["Boost"]
local bcard=section(bpage,"BOOST V7.02",100)
local boostToggle=btn(bcard,"BOOST : ON",GREEN2)
boostToggle.Position=UDim2.fromOffset(17,45)
boostToggle.Size=UDim2.new(1,-34,0,40)
listen(boostToggle.Activated,function()api.setBoost(not api.getState().enabled)end)
local modesCard=section(bpage,"MODE DE VITESSE",107)
local modes={"ECO","SPORT","RACE","PERSO"}
local modeColors={ECO=Color3.fromRGB(42,184,106),SPORT=Color3.fromRGB(226,61,70),RACE=Color3.fromRGB(255,129,36),PERSO=Color3.fromRGB(159,92,235)}
local modeSpeeds={ECO="55",SPORT="80",RACE="125",PERSO="0-200"}
local modeButtons={}
for i,m in ipairs(modes) do
    local b=btn(modesCard,m.."  "..modeSpeeds[m],modeColors[m])
    b.Size=UDim2.new(.25,-14,0,40)
    b.Position=UDim2.new((i-1)*.25,14+(i-1)*1/4,0,50)
    modeButtons[m]=b
    listen(b.Activated,function()api.setMode(m)end)
end
local sliderCard=section(bpage,"LIMITE PERSO 0 - 200 (studs/s)",116)
local amount=label(sliderCard,"125 / 200",14,ACCENT,true)
amount.Position=UDim2.new(1,-98,0,15)
amount.Size=UDim2.fromOffset(81,23)
amount.TextXAlignment=Enum.TextXAlignment.Right
local track=create("Frame",{BackgroundColor3=Color3.fromRGB(67,69,83),BorderSizePixel=0,
    Active=true,Size=UDim2.new(1,-42,0,11),Position=UDim2.fromOffset(21,67)},sliderCard)
corner(track,7)
local fill=create("Frame",{BackgroundColor3=ACCENT,BorderSizePixel=0,
    Size=UDim2.fromScale(125/200,1)},track)
corner(fill,7)
local knob=btn(track,"",WHITE2)
knob.AnchorPoint=Vector2.new(.5,.5)
knob.Position=UDim2.fromScale(125/200,.5)
knob.Size=UDim2.fromOffset(23,23)
corner(knob,12)
local draggingSlider=false
local sliderType=nil
local function slideAt(x)
    local width=track.AbsoluteSize.X
    if width<=0 then return end
    local portion=math.clamp((x-track.AbsolutePosition.X)/width,0,1)
    api.setPersonal(math.floor(portion*200+.5))
end
local function beginSlide(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        draggingSlider=true
        sliderType=input.UserInputType
        slideAt(input.Position.X)
    end
end
listen(track.InputBegan,beginSlide)
listen(knob.InputBegan,beginSlide)
listen(UIS2.InputChanged,function(input)
    if not draggingSlider then return end
    if sliderType==Enum.UserInputType.Touch and input.UserInputType==Enum.UserInputType.Touch then
        slideAt(input.Position.X)
    elseif sliderType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement then
        slideAt(input.Position.X)
    end
end)
listen(UIS2.InputEnded,function(input)
    if draggingSlider and input.UserInputType==sliderType then draggingSlider=false end
end)
local gripCard=section(bpage,"STABILITE",86)
local gripToggle=btn(gripCard,"ANTI-DERAPAGE : ON",Color3.fromRGB(37,137,220))
gripToggle.Position=UDim2.fromOffset(17,41)
gripToggle.Size=UDim2.new(1,-34,0,33)
listen(gripToggle.Activated,function()api.setGrip(not api.getState().grip)end)

-- POLICE LOOK
local ppage=pages["Police Look"]
local pcard=section(ppage,"POLICE LOOK V7.02",179)
caption(pcard,"Contours rouges pour les vehicules de police charges dans le jeu.",47)
caption(pcard,"Portee du moteur V7.02 : 900 studs.",78)
local policeToggle=btn(pcard,"POLICE LOOK : OFF",SURFACE2)
policeToggle.Position=UDim2.fromOffset(17,121)
policeToggle.Size=UDim2.new(1,-34,0,42)
listen(policeToggle.Activated,function()api.setPolice(not api.getState().police)end)

-- DETACHER CHAQUE MODULE : une fenetre independante et mobile.
local updatePinned
local pinned={}
local floatWindows={}
local pinLetters={Boost="B",Wheelie="W",["Money Maker"]="$",Teleport="T",["Police Look"]="P"}
local pinLetters={Boost="B",Wheelie="W",["Money Maker"]="$",Teleport="T",["Police Look"]="P"}
local toggleFloating
toggleFloating=function(name)
    local page=pages[name]
    if not page then return end
    if floatWindows[name] then
        local f=floatWindows[name]
        page.Parent=pagesArea
        page.Size=UDim2.fromScale(1,1)
        page.Position=UDim2.fromOffset(0,0)
        f:Destroy()
        floatWindows[name]=nil
        pageSwitch(name)
        return
    end
    local f=create("Frame",{Name="Flottant_"..name,BackgroundColor3=BG,
        BorderSizePixel=0,Size=UDim2.fromOffset(390,365),
        Position=UDim2.new(.5,-195,.24,0),Active=true},ui)
    corner(f,15)
    outline(f,ACCENT,2)
    local bar=create("Frame",{BackgroundColor3=Color3.fromRGB(48,30,25),
        BorderSizePixel=0,Size=UDim2.new(1,0,0,45),Active=true},f)
    corner(bar,12)
    local title=label(bar,"KUKIRIN  •  "..name,15,ACCENT,true)
    title.Position=UDim2.fromOffset(12,8)
    title.Size=UDim2.new(1,-110,0,29)
    local restore=btn(bar,"RETOUR",Color3.fromRGB(118,57,29))
    restore.Position=UDim2.new(1,-76,0,7)
    restore.Size=UDim2.fromOffset(69,30)
    local minus=btn(bar,"−",Color3.fromRGB(55,52,59))
    minus.Position=UDim2.new(1,-152,0,7)
    minus.Size=UDim2.fromOffset(32,30)
    local plus=btn(bar,"+",Color3.fromRGB(178,76,24))
    plus.Position=UDim2.new(1,-116,0,7)
    plus.Size=UDim2.fromOffset(32,30)
    local function resize(delta)
        f.Size=UDim2.fromOffset(math.clamp(f.Size.X.Offset+delta,260,680),
            math.clamp(f.Size.Y.Offset+delta,220,600))
    end
    listen(minus.Activated,function()resize(-45)end)
    listen(plus.Activated,function()resize(45)end)
    page.Parent=f
    page.Position=UDim2.fromOffset(10,52)
    page.Size=UDim2.new(1,-20,1,-62)
    page.Visible=true
    floatWindows[name]=f
    local dragging=false
    local startPos,origin,dragKind
    listen(bar.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true;startPos=input.Position;origin=f.Position;dragKind=input.UserInputType
        end
    end)
    listen(UIS2.InputChanged,function(input)
        if not dragging then return end
        if dragKind==Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.Touch then return end
        if dragKind==Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.MouseMovement then return end
        local d=input.Position-startPos
        f.Position=UDim2.new(origin.X.Scale,origin.X.Offset+d.X,origin.Y.Scale,origin.Y.Offset+d.Y)
    end)
    listen(UIS2.InputEnded,function(input)
        if input.UserInputType==dragKind then dragging=false end
    end)
    listen(restore.Activated,function()
        toggleFloating(name)
        shade.Visible=true
        main.Visible=true
        main.GroupTransparency=0
    end)
    main.Visible=false
    shade.Visible=false
end
for _,name in ipairs({"Teleport","Wheelie","Money Maker","Boost","Police Look"}) do
    local page=pages[name]
    local actions=create("Frame",{Name="ModuleActions",BackgroundTransparency=1,
        Size=UDim2.new(1,-8,0,42),LayoutOrder=-100},page)
    local pin=btn(actions,"EPINGLER",Color3.fromRGB(178,76,24))
    pin.Size=UDim2.new(.48,-4,1,-2)
    local floating=btn(actions,"AFFICHER SUR L'ECRAN",Color3.fromRGB(115,48,22),ACCENT)
    floating.Position=UDim2.new(.5,4,0,0)
    floating.Size=UDim2.new(.5,-4,1,-2)
    floating.TextSize=11
    listen(pin.Activated,function()
        updatePinned(name,not pinned[name])
        pin.Text=pinned[name] and "DESEPINGLER" or "EPINGLER"
    end)
    listen(floating.Activated,function()
        if floatWindows[name] then
            floatWindows[name].Visible=true
            main.Visible=false
        else
            toggleFloating(name)
        end
    end)
end

-- SAVE ALL : fichier local si disponible (pas de garantie de persistance selon executant).
local SAVE_PATH="KuKurinHub_V5_Settings.json"
local HttpService2=game:GetService("HttpService")
local saveCard=section(home,"SAUVEGARDE",94)
local saveAll=btn(saveCard,"SAVE ALL",Color3.fromRGB(209,95,28))
saveAll.Position=UDim2.fromOffset(16,43)
saveAll.Size=UDim2.new(1,-32,0,36)
local function saveSettings()
    if type(writefile)~="function" then return false,"Sauvegarde fichier non disponible" end
    local st=api.getState()
    local data={mode=st.mode,personal=st.personal,boost=st.enabled,grip=st.grip,
        police=st.police,wheelAngle=wheelie.angle,wheelSense=wheelie.sense,pinned=pinned}
    local ok,err=pcall(function()writefile(SAVE_PATH,HttpService2:JSONEncode(data))end)
    return ok,ok and "Preferences enregistrees" or tostring(err)
end
listen(saveAll.Activated,function()
    local ok,msg=saveSettings()
    saveAll.Text=ok and "SAVE ALL : OK" or "SAVE ALL : INDISPONIBLE"
    task.delay(2,function()if alive then saveAll.Text="SAVE ALL" end end)
end)
local function loadSettings()
    if type(readfile)~="function" then return end
    local ok,data=pcall(function()return HttpService2:JSONDecode(readfile(SAVE_PATH))end)
    if not ok or type(data)~="table" then return end
    if type(data.personal)=="number" then api.setPersonal(math.clamp(data.personal,0,200))end
    if type(data.mode)=="string" then api.setMode(data.mode)end
    if type(data.grip)=="boolean" then api.setGrip(data.grip)end
    if type(data.police)=="boolean" then api.setPolice(data.police)end
    if type(data.boost)=="boolean" then api.setBoost(data.boost)end
    if type(data.wheelAngle)=="number" then wheelie.angle=math.clamp(data.wheelAngle,0,85)end
    if data.wheelSense==1 or data.wheelSense==-1 then wheelie.sense=data.wheelSense end
    if type(data.pinned)=="table" then
        for name,value in pairs(data.pinned) do
            if pinLetters[name] and value then updatePinned(name,true) end
        end
    end
end
loadSettings()

-- RESET and DISABLE. Reset changes settings, does not unload the GUI.
local footer=create("Frame",{BackgroundColor3=BG,BorderSizePixel=0,
    Position=UDim2.fromOffset(14,385),Size=UDim2.fromOffset(158,40)},main)
local reset=btn(footer,"RESET",SURFACE2)
reset.Size=UDim2.fromOffset(71,34)
reset.Position=UDim2.fromOffset(1,1)
local disable=btn(footer,"DISABLE",Color3.fromRGB(116,37,51))
disable.Size=UDim2.fromOffset(80,34)
disable.Position=UDim2.fromOffset(77,1)

-- Vrai layout adaptatif : sur telephone, onglets defilants sur une ligne,
-- contenu plus large et texte lisible au lieu d'un minuscule panneau desktop.
local function adaptLayout()
    if not alive then return end
    local camera=Workspace2.CurrentCamera
    local vp=camera and camera.ViewportSize or Vector2.new(1280,720)
    if vp.X<720 then
        main.Size=UDim2.fromOffset(430,560)
        side.Position=UDim2.fromOffset(10,70)
        side.Size=UDim2.fromOffset(410,56)
        side.ScrollingDirection=Enum.ScrollingDirection.X
        side.ScrollBarThickness=2
        side.ScrollBarImageColor3=ACCENT
        side.CanvasSize=UDim2.fromOffset(#menuNames*122+10,0)
        pagesArea.Position=UDim2.fromOffset(12,138)
        pagesArea.Size=UDim2.fromOffset(406,350)
        footer.Position=UDim2.fromOffset(14,503)
        for i,name in ipairs(menuNames) do
            local n=navButtons[name]
            n.Size=UDim2.fromOffset(112,39)
            n.Position=UDim2.fromOffset(10+(i-1)*122,7)
            n.TextSize=12
        end
        welcome.Size=UDim2.fromOffset(273,34)
        welcome.TextSize=19
        by.Size=UDim2.fromOffset(270,24)
    else
        main.Size=UDim2.fromOffset(790,475)
        side.Position=UDim2.fromOffset(12,73)
        side.Size=UDim2.fromOffset(185,388)
        side.ScrollingDirection=Enum.ScrollingDirection.Y
        side.ScrollBarThickness=0
        side.CanvasSize=UDim2.fromOffset(0,0)
        pagesArea.Position=UDim2.fromOffset(189,72)
        pagesArea.Size=UDim2.fromOffset(485,351)
        footer.Position=UDim2.fromOffset(14,385)
        for i,name in ipairs(menuNames) do
            local n=navButtons[name]
            n.Position=UDim2.fromOffset(11,12+(i-1)*49)
            n.Size=UDim2.fromOffset(161,43)
            n.TextSize=13
        end
        welcome.Size=UDim2.fromOffset(330,34)
        welcome.TextSize=23
        by.Size=UDim2.fromOffset(360,23)
    end
    adaptScale()
end
adaptLayout()
listen(Workspace2:GetPropertyChangedSignal("CurrentCamera"),adaptLayout)
if Workspace2.CurrentCamera then
    listen(Workspace2.CurrentCamera:GetPropertyChangedSignal("ViewportSize"),adaptLayout)
end

-- Les raccourcis ne sont crees que lorsqu'un module est epingle.
local pinButtons={}
local enableDrag
local pinLetters={Boost="B",Wheelie="W",["Money Maker"]="$",Teleport="T",["Police Look"]="P"}
updatePinned=function(name, enabled)
    pinned[name]=enabled or nil
    if pinButtons[name] then pinButtons[name]:Destroy();pinButtons[name]=nil end
    if enabled then
        local shortcut=btn(ui,pinLetters[name],Color3.fromRGB(35,31,29),ACCENT)
        shortcut.Name="Epingle_"..name:gsub("%s","")
        shortcut.Size=UDim2.fromOffset(48,46)
        shortcut.Position=UDim2.new(1,-66,.18+(#menuNames*0),0)
        shortcut.TextSize=21
        corner(shortcut,13)
        outline(shortcut,ACCENT,1.5)
        pinButtons[name]=shortcut
        if enableDrag then enableDrag(shortcut,shortcut,true) end
        listen(shortcut.Activated,function()
            if floatWindows[name] then
                floatWindows[name].Visible=not floatWindows[name].Visible
            else
                toggleFloating(name)
            end
        end)
    end
    local i=0
    for _,k in ipairs({"Boost","Wheelie","Money Maker","Teleport","Police Look"}) do
        if pinButtons[k] then
            i=i+1
            if not pinPositions or not pinPositions[k] then
                pinButtons[k].Position=UDim2.new(1,-66,.16,(i-1)*56)
            end
        end
    end
end
local mini=btn(ui,"K",Color3.fromRGB(37,31,46),ACCENT)
mini.Name="KuKurinRoundOpen"
mini.Size=UDim2.fromOffset(59,59)
mini.Position=UDim2.new(1,-74,.43,0)
mini.TextSize=27
mini.Visible=false
corner(mini,30)
outline(mini,ACCENT,2)
local miniTag=label(mini,"KH",9,ACCENT,true)
miniTag.Size=UDim2.new(1,0,0,15)
miniTag.Position=UDim2.fromOffset(0,39)
miniTag.TextXAlignment=Enum.TextXAlignment.Center
local preview=create("CanvasGroup",{BackgroundColor3=BG,Size=UDim2.fromOffset(372,234),
    AnchorPoint=Vector2.new(.5,.5), Position=UDim2.fromScale(.5,.5),
    GroupTransparency=1,Visible=true},ui)
corner(preview,21)
outline(preview,ACCENT,1.5,.15)
local startGradient=Instance.new("UIGradient")
startGradient.Color=ColorSequence.new({
    ColorSequenceKeypoint.new(0,Color3.fromRGB(60,30,18)),
    ColorSequenceKeypoint.new(.55,Color3.fromRGB(23,24,39)),
    ColorSequenceKeypoint.new(1,Color3.fromRGB(65,30,16))})
startGradient.Rotation=18
startGradient.Parent=preview
local pvScale=create("UIScale",{Scale=.78},preview)
local pvAvatar=create("ImageLabel",{Name="ProfileHD",BackgroundColor3=SURFACE2,
    Image="",Position=UDim2.fromOffset(141,16),Size=UDim2.fromOffset(90,90),
    ScaleType=Enum.ScaleType.Crop},preview)
corner(pvAvatar,45)
outline(pvAvatar,ACCENT,2)
local pvIcon=label(pvAvatar,"K",49,ACCENT,true)
pvIcon.TextXAlignment=Enum.TextXAlignment.Center
pvIcon.Size=UDim2.fromScale(1,1)
local pvTitle=label(preview,"KUKURIN HUB",26,WHITE2,true)
pvTitle.TextXAlignment=Enum.TextXAlignment.Center
pvTitle.Position=UDim2.fromOffset(0,113)
pvTitle.Size=UDim2.fromOffset(372,35)
local pvBy=label(preview,"Bienvenue  •  by Mmss_212",14,MUTED)
pvBy.TextXAlignment=Enum.TextXAlignment.Center
pvBy.Position=UDim2.fromOffset(0,156)
pvBy.Size=UDim2.fromOffset(372,27)
local pvSubtitle=label(preview,"V7.02  •  CONTROL SYSTEM",11,ACCENT,true)
pvSubtitle.TextXAlignment=Enum.TextXAlignment.Center
pvSubtitle.Position=UDim2.fromOffset(0,194)
pvSubtitle.Size=UDim2.fromOffset(372,23)

local function openPanel()
    if not alive then return end
    shade.Visible=true
    main.Visible=true
    mini.Visible=false
    horizontalBar.Visible=false
    main.GroupTransparency=1
    tween(main,.25,{GroupTransparency=0},Enum.EasingStyle.Back)
end
local function closePanel()
    if not alive then return end
    shade.Visible=false
    main.Visible=false
    mini.Visible=true
    horizontalBar.Visible=false
end
listen(xbtn.Activated,closePanel)
listen(minimizeMain.Activated,function()
    main.Visible=false
    shade.Visible=false
    mini.Visible=false
    horizontalBar.Visible=true
end)
listen(barRestore.Activated,openPanel)
listen(barClose.Activated,function()
    horizontalBar.Visible=false
    mini.Visible=true
end)
local suppressClick=false
enableDrag=function(target,handle,isMini)
    local dragging=false
    local start,initial,dragType=nil,nil,nil
    listen(handle.InputBegan,function(input)
        if input.UserInputType~=Enum.UserInputType.MouseButton1
          and input.UserInputType~=Enum.UserInputType.Touch then return end
        dragging=true
        start=input.Position
        initial=target.Position
        dragType=input.UserInputType
        if isMini then suppressClick=false end
    end)
    listen(UIS2.InputChanged,function(input)
        if not dragging then return end
        if dragType==Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.Touch then return end
        if dragType==Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.MouseMovement then return end
        local d=input.Position-start
        if isMini and d.Magnitude>9 then suppressClick=true end
        target.Position=UDim2.new(initial.X.Scale,initial.X.Offset+d.X,
            initial.Y.Scale,initial.Y.Offset+d.Y)
    end)
    listen(UIS2.InputEnded,function(input)
        if dragging and input.UserInputType==dragType then dragging=false end
    end)
end
enableDrag(main,top,false)
enableDrag(horizontalBar,horizontalBar,false)
enableDrag(mini,mini,true)
for _,button in pairs(pinButtons) do enableDrag(button,button,true) end
listen(mini.Activated,function()
    if suppressClick then suppressClick=false;return end
    openPanel() -- Intentionally no welcome animation here.
end)
listen(reset.Activated,function()
    setPizza(false)
    setWheelie(false)
    endFlight()
    wheelie.angle=40
    wheelie.sense=1
    api.setPolice(false)
    api.setGrip(true)
    api.setMode("RACE")
    api.setPersonal(125) -- personal setting preserved at default, RACE restored below.
    api.setMode("RACE")
    api.setBoost(true)
    pageSwitch("Accueil")
end)
local function cleanupEverything()
    if not alive then return end
    alive=false
    setPizza(false)
    setWheelie(false)
    endFlight()
    table.clear(waypoints)
    for _,button in pairs(pinButtons) do pcall(function()button:Destroy()end)end
    for _, c in ipairs(connections2) do pcall(function()c:Disconnect()end) end
    if ui then pcall(function()ui:Destroy()end) end
    pcall(api.stop)
    env2.KuKirinLegacyAPI=nil
    env2.KuKirinUnifiedCleanup=nil
    env2.KuKirinHubCleanup=nil
end
env2.KuKirinUnifiedCleanup=cleanupEverything
env2.KuKirinHubCleanup=cleanupEverything
listen(disable.Activated,cleanupEverything)

local function refreshUI()
    local st=api.getState()
    boostToggle.Text=st.enabled and "BOOST : ON" or "BOOST : OFF"
    boostToggle.BackgroundColor3=st.enabled and GREEN2 or SURFACE2
    gripToggle.Text=st.grip and "STABILITE : ON" or "STABILITE : OFF"
    gripToggle.BackgroundColor3=st.grip and Color3.fromRGB(35,153,222) or Color3.fromRGB(110,111,121)
    policeToggle.Text=st.police and "POLICE LOOK : ON" or "POLICE LOOK : OFF"
    policeToggle.BackgroundColor3=st.police and RED2 or SURFACE2
    wheelToggle.Text=wheelie.enabled and "DESACTIVER LE WHEELIE" or "ACTIVER LE WHEELIE"
    wheelToggle.BackgroundColor3=wheelie.enabled and GREEN2 or ACCENT
    angleLabel.Text=tostring(wheelie.angle).."°"
    sens.Text=wheelie.sense==1 and "SENS : NORMAL" or "SENS : INVERSE"
    amount.Text=tostring(st.personal).." / 200"
    local alpha=st.personal/200
    fill.Size=UDim2.fromScale(alpha,1)
    knob.Position=UDim2.fromScale(alpha,.5)
    for modeName,b in pairs(modeButtons) do
        b.BackgroundColor3=modeColors[modeName]
        b.BackgroundTransparency=(modeName==st.mode) and 0 or .38
        b.TextColor3=WHITE2
    end
    if flight.phase=="ascend" then
        flyState.Text="Statut : montee en cours"
        flyToggle.Text="ARRETER LA MONTEE"
    elseif flight.phase=="fall" then
        flyState.Text="Statut : chute libre / atterrissage doux"
        flyToggle.Text="EN VOL"
    else
        flyState.Text="Statut : pret"
        flyToggle.Text="MONTER AVEC LA TROTTINETTE"
    end
    pizzaButton.Text=pizza.enabled and "STOP AUTO PIZZA" or "DEMARRER AUTO PIZZA"
    pizzaButton.BackgroundColor3=pizza.enabled and GREEN2 or SURFACE2
    pizzaState.Text="Statut : "..pizza.status
    if statusTiles then
        local states={Boost=st.enabled,Wheelie=wheelie.enabled,["Money Maker"]=flight.phase~="idle",Police=st.police,Pizza=pizza.enabled}
        for name,widget in pairs(statusTiles) do
            local on=states[name]
            widget.Text=on and "ON" or (name=="Money Maker" and "PRÊT" or "OFF")
            widget.TextColor3=on and GREEN2 or (name=="Money Maker" and ACCENT or MUTED)
        end
    end
    overview.Text=(st.enabled and "Boost ON" or "Boost OFF")..
        (wheelie.enabled and "  •  Wheelie ON" or "  •  Wheelie OFF")..
        (flight.phase~="idle" and "  •  En vol" or "  •  Money Maker pret")..
        (st.police and "  •  Police ON" or "  •  Police OFF")..
        (pizza.enabled and "  •  Pizza ON" or "  •  Pizza OFF")
end
listen(RunService2.Heartbeat,function(dt)
    if not alive then return end
    dt=math.clamp(dt,0,.08)
    updateFlight(dt)
    updateWheelie(dt)
    local now=os.clock()
    if now-lastRefresh>.15 then
        lastRefresh=now
        refreshUI()
    end
end)

-- Avatar HD charge via Roblox : pas de vieux screenshot pixelise.
-- La miniature Roblox depend du nom d'utilisateur et de sa disponibilite.
task.spawn(function()
    local success,url=pcall(function()
        local uid=Players2.LocalPlayer.UserId
        return Players2:GetUserThumbnailAsync(uid,Enum.ThumbnailType.HeadShot,
            Enum.ThumbnailSize.Size420x420)
    end)
    if alive and success and url and avatar.Parent and pvAvatar.Parent then
        avatar.Image=url
        avatarFallback.Visible=false
        pvAvatar.Image=url
        pvIcon.Visible=false
    end
end)

-- Intro exactly once after executing. A reopen uses openPanel directly.
task.spawn(function()
    if not alive then return end
    tween(preview,.43,{GroupTransparency=0})
    tween(pvScale,.66,{Scale=1},Enum.EasingStyle.Back)
    tween(startGradient,1.7,{Rotation=66})
    task.wait(1.7)
    if not alive then return end
    tween(preview,.36,{GroupTransparency=1})
    tween(pvScale,.36,{Scale=1.07})
    task.wait(.40)
    if not alive then return end
    preview.Visible=false
    openedOnce=true
    openPanel()
end)
print("KuKurinHub UNIFIE V2 TEST: V7.02, boost, police, anti-derapage, wheelie, figures, pizza beta et 6 teleports")
end)()