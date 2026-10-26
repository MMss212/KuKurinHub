-- KuKurinHub V8 | chargeur Xeno PC et Delta mobile
-- Choisit le fichier selon le type d'appareil.
local UIS = game:GetService("UserInputService")
local env = (getgenv and getgenv()) or _G
local base = "https://raw.githubusercontent.com/MMss212/KuKurinHub/main/"
local file = (UIS.TouchEnabled and not UIS.KeyboardEnabled)
    and "KuKurinHub_V8_DELTA_MOBILE.lua"
    or "KuKurinHub_V8_XENO_PC.lua"
local ok, source = pcall(function() return game:HttpGet(base .. file) end)
if not ok or type(source) ~= "string" or source == "" then
    warn("KuKurinHub V8 : téléchargement impossible", source)
    return
end
local fn, err = loadstring(source)
if not fn then
    warn("KuKurinHub V8 : erreur de syntaxe", err)
    return
end
local success, runtimeError = pcall(fn)
if not success then warn("KuKurinHub V8 : erreur d'exécution", runtimeError) end
