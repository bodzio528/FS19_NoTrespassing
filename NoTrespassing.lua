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
NoTrespassing.UPDATE_INTERVAL_MS = 100.0 -- 1/10th second between penalty calculations
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

                -- ...wheel properties... --
                local tyreDamageCoeff = getTyreDamage(wheel)

                -- ...ground properties... --
                local cropDamageCoeff = 0.0
                if spec.seasons then
                    cropDamageCoeff = getCropDamageSeasons(x0, z0)
                else
                    cropDamageCoeff = getCropDamage(x0, z0)
                end

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

local l_cachedFruitType = nil

function setCachedFruitType(fruit)
    l_cachedFruitType = fruit
end

function getCachedFruitType()
    return l_cachedFruitType
end

function clearCachedFruitType()
    l_cachedFruitType = nil
end

function getFruitAt(x, z)
    print(string.format("start getFruiTypeIndexAt(x=%f, y=%f)", x, z))

	local widthX = widthX or 0.5;
	local widthZ = widthZ or 0.5;

	local density = 0;
	local totalArea = 0

    if getCachedFruitType() ~= nil then
        local cachedFruitType = getCachedFruitType()
        if cachedFruitType.index ~= FruitType.UNKNOWN then
            local minGrowthState, maxGrowthState = 1, cachedFruitType.numGrowthStates

            density, totalArea = FieldUtil.getFruitArea(x, z, x - widthX, z - widthZ, x + widthX, z + widthZ, 
                                                        {},                     -- terrainDetailRequiredValueRanges
                                                        {},                     -- terrainDetailProhibitValueRanges
                                                        cachedFruitType.index,  -- requiredFruitType
                                                        minGrowthState,         -- requiredMinGrowthState
                                                        maxGrowthState,         -- requiredMaxGrowthState
                                                        0,                      -- prohibitedFruitType
                                                        0,                      -- prohibitedMinGrowthState
                                                        0,                      -- prohibitedMaxGrowthState
                                                        false)                  -- useWindrowed
            if density > 0 then
                print(string.format("end getFruiTypeIndexAt(x=%f, y=%f) return [cached] fruitType=%s density=%d totalArea=%f", x, z, cachedFruitType.name, density, totalArea))
                return cachedFruitType, density, totalArea
            end
        end
    end

    -- clear cache --
    clearCachedFruitType()

	local maxDensity = 0;
	local maxFruitType = 0

    for i = 1, #g_fruitTypeManager.fruitTypes do
        if i ~= g_fruitTypeManager.nameToIndex['GRASS'] 
            and i ~= g_fruitTypeManager.nameToIndex['DRYGRASS'] 
            and i ~= g_fruitTypeManager.nameToIndex['WEED'] 
            and i ~= g_fruitTypeManager.nameToIndex["SEMIDRY_GRASS_WINDROW"] then 

            local fruitType = g_fruitTypeManager.fruitTypes[i]
            local minGrowthState, maxGrowthState = 1, fruitType.numGrowthStates

            density, totalArea = FieldUtil.getFruitArea(x, z, x - widthX, z - widthZ, x + widthX, z + widthZ, 
                                                        {},                 -- terrainDetailRequiredValueRanges
                                                        {},                 -- terrainDetailProhibitValueRanges
                                                        i,                  -- requiredFruitType
                                                        minGrowthState,     -- requiredMinGrowthState
                                                        maxGrowthState,     -- requiredMaxGrowthState
                                                        0,                  -- prohibitedFruitType
                                                        0,                  -- prohibitedMinGrowthState
                                                        0,                  -- prohibitedMaxGrowthState
                                                        false)              -- useWindrowed
            -- minimax algorithm to get most frequent crop type on on probed area --
            if density > maxDensity then
                maxDensity = density
                maxFruitType = i
            end
        end
    end

    if maxDensity > 0 then
        local fruitType = g_fruitTypeManager.fruitTypes[maxFruitType]

        -- I can save a whole lot of effort by caching last encountered fruit before exit --
        -- but doing so lifts function purity --
        setCachedFruitType(fruitType)

        print(string.format("end getFruiTypeIndexAt(x=%f, y=%f) return fruitType=%s density=%d totalArea=%f", x, z, fruitType.name, density, totalArea))
        return fruitType, maxDensity, totalArea
    end
        
    print(string.format("end getFruiTypeIndexAt(x=%f, y=%f) return fruitType=nil density=0 totalArea=0", x, z))
    return nil, 0, 0
end

function getCropDamageSeasons(x, z)
    print(string.format("start getCropDamageSeasons(x=%f, y=%f)", x, z))
    
    local data = g_noTrespassingMod.data

    local fruitType, density, totalArea = getFruitAt(x, z)
    DebugUtil.printTableRecursively(fruitType, "-", 0, 2, nil)
--[[
    local modifier = g_currentMission.densityMapModifiers.cutFruitArea.modifier
    for index, fruit in pairs(g_currentMission.fruits) do
        local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(index)
        
        modifier:resetDensityMapAndChannels(fruit.id, fruitDesc.startStateChannel, fruitDesc.numStateChannels)
        local d = 0.125 -- ori 0.5
        modifier:setParallelogramWorldCoords(x - d, z - d, 2*d,0, 0,2*d, "pvv")

        local area, totalArea, xyz = modifier:executeGet()
        if area > 0 then
            local state = area / totalArea   
            print(string.format(
                "FRUIT_DESC TABLE area=%f totalArea=%f xyz=%f state=%f", 
                area, totalArea, xyz, state))

            DebugUtil.printTableRecursively(fruitDesc, "-", 0, 2, nil)
            print("FRUIT_DESC TABLE END")
        end
    end
--]]
    print(string.format("end getCropDamageSeasons(x=%f, y=%f)", x, z))
    return 1.0
end

function getCropDamage(x, z)
    print(string.format("start getCropDamage(x=%f, y=%f)", x, z))


    print("end getCropDamage()")
    return 1.0
end

--function getGrowthStateCoeff(fruitDesc, state)
--    if fruitDesc.destruction == nil then 
--        return 0.0
--    end
--
--    if state == fruitDesc.destruction.state then
--        return 0.01 --tiny fee for harvested ground
--    end
--
--    if state < fruitDesc.destruction.filterStart then
--        return 0.25 -- fee for driving over first germination stages (sowed and germinated)
--    end
--
--    return 1.0
--end
--
--function getCropTypeCoeff(x, z) -- send fruits immune to damage there instead of calculating
--    local difficultyIdx = (self.mission.missionInfo.economicDifficulty or self.mission.missionInfo.difficulty)
--    local data = g_noTrespassingMod.data
--    print(string.format("getCropTypeCoeff (%f;%f) difficultyCoeff=%f", x, z, data.difficulty[difficultyIdx]))
--
--    local modifier = g_currentMission.densityMapModifiers.cutFruitArea.modifier
--    for index, fruit in pairs(g_currentMission.fruits) do
--        local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(index)
--
--        modifier:resetDensityMapAndChannels(fruit.id, fruitDesc.startStateChannel, fruitDesc.numStateChannels)
--        modifier:setParallelogramWorldCoords(x - 0.5, z - 0.5, 1,0, 0,1, "pvv")
--
--        local area, totalArea, _ = modifier:executeGet()
--        if area > 0 then
--            local state = area / totalArea
--            if "WEED" == fruitDesc.fruitName then 
--                return 0.0 
--            end
--            if "GRASS" == fruitDesc.fruitName then 
--                return 0.2
--            end 
--            if "SUGARCANE" == fruitDesc.fruitName then 
--                return 0.5 * getGrowthStateCoeff(fruitDesc, state) 
--            end
--            if "POTATO"  == fruitDesc.fruitName or "SUGARBEET" == fruitDesc.fruitName then 
--                return 0.75 * getGrowthStateCoeff(fruitDesc, state) 
--            end
--            if "SUNFLOWER" == fruitDesc.fruitName then
--                return 1.25 * getGrowthStateCoeff(fruitDesc, state) 
--            end
--            if "CANOLA" == fruitDesc.fruitName then
--                return 1.5
--            end
--            return 1.0 * getGrowthStateCoeff(fruitDesc, state)
--        end
--    end
--    return 1.0
--end
--
--function getTyreBaseDamage(wheel, dt, speed)
--    if wheel.isCareWheel then
--        return 0.0 -- narrow tires do not inflict damage to crops
--    end
--
--    if speed < 0.1 then
--        return 0.0
--    end
--
--    -- todo: base it on travelled distance, where distance = speed * dt
--    return wheel.width * dt * speed / 365.25
--end
--