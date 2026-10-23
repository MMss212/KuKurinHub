-- KuKirin Hub V7.02 - Chargeur distant officiel
-- Ce fichier sera heberge sur GitHub; partage uniquement la ligne indiquee dans le README.
local env = (getgenv and getgenv()) or _G
local BASE = "https://raw.githubusercontent.com/MMss212/KuKirinHub/main/"
local CODE_FILE = "KuKirin_Hub_V7_02.lua"
local CHECK_SECONDS = 60

-- Eviter les chargeurs simultanes.
if type(env.KuKirinHubRemoteStop) == "function" then
    pcall(env.KuKirinHubRemoteStop)
end

local active = true
local loadedVersion = nil
local failedControls = 0
local failedCodeChecks = 0

local function stop()
    if not active then return end
    active = false
    if type(env.KuKirinHubCleanup) == "function" then
        pcall(env.KuKirinHubCleanup)
    end
end
env.KuKirinHubRemoteStop = stop

local function fetch(filename)
    local url = BASE .. filename .. "?check=" .. tostring(math.floor(os.clock() * 1000))
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if not ok or type(body) ~= "string" or #body == 0 then
        return nil
    end
    if body:find("<html", 1, true) then return nil end
    return body
end

local function readControl()
    local data = fetch("control.txt")
    if not data then return nil, nil end
    local state, version = data:match("^%s*(%u+)%s*|%s*([^%s]+)")
    if (state ~= "ON" and state ~= "OFF") or not version then
        return nil, nil
    end
    return state, version
end

local function runMain(version)
    local code = fetch(CODE_FILE)
    if not code then return false end
    local compileOk, fn = pcall(loadstring, code)
    if not compileOk or type(fn) ~= "function" then
        warn("KuKirin Hub : impossible de compiler le nouveau script")
        return false
    end
    local ok, err = pcall(fn)
    if not ok then
        warn("KuKirin Hub : erreur de chargement", err)
        return false
    end
    loadedVersion = version
    return true
end

-- Demarrage : le createur peut couper le Hub avec OFF|7.02.0.
local state, version = readControl()
if state ~= "ON" then
    warn("KuKirin Hub : indisponible ou desactive par le createur")
    stop()
    return
end
if not runMain(version) then
    warn("KuKirin Hub : fichier principal indisponible")
    stop()
    return
end

-- Mise a jour des sessions actives, et arret a distance.
task.spawn(function()
    local polls = 0
    while active do
        task.wait(CHECK_SECONDS)
        if not active then break end
        polls = polls + 1

        local newState, newVersion = readControl()
        if newState == "OFF" then
            warn("KuKirin Hub : desactive par le createur")
            stop()
            break
        elseif newState == "ON" then
            failedControls = 0
            if newVersion ~= loadedVersion then
                runMain(newVersion)
            end
        else
            failedControls = failedControls + 1
            if failedControls >= 3 then
                warn("KuKirin Hub : serveur de controle inaccessible")
                stop()
                break
            end
        end

        -- Si le fichier principal disparait mais control.txt reste ON,
        -- on peut aussi arreter les anciennes sessions apres deux controles rates.
        if active and polls % 5 == 0 then
            if fetch(CODE_FILE) then
                failedCodeChecks = 0
            else
                failedCodeChecks = failedCodeChecks + 1
                if failedCodeChecks >= 2 then
                    warn("KuKirin Hub : fichier principal supprime ou indisponible")
                    stop()
                    break
                end
            end
        end
    end
end)
