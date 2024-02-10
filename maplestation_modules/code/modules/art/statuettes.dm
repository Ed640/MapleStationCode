//Copied mostly from statues.dm with edits to apply for an item
/obj/item/statue/custom
	name = "custom statue"
	icon = 'icons/obj/art/statue.dmi'
	icon_state = "base"
	obj_flags = UNIQUE_RENAME
	appearance_flags = TILE_BOUND | PIXEL_SCALE | KEEP_TOGETHER//Added keep together in case targets has weird layering
	w_class = WEIGHT_CLASS_SMALL
	/// primary statue overlay
	var/mutable_appearance/content_ma
	var/static/list/greyscale_with_value_bump = list(0,0,0, 0,0,0, 0,0,1, 0,0,-0.05)

//When out in the world, is tiny like action figures, but can pick up to see better
/obj/item/statue/custom/Initialize(mapload)
	. = ..()
	AddElement(/datum/element/item_scaling, 0.4, 1)
	AddComponent(/datum/component/simple_rotation)

/obj/item/statue/AltClick(mob/user)
	return ..() // This hotkey is BLACKLISTED since it's used by /datum/component/simple_rotation

/obj/item/statue/custom/Destroy()
	content_ma = null
	return ..()

/obj/item/statue/custom/proc/set_visuals(model_appearance)
	if(content_ma)
		QDEL_NULL(content_ma)
	content_ma = new
	content_ma.appearance = model_appearance
	content_ma.pixel_x = 0
	content_ma.pixel_y = 0
	content_ma.alpha = 255

	var/static/list/plane_whitelist = list(FLOAT_PLANE, GAME_PLANE, FLOOR_PLANE)

	/// Ideally we'd have knowledge what we're removing but i'd have to be done on target appearance retrieval
	var/list/overlays_to_keep = list()
	for(var/mutable_appearance/special_overlay as anything in content_ma.overlays)
		var/mutable_appearance/real = new()
		real.appearance = special_overlay
		if(PLANE_TO_TRUE(real.plane) in plane_whitelist)
			content_ma.overlays -= real
			real.plane = FLOAT_PLANE
			real.layer = FLOAT_LAYER
			overlays_to_keep += real
		else
			content_ma.overlays -= real
	content_ma.overlays = overlays_to_keep

	var/list/underlays_to_keep = list()
	for(var/mutable_appearance/special_underlay as anything in content_ma.underlays)
		var/mutable_appearance/real = new()
		real.appearance = special_underlay
		if(PLANE_TO_TRUE(real.plane) in plane_whitelist)
			content_ma.underlays -= real
			real.plane = FLOAT_PLANE
			real.layer = FLOAT_LAYER
			underlays_to_keep += real
		else
			content_ma.underlays -= real
	content_ma.underlays = underlays_to_keep

	content_ma.appearance_flags &= ~KEEP_APART //Don't want this
	content_ma.filters = filter(type="color",color=greyscale_with_value_bump,space=FILTER_COLOR_HSV)
	content_ma.plane = FLOAT_PLANE
	content_ma.layer = FLOAT_LAYER
	update_appearance()

/obj/item/modeling_block/update_overlays()
	. = ..()
	if(!target_appearance_with_filters)
		return
	//We're only keeping one instance here that changes in the middle so we have to clone it to avoid managed overlay issues
	var/mutable_appearance/clone = new(target_appearance_with_filters)
	. += clone

/obj/item/statue/custom/update_overlays()
	. = ..()
	if(content_ma)
		. += content_ma

//Inhand version of a carving block that doesnt need a chisel
/obj/item/modeling_block
	name = "Modeling block"
	desc = "Ready for sculpting. Look for a subject and use in hand to sculpt."
	icon = 'icons/obj/art/statue.dmi'
	icon_state = "block"
	w_class = WEIGHT_CLASS_SMALL

	/// The thing it will look like - Unmodified resulting statue appearance
	var/current_target
	/// Currently chosen preset statue type
	var/current_preset_type
	/// statue completion from 0 to 1.0
	var/completion = 0
	/// Greyscaled target with cutout filter
	var/mutable_appearance/target_appearance_with_filters
	/// HSV color filters parameters
	var/static/list/greyscale_with_value_bump = list(0,0,0, 0,0,0, 0,0,1, 0,0,-0.05)

	//Adding chisel vars
	/// Block we're currently carving in
	var/obj/item/modeling_block/prepared_block
	/// If tracked user moves we stop sculpting
	var/mob/living/tracked_user
	/// Currently sculpting
	var/sculpting = FALSE

/obj/item/modeling_block/Initialize(mapload)
	. = ..()
	AddElement(/datum/element/item_scaling, 0.4, 1)

// Add to plastic recipes
/obj/item/stack/sheet/plastic/get_main_recipes()
	. = ..()
	. += list(new /datum/stack_recipe("Modeling block", /obj/item/modeling_block, 2, check_density = FALSE))


/obj/item/modeling_block/Destroy()
	current_target = null
	target_appearance_with_filters = null
	return ..()

// We aim at something to turn into our sculpting target
/obj/item/modeling_block/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	. = ..()

	if (!sculpting && ismovable(target))
		set_target(target,user)
		//skip sculpting time
		if(current_target != null)
			create_statue(user)

	return . | AFTERATTACK_PROCESSED_ITEM

/obj/item/modeling_block/proc/is_viable_target(mob/living/user, atom/movable/target)
	//Only things on turfs
	if(!isturf(target.loc))
		user.balloon_alert(user, "no sculpt target!")
		return FALSE
	//No big icon things
	var/list/icon_dimensions = get_icon_dimensions(target.icon)
	if(icon_dimensions["width"] > 2*world.icon_size || icon_dimensions["height"] > 2*world.icon_size)
		user.balloon_alert(user, "sculpt target is too big!")
		return FALSE
	return TRUE

/obj/item/modeling_block/proc/set_target(atom/movable/target, mob/living/user)
	if(!is_viable_target(user, target))
		return
	if(istype(target,/obj/item/statue/custom))
		var/obj/item/statue/custom/original = target
		current_target = original.content_ma
	else
		current_target = target.appearance
	var/mutable_appearance/ma = current_target
	user.balloon_alert(user, "sculpt target is [ma.name]")
/* Seeing if i can skip the sculpting time and/or if setting target works
/obj/item/modeling_block/attack_self(mob/user)
	create_statue(user)

/// Starts or continues the sculpting action on the carving block material
/obj/item/modeling_block/proc/start_sculpting(mob/living/user)
	user.balloon_alert(user, "sculpting block...")
	playsound(src, pick(usesound), 75, TRUE)
	sculpting = TRUE
	//How long whole process takes
	var/sculpting_time = 30 SECONDS
	//Single interruptible progress period
	var/sculpting_period = round(sculpting_time / world.icon_size) //this is just so it reveals pixels line by line for each.
	var/interrupted = FALSE
	var/remaining_time = sculpting_time - (prepared_block.completion * sculpting_time)

	var/datum/progressbar/total_progress_bar = new(user, sculpting_time, prepared_block)
	while(remaining_time > 0 && !interrupted)
		if(do_after(user, sculpting_period, target = prepared_block, progress = FALSE))
			var/time_delay = !(remaining_time % SCULPT_SOUND_INCREMENT)
			if(time_delay)
				playsound(src, 'sound/effects/break_stone.ogg', 50, TRUE)
			remaining_time -= sculpting_period
			prepared_block.set_completion((sculpting_time - remaining_time)/sculpting_time)
			total_progress_bar.update(sculpting_time - remaining_time)
		else
			interrupted = TRUE
	total_progress_bar.end_progress()
	if(!interrupted && !QDELETED(prepared_block))
		prepared_block.create_statue()
		user.balloon_alert(user, "statue finished")
	stop_sculpting(silent = !interrupted)

/obj/item/modeling_block/dropped(mob/user, silent)
	. = ..()
	stop_sculpting()

/// Cancel the sculpting action
/obj/item/modeling_block/proc/stop_sculpting(silent = FALSE)
	sculpting = FALSE
	if(prepared_block && prepared_block.completion == 0)
		prepared_block.reset_target()
	prepared_block = null

	if(!silent && tracked_user)
		tracked_user.balloon_alert(tracked_user, "sculpting cancelled!")

	if(tracked_user)
		UnregisterSignal(tracked_user, COMSIG_MOVABLE_MOVED)
		tracked_user = null

/obj/item/modeling_block/proc/on_moved()
	SIGNAL_HANDLER

	stop_sculpting()
	*/

/obj/item/modeling_block/proc/create_statue(mob/user)
	var/obj/item/statue/custom/new_statue = new(user.loc)
	new_statue.set_visuals(current_target)
	var/mutable_appearance/ma = current_target
	new_statue.name = "statuette of [ma.name]"
	new_statue.desc = "A carved statuette depicting [ma.name]."
	qdel(src)
	user.put_in_active_hand(new_statue, TRUE)

