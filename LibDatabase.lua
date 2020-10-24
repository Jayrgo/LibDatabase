local _NAME = "LibDatabase"
local _VERSION = "1.0.0"
local _LICENSE = [[
    MIT License

    Copyright (c) 2020 Jayrgo

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
]]

assert(LibMan1, format("%s requires LibMan-1.x.x.", _NAME))
assert(LibMan1:Exists("LibCallback", 1), format("%s requires LibCallback-1.x.x.", _NAME))
assert(LibMan1:Exists("LibMixin", 1), format("%s requires LibMixin-1.x.x.", _NAME))
assert(LibMan1:Exists("LibEvent", 1), format("%s requires LibEvent-1.x.x.", _NAME))

local LibDatabase --[[ , oldVersion ]] = LibMan1:New(_NAME, _VERSION, "_LICENSE", _LICENSE)
if not LibDatabase then return end

LibDatabase.dbs = LibDatabase.dbs or {}
local dbs = LibDatabase.dbs

local CHAR_KEY = UnitName("player") .. " - " .. GetRealmName()

---@class Database
local DatabaseMixin = {}

local next = next
local pairs = pairs
local type = type

---@param profile table
---@param defaults table
local function removeDefaults(profile, defaults)
    if type(profile) ~= "table" or type(defaults) ~= "table" then return end

    for k, v in pairs(profile) do
        if type(v) == "table" and type(defaults[k]) == "table" then
            removeDefaults(v, defaults[k])
            if not next(v) then profile[k] = nil end
        elseif v == defaults[k] then
            profile[k] = nil
        end
    end
end

function DatabaseMixin:Save()
    for profileKey, profile in pairs(self.profiles) do
        removeDefaults(profile, self.defaults)
        if not next(profile) then self.profiles[profileKey] = nil end
    end
    removeDefaults(self.globals, self.defaults_globals)

    _G[self.variableName] = {
        profileKeys = self.profileKeys,
        profiles = self.profiles,
        globals = self.globals,
        lastChangeTime = self.lastChangeTime,
        lastChangeChar = self.lastChangeChar,
    }
end

---@param self Database
local function PLAYER_LOGOUT(self) if self.restored then self:Save() end end

local GetServerTime = GetServerTime

---@param self Database
local function setLastChange(self)
    self.lastChangeTime = GetServerTime()
    self.lastChangeChar = CHAR_KEY
end

local wipe = wipe
local CopyTable = CopyTable

---@param self Database
local function Restore(self)
    local profileKeys, profiles, globals

    if type(_G[self.variableName]) == "table" then
        profileKeys = _G[self.variableName].profileKeys
        profiles = _G[self.variableName].profiles
        globals = _G[self.variableName].globals

        self.lastChangeTime = _G[self.variableName].lastChangeTime
        self.lastChangeChar = _G[self.variableName].lastChangeChar

        wipe(_G[self.variableName])
    end

    self.lastChangeTime = type(self.lastChangeTime) == "number" and self.lastChangeTime or GetServerTime()
    self.lastChangeChar = type(self.lastChangeChar) == "string" and self.lastChangeChar or CHAR_KEY

    for char, key in pairs(type(profileKeys) == "table" and profileKeys or {}) do
        if type(char) == "string" and type(key) == "string" then self.profileKeys[char] = key end
    end

    for key, data in pairs(type(profiles) == "table" and profiles or {}) do
        if type(key) == "string" and type(data) == "table" then self.profiles[key] = CopyTable(data) end
    end

    for k, v in pairs(type(globals) == "table" and globals or {}) do
        if type(k) == "string" then
            if type(v) == "table" then
                self.globals[k] = CopyTable(v)
            else
                self.globals[k] = v
            end
        end
    end

    self.restored = true

    self:SetProfile(self.profileKeys[CHAR_KEY] or self.defaultProfile)
end

local LibEvent = LibMan1:Get("LibEvent", 1)

---@param self Database
---@param addonName string
local function ADDON_LOADED(self, addonName)
    if addonName == self.addonName then
        LibEvent:Unregister("ADDON_LOADED", ADDON_LOADED, self)

        Restore(self)
    end
end

local LibCallback = LibMan1:Get("LibCallback", 1)
local IsAddOnLoaded = IsAddOnLoaded

function DatabaseMixin:OnLoad()
    self.OnLoad = nil

    self.callbacks = self.callbacks or LibCallback:New(self)

    self.defaults = self.defaults or {}
    self.db = {}
    self.profileKeys = {}
    self.profiles = {}
    self.defaults_globals = self.defaults_globals or {}
    self.globals = {}

    LibEvent:Register("PLAYER_LOGOUT", PLAYER_LOGOUT, self)

    local loaded, finished = IsAddOnLoaded(self.addonName)
    if not loaded or not finished then
        LibEvent:Register("ADDON_LOADED", ADDON_LOADED, self)
    else
        Restore(self)
    end

    dbs[self] = true
end

---@param profile table
---@param defaults table
local function copyDefaults(profile, defaults)
    for k, v in pairs(defaults) do
        if type(profile[k]) == "nil" then
            if type(v) == "table" then
                profile[k] = CopyTable(v)
            else
                profile[k] = v
            end
        elseif type(v) == "table" and type(profile[k]) == "table" then
            copyDefaults(profile[k], v)
        end
    end
end

---@param self Database
---@param event string
---@vararg any
local function TriggerEvent(self, event, ...)
    local callbacks = self.callbacks
    callbacks:xTriggerEvent(event, self, ...)
    callbacks:xTriggerEvent("OnChanged", self)
end

local error = error
local format = format

---@param profileKey string
function DatabaseMixin:SetProfile(profileKey)
    if type(profileKey) ~= "string" then
        error(format("Usage: Database:SetProfile(profileKey): 'profileKey' - string expected got %s", type(profileKey),
                     2))
    end

    if self.profile and self.profile == profileKey then return end

    if type(self.profiles[profileKey]) ~= "table" then
        self.profiles[profileKey] = CopyTable(self.defaults)
    else
        copyDefaults(self.profiles[profileKey], self.defaults)
    end
    self.db = self.profiles[profileKey]
    self.profileKeys[CHAR_KEY] = profileKey
    if self.profile then setLastChange(self) end
    self.profile = profileKey
    TriggerEvent(self, "OnProfileChanged", profileKey)
end

---@param profileKey string
function DatabaseMixin:ResetProfile(profileKey)
    if type(profileKey) ~= "string" then
        error(format("Usage: Database:ResetProfile(profileKey): 'profileKey' - string expected got %s",
                     type(profileKey), 2))
    end

    if self.profiles[profileKey] then
        wipe(self.profiles[profileKey])
        self.profiles[profileKey] = CopyTable(self.defaults)
        if self.profile == profileKey then self.db = self.profiles[profileKey] end
    end

    setLastChange(self)

    TriggerEvent(self, "OnProfileReset", profileKey)
end

---@return string
function DatabaseMixin:GetProfile() return self.profile or self.defaultProfile end

---@type table<string, string>
local DEFAULT_PROFILES = {
    ---@type string
    REALM = GetRealmName(),
    ---@type string
    FACTION = UnitFactionGroup("player"),
    ---@type string
    RACE = select(2, UnitRace("player")),
    ---@type string
    CLASS = select(2, UnitClass("player")),
}

---@return string[]
function DatabaseMixin:GetProfiles()
    local profiles = {}

    local addDefault = true
    for key in pairs(self.profiles) do
        profiles[#profiles + 1] = key
        if key == self.defaultProfile then addDefault = false end
    end
    if addDefault then profiles[#profiles + 1] = self.defaultProfile end

    return profiles
end

local tContains = tContains

---@return string[]
function DatabaseMixin:GetUsedProfiles()
    local usedProfiles = {}
    for _, key in pairs(self.profileKeys) do
        if not tContains(usedProfiles, key) then usedProfiles[#usedProfiles + 1] = key end
    end
    return usedProfiles
end

---@return string[]
function DatabaseMixin:GetUnusedProfiles()
    local usedProfiles = self:GetUsedProfiles()
    local unusedProfiles = {}
    for key in pairs(self.profiles) do
        if not tContains(usedProfiles, key) then unusedProfiles[#unusedProfiles + 1] = key end
    end
    return unusedProfiles
end

---@param profileKey string
function DatabaseMixin:DeleteProfile(profileKey)
    if type(profileKey) ~= "string" then
        error(format("Usage: Database:DeleteProfile(profileKey): 'profileKey' - string expected got %s",
                     type(profileKey), 2))
    end

    if self.profile == profileKey then
        error(format("Usage: Database:DeleteProfile(profileKey): 'profileKey' - cannot delete current profile (%s)",
                     profileKey), 2)
    end

    self.profiles[profileKey] = nil
    for char, key in pairs(self.profileKeys) do if key == profileKey then self.profileKeys[char] = nil end end

    setLastChange(self)

    TriggerEvent(self, "OnProfileDeleted", profileKey)
end

---@param from string
function DatabaseMixin:CopyProfile(from)
    if type(from) ~= "string" then
        error(format("Usage: Database:CopyProfile(from): 'from' - string expected got %s", type(from), 2))
    end

    if not self.profiles[from] then
        error(format("Usage: Database:CopyProfile(from): 'from' - cannot find profile (%s)", from), 2)
    end

    local current = self:GetProfile()
    wipe(self.profiles[current])
    --[[ for k, v in pairs(self.profiles[current]) do
        self.profiles[current][k] = nil
    end ]]
    --[[ for k, v in pairs(self.profiles[from]) do
        self.profiles[current][k] = type(v) == "table" and CopyTable(v) or v
    end ]]
    self.profiles[current] = CopyTable(self.profiles[from])
    copyDefaults(self.profiles[current], self.defaults)
    self.db = self.profiles[current]

    setLastChange(self)

    TriggerEvent(self, "OnProfileCopied", from)
end

local tostringall = tostringall

---@vararg any
---@return string
local function coercePath(...) return tostringall(...) end

local validValueTypes = {"boolean", "number", "string", "nil"}
for i = 1, #validValueTypes do validValueTypes[validValueTypes[i]] = true end
local validValueTypesString = table.concat(validValueTypes, ", ", 1, #validValueTypes - 1)
validValueTypesString = format("%s or %s", validValueTypesString, validValueTypes[#validValueTypes])

---@param value any
---@param usage string
local function checkValue(value, usage)
    if not validValueTypes[type(value)] then
        error(format("Usage: %s: 'value' - %s expected got %s", usage, validValueTypesString, type(value)), 3)
    end
end

local select = select

---@param tbl table
---@param value any
---@param path string
---@vararg string
---@return boolean
local function set(tbl, value, path, ...)
    if select("#", ...) > 0 then
        if type(tbl[path]) ~= "table" then tbl[path] = {} end
        return set(tbl[path], value, ...)
    else
        if tbl[path] ~= value then
            tbl[path] = value
            return true
        end
    end
    return false
end

---@param value boolean | number | string | nil
---@param path any
---@vararg any
function DatabaseMixin:SetDefault(value, path, ...)
    checkValue(value, "Database:SetDefault(value, path[, ...])")

    set(self.defaults, value, coercePath(path, ...))

    if self.restored then copyDefaults(self.profiles[self:GetProfile()], self.defaults) end
end

---@param value boolean | number | string | nil
---@param path any
---@vararg any
function DatabaseMixin:SetWithoutResponse(value, path, ...)
    checkValue(value, "Database:SetWithoutResponse(value, path[, ...]")
    if set(self.db, value, coercePath(path, ...)) then setLastChange(self) end
end

---@param value boolean | number | string | nil
---@param path string
---@vararg any
function DatabaseMixin:Set(value, path, ...)
    checkValue(value, "Database:Set(value, path[, ...]")
    if set(self.db, value, coercePath(path, ...)) then
        setLastChange(self)
        TriggerEvent(self, "OnValueChanged", value, coercePath(path, ...))
    end
end

---@param tbl table
---@vararg string
---@return boolean | number | string | nil
local function get(tbl, ...)
    if select("#", ...) > 1 then
        tbl = tbl[(...)]
        if type(tbl) == "table" then return get(tbl, select(2, ...)) end
    else
        return tbl[(...)]
    end
end

---@vararg any
---@return boolean | number | string | nil
function DatabaseMixin:Get(...)
    if self.restored then
        local value = get(self.db, coercePath(...))
        if type(value) ~= "nil" then return value end
    end
    return get(self.defaults, coercePath(...))
end

---@vararg any
function DatabaseMixin:Reset(...) self:Set(get(self.defaults, coercePath(...)), coercePath(...)) end

---@vararg any
---@return boolean | number | string | nil
function DatabaseMixin:GetDefault(...) return get(self.defaults, coercePath(...)) end

local LAST_CHANGE_FORMAT = "|cffcfcfcf%s (%s)|r"
local date = date

---@return string
function DatabaseMixin:GetLastChange()
    return format(LAST_CHANGE_FORMAT, date("%Y-%m-%d %X", self.lastChangeTime), self.lastChangeChar),
           self.lastChangeTime, self.lastChangeChar
end

function DatabaseMixin:Clear()
    local restored = self.restored
    self:Save()
    self.restored = nil
    _G[self.variableName] = nil
    if restored then Restore(self) end
end

---@param value boolean | number | string | nil
---@param path string
---@vararg any
function DatabaseMixin:SetGlobalDefault(value, path, ...)
    checkValue(value, "Database:SetGlobalDefault(value, path[, ...]")

    set(self.defaults_globals, value, coercePath(path, ...))
end

---@vararg any
---@return boolean | number | string | nil
function DatabaseMixin:GetGlobalDefault(...) return get(self.defaults_globals, coercePath(...)) end

---@param value boolean | number | string | nil
---@param path string
---@vararg any
function DatabaseMixin:SetGlobal(value, path, ...)
    checkValue(value, "Database:SetGlobal(value, path[, ...]")

    if set(self.globals, value, coercePath(path, ...)) then
        setLastChange(self)
        TriggerEvent(self, "OnGlobalValueChanged", value, coercePath(path, ...))
    end
end

---@vararg any
---@return boolean | number | string | nil
function DatabaseMixin:GetGlobal(...)
    if self.restored then
        local value = get(self.globals, coercePath(...))
        if type(value) ~= "nil" then return value end
    end
    return get(self.defaults_globals, coercePath(...))
end

---@return boolean
function DatabaseMixin:IsRestored() return self.restored end

local tostring = tostring
local LibMixin = LibMan1:Get("LibMixin")

---@param addonName string
---@param variableName string
---@param defaultProfile string | "\"REALM\"" | "\"FACTION\"" | "\"RACE\"" | "\"CLASS\""
---@return Database
function LibDatabase:New(addonName, variableName, defaultProfile)
    if type(addonName) ~= "string" then
        error(format("Usage: %s:New(addonName, variableName[, defaultProfile]): 'addonName' - string expected got %s",
                     tostring(LibDatabase), type(addonName), 2))
    end
    if type(variableName) ~= "string" then
        error(format(
                  "Usage: %s:New(addonName, variableName[, defaultProfile]): 'variableName' - string expected got %s",
                  tostring(LibDatabase), type(variableName), 2))
    end
    defaultProfile = defaultProfile or CHAR_KEY
    if type(defaultProfile) ~= "string" then
        error(format(
                  "Usage: %s:New(addonName, variableName[, defaultProfile]): 'defaultProfile' - string expected got %s",
                  tostring(LibDatabase), type(defaultProfile), 2))
    end

    return LibMixin:Mixin({
        addonName = addonName,
        variableName = variableName,
        defaultProfile = DEFAULT_PROFILES[defaultProfile] or defaultProfile,
    }, DatabaseMixin)
end

for db in pairs(dbs) do -- upgrade
    if db.restored then
        db:Save()
        db.restored = nil
    end
    LibMixin:Mixin(db, DatabaseMixin)
end
