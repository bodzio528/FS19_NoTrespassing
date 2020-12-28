--[[

NoTrespassing.lua

This is file with vehicle specialization that issues penalty upon trespassing NPC's areable ground

Author: bodzio528
Version: 0.1
Created: 2020-12-16

Changelog:
2020-12-16 initial version
]]

NoTrespassing = {}

NoTrespassing.PENALTY_COOLDOWN = 5000.0 -- five seconds between paying compensation
NoTrespassing.WARNING_DISPLAY_TIME = 3000.0
NoTrespassing.UPDATE_INTERVAL_MS = 250.0 -- 1/4 second between penalty calculations
NoTrespassing.AREA_COEFFICIENT = 1.0 / 8192 -- this constant holds average real-world area to in-game units conversion (23355.5)

function NoTrespassing.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Enterable, specializations) 
        and SpecializationUtil.hasSpecialization(Motorized, specializations)
        and SpecializationUtil.hasSpecialization(Drivable, specializations)
        and not SpecializationUtil.hasSpecialization(SplineVehicle, specializations)
end

function NoTrespassing.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", NoTrespassing)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", NoTrespassing)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", NoTrespassing)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", NoTrespassing)
end

function NoTrespassing:onLoad(savegame)
    local spec = self:getNoTrespassingSpec()

    spec.dt = 0

    spec.penaltyCooldown = NoTrespassing.PENALTY_COOLDOWN

    spec.penalty = 0
    spec.totalPenalty = 0

    spec.isPlayerInside = false

    spec.displayWarning = false

    spec.seasons = g_seasons ~= nil

    DebugUtil.printTableRecursively(g_currentMission.densityMapModifiers, "D", 0, 3, nil)
end


function NoTrespassing:onReadStream(streamId, connection)
end

function NoTrespassing:onWriteStream(streamId, connection)
end

function NoTrespassing:onUpdate(dt)
    -- todo: find a way to call this function less frequently --
    local spec = self:getNoTrespassingSpec()
    dt = spec.dt + dt
    if dt < NoTrespassing.UPDATE_INTERVAL_MS then
        spec.dt = dt
        return
    end
    spec.dt = 0
    -- / --
    if not g_currentMission.missionInfo.fruitDestruction then
        -- player disabled crop damage in options, so why bother --
        return
    end

    if not self.spec_enterable.isEntered then
        -- only inflict damage if someone is inside vehicle --
        return
    end

    if self.isClient and self:getIsActiveForInput(true) then
        -- print visible warning on screen --
        -- this is client-side function --
        if spec.displayWarning then
            if spec.totalPenalty > 0 then
                local text = string.format("%s (%s: %.0f)",
                                           g_i18n:getText("noTrespassing_warning_penalty"), 
                                           g_i18n:getText("noTrespassing_total_cost_label"), 
                                           math.floor(spec.totalPenalty))
                g_currentMission:showBlinkingWarning(text, NoTrespassing.WARNING_DISPLAY_TIME)
            end
            spec.displayWarning = false
        else
            spec.totalPenalty = 0
        end
    end

    if self.isServer then
        -- call deduce penalty from bank account --
        spec.penaltyCooldown = spec.penaltyCooldown - dt
        if spec.penalty > 0 and spec.penaltyCooldown < 0 then
            local farmId = self:getOwnerFarmId() 
            local stats = g_farmManager:getFarmById(g_currentMission.player.farmId).stats 
            stats:updateStats("expenses", spec.penalty) 
            g_currentMission:addMoney(-spec.penalty, farmId, MoneyType.TRANSFER)

            -- update statistics --
            g_noTrespassingMod.statistics.total = g_noTrespassingMod.statistics.total + spec.penalty

            spec.penaltyCooldown = NoTrespassing.PENALTY_COOLDOWN
            spec.penalty = 0
        end
    end

    local penalty = 0 -- variable for storing penalty for all wheels
    for k, wheel in pairs(self:getWheels()) do
        if self:getIsWheelFoliageDestructionAllowed(wheel) then -- this function checks AI helper drivinf over crops
            local width = 0.5 * wheel.width
            local length = math.min(0.5, 0.5 * wheel.width)
            local x, _, z = localToLocal(wheel.driveNode, wheel.repr, 0, 0, 0)

            local x0, y0, z0 = localToWorld(wheel.repr, x + width, 0, z - length) -- world coordinates of wheel center

            local farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(x0, z0)
            local farmland = g_farmlandManager:getFarmlandById(farmlandId)

            if farmland == nil then
                -- at least one wheel has contact with road - no damage (eg. driving wide combine harvesters) --
                return
            end

            if farmland.isOwned then
                -- drop procedure for owned fields --
                return
            end

            for f, field in pairs(g_fieldManager.farmlandIdFieldMapping[farmlandId]) do
                local mission = g_missionManager.fieldToMission[field.fieldId]
                if mission ~= nil and mission.farmId == self:getActiveFarm() then
                    -- field with active mission, stop --

                    spec.currentWarning = 0
                    spec.totalPenalty = 0
                    spec.penalty = 0

                    return
                end
            end

            local isOnField = wheel.densityType ~= 0
            if isOnField then
                -- distance... --
                local ds = self:getLastSpeed() * dt

                -- ...wheel width... --
                local tyreDamageCoeff = getTyreDamage(wheel)

                -- ...and ground properties... --
                local cropDamageCoeff = getCropDamage(x0, z0)

                -- ...by your powers combined, here I am... --
                penalty = penalty + ds * tyreDamageCoeff * cropDamageCoeff
            end
        end

        --[[ TODO: ADDITIONAL WHEELS ]]--
    end

    if penalty > 0 then
        local difficultyIdx = (g_noTrespassingMod.mission.missionInfo.economicDifficulty or g_noTrespassingMod.mission.missionInfo.difficulty)
        local difficultyCoeff = g_noTrespassingMod.data.difficulty[difficultyIdx]

        penalty = difficultyCoeff * penalty * NoTrespassing.AREA_COEFFICIENT

        spec.penalty = spec.penalty + penalty
        spec.totalPenalty = spec.totalPenalty + penalty
        spec.displayWarning = true
    end
end

function NoTrespassing:onWriteStream(streamId, connection)
    print(string.format("%s", "NoTrespassing:onWriteStream(streamId, connection)"))
end

function NoTrespassing:onReadStream(streamId, connection)
    print(string.format("%s", "NoTrespassing:onReadStream(streamId, connection)"))
end


function getTyreDamage(wheel)
    -- local data = g_noTrespassingMod.data
    -- todo: handle tracks, get additional attached wheels etc. --

    return wheel.width
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
                if fruitDesc.witheringNumGrowthStates <= state then
                    return g_noTrespassingMod.data.ground
                end

                local coeffs = g_noTrespassingMod.data.crops[fruitDesc.name]
                if coeffs == nil then
                    coeffs = g_noTrespassingMod.data.crops["BARLEY"]
                end

                if fruitDesc.cutState <= state then
                    return coeffs["harvested"]
                end

                if fruitDesc.minForageGrowthState <= state and state <= fruitDesc.maxHarvestingGrowthState then
                    return coeffs["base"] * coeffs["mature"]
                end

                if state <= fruitDesc.minForageGrowthState then
                    return coeffs["base"] * coeffs["young"]
                end
            end
        end
    end
    return g_noTrespassingMod.data.ground
end