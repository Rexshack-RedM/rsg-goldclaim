lib.locale()

local RSGCore = exports['rsg-core']:GetCoreObject()
local PropsLoaded = false
local ProcessingRockers = {}
local PendingRockerOutputs = {} -- [propid] = 'gold' | 'paydirt' (set only by the server when a processing cycle completes)
local GatherCooldowns = {} -- [citizenid] = os.time() when the next dig/fill is allowed

---------------------------------------------
-- helper: send an ox_lib notification to a client (target = -1 to broadcast)
---------------------------------------------
local NotifyIcons = {
    warning          = 'triangle-exclamation',
    cross            = 'circle-xmark',
    tick             = 'circle-check',
    leaderboard_gold = 'coins',
    awards_set_c_001 = 'box-open',
}

local NotifyTypes = {
    ERROR    = 'error',
    SUCCESS  = 'success',
    INFO     = 'info',
    TIP_GOLD = 'success',
}

function Notify(target, title, description, icon, duration, template)
    TriggerClientEvent('ox_lib:notify', target, {
        title = title,
        description = description,
        type = NotifyTypes[template] or 'info',
        icon = NotifyIcons[icon] or icon,
        duration = duration or 5000,
        position = 'center-right',
    })
end

---------------------------------------------
-- helper: simple per-citizenid cooldown gate
-- returns true if still on cooldown (call should be rejected)
---------------------------------------------
local function OnGatherCooldown(citizenid, seconds)
    local expires = GatherCooldowns[citizenid]
    if expires and expires > os.time() then
        return true
    end
    GatherCooldowns[citizenid] = os.time() + (seconds or 1)
    return false
end

---------------------------------------------
-- internal: persist a prop to the database
-- (plain function, NOT a net event - never trust this with client-supplied data)
---------------------------------------------
function RockerSaveProp(data, propId, citizenid, owner, proptype, licensed, claimname)
    local datas = json.encode(data)
    MySQL.Async.execute('INSERT INTO player_goldrockers (properties, propid, citizenid, owner, proptype, licensed, claimname) VALUES (@properties, @propid, @citizenid, @owner, @proptype, @licensed, @claimname)', {
        ['@properties'] = datas,
        ['@propid']     = propId,
        ['@citizenid']  = citizenid,
        ['@owner']      = owner,
        ['@proptype']   = proptype,
        ['@licensed']   = licensed or 0,
        ['@claimname']  = claimname,
    })
end

---------------------------------------------
-- internal: broadcast current prop data to all clients
---------------------------------------------
function RockerUpdateProps()
    TriggerClientEvent('rsg-goldclaim:rocker:client:updatePropData', -1, Config.PlayerProps)
end

---------------------------------------------
-- internal: load props from the database into memory (idempotent)
---------------------------------------------
function RockerLoadProps()
    Config.PlayerProps = {}

    local result = MySQL.query.await('SELECT * FROM player_goldrockers')
    if not result or not result[1] then return end

    for i = 1, #result do
        local propData = json.decode(result[i].properties)
        -- inject license/claim data into prop data for client use
        propData.licensed  = result[i].licensed or 0
        propData.claimname = result[i].claimname
        if Config.Debug then print('[rsg-goldclaim] loading ' .. propData.proptype .. ' prop with ID: ' .. propData.id) end
        table.insert(Config.PlayerProps, propData)
    end
end

---------------------------------------------
-- helper: find a loaded prop's data by id (from Config.PlayerProps)
---------------------------------------------
local function GetRockerPropById(propid)
    for _, v in pairs(Config.PlayerProps) do
        if v.id == propid then
            return v
        end
    end
    return nil
end

---------------------------------------------
-- helper: is this player currently near the given prop's stored location?
-- (defense in depth: several events below are only ever meant to be fired
-- while physically at the rocker, but nothing stops a modified client from
-- firing them directly, so re-check distance server-side)
---------------------------------------------
local function IsPlayerNearProp(src, propData, radius)
    if not propData then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pos = GetEntityCoords(ped)
    local dist = #(pos - vector3(propData.x, propData.y, propData.z))
    return dist <= (radius or 5.0)
end

---------------------------------------------
-- use goldrocker item (triggers placement)
---------------------------------------------
RSGCore.Functions.CreateUseableItem("goldrocker", function(source)
    local src = source
    TriggerClientEvent('rsg-goldclaim:rocker:client:createprop', src, 'goldrocker', Config.GoldRocker, 'goldrocker')
end)

---------------------------------------------
-- use shovel (dig paydirt from water)
---------------------------------------------
RSGCore.Functions.CreateUseableItem("shovel", function(source)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    TriggerClientEvent('rsg-goldclaim:rocker:client:useshovel', src)
end)

---------------------------------------------
-- use bucket (fill with water)
---------------------------------------------
RSGCore.Functions.CreateUseableItem("bucket", function(source)
    local src = source
    TriggerClientEvent('rsg-goldclaim:rocker:client:usebucket', src)
end)

---------------------------------------------
-- client handler: use shovel in water
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:server:digpaydirt', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    if OnGatherCooldown(citizenid, math.max(1, math.floor(Config.ShovelDigTime / 1000))) then return end

    local hasShovel = Player.Functions.GetItemByName('shovel')
    if not hasShovel then return end

    Player.Functions.AddItem('paydirt', 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['paydirt'], "add")
end)

---------------------------------------------
-- client handler: fill bucket in water
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:server:fillbucket', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    if OnGatherCooldown(citizenid, math.max(1, math.floor(Config.BucketFillTime / 1000))) then return end

    local hasBucket = Player.Functions.GetItemByName('bucket')
    if not hasBucket or hasBucket.amount < 1 then return end

    -- remove bucket, give fullbucket
    Player.Functions.RemoveItem('bucket', 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['bucket'], "remove")
    Player.Functions.AddItem('fullbucket', 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['fullbucket'], "add")
end)

---------------------------------------------
-- count props callback
---------------------------------------------
RSGCore.Functions.CreateCallback('rsg-goldclaim:rocker:server:countprop', function(source, cb, proptype)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return cb(0) end
    local citizenid = Player.PlayerData.citizenid
    local result = MySQL.prepare.await("SELECT COUNT(*) as count FROM player_goldrockers WHERE citizenid = ? AND proptype = ?", { citizenid, proptype })
    if result then
        cb(result)
    else
        cb(0)
    end
end)

---------------------------------------------
-- get rocker data callback
---------------------------------------------
RSGCore.Functions.CreateCallback('rsg-goldclaim:rocker:server:getrockerdata', function(source, cb, propid)
    MySQL.query('SELECT * FROM player_goldrockers WHERE propid = ?', {propid}, function(result)
        if result and result[1] then
            cb(result[1])
        else
            cb(nil)
        end
    end)
end)

---------------------------------------------
-- new prop (with license check)
---------------------------------------------
RegisterServerEvent('rsg-goldclaim:rocker:server:newProp')
AddEventHandler('rsg-goldclaim:rocker:server:newProp', function(proptype, location, heading, hash)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    if proptype ~= 'goldrocker' then return end
    if not location or type(location.x) ~= 'number' or type(location.y) ~= 'number' or type(location.z) ~= 'number' then return end
    heading = tonumber(heading) or 0.0

    local propId = math.random(111111, 999999)
    while GetRockerPropById(propId) do
        propId = math.random(111111, 999999)
    end
    local citizenid = Player.PlayerData.citizenid
    local firstname = Player.PlayerData.charinfo.firstname
    local lastname = Player.PlayerData.charinfo.lastname
    local owner = firstname .. ' ' .. lastname

    -- check for license
    local hasLicense = Player.Functions.GetItemByName('goldclaimlicense')
    local licensed = 0
    local claimname = nil

    local PropCount = 0
    for _, v in pairs(Config.PlayerProps) do
        if v.builder == citizenid then
            PropCount = PropCount + 1
        end
    end

    if PropCount >= Config.MaxGoldRockers then
        Notify(src, locale('rocker_server_max_reached'), nil, 'cross', 5000, 'ERROR')
        return
    end

    -- verify the player actually has the rocker item before creating anything
    -- (RemoveItem's return value isn't a reliable success indicator in this framework)
    local hasProp = Player.Functions.GetItemByName(proptype)
    if not hasProp or hasProp.amount < 1 then return end

    Player.Functions.RemoveItem(proptype, 1)

    if hasLicense and hasLicense.amount > 0 then
        licensed = 1
        claimname = owner .. "'s Gold Claim"
        -- consume the license
        Player.Functions.RemoveItem('goldclaimlicense', 1)
        TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['goldclaimlicense'], "remove")
    end

    local PropData = {
        id        = propId,
        proptype  = proptype,
        x         = location.x,
        y         = location.y,
        z         = location.z,
        h         = heading,
        hash      = hash,
        builder   = citizenid,
        buildtime = os.time(),
        licensed  = licensed,
        claimname = claimname,
    }

    table.insert(Config.PlayerProps, PropData)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[proptype], "remove")
    RockerSaveProp(PropData, propId, citizenid, owner, proptype, licensed, claimname)
    RockerUpdateProps()

    -- if unlicensed, let the placer know their claim is illegal and unprotected
    if licensed == 0 then
        Notify(src, locale('rocker_unlicensed_notice_title'), locale('rocker_unlicensed_notice_desc'), 'warning', 10000, 'ERROR')
    end
end)

---------------------------------------------
-- periodic prop update
---------------------------------------------
CreateThread(function()
    while true do
        Wait(300000)
        if PropsLoaded then
            RockerUpdateProps()
        end
    end
end)

---------------------------------------------
-- load props on start
---------------------------------------------
CreateThread(function()
    RockerLoadProps()
    Wait(2000)
    PropsLoaded = true
    RockerUpdateProps()
end)

---------------------------------------------
-- send props to new player on spawn
---------------------------------------------
RegisterNetEvent('RSGCore:Server:PlayerLoaded', function(Player)
    local src = source
    if PropsLoaded then
        TriggerClientEvent('rsg-goldclaim:rocker:client:updatePropData', src, Config.PlayerProps)
    end
end)

---------------------------------------------
-- destroy prop (pack up - returns the rocker's own item type to its owner)
---------------------------------------------
RegisterServerEvent('rsg-goldclaim:rocker:server:destroyProp')
AddEventHandler('rsg-goldclaim:rocker:server:destroyProp', function(propid)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local result = MySQL.query.await('SELECT citizenid, proptype, quality FROM player_goldrockers WHERE propid = ?', {propid})
    if not result or not result[1] then return end
    if result[1].citizenid ~= citizenid then return end
    if result[1].quality ~= 100 then return end

    local proptype = result[1].proptype

    for k, v in pairs(Config.PlayerProps) do
        if v.id == propid then
            table.remove(Config.PlayerProps, k)
            break
        end
    end

    TriggerClientEvent('rsg-goldclaim:rocker:client:removePropObject', -1, propid)
    RockerUpdateProps()

    -- remove from DB
    MySQL.Async.execute('DELETE FROM player_goldrockers WHERE propid = ?', {propid})

    -- return the rocker's own item type to the owner
    Player.Functions.AddItem(proptype, 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[proptype], "add")
end)

---------------------------------------------
-- LEO destroy illegal claim (confiscate as evidence)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:server:leodestroy', function(propid)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    -- verify LEO
    if not Player.PlayerData.job or Player.PlayerData.job.type ~= 'leo' then
        return
    end

    local result = MySQL.query.await('SELECT licensed FROM player_goldrockers WHERE propid = ?', {propid})
    if not result or not result[1] then return end
    if result[1].licensed == 1 then return end -- LEO may only confiscate unlicensed (illegal) claims

    for k, v in pairs(Config.PlayerProps) do
        if v.id == propid then
            table.remove(Config.PlayerProps, k)
            break
        end
    end

    TriggerClientEvent('rsg-goldclaim:rocker:client:removePropObject', -1, propid)
    RockerUpdateProps()

    -- remove from DB
    MySQL.Async.execute('DELETE FROM player_goldrockers WHERE propid = ?', {propid})

    -- give rocker to LEO as evidence
    Player.Functions.AddItem('goldrocker', 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['goldrocker'], "add")
end)

---------------------------------------------
-- add paydirt to rocker
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:server:addpaydirt', function(propid)
    print('[rsg-goldclaim][DEBUG] addpaydirt fired, propid=' .. tostring(propid))
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then print('[rsg-goldclaim][DEBUG] addpaydirt: no Player') return end

    local hasPaydirt = Player.Functions.GetItemByName('paydirt')
    if not hasPaydirt or hasPaydirt.amount < 1 then print('[rsg-goldclaim][DEBUG] addpaydirt: no paydirt item, hasPaydirt=' .. tostring(hasPaydirt)) return end

    -- get current paydirt level
    local result = MySQL.query.await('SELECT paydirt FROM player_goldrockers WHERE propid = ?', {propid})
    if not result or not result[1] then print('[rsg-goldclaim][DEBUG] addpaydirt: no DB row for propid=' .. tostring(propid)) return end

    local currentPaydirt = result[1].paydirt
    if currentPaydirt >= Config.MaxPaydirt then print('[rsg-goldclaim][DEBUG] addpaydirt: already at max, current=' .. tostring(currentPaydirt)) return end

    local newPaydirt = math.min(currentPaydirt + 1, Config.MaxPaydirt)

    Player.Functions.RemoveItem('paydirt', 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['paydirt'], 'remove')
    MySQL.update('UPDATE player_goldrockers SET paydirt = ? WHERE propid = ?', {newPaydirt, propid})
    print('[rsg-goldclaim][DEBUG] addpaydirt: success, new value=' .. tostring(newPaydirt))
end)

---------------------------------------------
-- add water to rocker (from fullbucket)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:server:addwater', function(propid)
    print('[rsg-goldclaim][DEBUG] addwater fired, propid=' .. tostring(propid))
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then print('[rsg-goldclaim][DEBUG] addwater: no Player') return end

    local hasFullbucket = Player.Functions.GetItemByName('fullbucket')
    if not hasFullbucket or hasFullbucket.amount < 1 then print('[rsg-goldclaim][DEBUG] addwater: no fullbucket item, hasFullbucket=' .. tostring(hasFullbucket)) return end

    local result = MySQL.query.await('SELECT water FROM player_goldrockers WHERE propid = ?', {propid})
    if not result or not result[1] then print('[rsg-goldclaim][DEBUG] addwater: no DB row for propid=' .. tostring(propid)) return end

    local currentWater = result[1].water
    if currentWater >= Config.MaxWater then print('[rsg-goldclaim][DEBUG] addwater: already at max, current=' .. tostring(currentWater)) return end

    local newWater = math.min(currentWater + 1, Config.MaxWater)

    -- remove fullbucket, give back empty bucket
    Player.Functions.RemoveItem('fullbucket', 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['fullbucket'], 'remove')
    Player.Functions.AddItem('bucket', 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['bucket'], 'add')
    MySQL.update('UPDATE player_goldrockers SET water = ? WHERE propid = ?', {newWater, propid})
    print('[rsg-goldclaim][DEBUG] addwater: success, new value=' .. tostring(newWater))
end)

---------------------------------------------
-- process rocker (async - loops until water or paydirt runs out)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:server:processrocker', function(propid)
    local src = source

    -- prevent double-processing on the same rocker
    if ProcessingRockers[propid] then
        Notify(src, locale('rocker_already_processing_title'), locale('rocker_already_processing_desc'), 'cross', 5000, 'ERROR')
        return
    end

    local result = MySQL.query.await('SELECT * FROM player_goldrockers WHERE propid = ?', {propid})
    if not result or not result[1] then return end

    local water = result[1].water
    local paydirt = result[1].paydirt

    if water <= 0 or paydirt <= 0 then return end

    ProcessingRockers[propid] = true

    -- recursive function: each call = one processing cycle
    local function RunCycle(remainingWater, remainingPaydirt)
        local newWater = remainingWater - 1
        local newPaydirt = remainingPaydirt - 1
        MySQL.update('UPDATE player_goldrockers SET water = ?, paydirt = ? WHERE propid = ?', {newWater, newPaydirt, propid})

        SetTimeout(Config.ProcessingTime, function()
            -- determine result
            local roll = math.random(1, 100)
            local resultType = 'paydirt'
            if roll <= Config.GoldChance then
                resultType = 'gold'
            end

            -- flag this propid as having an unclaimed output before telling the client to spawn it
            PendingRockerOutputs[propid] = resultType
            TriggerClientEvent('rsg-goldclaim:rocker:client:spawnoutputprop', src, propid, resultType)

            -- check if we can continue
            if newWater > 0 and newPaydirt > 0 then
                RunCycle(newWater, newPaydirt)
            else
                ProcessingRockers[propid] = nil
                TriggerClientEvent('rsg-goldclaim:rocker:client:processingcomplete', src, propid)
            end
        end)
    end

    RunCycle(water, paydirt)
end)

---------------------------------------------
-- pick up gold (gives random nugget type + random amount)
-- only honored if the server itself flagged this propid as having pending gold output
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:server:pickupgold', function(propid)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    if PendingRockerOutputs[propid] ~= 'gold' then return end
    if not IsPlayerNearProp(src, GetRockerPropById(propid), 10.0) then return end
    PendingRockerOutputs[propid] = nil

    -- weighted random nugget type
    local roll = math.random(1, 100)
    local nugget = 'smallnugget'
    local amountRange = Config.NuggetAmounts.small

    if roll <= Config.NuggetWeights.large then
        nugget = 'largenugget'
        amountRange = Config.NuggetAmounts.large
    elseif roll <= Config.NuggetWeights.large + Config.NuggetWeights.medium then
        nugget = 'mediumnugget'
        amountRange = Config.NuggetAmounts.medium
    end

    -- random amount between min and max
    local amount = math.random(amountRange.min, amountRange.max)

    Player.Functions.AddItem(nugget, amount)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[nugget], "add")

    -- tell client what they got so it can show a detailed notification
    TriggerClientEvent('rsg-goldclaim:rocker:client:goldpickupresult', src, nugget, amount)
end)

---------------------------------------------
-- pick up paydirt (gives 1 paydirt back)
-- only honored if the server itself flagged this propid as having pending paydirt output
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:server:pickuppaydirt', function(propid)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    if PendingRockerOutputs[propid] ~= 'paydirt' then return end
    if not IsPlayerNearProp(src, GetRockerPropById(propid), 10.0) then return end
    PendingRockerOutputs[propid] = nil

    Player.Functions.AddItem('paydirt', 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['paydirt'], "add")
end)

---------------------------------------------
-- repair rocker (5x wood)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:server:repairrocker', function(propid)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local hasWood = Player.Functions.GetItemByName('wood')
    if not hasWood or hasWood.amount < Config.RepairWoodAmount then return end

    Player.Functions.RemoveItem('wood', Config.RepairWoodAmount)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['wood'], 'remove')
    MySQL.update('UPDATE player_goldrockers SET quality = ? WHERE propid = ?', {100, propid})
end)

---------------------------------------------
-- rename claim
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:server:renameclaim', function(propid, newname)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    if type(newname) ~= 'string' or #newname < 1 or #newname > 100 then return end

    local citizenid = Player.PlayerData.citizenid

    -- verify ownership
    local result = MySQL.query.await('SELECT citizenid, licensed FROM player_goldrockers WHERE propid = ?', {propid})
    if not result or not result[1] then return end
    if result[1].citizenid ~= citizenid then return end
    if result[1].licensed ~= 1 then return end

    MySQL.update('UPDATE player_goldrockers SET claimname = ? WHERE propid = ?', {newname, propid})

    -- update in-memory prop data
    for _, v in pairs(Config.PlayerProps) do
        if v.id == propid then
            v.claimname = newname
            break
        end
    end

    -- tell all clients to refresh zone/blip
    TriggerClientEvent('rsg-goldclaim:rocker:client:refreshclaim', -1, propid, newname)
end)

---------------------------------------------
-- smelt nuggets into gold bars (server derives the required nugget cost/ratio itself)
---------------------------------------------
local NuggetSmeltCosts = {
    smallnugget  = Config.SmallNuggetSmelt,
    mediumnugget = Config.MediumNuggetSmelt,
    largenugget  = Config.LargeNuggetSmelt,
}

RegisterNetEvent('rsg-goldclaim:rocker:server:finishsmelt', function(nuggettype, bars)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local costPerBar = NuggetSmeltCosts[nuggettype]
    bars = tonumber(bars)

    if not costPerBar or not bars or bars <= 0 or bars ~= math.floor(bars) then return end

    local amountnuggets = costPerBar * bars

    local hasItem = Player.Functions.GetItemByName(nuggettype)
    if not hasItem or hasItem.amount < amountnuggets then return end

    Player.Functions.RemoveItem(nuggettype, amountnuggets)

    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[nuggettype], 'remove')
    Player.Functions.AddItem('goldbar', bars)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['goldbar'], 'add')
end)

---------------------------------------------
-- sell gold bars (server computes the true amount from inventory, never trusts the client)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:server:sellgoldbars', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local goldBarCount = 0
    for _, item in pairs(Player.PlayerData.items) do
        if item and item.name == 'goldbar' then
            goldBarCount = goldBarCount + item.amount
        end
    end

    if goldBarCount <= 0 then return end

    Player.Functions.RemoveItem('goldbar', goldBarCount)

    local totalvalue = goldBarCount * Config.GoldBarPrice
    Player.Functions.AddMoney('cash', totalvalue, 'rsg-goldclaim-sell-goldbar')
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['goldbar'], "remove")
end)

---------------------------------------------
-- sell silver bars (server computes the true amount from inventory, never trusts the client)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:server:sellsilverbars', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local silverBarCount = 0
    for _, item in pairs(Player.PlayerData.items) do
        if item and item.name == 'silverbar' then
            silverBarCount = silverBarCount + item.amount
        end
    end

    if silverBarCount <= 0 then return end

    Player.Functions.RemoveItem('silverbar', silverBarCount)

    local totalvalue = silverBarCount * Config.SilverBarPrice
    Player.Functions.AddMoney('cash', totalvalue, 'rsg-goldclaim-sell-silverbar')
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['silverbar'], "remove")
end)

---------------------------------------------
-- equipment degradation cron (no gold processing)
---------------------------------------------
lib.cron.new(Config.CronJob, function()
    local degradechance = math.random(1, 100)
    local result = MySQL.query.await('SELECT * FROM player_goldrockers')

    if not result then return end

    for i = 1, #result do
        local quality = result[i].quality
        local propid = result[i].propid
        local owner = result[i].owner

        -- degrade equipment
        if quality > 0 and degradechance > (100 - Config.DegradeChance) then
            MySQL.update('UPDATE player_goldrockers SET quality = ? WHERE propid = ?', {quality - 1, propid})
        end

        -- remove equipment if fully degraded
        if quality == 0 then
            for k, v in pairs(Config.PlayerProps) do
                if v.id == propid then
                    table.remove(Config.PlayerProps, k)
                    break
                end
            end
            TriggerClientEvent('rsg-goldclaim:rocker:client:removePropObject', -1, propid)
            RockerUpdateProps()
            TriggerEvent('rsg-log:server:CreateLog', 'rsggoldclaim', 'Gold Equipment Lost', 'red', 'Gold Rocker with ID:' .. propid .. ' belonging to ' .. owner .. ' was lost due to non maintenance!')
            MySQL.Async.execute('DELETE FROM player_goldrockers WHERE propid = ?', {propid})
        end
    end

    if Config.Debug then
        print(locale('rocker_server_cron_ran'))
    end
end)
