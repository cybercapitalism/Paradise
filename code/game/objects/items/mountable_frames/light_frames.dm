/obj/item/mounted/frame/light_fixture
	name = "light fixture frame"
	desc = "Used for building lights."
	icon = 'icons/obj/lighting.dmi'
	icon_state = "tube-construct-item"

	mount_requirements = MOUNTED_FRAME_SIMFLOOR
	metal_sheets_refunded = 2
	///specifies which type of light fixture this frame will build
	var/fixture_type = "tube"

/obj/item/mounted/frame/light_fixture/do_build(turf/on_wall, mob/user)
	to_chat(user, "You begin attaching [src] to [on_wall].")
	playsound(get_turf(src), 'sound/machines/click.ogg', 75, 1)
	var/constrdir = user.dir
	var/constrloc = get_turf(user)
	if(!do_after(user, 30, target = on_wall))
		return
	var/obj/machinery/light_construct/newlight
	switch(fixture_type)
		if("bulb")
			newlight = new /obj/machinery/light_construct/small(constrloc)
		if("tube")
			newlight = new /obj/machinery/light_construct(constrloc)
		else
			newlight = new /obj/machinery/light_construct/small(constrloc)
	newlight.dir = constrdir
	newlight.fingerprints = src.fingerprints
	newlight.fingerprintshidden = src.fingerprintshidden
	newlight.fingerprintslast = src.fingerprintslast

	user.visible_message("[user] attaches [src] to [on_wall].", \
		"You attach [src] to [on_wall].")
	qdel(src)

/obj/item/mounted/frame/light_fixture/small
	name = "small light fixture frame"
	desc = "Used for building small lights."
	icon = 'icons/obj/lighting.dmi'
	icon_state = "bulb-construct-item"
	fixture_type = "bulb"
	metal_sheets_refunded = 1
