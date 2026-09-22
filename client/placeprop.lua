local RSGCore = exports['rsg-core']:GetCoreObject()

math.randomseed(GetGameTimer())
local CancelPrompt
local SetPrompt
local RotateLeftPrompt
local RotateRightPrompt
local active = false
local Props = {}

local PromptPlacerGroup = GetRandomIntInRange(0, 0xffffff)

Citizen.CreateThread(function()
    Set()
    Del()
    RotateLeft()
    RotateRight()
end)

function Del()
    Citizen.CreateThread(function()
        local str = Config.PromptCancelName
        CancelPrompt = PromptRegisterBegin()
        PromptSetControlAction(CancelPrompt, 0xF84FA74F)
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(CancelPrompt, str)
        PromptSetEnabled(CancelPrompt, true)
        PromptSetVisible(CancelPrompt, true)
        PromptSetHoldMode(CancelPrompt, true)
        PromptSetGroup(CancelPrompt, PromptPlacerGroup)
        PromptRegisterEnd(CancelPrompt)
    end)
end

function Set()
    Citizen.CreateThread(function()
        local str = Config.PromptPlaceName
        SetPrompt = PromptRegisterBegin()
        PromptSetControlAction(SetPrompt, 0x07CE1E61)
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(SetPrompt, str)
        PromptSetEnabled(SetPrompt, true)
        PromptSetVisible(SetPrompt, true)
        PromptSetHoldMode(SetPrompt, true)
        PromptSetGroup(SetPrompt, PromptPlacerGroup)
        PromptRegisterEnd(SetPrompt)
    end)
end

function RotateLeft()
    Citizen.CreateThread(function()
        local str = Config.PromptRotateLeft
        RotateLeftPrompt = PromptRegisterBegin()
        PromptSetControlAction(RotateLeftPrompt, 0xA65EBAB4)
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(RotateLeftPrompt, str)
        PromptSetEnabled(RotateLeftPrompt, true)
        PromptSetVisible(RotateLeftPrompt, true)
        PromptSetStandardMode(RotateLeftPrompt, true)
        PromptSetGroup(RotateLeftPrompt, PromptPlacerGroup)
        PromptRegisterEnd(RotateLeftPrompt)
    end)
end

function RotateRight()
    Citizen.CreateThread(function()
        local str = Config.PromptRotateRight
        RotateRightPrompt = PromptRegisterBegin()
        PromptSetControlAction(RotateRightPrompt, 0xDEB34313)
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(RotateRightPrompt, str)
        PromptSetEnabled(RotateRightPrompt, true)
        PromptSetVisible(RotateRightPrompt, true)
        PromptSetStandardMode(RotateRightPrompt, true)
        PromptSetGroup(RotateRightPrompt, PromptPlacerGroup)
        PromptRegisterEnd(RotateRightPrompt)
    end)
end

function modelrequest(model)
    Citizen.CreateThread(function()
        RequestModel(model)
    end)
end

function PropPlacer(proptype, prop, item)
    local myPed = PlayerPedId()
    local pHead = GetEntityHeading(myPed)
    local pos = GetEntityCoords(myPed)
    local PropHash = prop
    local coords = GetEntityCoords(myPed)
    local _x, _y, _z = table.unpack(coords)
    local forward = GetEntityForwardVector(myPed)
    local x, y, z = table.unpack(pos - forward * -Config.ForwardDistance)
    local ox = x - _x
    local oy = y - _y
    local oz = z - _z
    local heading = 0.0
    local object

    SetCurrentPedWeapon(myPed, -1569615261, true)
    while not HasModelLoaded(PropHash) do
        Wait(500)
        modelrequest(PropHash)
    end
    local tempObj = CreateObject(PropHash, pos.x, pos.y, pos.z, false, false, false)
    local tempObj2 = CreateObject(PropHash, pos.x, pos.y, pos.z, false, false, false)
    AttachEntityToEntity(tempObj2, myPed, 0, ox, oy, 0.5, 0.0, 0.0, 0, true, false, false, false, false)
    SetEntityAlpha(tempObj, 180)
    SetEntityAlpha(tempObj2, 0)

    while true do
        Wait(5)
        local PropPlacerGroupName = CreateVarString(10, 'LITERAL_STRING', Config.PromptGroupName)
        PromptSetActiveGroupThisFrame(PromptPlacerGroup, PropPlacerGroupName)

        AttachEntityToEntity(tempObj, myPed, 0, ox, oy, -0.8, 0.0, 0.0, heading, true, false, false, false, false)
        if IsControlPressed(1, 0xA65EBAB4) then
            heading = heading - 1
        end
        if IsControlPressed(1, 0xDEB34313) then
            heading = heading + 1
        end

        local pPos = GetEntityCoords(tempObj2)

        if PromptHasHoldModeCompleted(SetPrompt) then
            FreezeEntityPosition(PlayerPedId(), true)
            TriggerEvent('rsg-goldclaim:rocker:client:placeNewProp', proptype, PropHash, item, pPos, heading)
            DeleteEntity(tempObj2)
            DeleteEntity(tempObj)
            FreezeEntityPosition(PlayerPedId(), false)
            break
        end

        if PromptHasHoldModeCompleted(CancelPrompt) then
            DeleteEntity(tempObj2)
            DeleteEntity(tempObj)
            SetModelAsNoLongerNeeded(PropHash)
            break
        end
    end
end

RegisterNetEvent('rsg-goldclaim:rocker:client:createprop', function(proptype, prop, item)
    PropPlacer(proptype, prop, item)
end)
