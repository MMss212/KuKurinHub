-- KuKirin Hub V7.02 | Loader corrigé

local env = (getgenv and getgenv()) or _G
local BASE = "https://raw.githubusercontent.com/MMss212/KuKurinHub/main/"
local active = true
local loadedVersion = nil

local function fetch(name)
    local ok, result = pcall(function()
        return game:HttpGet(BASE .. name)
    end)

    if not ok or type(result) ~= "string"
        or result == "" or result:find("<html", 1, true) then
        warn("KuKirin : téléchargement impossible", name, result)
        return nil
    end

    return result
end

local function readControl()
    local data = fetch("control.txt")
    if not data then return nil, nil end

    local state, version =
        data:match("^%s*(%u+)%s*|%s*([^%s]+)")

    if state ~= "ON" and state ~= "OFF" then
        warn("KuKirin : contrôle invalide", data)
        return nil, nil
    end

    return state, version
end

local function stop()
    if not active then return end
    active = false

    if type(env.KuKirinHubCleanup) == "function" then
        pcall(env.KuKirinHubCleanup)
    end
end

local function prepare()
    local code = fetch("KuKirin_Hub_V7_02.lua")
    if not code then return nil end

    local fn, err = loadstring(code)
    if not fn then
        warn("KuKirin : erreur Lua", err)
    end

    return fn
end

local state, version = readControl()

if not state then
    warn("KuKirin : connexion impossible, ancien menu conservé")
    return
end

if state == "OFF" then
    local oldStop = env.KuKirinHubRemoteStop
    if type(oldStop) == "function" then
        pcall(oldStop)
    elseif type(env.KuKirinHubCleanup) == "function" then
        pcall(env.KuKirinHubCleanup)
    end
    warn("KuKirin : désactivé par le créateur")
    return
end

local fn = prepare()

if not fn then
    warn("KuKirin : fichier inaccessible, ancien menu conservé")
    return
end

local oldStop = env.KuKirinHubRemoteStop
if type(oldStop) == "function" then
    pcall(oldStop)
end

local ok, err = pcall(fn)

if not ok then
    warn("KuKirin : erreur du script", err)
    return
end

loadedVersion = version
env.KuKirinHubRemoteStop = stop

print("KuKirin Hub chargé ! Version : " .. version)

task.spawn(function()
    while active do
        task.wait(60)
        if not active then break end

        local newState, newVersion = readControl()

        if newState == "OFF" then
            warn("KuKirin : arrêt à distance")
            stop()
            break
        end

        if newState == "ON"
            and newVersion ~= loadedVersion then

            local nextFn = prepare()

            if nextFn then
                local success, errorMessage = pcall(nextFn)

                if success then
                    loadedVersion = newVersion
                    print("KuKirin mis à jour : " .. newVersion)
                else
                    warn("KuKirin : échec mise à jour", errorMessage)
                end
            end
        end
    end
end)
