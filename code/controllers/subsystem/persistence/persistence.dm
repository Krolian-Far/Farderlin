#define FILE_ANTAG_REP "data/AntagReputation.json"
#define INFINITE_AUTOSAVES -1

SUBSYSTEM_DEF(persistence)
	name = "Persistence"
	init_order = INIT_ORDER_PERSISTENCE
	flags = SS_BACKGROUND
	wait = INFINITY
	runlevels = RUNLEVEL_GAME

	/// This is used to skip the 1st autosave that is automatically done vis the subsystems fire() at roundstart
	var/was_first_roundstart_autosave_skipped = FALSE

	var/list/saved_messages = list()
	var/list/saved_modes = list(1,2,3)
	var/list/saved_trophies = list()
	var/list/antag_rep = list()
	var/list/antag_rep_change = list()
	var/list/picture_logging_information = list()
	/// A list of map config jsons used by persistence organized by z-level traits
	var/list/map_configs_cache

/datum/controller/subsystem/persistence/Initialize()
	LoadRecentModes()
	if(CONFIG_GET(flag/use_antag_rep))
		LoadAntagReputation()
	LoadRandomizedRecipes()

	if(CONFIG_GET(number/persistent_autosave_period) > 0 && CONFIG_GET(flag/persistent_save_enabled))
		wait = CONFIG_GET(number/persistent_autosave_period) HOURS

	return ..()

/datum/controller/subsystem/persistence/fire(resumed = FALSE)
	if(!was_first_roundstart_autosave_skipped) // prevents pointless autosave at the start of the game
		was_first_roundstart_autosave_skipped = TRUE
		return

	save_world()

/// Saves map z-levels in the world based on PERSISTENT_SAVE_ENABLED config options in config/persistence.txt
/datum/controller/subsystem/persistence/proc/save_world()
	log_world("World map save initiated at [time_stamp()]")
	to_chat(world, span_boldannounce("World map save initiated at [time_stamp()]"))
	save_persistent_maps()
	to_chat(world, span_boldannounce("World map save finished at [time_stamp()]"))
	log_world("World map save finished at [time_stamp()]")
	prune_old_autosaves()

/datum/controller/subsystem/persistence/proc/LoadRecentModes()
	var/json_file = file("data/RecentModes.json")
	if(!fexists(json_file))
		return
	var/list/json = json_decode(file2text(json_file))
	if(!json)
		return
	saved_modes = json["data"]

/datum/controller/subsystem/persistence/proc/LoadAntagReputation()
	var/json = file2text(FILE_ANTAG_REP)
	if(!json)
		var/json_file = file(FILE_ANTAG_REP)
		if(!fexists(json_file))
			WARNING("Failed to load antag reputation. File likely corrupt.")
			return
		return
	antag_rep = json_decode(json)

/datum/controller/subsystem/persistence/proc/CollectData()
	CollectRoundtype()				//THIS IS PERSISTENCE, NOT THE LOGGING PORTION.
	if(CONFIG_GET(flag/use_antag_rep))
		CollectAntagReputation()
	SaveRandomizedRecipes()

/datum/controller/subsystem/persistence/proc/GetPhotoAlbums()
	var/album_path = file("data/old/photo_albums.json")
	if(fexists(album_path))
		return json_decode(file2text(album_path))

/datum/controller/subsystem/persistence/proc/GetPhotoFrames()
	var/frame_path = file("data/old/photo_frames.json")
	if(fexists(frame_path))
		return json_decode(file2text(frame_path))

/datum/controller/subsystem/persistence/proc/remove_duplicate_trophies(list/trophies)
	var/list/ukeys = list()
	. = list()
	for(var/trophy in trophies)
		var/tkey = "[trophy["path"]]-[trophy["message"]]"
		if(ukeys[tkey])
			continue
		else
			. += list(trophy)
			ukeys[tkey] = TRUE

/datum/controller/subsystem/persistence/proc/CollectRoundtype()
	saved_modes[3] = saved_modes[2]
	saved_modes[2] = saved_modes[1]
	saved_modes[1] = "storyteller"
	var/json_file = file("data/RecentModes.json")
	var/list/file_data = list()
	file_data["data"] = saved_modes
	fdel(json_file)
	WRITE_FILE(json_file, json_encode(file_data))

/datum/controller/subsystem/persistence/proc/CollectAntagReputation()
	var/ANTAG_REP_MAXIMUM = CONFIG_GET(number/antag_rep_maximum)

	for(var/p_ckey in antag_rep_change)
//		var/start = antag_rep[p_ckey]
		antag_rep[p_ckey] = max(0, min(antag_rep[p_ckey]+antag_rep_change[p_ckey], ANTAG_REP_MAXIMUM))

//		WARNING("AR_DEBUG: [p_ckey]: Committed [antag_rep_change[p_ckey]] reputation, going from [start] to [antag_rep[p_ckey]]")

	antag_rep_change = list()

	fdel(FILE_ANTAG_REP)
	text2file(json_encode(antag_rep), FILE_ANTAG_REP)


/datum/controller/subsystem/persistence/proc/LoadRandomizedRecipes()
	var/json_file = file("data/old/RandomizedChemRecipes.json")
	var/json
	if(fexists(json_file))
		json = json_decode(file2text(json_file))

	for(var/randomized_type in subtypesof(/datum/chemical_reaction/randomized))
		var/datum/chemical_reaction/randomized/R = new randomized_type
		var/loaded = FALSE
		if(R.persistent && json)
			var/list/recipe_data = json[R.id]
			if(recipe_data)
				if(R.LoadOldRecipe(recipe_data) && (daysSince(R.created) <= R.persistence_period))
					loaded = TRUE
		if(!loaded) //We do not have information for whatever reason, just generate new one
			R.GenerateRecipe()

		if(!R.HasConflicts()) //Might want to try again if conflicts happened in the future.
			add_chemical_reaction(R)

/datum/controller/subsystem/persistence/proc/SaveRandomizedRecipes()
	var/json_file = file("data/old/RandomizedChemRecipes.json")
	var/list/file_data = list()

	//asert globchems done
	for(var/randomized_type in subtypesof(/datum/chemical_reaction/randomized))
		var/datum/chemical_reaction/randomized/R = randomized_type
		R = get_chemical_reaction(initial(R.id)) //ew, would be nice to add some simple tracking
		if(R && R.persistent && R.id)
			var/recipe_data = list()
			recipe_data["timestamp"] = R.created
			recipe_data["required_reagents"] = R.required_reagents
			recipe_data["required_catalysts"] = R.required_catalysts
			recipe_data["required_temp"] = R.required_temp
			recipe_data["is_cold_recipe"] = R.is_cold_recipe
			recipe_data["results"] = R.results
			recipe_data["required_container"] = "[R.required_container]"
			file_data["[R.id]"] = recipe_data

	fdel(json_file)
	WRITE_FILE(json_file, json_encode(file_data))

///Returns the path to persistence maps directory based on current timestamp format via YYYY-MM-DD_UTC_hh.mm.ss
/datum/controller/subsystem/persistence/proc/get_current_persistence_map_directory()
	var/realtime = world.realtime
	var/time  = realtime //Probably bad but I can't be bothered right now
	var/map_directory = MAP_PERSISTENT_DIRECTORY + time
	return map_directory

///Deletes empty save directories and removes the oldest saves if the total count exceeds the max autosaves allowed in config
/datum/controller/subsystem/persistence/proc/prune_old_autosaves()
	if(!CONFIG_GET(flag/persistent_save_enabled))
		return
	if(CONFIG_GET(number/persistent_max_autosaves) == INFINITE_AUTOSAVES)
		return

	// organize by oldest saves first
	var/list/all_saves = get_all_saves(GLOBAL_PROC_REF(cmp_text_asc))
	if(!all_saves.len)
		return // no saves exist yet

	var/total_saves = all_saves.len
	var/saves_to_delete = total_saves - CONFIG_GET(number/persistent_max_autosaves)
	if(saves_to_delete <= 0)
		return

	for(var/i in 1 to saves_to_delete)
		var/oldest_autosave_full_path = MAP_PERSISTENT_DIRECTORY + all_saves[i]
		log_mapping("Deleted oldest autosave: [oldest_autosave_full_path]")
		log_admin("Deleted oldest autosave: [oldest_autosave_full_path]")
		fdel(oldest_autosave_full_path)

/// Returns the directory path to the last save if it exists
/datum/controller/subsystem/persistence/proc/get_last_save()
	// organize by newest saves first
	var/list/all_saves = get_all_saves(GLOBAL_PROC_REF(cmp_text_dsc))
	if(!all_saves.len)
		return // no saves exist yet

	return all_saves[1]

/// Based on the last recent save, get a list of all z levels as numbers which have the specific trait
/// Will return null if no traits match or a save file doesn't exist yet
/datum/controller/subsystem/persistence/proc/cache_z_levels_map_configs()
	var/last_save = MAP_PERSISTENT_DIRECTORY + get_last_save()
	if(!last_save)
		return null // no saves exist yet

	var/list/matching_z_levels = list()
	var/list/last_save_files = flist(last_save)

	// prune the map .dmm files from our list since we only need JSONs
	for(var/dmm_file in last_save_files)
		if(copytext("[dmm_file]", -4) == ".dmm")
			last_save_files.Remove(dmm_file)

	// make sure only json files exist in this list because we have to sort them a special way
	for(var/file in last_save_files)
		if(copytext("[file]", -5) != ".json")
			CRASH("[file] in [last_save] directory is neither a .json or .dmm file")

	sortTim(last_save_files, GLOBAL_PROC_REF(cmp_persistent_saves_asc))
	last_save = copytext(last_save, 1, -1) // drop the "/" from the directory

	var/list/persistent_save_z_levels = CONFIG_GET(keyed_list/persistent_save_z_levels)

	for(var/json_file in last_save_files)
		// need to reformat the file name and directory to work with load_map_config()
		json_file = copytext(json_file, 1, -5) // drop the ".json" from file name
		var/datum/map_config/map_config = load_map_config(json_file, last_save, persistence_save = TRUE)

		// for persistent autosaves, the name is always a number which indicates the z-level
		var/current_z = map_config.map_name
		if(!islist(map_config.traits))
			CRASH("Missing list of traits in autosave json for [last_save]/[current_z].json")

		// for multi-z maps if a trait is found on ANY z-levels, the entire map is considered to have that trait
		for(var/level in map_config.traits)
			if(persistent_save_z_levels[ZTRAIT_CENTCOM] && (ZTRAIT_CENTCOM in level))
				LAZYINITLIST(matching_z_levels[ZTRAIT_CENTCOM])
				matching_z_levels[ZTRAIT_CENTCOM] |= map_config
			else if(persistent_save_z_levels[ZTRAIT_STATION] && (ZTRAIT_STATION in level))
				LAZYINITLIST(matching_z_levels[ZTRAIT_STATION])
				matching_z_levels[ZTRAIT_STATION] |= map_config
			else if(persistent_save_z_levels[ZTRAIT_MINING] && (ZTRAIT_MINING in level))
				LAZYINITLIST(matching_z_levels[ZTRAIT_MINING])
				matching_z_levels[ZTRAIT_MINING] |= map_config
			else if(persistent_save_z_levels[ZTRAIT_SPACE_RUINS] && (ZTRAIT_SPACE_RUINS in level))
				LAZYINITLIST(matching_z_levels[ZTRAIT_SPACE_RUINS])
				matching_z_levels[ZTRAIT_SPACE_RUINS] |= map_config
			else if(persistent_save_z_levels[ZTRAIT_RESERVED] && (ZTRAIT_RESERVED in level)) // for shuttles in transit (hyperspace)
				LAZYINITLIST(matching_z_levels[ZTRAIT_RESERVED])
				matching_z_levels[ZTRAIT_RESERVED] |= map_config
			else if(persistent_save_z_levels[ZTRAIT_AWAY] && (ZTRAIT_AWAY in level)) // gateway away missions
				LAZYINITLIST(matching_z_levels[ZTRAIT_AWAY])
				matching_z_levels[ZTRAIT_AWAY] |= map_config

	if(!matching_z_levels.len)
		return null

	matching_z_levels[PERSISTENT_LOADED_Z_LEVELS] = list()
	map_configs_cache = matching_z_levels
	return map_configs_cache

/*
 * Helper proc to get all saves that returns a list of paths relative to MAP_PERSISTENT_DIRECTORY
 * This will also prune any empty save directories by deleting them automatically
 * Args:
 * * sorting_method: This determines the sorting method and must be either OLDEST or NEWEST
 */
/datum/controller/subsystem/persistence/proc/get_all_saves(sorting_method)
	var/list/all_saves = flist(MAP_PERSISTENT_DIRECTORY)

	// Prune any empty save directories
	for(var/path in all_saves)
		var/full_path = MAP_PERSISTENT_DIRECTORY + path

		if(!flist(full_path).len) // empty save directory
			log_mapping("Deleted empty autosave: [full_path]")
			log_admin("Deleted empty autosave: [full_path]")
			all_saves -= full_path
			fdel(full_path)

	sortTim(all_saves, sorting_method)
	return all_saves

/datum/controller/subsystem/persistence/proc/get_save_flags()
	var/flags = NONE

	var/list/persistent_save_flags = CONFIG_GET(keyed_list/persistent_save_flags)

	if(persistent_save_flags["objects"])
		flags |= SAVE_OBJECTS
	if(persistent_save_flags["objects_variables"])
		flags |= SAVE_OBJECTS_VARIABLES
	if(persistent_save_flags["objects_properties"])
		flags |= SAVE_OBJECTS_PROPERTIES

	if(persistent_save_flags["mobs"])
		flags |= SAVE_MOBS

	if(persistent_save_flags["turfs"])
		flags |= SAVE_TURFS

	if(persistent_save_flags["areas"])
		flags |= SAVE_AREAS

	return flags

/datum/controller/subsystem/persistence/proc/save_persistent_maps()
	var/map_save_directory = get_current_persistence_map_directory()
	var/save_flags = get_save_flags()
	var/list/persistent_save_z_levels = CONFIG_GET(keyed_list/persistent_save_z_levels)

	for(var/z in 1 to world.maxz)
		var/list/level_traits = list()
		var/datum/space_level/level_to_check = SSmapping.z_list[z]
		var/list/z_traits = level_to_check.traits
		if(level_to_check.xi || level_to_check.yi)
			z_traits["xi"] = level_to_check.xi
			z_traits["yi"] = level_to_check.yi
		level_traits += list(z_traits)

		// skip saving certain z-levels depending on config settings
		if(!persistent_save_z_levels[ZTRAIT_CENTCOM] && is_centcom_level(z))
			continue
		else if(!persistent_save_z_levels[ZTRAIT_STATION] && is_station_level(z))
			continue
		else if(!persistent_save_z_levels[ZTRAIT_MINING] && is_mining_level(z))
			continue
		else if(!persistent_save_z_levels[ZTRAIT_RESERVED] && is_reserved_level(z)) // for shuttles in transit (hyperspace)
			continue
		else if(!persistent_save_z_levels[ZTRAIT_AWAY] && is_away_level(z)) // gateway away missions
			continue

		var/bottom_z = z
		var/top_z = z
		if(is_multi_z_level(z))
			if(!SSmapping.level_trait(z, ZTRAIT_UP) || SSmapping.level_trait(z, ZTRAIT_DOWN))
				continue // skip all the other z levels if they aren't a bottom

			for(var/above_z in (bottom_z + 1) to world.maxz)
				var/datum/space_level/above_level_to_check = SSmapping.z_list[above_z]
				var/list/above_z_traits = above_level_to_check.traits
				if(above_level_to_check.xi || above_level_to_check.yi)
					above_z_traits["xi"] = above_level_to_check.xi
					above_z_traits["yi"] = above_level_to_check.yi
				level_traits += list(above_z_traits)

				if(!SSmapping.level_trait(above_z, ZTRAIT_UP) && SSmapping.level_trait(above_z, ZTRAIT_DOWN))
					top_z = above_z
					break

		var/map = write_map(1, 1, bottom_z, world.maxx, world.maxy, top_z, save_flags)

		var/file_path = "[map_save_directory]/[z].dmm"
		rustg_file_write(map, file_path)

		var/map_path = copytext(map_save_directory, 7) // drop the "_maps/" from directory

		var/json_data = list(
			"map_name" = level_to_check.name,
			"map_path" = map_path,
			"map_file" = "[z].dmm",
			"traits" = level_traits,
			"delve" = level_to_check.delve,
		)

		rustg_file_write(json_encode(json_data, JSON_PRETTY_PRINT), "[map_save_directory]/[z].json")

#undef FILE_ANTAG_REP
#undef INFINITE_AUTOSAVES
