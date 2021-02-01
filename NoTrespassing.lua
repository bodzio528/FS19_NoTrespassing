--[[

NoTrespassing.lua

This is file with vehicle specialization that issues penalty upon trespassing NPC's areable ground

Author: bodzio528
Version: 0.1
Created: 2020-12-16

Changelog:
2020-12-16 initial version
2021-02-01 rewrite update function, cleanup the code
]]


NoTrespassing = {}

NoTrespassing.MOD_NAME = g_currentModName

NoTrespassing.WARNING_DISPLAY_TIME = 3000.0
NoTrespassing.NOTIFICATION_DISPLAY_TIME = 8000.0

NoTrespassing.AREA_COEFFICIENT = 1.0 / 1024.0 -- this constant holds average real-world area to in-game units conversion (23355.5)
NoTrespassing.KPH_TO_MPS = 0.28

NoTrespassing.PAYMENT_UNIT = 250

NoTrespassing.NDEBUG = 0 -- 1 = chatty; 2 = talkative

-- sincere apologies to everyone reading this :(
g_noTrespassing = getfenv(0)["g_noTrespassing"]

function NoTrespassing.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Enterable, specializations)
        and SpecializationUtil.hasSpecialization(Motorized, specializations)
        and not SpecializationUtil.hasSpecialization(SplineVehicle, specializations)
end

function NoTrespassing.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", NoTrespassing)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", NoTrespassing)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", NoTrespassing)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", NoTrespassing)
end

function NoTrespassing:onLoad(savegame)
    local spec = self:getNoTrespassingSpec()
    spec.penalty = 0

    spec.visiblePenalty = 0
end

function NoTrespassing:onReadStream(streamId, connection)
    if NoTrespassnig.NDEBUG > 0 then
        print(string.format("NoTrespassing:onReadStream(streamId=%s, connection=%s) penalty -> %f", tostring(streamId), tostring(connection), spec.penalty))
    end

    local spec = Vehicle:getNoTrespassingSpec()
    spec.penalty = streamReadFloat32(streamId)
end

function NoTrespassing:onWriteStream(streamId, connection)
    if NoTrespassnig.NDEBUG > 0 then
        print(string.format("NoTrespassing:onWriteStream(streamId=%s, connection=%s) penalty <- %f", tostring(streamId), tostring(connection), spec.penalty))
    end

    local spec = Vehicle:getNoTrespassingSpec()
    streamWriteFloat32(streamId, spec.penalty)
end

function NoTrespassing:onUpdateTick(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if not g_currentMission.missionInfo.fruitDestruction then
        -- player disabled crop damage in options, so why bother --
        return
    end

    local spec = self:getNoTrespassingSpec()
    if not self.spec_enterable.isEntered then
        -- only inflict damage if someone is inside vehicle --
        return
    end

    if self.isClient then
        local penalty = getPenalty(self, dt)
        if penalty > 0 then
            local difficultyIdx = (g_currentMission.missionInfo.economicDifficulty or g_currentMission.missionInfo.difficulty)
            local difficultyCoeff = g_noTrespassing.data.difficulty[difficultyIdx]

            penalty = penalty * difficultyCoeff * NoTrespassing.AREA_COEFFICIENT

            spec.penalty = spec.penalty + penalty
            spec.visiblePenalty = spec.visiblePenalty + penalty

            -- display warning
            local text = string.format("%s (%s: %.0f)",
                                       g_i18n:getText("noTrespassing_warning_penalty"),
                                       g_i18n:getText("noTrespassing_total_cost_label"),
                                       math.floor(spec.visiblePenalty))
            g_currentMission:showBlinkingWarning(text, NoTrespassing.WARNING_DISPLAY_TIME)
        else
            if spec.visiblePenalty > 0 then
                g_currentMission.hud:addSideNotification({0.9375, 0.9, 0.546875, 1}, string.format("%s -%d", g_i18n:getText("noTrespassing_total_cost_notification"), spec.visiblePenalty), NoTrespassing.NOTIFICATION_DISPLAY_TIME)
            end

            spec.visiblePenalty = 0
        end
    end

    if self.isServer then
        -- call deduce penalty from bank account --
        if spec.penalty > NoTrespassing.PAYMENT_UNIT then
            local farmId = self:getOwnerFarmId() 
            local stats = g_farmManager:getFarmById(g_currentMission.player.farmId).stats 
            stats:updateStats("expenses", spec.penalty) 
            g_currentMission:addMoney(-spec.penalty, farmId, MoneyType.TRANSFER)

            spec.penalty = 0
        end
    end
end

function getPenalty(vehicle, dt)
    -- variable for storing penalty for all wheels
    local penalty = 0
    for k, wheel in pairs(vehicle:getWheels()) do
        if vehicle:getIsWheelFoliageDestructionAllowed(wheel) then -- this function checks AI helper driving over crops
            local width = 0.5 * wheel.width
            local length = math.min(0.5, 0.5 * wheel.width)
            local x, _, z = localToLocal(wheel.driveNode, wheel.repr, 0, 0, 0)

            local x0, y0, z0 = localToWorld(wheel.repr, x + width, 0, z - length) -- world coordinates of wheel center

            local farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(x0, z0)
            local farmland = g_farmlandManager:getFarmlandById(farmlandId)

            if farmland == nil or farmlandId == 0 then
                -- at least one wheel has contact with road - no damage (eg. driving wide combine harvesters) --
                return 0
            end

            if farmland.isOwned then
                -- drop procedure for owned fields --
                return 0
            end
            
            if g_fieldManager.farmlandIdFieldMapping == nil or g_fieldManager.farmlandIdFieldMapping[farmlandId] == nil then
                -- error on Wola Brudnowska map --
                return 0
            end

            for f, field in pairs(g_fieldManager.farmlandIdFieldMapping[farmlandId]) do
                local mission = g_missionManager.fieldToMission[field.fieldId]
                if mission ~= nil and mission.farmId == vehicle:getActiveFarm() then
                    -- field with active mission, stop --
                    return 0
                end
            end

            local isOnField = wheel.densityType ~= 0
            if isOnField then
                -- distance... --
                local ds = dt * vehicle:getLastSpeed() * NoTrespassing.KPH_TO_MPS

                -- ...and ground properties... --
                local cropDamageCoeff = getCropDamage(x0, z0)

                -- ...wheel width... --
                local tyreDamageCoeff = getTyreDamage(x0, z0, wheel.width)

                -- ...by your powers combined, here I am... --
                local wheelDamage = ds * tyreDamageCoeff * cropDamageCoeff
                penalty = penalty + wheelDamage
            end
        end

        --[[ TODO: ADDITIONAL WHEELS ]]--
    end

    return penalty
end

function getTyreDamage(x0, z0, width)
    -- local data = g_noTrespassing.data
    -- todo: handle crawlers, get additional attached wheels etc. --
    local t = width/4
    FSDensityMapUtil.updateWheelDestructionArea(x0-t,z0-t, x0,z0+t, x0+t,z0)
    
    return width
end

function getCropDamage(x, z)
    local modifier = g_currentMission.densityMapModifiers.cutFruitArea.modifier
    for index, fruit in pairs(g_currentMission.fruits) do
        local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(index)
        if fruitDesc.name ~= "WEED" then
            modifier:resetDensityMapAndChannels(fruit.id, fruitDesc.startStateChannel, fruitDesc.numStateChannels)
            modifier:setParallelogramWorldCoords(x - 0.5, z - 0.5, 1,0, 0,1, "pvv")

            local area, totalArea, _ = modifier:executeGet()
            if area > 0 then
                local state = area / totalArea
    
                if NoTrespassing.NDEBUG > 1 then
                    print(string.format("FRUIT = %s STATE = %f ", fruitDesc.name, state))
                end

                -- GROUND = (state >= fruitDesc.destruction.state[10]) --
                if  state >= fruitDesc.destruction.state then
                    return g_noTrespassing.data.ground
                end

                -- load default (BARLEY) if damage data could not be found in config --
                local coeffs = g_noTrespassing.data.crops[fruitDesc.name]
                if coeffs == nil then
                    coeffs = g_noTrespassing.data.crops["BARLEY"]
                end

                --- YOUNG = (state <= youngPlantMaxState[4])
                if state <= fruitDesc.youngPlantMaxState then
                    return coeffs["base"] * coeffs["young"]
                end
                
                -- MATURE = (maturePlantMinState[5] <= state < cutState[8])
                if fruitDesc.maturePlantMinState <= state and state < fruitDesc.cutState then
                    return 64 * coeffs["base"] * coeffs["mature"]
                end

                -- CUT = (cutState[8] <= state < fruitDesc.destruction.state[10])
                if fruitDesc.cutState <= state and state < fruitDesc.destruction.state then
                    return coeffs["harvested"]
                end

            end
        end
    end

    return g_noTrespassing.data.ground
end