--[[

No Trespassing Mod

register specialization script
--]]

if g_specializationManager:getSpecializationByName("NoTrespassing") == nil then

    local status = g_specializationManager:addSpecialization("noTrespassing", "NoTrespassing", Utils.getFilename("NoTrespassing.lua", g_currentModDirectory), true, nil)

    print("Mod: register spec noTrespassing by bodzio528")

    for typeName, typeEntry in pairs(g_vehicleTypeManager.vehicleTypes) do
        if typeEntry ~= nil and typeName ~= "locomotive" then
			local isDrivable = false;
			local isEnterable = false;
			local hasMotor = false;
			local isOwnSpec = false;

            for name, spec in pairs(typeEntry.specializationsByName) do
				if name == "drivable" then
					isDrivable = true;
				elseif name == "motorized" then
					hasMotor = true;
				elseif name == "enterable" then
					isEnterable = true;
				elseif name == "NoTrespassing" then
					isOwnSpec = true;
				end;
			end

			if isDrivable and isEnterable and hasMotor and not isOwnSpec then
				local obj = g_specializationManager:getSpecializationObjectByName("noTrespassing");
				typeEntry.specializationsByName["noTrespassing"] = obj;
				table.insert(typeEntry.specializationNames, "noTrespassing");
				table.insert(typeEntry.specializations, obj);

                print(string.format("spec noTrespassing added to type %s", typeName))
			end;
        end
    end
end