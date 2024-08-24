/datum/pipeline
	var/datum/gas_mixture/air
	var/list/datum/gas_mixture/other_airs = list()

	var/list/obj/machinery/atmospherics/pipe/members = list()
	var/list/obj/machinery/atmospherics/other_atmos_machines = list()

	var/update = TRUE

/datum/pipeline/New()
	SSair.pipenets += src

/datum/pipeline/Destroy()
	SSair.pipenets -= src
	var/datum/gas_mixture/ghost = null
	if(air && air.volume)
		ghost = air
		air = null
	for(var/obj/machinery/atmospherics/pipe/considered_pipe in members)
		considered_pipe.parent = null // this might fuck up?
		if(QDELETED(considered_pipe))
			continue
		considered_pipe.ghost_pipeline = ghost
	for(var/obj/machinery/atmospherics/considered_machine in other_atmos_machines)
		considered_machine.nullify_pipenet(src)
	return ..()

/datum/pipeline/process()//This use to be called called from the pipe networks
	if(update)
		update = FALSE
		reconcile_air()
	return

/datum/pipeline/proc/build_pipeline(obj/machinery/atmospherics/base)
	var/volume = 0
	var/list/ghost_pipelines = list()
	if(istype(base, /obj/machinery/atmospherics/pipe))
		var/obj/machinery/atmospherics/pipe/considered_pipe = base
		volume = considered_pipe.volume
		members += considered_pipe
		if(considered_pipe.ghost_pipeline)
			ghost_pipelines[considered_pipe.ghost_pipeline] = considered_pipe.volume
			considered_pipe.ghost_pipeline = null
	else
		add_machinery_member(base)

	if(!air)
		air = new

	var/list/possible_expansions = list(base)
	while(length(possible_expansions))
		for(var/obj/machinery/atmospherics/borderline in possible_expansions)
			var/list/result = borderline.pipeline_expansion(src)

			if(!length(result))
				possible_expansions -= borderline
				continue

			for(var/obj/machinery/atmospherics/considered_device in result)
				if(!istype(considered_device, /obj/machinery/atmospherics/pipe))
					considered_device.set_pipenet(src, borderline)
					add_machinery_member(considered_device)
					continue

				var/obj/machinery/atmospherics/pipe/item = considered_device
				if(members.Find(item))
					continue
				if(item.parent)
					stack_trace("[item.type] \[\ref[item]] added to a pipenet while still having one ([item.parent]) (pipes leading to the same spot stacking in one turf). Nearby: [item.x], [item.y], [item.z].")

				members += item
				possible_expansions += item

				volume += item.volume
				item.parent = src

				if(item.ghost_pipeline)
					if(!ghost_pipelines[item.ghost_pipeline])
						ghost_pipelines[item.ghost_pipeline] = item.volume
					else
						ghost_pipelines[item.ghost_pipeline] += item.volume
					item.ghost_pipeline = null

			possible_expansions -= borderline

	for(var/datum/gas_mixture/ghost in ghost_pipelines)
		var/collected_ghost_volume = ghost_pipelines[ghost]
		var/collected_fraction = collected_ghost_volume / ghost.volume

		var/datum/gas_mixture/ghost_copy = new()
		ghost_copy.copy_from(ghost)
		air.merge(ghost_copy.remove_ratio(collected_fraction))

	air.volume = volume

/datum/pipeline/proc/add_machinery_member(obj/machinery/atmospherics/A)
	other_atmos_machines |= A
	var/datum/gas_mixture/G = A.return_pipenet_air(src)
	other_airs |= G

/datum/pipeline/proc/addMember(obj/machinery/atmospherics/device_ref, obj/machinery/atmospherics/device_to_add)
	//update = TRUE // LOL
	if(!istype(device_ref, /obj/machinery/atmospherics/pipe))
		device_ref.set_pipenet(src, device_to_add)
		add_machinery_member(device_ref)
		return

	var/obj/machinery/atmospherics/pipe/pipe_ref = device_ref

	// merge pipe_ref's pipeline into this pipeline and then transfer ownership
	if(pipe_ref.parent)
		merge(pipe_ref.parent)
	pipe_ref.parent = src

	var/list/adjacent = pipe_ref.pipeline_expansion()
	for(var/obj/machinery/atmospherics/pipe/adjacent_pipe in adjacent)
		if(adjacent_pipe.parent == src)
			continue
		var/datum/pipeline/parent_pipeline = adjacent_pipe.parent
		merge(parent_pipeline)

	if(!members.Find(pipe_ref))
		members += pipe_ref
		air.volume += pipe_ref.volume



/datum/pipeline/proc/merge(datum/pipeline/parent_pipeline)
	if(parent_pipeline == src)
		return

	air.volume += parent_pipeline.air.volume
	members.Add(parent_pipeline.members)

	for(var/obj/machinery/atmospherics/pipe/pipe_ref in parent_pipeline.members)
		pipe_ref.parent = src

	air.merge(parent_pipeline.air)

	for(var/obj/machinery/atmospherics/device_ref in parent_pipeline.other_atmos_machines)
		device_ref.replace_pipenet(parent_pipeline, src)

	other_atmos_machines |= parent_pipeline.other_atmos_machines
	other_airs |= parent_pipeline.other_airs
	parent_pipeline.members.Cut()
	parent_pipeline.other_atmos_machines.Cut()
	update = TRUE // lol
	qdel(parent_pipeline)

/obj/machinery/atmospherics/proc/addMember(obj/machinery/atmospherics/considered_device)
	var/datum/pipeline/device_pipeline = return_pipenet(considered_device)
	device_pipeline.addMember(considered_device, src)

/obj/machinery/atmospherics/pipe/addMember(obj/machinery/atmospherics/considered_device)
	parent.addMember(considered_device, src)

/datum/pipeline/proc/temperature_interact(turf/target, share_volume, thermal_conductivity)
	var/datum/milla_safe/pipeline_temperature_interact/milla = new()
	milla.invoke_async(src, target, share_volume, thermal_conductivity)

/datum/milla_safe/pipeline_temperature_interact

/datum/milla_safe/pipeline_temperature_interact/on_run(datum/pipeline/pipeline, turf/target, share_volume, thermal_conductivity)
	var/datum/gas_mixture/environment = get_turf_air(target)

	var/total_heat_capacity = pipeline.air.heat_capacity()
	var/partial_heat_capacity = total_heat_capacity*(share_volume/pipeline.air.volume)

	if(issimulatedturf(target))
		var/turf/simulated/modeled_location = target

		if(modeled_location.blocks_air)

			if((modeled_location.heat_capacity>0) && (partial_heat_capacity>0))
				var/delta_temperature = pipeline.air.temperature() - modeled_location.temperature

				var/heat = thermal_conductivity*delta_temperature* \
					(partial_heat_capacity*modeled_location.heat_capacity/(partial_heat_capacity+modeled_location.heat_capacity))

				pipeline.air.set_temperature(pipeline.air.temperature() - heat / total_heat_capacity)
				modeled_location.temperature += heat/modeled_location.heat_capacity

		else
			var/delta_temperature = 0
			var/sharer_heat_capacity = 0

			delta_temperature = (pipeline.air.temperature() - environment.temperature())
			sharer_heat_capacity = environment.heat_capacity()

			var/self_temperature_delta = 0
			var/sharer_temperature_delta = 0

			if((sharer_heat_capacity>0) && (partial_heat_capacity>0))
				var/heat = thermal_conductivity*delta_temperature* \
					(partial_heat_capacity*sharer_heat_capacity/(partial_heat_capacity+sharer_heat_capacity))

				self_temperature_delta = -heat/total_heat_capacity
				sharer_temperature_delta = heat/sharer_heat_capacity
			else
				return 1

			pipeline.air.set_temperature(pipeline.air.temperature() + self_temperature_delta)

			environment.set_temperature(environment.temperature() + sharer_temperature_delta)


	else
		if((target.heat_capacity>0) && (partial_heat_capacity>0))
			var/delta_temperature = pipeline.air.temperature() - target.temperature

			var/heat = thermal_conductivity * delta_temperature * \
				(partial_heat_capacity * target.heat_capacity / (partial_heat_capacity + target.heat_capacity))

			pipeline.air.set_temperature(pipeline.air.temperature() - heat / total_heat_capacity)
	pipeline.update = TRUE

/datum/pipeline/proc/reconcile_air()
	var/list/datum/gas_mixture/GL = list()
	var/list/datum/pipeline/PL = list()
	PL += src

	for(var/i=1;i<=length(PL);i++)
		var/datum/pipeline/P = PL[i]
		if(!P)
			return
		GL += P.air
		GL += P.other_airs
		for(var/obj/machinery/atmospherics/binary/valve/V in P.other_atmos_machines)
			if(V.open)
				PL |= V.parent1
				PL |= V.parent2
		for(var/obj/machinery/atmospherics/trinary/tvalve/T in P.other_atmos_machines)
			if(!T.state)
				if(src != T.parent2) // otherwise dc'd side connects to both other sides!
					PL |= T.parent1
					PL |= T.parent3
			else
				if(src != T.parent3)
					PL |= T.parent1
					PL |= T.parent2
		for(var/obj/machinery/atmospherics/unary/portables_connector/C in P.other_atmos_machines)
			if(C.connected_device)
				GL += C.portableConnectorReturnAir()

	share_many_airs(GL)
