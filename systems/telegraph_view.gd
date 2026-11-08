extends RefCounted
class_name TelegraphView
# pure: แปลงสถานะ combatant เป็นข้อมูลวาด ไม่มี Node ไม่มีกฎเกม
# phase: &"none" | &"windup" | &"active"

static func of(world : CombatWorld, id : String, now : float) -> Dictionary:
	var none : Dictionary = {"phase": &"none", "progress": 0.0}
	if not world.actors.has(id):
		return none
	var a : Dictionary = world.actors[id]
	var c : Combatant = a["c"]
	var w : WeaponData = a["weapon"]
	if w == null:
		return none
	var cone : Dictionary = {"origin": a["pos"], "aim": c.aim, "reach": w.attack_range, "half_angle": c.p.cone_half_angle}
	match c.state:
		Combatant.State.WINDUP:
			var dur : float = c.p.windup / c.speed
			var prog : float = clampf((now - c.phase_start) / dur, 0.0, 1.0) if dur > 0.0 else 1.0
			return {"phase": &"windup", "progress": prog, "cone": cone}
		Combatant.State.ACTIVE:
			return {"phase": &"active", "progress": 1.0, "cone": cone}
	return none
