--[[Copyright © 2023 Mycroft (Kasey Fitton)

All rights reserved.

Permission is hereby granted, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software with 'All rights reserved'. Even if 'All rights reserved' is very clear :

  You shall not sell and/or resell this software
  You Can use and Modify this software
  You Shall Not Distribute and/or Redistribute the software
  The above copyright notice and this permission notice shall be included in all copies and files of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.]]

VendingHandler = setmetatable({}, VendingHandler)
VendingHandler.__index = VendingHandler
VendingHandler.storage = {}
VendingHandler.currentMachine = nil
VendingHandler.currentIndex = nil
VendingHandler.helpText = { showing = false, text = "" }

------------- Performance Optimisation ------------------- 
local CreateThread = CreateThread
local Wait = Wait
local GetEntityCoords = GetEntityCoords
local GetClosestObjectOfType = GetClosestObjectOfType
local DoesEntityExist = DoesEntityExist
local joaat = joaat
local exports = exports
local IsNuiFocused = IsNuiFocused
local IsControlEnabled = IsControlEnabled
local IsEntityAtCoord = IsEntityAtCoord
local TaskGoStraightToCoord = TaskGoStraightToCoord
local TaskTurnPedToFaceEntity = TaskTurnPedToFaceEntity
local RequestAnimDict = RequestAnimDict
local HasAnimDictLoaded = HasAnimDictLoaded
local RequestAmbientAudioBank = RequestAmbientAudioBank
local HintAmbientAudioBank = HintAmbientAudioBank
local SetPedCurrentWeaponVisible = SetPedCurrentWeaponVisible
local RequestModel = RequestModel
local HasModelLoaded = HasModelLoaded
local SetPedResetFlag = SetPedResetFlag
local GetPedBoneIndex = GetPedBoneIndex
local AttachEntityToEntity = AttachEntityToEntity
local SetEntityAsMissionEntity = SetEntityAsMissionEntity
local SetEntityProofs = SetEntityProofs
local ApplyForceToEntity = ApplyForceToEntity
local SetEntityAsNoLongerNeeded = SetEntityAsNoLongerNeeded
local ClearPedTasks = ClearPedTasks
local ReleaseAmbientAudioBank = ReleaseAmbientAudioBank
local RemoveAnimDict = RemoveAnimDict
local SetModelAsNoLongerNeeded = SetModelAsNoLongerNeeded
local TriggerEvent = TriggerEvent
local TriggerServerEvent = TriggerServerEvent
-----------------------------------------------------------------

function VendingHandler:RegisterMachine(model, distance, helpText)
    self.storage[#self.storage + 1] = {
        model = model,
        distance = distance,
        helpText = helpText,
    }
end

function VendingHandler:RegisterTargets()
    for i = 1, #(Config.Models) do
        local options = {
            {
                name = Config.Models[i].model .. '-vend',
                icon = 'fa-solid fa-whiskey-glass',
                label = Config.Models[i].interactionLabel,
                distance = 1.0,
                onSelect = function(data)
                    VendingHandler.currentMachine = data.entity
                    VendingHandler.currentIndex = i
                    VendingHandler:Interact()
                end
            },
        }
        exports.ox_target:addModel(Config.Models[i].model, options)
    end
end

function VendingHandler:NearThread()
    while true do
        local ped = ESX.PlayerData.ped
        local coords = GetEntityCoords(ped)
        local success, machine, index = false, nil, nil
        for i = 1, #self.storage do
            local storage = self.storage[i]
            local Object = GetClosestObjectOfType(coords.x, coords.y, coords.z, storage.distance, joaat(storage.model),
                false, false, false)
            if Object and DoesEntityExist(Object) then
                machine = Object
                index = i
                success = true
            end
        end
        self.currentMachine = success and machine or nil
        self.currentIndex = success and index or nil
        Wait(500)
    end
end

function VendingHandler:HandleNearThread()
    while true do
        if self.currentMachine then
            local interation = self.storage[self.currentIndex]
            if interation.helpText then
                if not self.helpText.showing or self.helpText.text ~= interation.helpText then
                    ESX.TextUI(interation.helpText, "info")
                    self.helpText.showing = true
                    self.helpText.text = interation.helpText
                end
            end
        else
            if self.helpText.showing then
                ESX.HideUI()
                self.helpText.showing = false
                self.helpText.text = ""
            end
        end
        Wait(500)
    end
end

function VendingHandler:RegisterInteraction()
    ESX.RegisterInput("vending_use", "Use Vending Machine", "keyboard", "e", function()
        print("E Pressed")
        if IsNuiFocused() then
            print("NUI Focused")
            return
        end
        if not IsControlEnabled(0, 38) then
            print("Control Disabled")
            return
        end
        if not self.currentMachine or not self.currentIndex then
            print("No Machine")
            return
        end
        self:Interact()
    end)
end

function VendingHandler:Init()
    if Config.oxTarget then
        self:RegisterTargets()
    else
        for i = 1, #(Config.Models) do
            local storage = Config.Models[i]
            local model = storage.model
            local distance = 1.0
            local helpText = storage.interactionLabel
            self:RegisterMachine(model, distance, helpText)
        end

        CreateThread(function()
            self:NearThread()
        end)
        CreateThread(function()
            self:HandleNearThread()
        end)
        self:RegisterInteraction()
    end
end

CreateThread(function()
    while not ESX.PlayerLoaded do
        Wait(500)
    end
    VendingHandler:Init()
end)

function VendingHandler:Interact()
    local storage = Config.Models[self.currentIndex]
    -- Function Based upon: https://github.com/smallo92/xnVending
    ESX.TriggerServerCallback("vending:canBuyDink", function(canBuy)
        if canBuy then
            local ped = ESX.PlayerData.ped
            local position = GetOffsetFromEntityInWorldCoords(self.currentMachine, 0.0, -0.97, 0.05)

            TaskTurnPedToFaceEntity(ped, self.currentMachine, -1)
            RequestAnimDict(Config.DispenseDict[1])

            while not HasAnimDictLoaded(Config.DispenseDict[1]) do
                Wait(0)
            end

            RequestAmbientAudioBank("VENDING_MACHINE")
            HintAmbientAudioBank("VENDING_MACHINE", 0, -1)

            SetPedCurrentWeaponVisible(ped, false, true, 1, 0)
            RequestModel(storage.obj)
            while not HasModelLoaded(storage.obj) do
                Wait(0)
            end
            SetPedResetFlag(ped, 322, true)
            local machineHeading = GetEntityHeading(self.currentMachine)
            if not IsEntityAtCoord(ped, position, 0.1, 0.1, 0.1, false, true, 0) then
                TaskGoStraightToCoord(ped, position, 2.0, 20000, machineHeading, 0.1)
                while not IsEntityAtCoord(ped, position, 0.1, 0.1, 0.1, false, true, 0) do
                    TaskGoStraightToCoord(ped, position, 5.0, 20000, machineHeading, 0.2)
                    Wait(1000)
                end
            end
            TriggerServerEvent("vending:buyDrink", self.currentIndex)
            TaskTurnPedToFaceEntity(ped, self.currentMachine, -1)
            Wait(500)
            TaskPlayAnim(ped, Config.DispenseDict[1], Config.DispenseDict[2], 4.0, 5.0, -1, true, 1, 0, 0, 0)
            Wait(2500)
            local canModel = CreateObjectNoOffset(storage.obj, position, true, false, false)
            SetEntityAsMissionEntity(canModel, true, true)
            SetEntityProofs(canModel, false, true, false, false, false, false, 0, false)
            AttachEntityToEntity(canModel, ped, GetPedBoneIndex(ped, 28422), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1, 1, 0, 0, 2,
                1)
            Wait(3700)
            TaskPlayAnim(ped, Config.DispenseDict[1], "PLYR_BUY_DRINK_PT2", 4.0, 5.0, -1, true, 1, 0, 0, 0)
            Wait(1800)
            TriggerEvent('esx_status:add', 'hunger', storage.hunger)
            TriggerEvent('esx_status:add', 'thirst', storage.thirst)
            TaskPlayAnim(ped, Config.DispenseDict[1], "PLYR_BUY_DRINK_PT3", 4.0, 5.0, -1, true, 1, 0, 0, 0)
            Wait(600)
            DetachEntity(canModel, true, true)
            ApplyForceToEntity(canModel, 1, vector3(-6.0, -10.0, -2.0), 0, 0, 0, 0, true, true, false, false, true)
            SetEntityAsNoLongerNeeded(canModel)
            Wait(1600)
            ClearPedTasks(ped)
            ReleaseAmbientAudioBank()
            RemoveAnimDict(Config.DispenseDict[1])
            SetModelAsNoLongerNeeded(storage.obj)
        else
            ESX.ShowNotification("Cannot Afford Drink!", "error")
        end
    end, self.currentIndex)
end
