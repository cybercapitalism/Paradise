/*
Usage:
Override /Run() to run your test code
Call Fail() to fail the test (You should specify a reason)
You may use /New() and /Destroy() for setup/teardown respectively
You can use the run_loc_bottom_left and run_loc_top_right to get turfs for testing
*/

/datum/unit_test
	//Bit of metadata for the future maybe
	var/list/procs_tested

	/// The bottom left floor turf of the testing zone
	var/turf/run_loc_bottom_left

	/// The top right floor turf of the testing zone
	var/turf/run_loc_top_right

	///The priority of the test, the larger it is the later it fires
	var/priority = TEST_DEFAULT

	//internal shit
	var/succeeded = TRUE
	var/list/fail_reasons

	/// List of atoms that we don't want to ever initialize in an agnostic context, like for Create and Destroy. Stored on the base datum for usability in other relevant tests that need this data.
	var/static/list/uncreatables = null

/proc/cmp_unit_test_priority(datum/unit_test/a, datum/unit_test/b)
	return initial(a.priority) - initial(b.priority)

/datum/unit_test/New()
	run_loc_bottom_left = locate(1, 1, 1)
	run_loc_top_right = locate(5, 5, 1)

	if (isnull(uncreatables))
		uncreatables = build_list_of_uncreatables()

/datum/unit_test/Destroy()
	//clear the test area
	for(var/atom/movable/AM in block(run_loc_bottom_left, run_loc_top_right))
		qdel(AM)
	return ..()

/datum/unit_test/proc/Run()
	Fail("Run() called parent or not implemented")

/datum/unit_test/proc/Fail(reason = "No reason")
	succeeded = FALSE

	if(!istext(reason))
		reason = "FORMATTED: [reason != null ? reason : "NULL"]"

	LAZYADD(fail_reasons, reason)


/// Builds (and returns) a list of atoms that we shouldn't initialize in generic testing, like Create and Destroy.
/// It is appreciated to add the reason why the atom shouldn't be initialized if you add it to this list.
/datum/unit_test/proc/build_list_of_uncreatables()
	RETURN_TYPE(/list)
	var/list/returnable_list = list()
	// The following are just generic, singular types.
	returnable_list = list(
		// Branch types, should never be created
		/turf/simulated,
		/turf/space, // ???
		/turf,
		//Never meant to be created, errors out the ass for mobcode reasons
		/mob/living/carbon,
		//This should be obvious
		/obj/machinery/doomsday_device,
		//Template type
		/obj/effect/mob_spawn,
		//Singleton
		/mob/dview,
		//Template type
		/obj/item/organ,
		//Both are abstract types meant to scream bloody murder if spawned in raw
		/obj/item/organ/external,
	)

	// Everything that follows is a typesof() check.

	//Say it with me now, type template
	returnable_list += typesof(/obj/effect/mapping_helpers)
	//This expects a seed, we can't pass it
	returnable_list += typesof(/obj/item/food/grown)
	//See above
	returnable_list += typesof(/obj/effect/timestop)
	//Sparks can ignite a number of things, causing a fire to burn the floor away. Only you can prevent CI fires
	returnable_list += typesof(/obj/effect/particle_effect/sparks)
	//this boi spawns turf changing stuff, and it stacks and causes pain. Let's just not
	returnable_list += typesof(/obj/effect/sliding_puzzle)
	//these can explode and cause the turf to be destroyed at unexpected moments
	returnable_list += typesof(/obj/effect/mine)
	//Stacks baseturfs, can't be tested here
	returnable_list += typesof(/obj/effect/temp_visual/lava_warning)
	//Our system doesn't support it without warning spam from unregister calls on things that never registered
	returnable_list += typesof(/obj/docking_port)
	//Needs a holodeck area linked to it which is not guarenteed to exist and technically is supposed to have a 1:1 relationship with computer anyway.
	returnable_list += typesof(/obj/machinery/computer/HolodeckControl)
	// Runtimes if the associated machinery does not exist, but not the base type
	returnable_list += subtypesof(/obj/machinery/airlock_controller)


	return returnable_list
