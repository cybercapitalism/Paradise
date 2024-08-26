/datum
	var/gc_destroyed //Time when this object was destroyed.
	var/list/active_timers  //for SStimer
	var/list/datum_components //for /datum/components
	/// Status traits attached to this datum
	var/list/status_traits
	var/list/comp_lookup
	var/list/list/datum/callback/signal_procs
	var/var_edited = FALSE //Warranty void if seal is broken
	var/tmp/unique_datum_id = null

	/// Used by SSprocessing
	var/isprocessing = FALSE

/**
  * A cached version of our \ref
  * The brunt of \ref costs are in creating entries in the string tree (a tree of immutable strings)
  * This avoids doing that more then once per datum by ensuring ref strings always have a reference to them after they're first pulled
  */
	var/cached_ref

#ifdef REFERENCE_TRACKING
	/// When was this datum last touched by a reftracker?
	/// If this value doesn't match with the start of the search
	/// We know this datum has never been seen before, and we should check it
	var/last_find_references = 0
	/// How many references we're trying to find when searching
	var/references_to_clear = 0
	#ifdef REFERENCE_TRACKING_DEBUG
	///Stores info about where refs are found, used for sanity checks and testing
	var/list/found_refs
	#endif
#endif
	// If we have called dump_harddel_info already. Used to avoid duped calls (since we call it immediately in some cases on failure to process)
	// Create and destroy is weird and I wanna cover my bases
	var/harddel_deets_dumped = FALSE //===CHUGAFIX=== idk

// Default implementation of clean-up code.
// This should be overridden to remove all references pointing to the object being destroyed.
// Return the appropriate QDEL_HINT; in most cases this is QDEL_HINT_QUEUE.
/datum/proc/Destroy(force = FALSE, ...)
	SHOULD_CALL_PARENT(TRUE)
	tag = null

	// Close our open TGUIs
	SStgui.close_uis(src)

	var/list/timers = active_timers
	active_timers = null
	for(var/thing in timers)
		var/datum/timedevent/timer = thing
		if(timer.spent && !(timer.flags & TIMER_DELETE_ME))
			continue
		qdel(timer)

	//BEGIN: ECS SHIT
	var/list/dc = datum_components
	if(dc)
		var/all_components = dc[/datum/component]
		if(length(all_components))
			for(var/I in all_components)
				var/datum/component/C = I
				qdel(C, FALSE, TRUE)
		else
			var/datum/component/C = all_components
			qdel(C, FALSE, TRUE)
		dc.Cut()

	var/list/lookup = comp_lookup
	if(lookup)
		for(var/sig in lookup)
			var/list/comps = lookup[sig]
			if(length(comps))
				for(var/i in comps)
					var/datum/component/comp = i
					comp.UnregisterSignal(src, sig)
			else
				var/datum/component/comp = comps
				comp.UnregisterSignal(src, sig)
		comp_lookup = lookup = null

	for(var/target in signal_procs)
		UnregisterSignal(target, signal_procs[target])
	//END: ECS SHIT

	return QDEL_HINT_QUEUE


/// Return text from this proc to provide extra context to hard deletes that happen to it
/// Optional, you should use this for cases where replication is difficult and extra context is required
/// Can be called more then once per object, use harddel_deets_dumped to avoid duplicate calls (I am so sorry)
/datum/proc/dump_harddel_info()
	return

///images are pretty generic, this should help a bit with tracking harddels related to them
/image/dump_harddel_info()
	if(harddel_deets_dumped)
		return
	harddel_deets_dumped = TRUE
	return "Image icon: [icon] - icon_state: [icon_state] [loc ? "loc: [loc] ([loc.x],[loc.y],[loc.z])" : ""]"


/datum/nothing
	// Placeholder object, used for ispath checks. Has to be defined to prevent errors, but shouldn't ever be created.
