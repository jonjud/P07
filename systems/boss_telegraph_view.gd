extends RefCounted
class_name BossTelegraphView
# pure: ข้อมูลวาด telegraph ของบอส ไม่มี Node ไม่มีกฎเกม ใช้พารามิเตอร์เดียวกับ resolve_pattern

static func of(brain : BossBrain, world : CombatWorld, now : float, blockers : Array = []) -> Dictionary:
	var none : Dictionary = {"phase": &"none", "progress": 0.0}
	if brain == null or not world.actors.has(brain.id) or brain.cur == null:
		return none
	var bc : Combatant = world.actors[brain.id]["c"]
	if bc.state == Combatant.State.DEAD:
		return none
	var p : BossPattern = brain.cur
	var origin : Vector2 = world.actors[brain.id]["pos"]
	if brain.state == BossBrain.S.RECOVERY:
		return {"phase": &"recovery", "progress": 1.0, "pattern": p.id, "shape": p.shape}
	if brain.state != BossBrain.S.TELEGRAPH:
		return none
	var prog : float = clampf((now - brain.t_start) / p.telegraph, 0.0, 1.0)
	var out : Dictionary = {"phase": &"telegraph", "progress": prog, "pattern": p.id, "shape": p.shape, "origin": origin}
	if p.shape == &"cone":
		out["aim"] = brain.aim
		out["reach"] = p.reach
		out["half_angle"] = p.half_angle
	elif p.shape == &"line3":
		var lines : Array = []
		for deg in [0.0, -p.spread_deg, p.spread_deg]:
			var dir : Vector2 = brain.aim.rotated(deg_to_rad(deg))
			lines.append({"dir": dir, "length": HitCheck.line_stop(origin, dir, p.reach, p.width, blockers)})
		out["lines"] = lines
		out["width"] = p.width
	elif p.shape == &"ring":
		out["inner"] = p.inner
		out["outer"] = p.outer
	return out
