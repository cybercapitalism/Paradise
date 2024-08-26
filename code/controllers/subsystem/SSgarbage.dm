SUBSYSTEM_DEF(garbage)
	name = "Garbage"
	priority = FIRE_PRIORITY_GARBAGE
	wait = 2 SECONDS
	flags = SS_POST_FIRE_TIMING|SS_BACKGROUND|SS_NO_INIT
	runlevels = RUNLEVELS_DEFAULT | RUNLEVEL_LOBBY
	init_order = INIT_ORDER_GARBAGE // AA 2020: Why does this have an init order if it has SS_NO_INIT? | AA 2022: Its used for shutdown
	offline_implications = "Garbage collection is no longer functional, and objects will not be qdel'd. Immediate server restart recommended."
	cpu_display = SS_CPUDISPLAY_HIGH

	var/list/collection_timeout = list(GC_FILTER_QUEUE, GC_CHECK_QUEUE, GC_DEL_QUEUE) // deciseconds to wait before moving something up in the queue to the next level

	//Stat tracking
	var/delslasttick = 0			// number of del()'s we've done this tick
	var/gcedlasttick = 0			// number of things that gc'ed last tick
	var/totaldels = 0
	var/totalgcs = 0

	var/highest_del_time = 0
	var/highest_del_tickusage = 0

	var/list/pass_counts
	var/list/fail_counts

	var/list/items = list()			// Holds our qdel_item statistics datums

	//Queue
	var/list/queues

	#ifdef REFERENCE_TRACKING
	var/list/reference_find_on_fail = list()
	var/ref_search_stop = FALSE
	#endif


/datum/controller/subsystem/garbage/PreInit()
	InitQueues()

/datum/controller/subsystem/garbage/get_stat_details()
	var/list/msg = list()
	var/list/counts = list()
	for(var/list/L in queues)
		counts += length(L)
	msg += "Q:[counts.Join(", ")] | D:[delslasttick] | S:[gcedlasttick] |"
	msg += "GCR:"
	if(!(delslasttick + gcedlasttick))
		msg += "n/a|"
	else
		msg += "[round((gcedlasttick / (delslasttick + gcedlasttick)) * 100, 0.01)]% |"

	msg += "TD:[totaldels] | TS:[totalgcs] |"
	if(!(totaldels + totalgcs))
		msg += "n/a|"
	else
		msg += "TGCR:[round((totalgcs / (totaldels + totalgcs)) * 100, 0.01)]% |"
	msg += " P:[pass_counts.Join(",")]"
	msg += " | F:[fail_counts.Join(",")]"
	return msg.Join("")

/datum/controller/subsystem/garbage/get_metrics()
	. = ..()
	var/list/cust = list()
	if((delslasttick + gcedlasttick) == 0) // Account for DIV0
		cust["gcr"] = 0
	else
		cust["gcr"] = (gcedlasttick / (delslasttick + gcedlasttick))
	cust["total_harddels"] = totaldels
	cust["total_softdels"] = totalgcs
	var/i = 0
	for(var/list/L in queues)
		i++
		cust["queue_[i]"] = length(L)

	.["custom"] = cust

/datum/controller/subsystem/garbage/Shutdown()
	//Adds the del() log to the qdel log file
	var/list/dellog = list()

	//sort by how long it's wasted hard deleting
	sortTim(items, GLOBAL_PROC_REF(cmp_qdel_item_time), TRUE)
	for(var/path in items)
		var/datum/qdel_item/I = items[path]
		dellog += "Path: [path]"
		if(I.failures)
			dellog += "\tFailures: [I.failures]"
		dellog += "\tqdel() Count: [I.qdels]"
		dellog += "\tDestroy() Cost: [I.destroy_time]ms"
		if(I.hard_deletes)
			dellog += "\tTotal Hard Deletes [I.hard_deletes]"
			dellog += "\tTime Spent Hard Deleting: [I.hard_delete_time]ms"
			dellog += "\tAverage References During Hardel: [I.reference_average] references."
		if(I.slept_destroy)
			dellog += "\tSleeps: [I.slept_destroy]"
		if(I.no_respect_force)
			dellog += "\tIgnored force: [I.no_respect_force] times"
		if(I.no_hint)
			dellog += "\tNo hint: [I.no_hint] times"
		if(LAZYLEN(I.extra_details))
			dellog += "\tExtra details: [I.extra_details]"
	log_qdel(dellog.Join("\n"))

/datum/controller/subsystem/garbage/fire()
	//the fact that this resets its processing each fire (rather then resume where it left off) is intentional.
	var/queue = GC_QUEUE_FILTER

	while(state == SS_RUNNING)
		switch(queue)
			if(GC_QUEUE_FILTER)
				HandleQueue(GC_QUEUE_FILTER)
				queue = GC_QUEUE_FILTER + 1
			if(GC_QUEUE_CHECK)
				HandleQueue(GC_QUEUE_CHECK)
				queue = GC_QUEUE_CHECK + 1
			if(GC_QUEUE_HARDDELETE)
				HandleQueue(GC_QUEUE_HARDDELETE)
				if(state == SS_PAUSED) //make us wait again before the next run.
					state = SS_RUNNING
				break

/datum/controller/subsystem/garbage/proc/InitQueues()
	if(isnull(queues)) // Only init the queues if they don't already exist, prevents overriding of recovered lists
		queues = new(GC_QUEUE_COUNT)
		pass_counts = new(GC_QUEUE_COUNT)
		fail_counts = new(GC_QUEUE_COUNT)
		for(var/i in 1 to GC_QUEUE_COUNT)
			queues[i] = list()
			pass_counts[i] = 0
			fail_counts[i] = 0

/datum/controller/subsystem/garbage/proc/HandleQueue(level = GC_QUEUE_FILTER)
	if(level == GC_QUEUE_FILTER)
		delslasttick = 0
		gcedlasttick = 0
	var/cut_off_time = world.time - collection_timeout[level] //ignore entries newer then this
	var/list/queue = queues[level]
	var/static/lastlevel
	var/static/count = 0
	if(count) //runtime last run before we could do this.
		var/c = count
		count = 0 //so if we runtime on the Cut, we don't try again.
		var/list/lastqueue = queues[lastlevel]
		lastqueue.Cut(1, c + 1)

	lastlevel = level

// 1 from the hard reference in the queue, and 1 from the variable used before this
#define REFS_WE_EXPECT 2

	//We do this rather then for(var/refID in queue) because that sort of for loop copies the whole list.
	//Normally this isn't expensive, but the gc queue can grow to 40k items, and that gets costly/causes overrun.
	for(var/i in 1 to length(queue))
		var/list/L = queue[i]
		if(length(L) < GC_QUEUE_ITEM_INDEX_COUNT)
			count++
			if(MC_TICK_CHECK)
				return
			continue

		var/queued_at_time = L[GC_QUEUE_ITEM_QUEUE_TIME]
		if(queued_at_time > cut_off_time)
			break // Everything else is newer, skip them
		count++

		var/GCd_at_time = L[GC_QUEUE_ITEM_GCD_DESTROYED]

		var/refID = L[GC_QUEUE_ITEM_REF]
		var/datum/D
		D = locate(refID)

		if(refcount(D) == REFS_WE_EXPECT) // So if something else coincidently gets the same ref, it's not deleted by mistake
			++gcedlasttick
			++totalgcs
			pass_counts[level]++
			#ifdef REFERENCE_TRACKING
			reference_find_on_fail -= text_ref(D) //It's deleted we don't care anymore.
			#endif
			if(MC_TICK_CHECK)
				return
			continue

		// Something's still referring to the qdel'd object.
		fail_counts[level]++

		#ifdef REFERENCE_TRACKING
		var/ref_searching = FALSE
		#endif

		switch(level)
			if(GC_QUEUE_CHECK)
				#ifdef REFERENCE_TRACKING
				var/remaining_refs = refcount(D) - REFS_WE_EXPECT
				if(reference_find_on_fail[text_ref(D)])
					INVOKE_ASYNC(D, TYPE_PROC_REF(/datum, find_references), remaining_refs)
					ref_searching = TRUE
				#ifdef GC_FAILURE_HARD_LOOKUP
				else
					INVOKE_ASYNC(D, TYPE_PROC_REF(/datum, find_references), remaining_refs)
					ref_searching = TRUE
				#endif
				reference_find_on_fail -= text_ref(D)
				#endif
				var/type = D.type
				var/datum/qdel_item/I = items[type]

				var/message = "## TESTING: GC: -- [text_ref(D)] | [type] was unable to be GC'd --"
				message = "[message] (ref count of [refcount(D)])"
				log_world(message)

				var/detail = D.dump_harddel_info()
				if(detail)
					LAZYADD(I.extra_details, detail)

				#ifdef TESTING
				for(var/c in GLOB.admins) //Using testing() here would fill the logs with ADMIN_VV garbage
					var/client/admin = c
					if(!check_rights_for(admin, R_ADMIN))
						continue
					to_chat(admin, "## TESTING: GC: -- [ADMIN_VV(D)] | [type] was unable to be GC'd --")
				#endif
				I.failures++
			if(GC_QUEUE_HARDDELETE)
				HardDelete(D)
				if(MC_TICK_CHECK)
					return
				continue

		Queue(D, level + 1)

		#ifdef REFERENCE_TRACKING
		if(ref_searching)
			return
		#endif

		if(MC_TICK_CHECK)
			return
	if(count)
		queue.Cut(1, count + 1)
		count = 0

#undef REFS_WE_EXPECT

/datum/controller/subsystem/garbage/proc/Queue(datum/D, level = GC_QUEUE_FILTER)
	if(isnull(D))
		return
	if(level > GC_QUEUE_COUNT)
		HardDelete(D)
		return
	var/queue_time = world.time

	var/refid = text_ref(D)
	var/static/uid = 0
	if(D.gc_destroyed <= 0)
		uid = WRAP(uid + 1, 1, SHORT_REAL_LIMIT - 1)
		D.gc_destroyed = uid

	var/list/queue = queues[level]

	queue[++queue.len] = list(queue_time, refid, D.gc_destroyed) // not += for byond reasons

//this is mainly to separate things profile wise.
/datum/controller/subsystem/garbage/proc/HardDelete(datum/D)
	var/time = world.timeofday
	var/tick = TICK_USAGE
	var/ticktime = world.time
	++delslasttick
	++totaldels
	var/type = D.type
	var/refID = text_ref(D)

	del(D)

	tick = (TICK_USAGE - tick + ((world.time - ticktime) / world.tick_lag * 100))

	var/datum/qdel_item/I = items[type]

	I.hard_deletes++
	I.hard_delete_time += TICK_DELTA_TO_MS(tick)
	I.reference_average = (refcount(I) + I.reference_average) / I.hard_deletes


	if(tick > highest_del_tickusage)
		highest_del_tickusage = tick
	time = world.timeofday - time
	if(!time && TICK_DELTA_TO_MS(tick) > 1)
		time = TICK_DELTA_TO_MS(tick) / 100
	if(time > highest_del_time)
		highest_del_time = time
	if(time > 10)
		log_game("Error: [type]([refID]) took longer than 1 second to delete (took [time / 10] seconds to delete)")
		message_admins("Error: [type]([refID]) took longer than 1 second to delete (took [time / 10] seconds to delete).")
		postpone(time)

/datum/controller/subsystem/garbage/Recover()
	InitQueues() //We first need to create the queues before recovering data
	if(istype(SSgarbage.queues))
		for(var/i in 1 to length(SSgarbage.queues))
			queues[i] |= SSgarbage.queues[i]


/datum/qdel_item
	var/name = ""
	var/qdels = 0			//Total number of times it's passed thru qdel.
	var/destroy_time = 0	//Total amount of milliseconds spent processing this type's Destroy()
	var/failures = 0		//Times it was queued for soft deletion but failed to soft delete.
	var/hard_deletes = 0 	//Different from failures because it also includes QDEL_HINT_HARDDEL deletions
	var/hard_delete_time = 0//Total amount of milliseconds spent hard deleting this type.
	var/no_respect_force = 0//Number of times it's not respected force=TRUE
	var/no_hint = 0			//Number of times it's not even bother to give a qdel hint
	var/slept_destroy = 0	//Number of times it's slept in its destroy
	/// Average amount of references that the hard deleted item holds when hard deleted
	var/reference_average = 0
	var/list/extra_details //!Lazylist of string metadata about the deleted objects

/datum/qdel_item/New(mytype)
	name = "[mytype]"

#ifdef REFERENCE_TRACKING
/proc/qdel_and_find_ref_if_fail(datum/thing_to_del, force = FALSE)
	thing_to_del.qdel_and_find_ref_if_fail(force)

/datum/proc/qdel_and_find_ref_if_fail(force = FALSE)
	SSgarbage.reference_find_on_fail[text_ref(src)] = TRUE
	qdel(src, force)

#endif

// Should be treated as a replacement for the 'del' keyword.
// Datums passed to this will be given a chance to clean up references to allow the GC to collect them.
/proc/qdel(datum/D, force = FALSE, ...)
	if(!istype(D))
		del(D)
		return

	var/datum/qdel_item/I = SSgarbage.items[D.type]
	if(!I)
		I = SSgarbage.items[D.type] = new /datum/qdel_item(D.type)
	I.qdels++

	if(isnull(D.gc_destroyed))
		if(SEND_SIGNAL(D, COMSIG_PARENT_PREQDELETED, force)) // Give the components a chance to prevent their parent from being deleted
			return
		D.gc_destroyed = GC_CURRENTLY_BEING_QDELETED
		var/start_time = world.time
		var/start_tick = world.tick_usage
		SEND_SIGNAL(D, COMSIG_PARENT_QDELETING, force) // Let the (remaining) components know about the result of Destroy
		var/hint = D.Destroy(arglist(args.Copy(2))) // Let our friend know they're about to get fucked up.
		if(world.time != start_time)
			I.slept_destroy++
		else
			I.destroy_time += TICK_USAGE_TO_MS(start_tick)
		if(!D)
			return
		switch(hint)
			if(QDEL_HINT_QUEUE)		//qdel should queue the object for deletion.
				SSgarbage.Queue(D)
			if(QDEL_HINT_IWILLGC)
				D.gc_destroyed = world.time
				return
			if(QDEL_HINT_LETMELIVE)	//qdel should let the object live after calling destory.
				if(!force)
					D.gc_destroyed = null //clear the gc variable (important!)
					return
				// Returning LETMELIVE after being told to force destroy
				// indicates the objects Destroy() does not respect force
				#ifdef TESTING
				if(!I.no_respect_force)
					testing("WARNING: [D.type] has been force deleted, but is \
						returning an immortal QDEL_HINT, indicating it does \
						not respect the force flag for qdel(). It has been \
						placed in the queue, further instances of this type \
						will also be queued.")
				#endif
				I.no_respect_force++

				SSgarbage.Queue(D)
			if(QDEL_HINT_HARDDEL)		//qdel should assume this object won't gc, and queue a hard delete
				SSgarbage.Queue(D, GC_QUEUE_HARDDELETE)
			if(QDEL_HINT_HARDDEL_NOW)	//qdel should assume this object won't gc, and hard del it post haste.
				SSgarbage.HardDelete(D)
			#ifdef REFERENCE_TRACKING
			if(QDEL_HINT_FINDREFERENCE)//qdel will, if TESTING is enabled, display all references to this object, then queue the object for deletion.
				SSgarbage.Queue(D)
				INVOKE_ASYNC(D, TYPE_PROC_REF(/datum, find_references))
			if(QDEL_HINT_IFFAIL_FINDREFERENCE)
				SSgarbage.Queue(D)
				SSgarbage.reference_find_on_fail[text_ref(D)] = TRUE
			#endif
			else
				#ifdef TESTING
				if(!I.no_hint)
					log_gc("WARNING: [D.type] is not returning a qdel hint. It is being placed in the queue. Further instances of this type will also be queued.")
				#endif
				I.no_hint++
				SSgarbage.Queue(D)
	else if(D.gc_destroyed == GC_CURRENTLY_BEING_QDELETED)
		CRASH("[D.type] destroy proc was called multiple times, likely due to a qdel loop in the Destroy logic")

// CHUGA - everything below goes into reference_tracking.dm
#ifdef REFERENCE_TRACKING
#define REFSEARCH_RECURSE_LIMIT 64

/datum/proc/find_references(references_to_clear = INFINITY)
	// set category = "Debug"
	// set name = "Find References"

	// if(!check_rights(R_DEBUG))
	// 	return
	// find_references(FALSE)
	if(usr?.client)
		if(tgui_alert(usr,"Running this will lock everything up for about 5 minutes.  Would you like to begin the search?", "Find References", list("Yes", "No")) != "Yes")
			return

	src.references_to_clear = references_to_clear
	//this keeps the garbage collector from failing to collect objects being searched for in here
	SSgarbage.can_fire = FALSE

	_search_references()
	//restart the garbage collector
	SSgarbage.can_fire = TRUE
	SSgarbage.update_nextfire(reset_time = TRUE)

/datum/proc/_search_references()
	log_gc("Beginning search for references to a [type], looking for [references_to_clear] refs.")

	var/starting_time = world.time
	//Time to search the whole game for our ref
	DoSearchVar(GLOB, "GLOB", starting_time) //globals
	log_gc("Finished searching globals")
	if(src.references_to_clear == 0)
		return

	//Yes we do actually need to do this. The searcher refuses to read weird lists
	//And global.vars is a really weird list
	var/global_vars = list()
	for(var/key in global.vars)
		global_vars[key] = global.vars[key]

	DoSearchVar(global_vars, "Native Global", starting_time)
	log_gc("Finished searching native globals")
	if(src.references_to_clear == 0)
		return

	for(var/datum/thing in world) //atoms (don't believe its lies)
		DoSearchVar(thing, "World -> [thing.type]", starting_time)
		if(src.references_to_clear == 0)
			break
	log_gc("Finished searching atoms")
	if(src.references_to_clear == 0)
		return

	for(var/datum/thing) //datums
		DoSearchVar(thing, "Datums -> [thing.type]", starting_time)
		if(src.references_to_clear == 0)
			break
	log_gc("Finished searching datums")
	if(src.references_to_clear == 0)
		return

	// ===CHUGAFIX=== live ref tracking todo lol
	//Warning, attempting to search clients like this will cause crashes if done on live. Watch yourself
#ifndef REFERENCE_DOING_IT_LIVE
	for(var/client/thing) //clients
		DoSearchVar(thing, "Clients -> [thing.type]", starting_time)
		if(src.references_to_clear == 0)
			break
	log_gc("Finished searching clients")
	if(src.references_to_clear == 0)
		return
#endif

	log_gc("Completed search for references to a [type].")

///CHUGAfix this
/datum/proc/qdel_then_find_references()
	set category = "Debug"
	set name = "qdel() then Find References"
	if(!check_rights(R_DEBUG))
		return

	qdel(src, TRUE) //force a qdel
	//if(!running_find_references)
	//	find_references(TRUE)

/datum/proc/qdel_then_if_fail_find_references()
	set category = "Debug"
	set name = "qdel() then Find References if GC failure"
	if(!check_rights(R_DEBUG))
		return

	qdel_and_find_ref_if_fail(src, TRUE)

/datum/proc/DoSearchVar(potential_container, container_name, search_time, recursion_count, is_special_list)
	if(recursion_count >= REFSEARCH_RECURSE_LIMIT)
		log_gc("Recursion limit reached. [container_name]")
		return

	if(references_to_clear == 0)
		return

	//Check each time you go down a layer. This makes it a bit slow, but it won't effect the rest of the game at all
	#ifndef FIND_REF_NO_CHECK_TICK
	CHECK_TICK
	#endif

	if(istype(potential_container, /datum))
		var/datum/datum_container = potential_container
		if(datum_container.last_find_references == search_time)
			return

		datum_container.last_find_references = search_time
		var/list/vars_list = datum_container.vars

		var/is_atom = FALSE
		var/is_area = FALSE
		if(isatom(datum_container))
			is_atom = TRUE
			if(isarea(datum_container))
				is_area = TRUE

		for(var/varname in vars_list)
			var/variable = vars_list[varname]
			if(islist(variable))
				//Fun fact, vis_locs don't count for references
				if(varname == "vars" || (is_atom && (varname == "vis_locs" || varname == "overlays" || varname == "underlays" || varname == "filters" || varname == "verbs" || (is_area && varname == "contents"))))
					continue
				// We do this after the varname check to avoid area contents (reading it incures a world loop's worth of cost)
				if(!length(variable))
					continue
				DoSearchVar(variable,\
					"[container_name] [datum_container.ref_search_details()] -> [varname] (list)",\
					search_time,\
					recursion_count + 1,\
					/*is_special_list = */ is_atom && (varname == "contents" || varname == "vis_contents" || varname == "locs"))
			else if(variable == src)
				#ifdef REFERENCE_TRACKING_DEBUG
				if(SSgarbage.should_save_refs)
					if(!found_refs)
						found_refs = list()
					found_refs[varname] = TRUE
					continue //End early, don't want these logging
				else
					log_gc("Found [type] [text_ref(src)] in [datum_container.type]'s [datum_container.ref_search_details()] [varname] var. [container_name]")
				#else
				log_gc("Found [type] [text_ref(src)] in [datum_container.type]'s [datum_container.ref_search_details()] [varname] var. [container_name]")
				#endif
				references_to_clear -= 1
				if(references_to_clear == 0)
					log_gc("All references to [type] [text_ref(src)] found, exiting.")
					return
				continue

	else if(islist(potential_container))
		var/list/potential_cache = potential_container
		for(var/element_in_list in potential_cache)
			//Check normal sublists
			if(islist(element_in_list))
				if(length(element_in_list))
					DoSearchVar(element_in_list, "[container_name] -> [element_in_list] (list)", search_time, recursion_count + 1)
			//Check normal entrys
			else if(element_in_list == src)
				#ifdef REFERENCE_TRACKING_DEBUG
				if(SSgarbage.should_save_refs)
					if(!found_refs)
						found_refs = list()
					found_refs[potential_cache] = TRUE
					continue
				else
					log_gc("Found [type] [text_ref(src)] in list [container_name].")
				#else
				log_gc("Found [type] [text_ref(src)] in list [container_name].")
				#endif

				// This is dumb as hell I'm sorry
				// I don't want the garbage subsystem to count as a ref for the purposes of this number
				// If we find all other refs before it I want to early exit, and if we don't I want to keep searching past it
				var/ignore_ref = FALSE
				var/list/queues = SSgarbage.queues
				for(var/list/queue in queues)
					if(potential_cache in queue)
						ignore_ref = TRUE
						break
				if(ignore_ref)
					log_gc("[container_name] does not count as a ref for our count")
				else
					references_to_clear -= 1
				if(references_to_clear == 0)
					log_gc("All references to [type] [text_ref(src)] found, exiting.")
					return

			if(!isnum(element_in_list) && !is_special_list)
				// This exists to catch an error that throws when we access a special list
				// is_special_list is a hint, it can be wrong
				try
					var/assoc_val = potential_cache[element_in_list]
					//Check assoc sublists
					if(islist(assoc_val))
						if(length(assoc_val))
							DoSearchVar(potential_container[element_in_list], "[container_name]\[[element_in_list]\] -> [assoc_val] (list)", search_time, recursion_count + 1)
					//Check assoc entry
					else if(assoc_val == src)
						#ifdef REFERENCE_TRACKING_DEBUG
						if(SSgarbage.should_save_refs)
							if(!found_refs)
								found_refs = list()
							found_refs[potential_cache] = TRUE
							continue
						else
							log_gc("Found [type] [text_ref(src)] in list [container_name]\[[element_in_list]\]")
						#else
						log_gc("Found [type] [text_ref(src)] in list [container_name]\[[element_in_list]\]")
						#endif
						references_to_clear -= 1
						if(references_to_clear == 0)
							log_gc("All references to [type] [text_ref(src)] found, exiting.")
							return
				catch
					// So if it goes wrong we kill it
					is_special_list = TRUE
					log_gc("Curiosity: [container_name] lead to an error when acessing [element_in_list], what is it?")
#undef REFSEARCH_RECURSE_LIMIT
#endif

// Kept outside the ifdef so overrides are easy to implement

/// Return info about us for reference searching purposes
/// Will be logged as a representation of this datum if it's a part of a search chain
/datum/proc/ref_search_details()
	return text_ref(src)

/datum/callback/ref_search_details()
	return "[text_ref(src)] (obj: [object] proc: [delegate] args: [json_encode(arguments)] user: [locateUID(usr_uid) || "null"])"
