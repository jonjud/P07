extends RefCounted
class_name CombatSnapshot
# pure: state combat ที่ host ส่งให้ client (ไม่มี node) schema v1

const SCHEMA_VERSION : int = 1

static func to_dict(world : CombatWorld, boss : BossBrain, flags : Dictionary) -> Dictionary:
	var acts : Dictionary = {}
	for id in world.actors:
		var a : Dictionary = world.actors[id]
		acts[id] = {"c": a["c"].to_dict(), "x": a["pos"].x, "y": a["pos"].y, "team": a["team"], "radius": a["radius"], "parked": a.get("parked", false)}
	var b : Dictionary = {}
	if boss != null:
		b = {"id": boss.id, "state": boss.state, "engaged": boss.engaged, "cur": String(boss.cur.id) if boss.cur != null else "",
			"aim_x": boss.aim.x, "aim_y": boss.aim.y, "t_start": boss.t_start, "recover_until": boss.recover_until,
			"cooldown_until": boss.cooldown_until, "seq_pos": boss.seq_pos}
	return {"schema_version": SCHEMA_VERSION, "actors": acts, "boss": b, "flags": flags.duplicate()}

static func _fail(reason : StringName) -> Dictionary:
	return {"ok": false, "snap": {}, "reason": reason}

static func _num(v : Variant) -> bool:
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v))

# ตรวจทั้งก้อนก่อน ค่อยคืน (ไม่สร้าง state ครึ่งๆ กลางๆ)
static func validate(d : Dictionary, params : CombatParams) -> Dictionary:
	for k in ["schema_version", "actors", "boss", "flags"]:
		if not d.has(k):
			return _fail(&"incomplete_data")
	if d["schema_version"] != SCHEMA_VERSION:
		return _fail(&"bad_schema")
	if typeof(d["actors"]) != TYPE_DICTIONARY or typeof(d["boss"]) != TYPE_DICTIONARY or typeof(d["flags"]) != TYPE_DICTIONARY:
		return _fail(&"bad_data")
	for id in d["actors"]:
		var a = d["actors"][id]
		if typeof(id) != TYPE_STRING or typeof(a) != TYPE_DICTIONARY:
			return _fail(&"bad_data")
		for k in ["c", "x", "y", "team", "radius", "parked"]:
			if not a.has(k):
				return _fail(&"incomplete_data")
		if typeof(a["c"]) != TYPE_DICTIONARY or not Combatant.from_dict(a["c"], params)["ok"]:
			return _fail(&"bad_data")
		if not _num(a["x"]) or not _num(a["y"]) or not _num(a["radius"]) or typeof(a["team"]) != TYPE_INT or typeof(a["parked"]) != TYPE_BOOL:
			return _fail(&"bad_data")
	var b : Dictionary = d["boss"]
	if not b.is_empty():
		for k in ["id", "state", "engaged", "cur", "aim_x", "aim_y", "t_start", "recover_until", "cooldown_until", "seq_pos"]:
			if not b.has(k):
				return _fail(&"incomplete_data")
		if typeof(b["id"]) != TYPE_STRING or typeof(b["cur"]) != TYPE_STRING or typeof(b["engaged"]) != TYPE_BOOL:
			return _fail(&"bad_data")
		if typeof(b["state"]) != TYPE_INT or b["state"] < 0 or b["state"] > BossBrain.S.DONE or typeof(b["seq_pos"]) != TYPE_INT or b["seq_pos"] < 0:
			return _fail(&"bad_data")
		for k in ["aim_x", "aim_y", "t_start", "recover_until", "cooldown_until"]:
			if not _num(b[k]):
				return _fail(&"bad_data")
		if not d["actors"].has(b["id"]):
			return _fail(&"bad_data")
	for k in d["flags"]:
		if typeof(k) != TYPE_STRING or k == "" or typeof(d["flags"][k]) != TYPE_BOOL:
			return _fail(&"bad_data")
	return {"ok": true, "snap": d, "reason": &"ok"}

static func hash_of(d : Dictionary) -> String:
	return JSON.stringify(d, "", true).sha256_text().left(12)
