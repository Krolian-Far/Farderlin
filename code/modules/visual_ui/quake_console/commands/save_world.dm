/datum/console_command/save_world
	command_key = "save_world"
	required_args = 0

/datum/console_command/save_world/help_information(obj/abstract/visual_ui_element/scrollable/console_output/output)
	output.add_line("save_world - Will force Tim's save to fire on all maps with the config enabled.")

/datum/console_command/save_world/execute(obj/abstract/visual_ui_element/scrollable/console_output/output, list/arg_list)
	. = ..()
	var/mob/current = output.parent.get_user()

	if(!current)
		output.add_line("Error: Unable to determine current user.")
		return

	var/mob_z = current.z
	if(!mob_z)
		output.add_line("Error: Unable to determine current Z level.")
		return

	var/round_id = GLOB.rogue_round_id || "unknown_round"
	output.add_line("Initiating world save...")
	output.add_line("Round ID: [round_id]")
	output.add_line("I fucking love coding.")

	SSpersistence.save_persistent_maps()

	output.add_line("Job's done.")
