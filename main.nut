class StationRenamer extends GSController {
    existing_stations_id = {};
    town_codes = {};
    used_town_codes = {};

    // Track assigned vehicle numbers for bus, tram, and truck stations within each town to ensure uniqueness
    vehicle_numbers = {
        bus = {},
        tram = {},
        truck = {}
    };

    station_numbers = {};

    // Name templates for different station types
    name_templates = {
        train = "{town}",
        airport = "{town} Airport",
        dock = "{town} Dock",
        bus = "{town} S{num}",
        tram = "{town} T{num}",
        truck = "{town} M{num}"
    };

    // Backup templates in case of name conflicts, include original name for reference
	backup_templates = {
        train = "{town}",
        airport = "{town} Airport",
        dock = "{town} Dock",
        bus = "{town} S{num}",
        tram = "{town} T{num}",
        truck = "{town} M{num}"
    };

    function Start() {

        local sleepduration = this.GetSetting("SleepDuration");
        local rename_on_boot = this.GetSetting("RenameAllStationsOnBoot");
        local previous_date = GSDate.GetCurrentDate();
        local i = 0;

        // Initial renaming on boot if enabled
        while (rename_on_boot) {
            local stations = GSStationList(GSStation.STATION_ANY);
            // Reset all data structures to ensure a clean state on boot renaming
            existing_stations_id = {};
            town_codes = {};
            used_town_codes = {};

            vehicle_numbers = {
                bus = {},
                tram = {},
                truck = {}
            };

            station_numbers = {};

            // If there are no stations, skip renaming
            if (stations == null || stations.IsEmpty()) { rename_on_boot = false; continue; }

            // Assign temporary unique names to all stations to avoid conflicts during renaming
            for (local id = stations.Begin(); !stations.IsEnd(); id = stations.Next()) {
            	this.SetStationName(id, i.tostring());
            	i++;
            }

            // Now rename stations with final names based on templates
            for (local id = stations.Begin(); !stations.IsEnd(); id = stations.Next()) {
                this.RenameStation(id);
                this.existing_stations_id[id] <- true;
            }

            rename_on_boot = false;
        }

        while (true) {
            local current_date = GSDate.GetCurrentDate();
            local stations = GSStationList(GSStation.STATION_ANY);

            // If there are no stations, skip this cycle
            if (stations == null || stations.IsEmpty()) { Sleep(sleepduration); previous_date = current_date; continue; }

            local current = {};

            // Track all current stations in the game
            for (local id = stations.Begin(); !stations.IsEnd(); id = stations.Next()) {
                current[id] <- true;
            }

            // Remove stations that no longer exist from tracking and free up their town codes and vehicle numbers
            foreach(id, _ in this.existing_stations_id) {
                if (!(id in current)) {
                    if (id in this.station_numbers) {
                    	local data = this.station_numbers[id];
                    	if (data != null) {
                    		delete vehicle_numbers[data.type][data.town_id][data.number];
                    		delete this.station_numbers[id];
                    	}
                    }
                    delete this.existing_stations_id[id];
                }
            }

            // Force rename stations that have been called "!rename"
            foreach(id, _ in current) {
                if (GSStation.GetName(id) == "!rename") {
                    if (id in this.existing_stations_id) delete this.existing_stations_id[id];
                    this.SetStationName(id, "Renaming...");
                    this.SetStationName(id, GSTown.GetName(GSStation.GetNearestTown(id)).tostring());
                    this.RenameStation(id);
                    this.existing_stations_id[id] <- true;
                }
            }


            // Rename any new stations that have been added since the last cycle
            foreach(id, _ in current) {
                if (!(id in this.existing_stations_id) && current_date >= previous_date) {
                    this.RenameStation(id);
                    this.existing_stations_id[id] <- true;
                }
            }

            previous_date = current_date;
            Sleep(sleepduration);
        }
    }

    // Pad a number with leading zeros to ensure it is at least 3 digits long
    function PadNumber(num) {
        if (num < 10) return "0" + num;
        if (num < 100) return "" + num;
        return num.tostring();
    }

    // Truncate station name to 31 characters if needed
    function TruncateName(name) {
        if (name.len() <= 31) return name;
        return name.slice(0, 31);
    }

    // Returns the next available vehicle number for the given type and town
    function GetNextVehicleNumber(type, town_id) {
        if (!(town_id in vehicle_numbers[type])) vehicle_numbers[type][town_id] <- {};
        local used_numbers = vehicle_numbers[type][town_id];

        local n = 1;
        while (n in used_numbers) n++;
        used_numbers[n] <- true;
        return n;
    }

    // Replace placeholders in the template with actual values
	function ReplaceTemplate(template, values) {
		local result = template;
		foreach(key, val in values) {
			local placeholder = "{" + key + "}";
			local pos = result.find(placeholder);
			while (pos != null) {
				result = result.slice(0,pos) + val + result.slice(pos + placeholder.len());
				pos = result.find(placeholder);
			}
		}
		return result;
	}

    // Main function to rename a station based on its type, nearest town, and assigned vehicle number if applicable
    function RenameStation(station_id) {
        // Need to act as the company that owns the station to rename it
        local company_id = GSBaseStation.GetOwner(station_id);
        local mode = GSCompanyMode(company_id);

        local town_id = GSStation.GetNearestTown(station_id);
        local code = this.GetTownCode(town_id);
        local town_name = GSTown.GetName(town_id);

		local old_station_name = GSStation.GetName(station_id);

        // Use fallback values if town name or station name is empty
        if (town_name == null || town_name == "") town_name = "Unknown";
        if (old_station_name == null) old_station_name = "";

        local code_prefix = "[" + code + "] ";

        // If the station already has the correct code prefix, remove it to get the base name for backup template
        if (old_station_name.find(code_prefix) == 0) {
            old_station_name = old_station_name.slice(code_prefix.len());
            if (old_station_name.len() > 0 && old_station_name[0] == " ") old_station_name = old_station_name.slice(1);
        }

        local new_name = null;
        local backup_name = null;

        local template = null;
		local backup_template = null;

        // Determine station type and select appropriate naming templates
        // TRAIN, AIRPORT, DOCK
        if (GSStation.HasStationType(station_id, GSStation.STATION_TRAIN)) {
        	template = this.name_templates.train;
			backup_template = this.backup_templates.train;
        }
        else if (GSStation.HasStationType(station_id, GSStation.STATION_AIRPORT)) {
        	template = this.name_templates.airport;
			backup_template = this.backup_templates.airport;
        }
        else if (GSStation.HasStationType(station_id, GSStation.STATION_DOCK)) {
        	template = this.name_templates.dock;
			backup_template = this.backup_templates.dock;
        }

        // TRUCK
		else if (GSStation.HasStationType(station_id, GSStation.STATION_TRUCK_STOP)) {
            // Assign a unique number to the station within the town
			if (!(station_id in this.station_numbers)) {
                local num = this.GetNextVehicleNumber("truck", town_id);
                this.station_numbers[station_id] <- {number=num, type="truck", town_id=town_id};
            }
            template = this.name_templates.truck;
            backup_template = this.backup_templates.truck;
            }

        // BUS or TRAM
		else if (GSStation.HasStationType(station_id, GSStation.STATION_BUS_STOP)) {
            // TRAM
			if (GSStation.HasRoadType(station_id, GSRoad.ROADTYPE_TRAM)) {
                // Assign a unique number to the station within the town
				if (!(station_id in this.station_numbers)) {
                    local num = this.GetNextVehicleNumber("tram", town_id);
                    this.station_numbers[station_id] <- {number=num, type="tram", town_id=town_id};
                }
                template = this.name_templates.tram;
                backup_template = this.backup_templates.tram;
			}
			else {
				// BUS
                // Assign a unique number to the station within the town
                if (!(station_id in this.station_numbers)) {
                    local num = this.GetNextVehicleNumber("bus", town_id);
                    this.station_numbers[station_id] <- {number=num, type="bus", town_id=town_id};
                }
                template = this.name_templates.bus;
				backup_template = this.backup_templates.bus;
			}
		}

		local num_str = "000";

		if (station_id in this.station_numbers) {
			num_str = this.PadNumber(this.station_numbers[station_id].number);
		}

        if (template == null) return;

        // Generate the new station name using the selected template and values
        new_name = this.ReplaceTemplate(template, {
			code = code,
			town = town_name,
			num  = num_str
		});

        // Generate the backup name using the backup template, which includes the original station name for reference
		backup_name = this.ReplaceTemplate(backup_template, {
			code = code,
			town = town_name,
			name = old_station_name,
			num  = num_str
		});

        // Get the current station name to check for conflicts before renaming
        local current_name = GSStation.GetName(station_id);
        if (current_name != new_name) {
            // Try to set the new station name
        	if (!GSStation.SetName(station_id, new_name)) {
                // If setting the new name fails, attempt to set the backup name
                if (current_name != backup_name) {
                    if (!GSStation.SetName(station_id, backup_name)) {
                        // If both attempts fail, append a unique number to the new name
                        local attempt = 1;
                        while (!GSStation.SetName(station_id, new_name + "-" + attempt.tostring())) {
                        	attempt++;
                        	if (attempt > 999) break;
                        }
        			}
        	    }
            }
        }
	}

    // Helper function to set station name
    function SetStationName(station_id, name) {
        // Need to act as the company that owns the station to rename it
        local company_id = GSBaseStation.GetOwner(station_id);
        local mode = GSCompanyMode(company_id);

        GSStation.SetName(station_id, name);
    }

    // Function to generate a unique 3-letter town code based on the town name
    function GetTownCode(town_id) {
        // If the town code has already been generated for this town, return it
        if (town_id in this.town_codes) {
            return this.town_codes[town_id];
        }

        local town_name = GSTown.GetName(town_id);
        // Use town ID as fallback if town name is empty
        if (town_name == null || town_name == "") town_name = "ZZZ" + town_id.tostring();

        // Remove non-letter characters from the town name
        local cleaned = "";
        foreach (i, c in town_name) {
            local ch = c.tochar();
            if ((ch >= "A" && ch <= "Z") || (ch >= "a" && ch <= "z")) {
                cleaned += ch;
            }
        }
        town_name = cleaned;

        // Generate initial code from the first 3 letters of the cleaned town name, padded with "X" if needed
        local code = "";
        for (local i = 0; i < 3 && i < town_name.len(); i++) {
            code += town_name[i].tochar().toupper();
        }
        while (code.len() < 3) code += "X";

        // If the generated code is already in use, try to create a unique code by replacing letters
        local original = [];
        for (local i = 0; i < code.len(); i++) {
            original.append(code[i].tochar().toupper());
        }

        local name_array = [];
        for (local i = 0; i < town_name.len(); i++) {
            name_array.append(town_name[i].tochar().toupper());
        }

        local extra_letters = ["X", "Y", "Z", "Q", "W"];
        local extra_index = 0;
        local position = 2;
        local attempt = 0;

        // Try different combinations of letters from the town name and extra letters to generate a unique code
        while (code in this.used_town_codes) {
            attempt++;

            // First try replacing the last letter with subsequent letters from the town name
            if (position < name_array.len()) {
                code = original[0] + original[1] + name_array[position];
                position++;
            // Then try replacing letters with extra letters if we run out of letters in the town name
            } else if (extra_index < extra_letters.len()) {
                code = original[0] + original[1] + extra_letters[extra_index];
                extra_index++;
            // Then try replacing the middle letter with extra letters
            } else if (extra_index < 2 * extra_letters.len()) {
                local mid = extra_index - extra_letters.len();
                code = original[0] + extra_letters[mid] + original[2];
                extra_index++;
            // Then try replacing the first letter with extra letters
            } else if (extra_index < 3 * extra_letters.len()) {
                local start = extra_index - 2 * extra_letters.len();
                code = extra_letters[start] + original[1] + original[2];
                extra_index++;
            // If all combinations are exhausted, generate a random code
            } else {
                code = "";
                for (local r = 0; r < 3; r++) {
                    code += String.fromchar(65 + (Random() % 26));
                }
            }

            if (attempt > 999) break;
        }

        // Use "XXX" as a fallback
        if (code == "") code = "XXX";

        this.used_town_codes[code] <- true;
        this.town_codes[town_id] <- code;
        return code;
    }


    // Save function to persist the state of the mod when the game is saved
    function Save() {
        return {
            existing_stations_id = this.existing_stations_id,
            town_codes = this.town_codes,
            used_town_codes = this.used_town_codes,
            vehicle_numbers = this.vehicle_numbers,
            station_numbers = this.station_numbers
        };
    }

    // Load function to restore the state of the mod when the game is loaded
    function Load(version, data) {
        if ("existing_stations_id" in data) this.existing_stations_id = data.existing_stations_id;
        if ("town_codes" in data) this.town_codes = data.town_codes;
        if ("used_town_codes" in data) this.used_town_codes = data.used_town_codes;
        if ("vehicle_numbers" in data) this.vehicle_numbers = data.vehicle_numbers;
        if ("station_numbers" in data) this.station_numbers = data.station_numbers;
    }
}
