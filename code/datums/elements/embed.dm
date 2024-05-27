/*
	The presence of this element allows an item (or a projectile carrying an item) to embed itself in a carbon when it is thrown into a target (whether by hand, gun, or explosive wave) with either
	at least 4 throwspeed (EMBED_THROWSPEED_THRESHOLD) or ignore_throwspeed_threshold set to TRUE. Items meant to be used as shrapnel for projectiles should have ignore_throwspeed_threshold set to true.

	Whether we're dealing with a direct /obj/item (throwing a knife at someone) or an /obj/item/projectile with a shrapnel_type, how we handle things plays out the same, with one extra step separating them.
	Items simply make their COMSIG_MOVABLE_IMPACT_ZONE check, while projectiles check on COMSIG_PROJECTILE_SELF_ON_HIT.
	Upon a projectile hitting a valid target, it spawns whatever type of payload it has defined, then has that try to embed itself in the target on its own.

	Otherwise non-embeddable or stickable items can be made embeddable/stickable through wizard events/sticky tape/admin memes.
*/

/datum/element/embed
	element_flags = ELEMENT_BESPOKE
	id_arg_index = 2
	var/initialized = FALSE /// whether we can skip assigning all the vars (since these are bespoke elements, we don't have to reset the vars every time we attach to something, we already know what we are!)

	// all of this stuff is explained in _DEFINES/combat.dm
	var/embed_chance
	var/fall_chance
	var/pain_chance
	var/pain_mult
	var/remove_pain_mult
	var/impact_pain_mult
	var/rip_time
	var/ignore_throwspeed_threshold
	var/jostle_chance
	var/jostle_pain_mult
	var/pain_stam_pct
	var/payload_type

/datum/element/embed/Attach(datum/target, embed_chance, fall_chance, pain_chance, pain_mult, remove_pain_mult, impact_pain_mult, rip_time, ignore_throwspeed_threshold, jostle_chance, jostle_pain_mult, pain_stam_pct, projectile_payload=/obj/item/shard)
	. = ..()

	if(!isitem(target)) // ===CHUGAFIX=== haha make sure this actually works oh my god
		return ELEMENT_INCOMPATIBLE

	RegisterSignal(target, COMSIG_ELEMENT_ATTACH, PROC_REF(severancePackage))
	if(isprojectile(target))
		// ===CHUGAFIX=== this is a disgusting hack but inheritance has backed me into a corner here - can't call parent's UpdateEmbedding() on an item/projectile! (fuck)
		// there has to be some other way around this
		// if not, get rid of the projectile_payload parameter because it's making me sad
		var/obj/item/projectile/proj = target
		if(proj?.shrapnel_type)
			payload_type = proj.shrapnel_type

		RegisterSignal(target, COMSIG_PROJECTILE_SELF_ON_HIT, PROC_REF(checkEmbedProjectile))
	else
		RegisterSignal(target, COMSIG_MOVABLE_IMPACT_ZONE, PROC_REF(checkEmbed))
		RegisterSignal(target, COMSIG_PARENT_EXAMINE, PROC_REF(examined))
		RegisterSignal(target, COMSIG_EMBED_TRY_FORCE, PROC_REF(tryForceEmbed))
		RegisterSignal(target, COMSIG_ITEM_DISABLE_EMBED, PROC_REF(detachFromWeapon))

	if(!initialized)
		src.embed_chance = embed_chance
		src.fall_chance = fall_chance
		src.pain_chance = pain_chance
		src.pain_mult = pain_mult
		src.remove_pain_mult = remove_pain_mult
		src.rip_time = rip_time
		src.impact_pain_mult = impact_pain_mult
		src.ignore_throwspeed_threshold = ignore_throwspeed_threshold
		src.jostle_chance = jostle_chance
		src.jostle_pain_mult = jostle_pain_mult
		src.pain_stam_pct = pain_stam_pct
		initialized = TRUE

/datum/element/embed/Detach(obj/target)
	. = ..()
	if(isitem(target))
		UnregisterSignal(target, list(COMSIG_MOVABLE_IMPACT_ZONE, COMSIG_ELEMENT_ATTACH, COMSIG_MOVABLE_IMPACT, COMSIG_PARENT_EXAMINE, COMSIG_EMBED_TRY_FORCE, COMSIG_ITEM_DISABLE_EMBED))
	else
		UnregisterSignal(target, list(COMSIG_PROJECTILE_SELF_ON_HIT, COMSIG_ELEMENT_ATTACH))


/// Checking to see if we're gonna embed into a human
/datum/element/embed/proc/checkEmbed(obj/item/weapon, mob/living/carbon/human/victim, hit_zone, blocked, datum/thrownthing/throwingdatum, forced=FALSE)
	SIGNAL_HANDLER	// COMSIG_MOVABLE_IMPACT_ZONE

	if(forced)
		embed_object(weapon, victim, hit_zone, throwingdatum)
		return TRUE

	if(blocked || !istype(victim) || HAS_TRAIT(victim, TRAIT_PIERCEIMMUNE))
		return FALSE

	if(victim.status_flags & GODMODE)
		return FALSE

	var/flying_speed = throwingdatum?.speed || weapon.throw_speed

	if(flying_speed < EMBED_THROWSPEED_THRESHOLD && !ignore_throwspeed_threshold)
		return FALSE

	if(!roll_embed_chance(weapon, victim, hit_zone, throwingdatum))
		return FALSE

	embed_object(weapon, victim, hit_zone, throwingdatum)
	return TRUE

/// Actually sticks the object to a victim
/datum/element/embed/proc/embed_object(obj/item/weapon, mob/living/carbon/human/victim, hit_zone, datum/thrownthing/throwingdatum)
	var/obj/item/organ/external/limb = victim.get_organ(hit_zone) || pick(victim.bodyparts)
	victim.AddComponent(/datum/component/embedded,\
		weapon,\
		throwingdatum,\
		part = limb,\
		embed_chance = embed_chance,\
		fall_chance = fall_chance,\
		pain_chance = pain_chance,\
		pain_mult = pain_mult,\
		remove_pain_mult = remove_pain_mult,\
		rip_time = rip_time,\
		ignore_throwspeed_threshold = ignore_throwspeed_threshold,\
		jostle_chance = jostle_chance,\
		jostle_pain_mult = jostle_pain_mult,\
		pain_stam_pct = pain_stam_pct)

///A different embed element has been attached, so we'll detach and let them handle things
/datum/element/embed/proc/severancePackage(obj/weapon, datum/element/E)
	SIGNAL_HANDLER	// COMSIG_ELEMENT_ATTACH

	if(istype(E, /datum/element/embed))
		Detach(weapon)

///If we don't want to be embeddable anymore (deactivating an e-dagger for instance)
/datum/element/embed/proc/detachFromWeapon(obj/weapon)
	SIGNAL_HANDLER	// COMSIG_ITEM_DISABLE_EMBED

	Detach(weapon)

///Someone inspected our embeddable item
/datum/element/embed/proc/examined(obj/item/I, mob/user, list/examine_list)
	SIGNAL_HANDLER	// COMSIG_PARENT_EXAMINE

	if(I.isEmbedHarmless())
		examine_list += "[I] feels sticky, and could probably get stuck to someone if thrown properly!"
	else
		examine_list += "[I] has a fine point, and could probably embed in someone if thrown properly!"

/**
 * checkEmbedProjectile() is what we get when a projectile with a defined shrapnel_type impacts a target.
 *
 * If we hit a valid target, we create the shrapnel_type object and then forcefully try to embed it on its
 * behalf. DO NOT EVER add an embed element to the payload and let it do the rest.
 * That's awful, and it'll limit us to drop-deletable shrapnels in the worry of stuff like
 * arrows and harpoons being embeddable even when not let loose by their weapons.
 */
// ===CHUGAFIX=== this starts working after shrapnel gets ripped up
/datum/element/embed/proc/checkEmbedProjectile(obj/item/projectile/source, atom/movable/firer, atom/hit, angle, hit_zone, blocked)
	SIGNAL_HANDLER	// COMSIG_PROJECTILE_SELF_ON_HIT

	if(!source.can_embed_into(hit))
		Detach(source)
		return // we don't care

	var/obj/item/payload = new payload_type(get_turf(hit))
	if(istype(payload, /obj/item/shrapnel/bullet))
		payload.name = source.name
	// ===CHUGAFIX=== This whole situation ends up causing a runtime with caseless if that gets 1 for 1 ported, fixed by https://github.com/tgstation/tgstation/pull/77942
	SEND_SIGNAL(source, COMSIG_PROJECTILE_ON_SPAWN_EMBEDDED, payload)
	var/mob/living/carbon/C = hit
	var/obj/item/organ/external/limb = C.get_organ(hit_zone)
	if(!limb)
		limb = C.get_organ() // ===CHUGAFIX===

	if(!tryForceEmbed(payload, limb))
		payload.failedEmbed()
	Detach(source)

/**
 * tryForceEmbed() is called here when we fire COMSIG_EMBED_TRY_FORCE from [/obj/item/proc/tryEmbed]. Mostly, this means we're a piece of shrapnel from a projectile that just impacted something, and we're trying to embed in it.
 *
 * The reason for this extra mucking about is avoiding having to do an extra hitby(), and annoying the target by impacting them once with the projectile, then again with the shrapnel, and possibly
 * AGAIN if we actually embed. This way, we save on at least one message.
 *
 * Arguments:
 * * embedding_item- the item we're trying to insert into the target
 * * target- what we're trying to shish-kabob, either an external organ or a carbon
 * * hit_zone- if our target is a carbon, try to hit them in this zone, if we don't have one, pick a random one. If our target is an external organ, we already know where we're hitting.
 * * forced- if we want this to succeed 100%
 */
/datum/element/embed/proc/tryForceEmbed(obj/item/embedding_item, atom/target, hit_zone, forced=FALSE)
	SIGNAL_HANDLER	// COMSIG_EMBED_TRY_FORCE

	var/obj/item/organ/external/limb
	var/mob/living/carbon/human/victim // ===CHUGAFIX=== BODYPARTS ARE ONLY DEFINED ON THE HUMAN LEVEL OMG

	if(iscarbon(target))
		victim = target
		if(!hit_zone)
			limb = pick(victim.bodyparts)
			hit_zone = limb.body_zone
	else if(isorgan(target))
		limb = target
		hit_zone = limb.body_zone
		victim = limb.owner

	if(!forced && !roll_embed_chance(embedding_item, victim, hit_zone))
		return

	return checkEmbed(embedding_item, victim, hit_zone, forced=TRUE) // Don't repeat the embed roll, we already did it

/// Calculates the actual chance to embed based on armour penetration and throwing speed, then returns true if we pass that probability check
/datum/element/embed/proc/roll_embed_chance(obj/item/embedding_item, mob/living/victim, hit_zone, datum/thrownthing/throwingdatum)
	var/actual_chance = embed_chance

	if(throwingdatum?.speed > embedding_item.throw_speed)
		actual_chance += (throwingdatum.speed - embedding_item.throw_speed) * EMBED_CHANCE_SPEED_BONUS

	if(embedding_item.isEmbedHarmless()) // all the armor in the world won't save you from a kick me sign
		return prob(actual_chance)

	var/armor = max(victim.run_armor_check(hit_zone, BULLET), victim.run_armor_check(hit_zone, BOMB)) * 0.5 // we'll be nice and take the better of bullet and bomb armor, halved
	if(!armor) // we only care about armor penetration if there's actually armor to penetrate
		return prob(actual_chance)

	/**
	 * ===CHUGAFIX=== i can't do math right now i don't even know if i want to keep this
	 */
	//Keep this above 1, as it is a multiplier for the pen_mod for determining actual embed chance.
	// var/penetrative_behaviour = embedding_item.weak_against_armour ? ARMOR_WEAKENED_MULTIPLIER : 1
	// var/pen_mod = -(armor * penetrative_behaviour) // if our shrapnel is weak into armor, then we restore our armor to the full value.
	// actual_chance += pen_mod // doing the armor pen as a separate calc just in case this ever gets expanded on
	// if(actual_chance <= 0)
	// 	victim.visible_message(span_danger("[embedding_item] bounces off [victim]'s armor, unable to embed!"), span_notice("[embedding_item] bounces off your armor, unable to embed!"))
	// 	return FALSE

	return prob(actual_chance)
