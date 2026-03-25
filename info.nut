class StationRenamer extends GSInfo {

    function GetAuthor()        { return "Ginger Ninja XL"; }
    function GetName()          { return "[STA] Station Renamer"; }
    function GetDescription()   { return "Renames stations with unique town codes of configurable length."; }
    function GetVersion()       { return 1; }
    function GetDate()          { return "2026-02-13"; }
    function CreateInstance()   { return "StationRenamer"; }
    function GetShortName()     { return "STRN"; } // unique 4-letter ID
    function GetAPIVersion()    { return "15"; }

    function GetSettings() {
		AddSetting({
			name = "TownCodeLength",
			description = "Number of letters used for town codes when renaming stations",
			min_value = 2,
			max_value = 6,
			easy_value = 3,
			medium_value = 3,
			hard_value = 3,
			custom_value = 3,
			step_size = 1,
			flags = 0  // normal numeric setting
		});
		AddSetting({
			name = "SleepDuration",
			description = "Sleep duration in ticks between station renaming cycles (1 tick = 30ms)",
			min_value = 1,
			max_value = 500,
			easy_value = 10,
			medium_value = 10,
			hard_value = 10,
			custom_value = 10,
			step_size = 5,
			flags = 0  // normal numeric setting
		});
		AddSetting({
			name = "RenameAllStationsOnBoot",
			description = "DO NOT USE! All station names will be renamed every boot",
			min_value = 0,
			max_value = 1,
			easy_value = 0,
			medium_value = 0,
			hard_value = 0,
			custom_value = 0,
			step_size = 1,
			flags = GSInfo.CONFIG_BOOLEAN
		});
	}

}

RegisterGS(StationRenamer());
