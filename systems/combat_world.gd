extends RefCounted
class_name CombatWorld
# pure logic: จุดเดียวที่ดาเมจเกิด request -> validate -> compute -> apply -> result
# actors: id -> {c:Combatant, pos:Vector2, radius:float, team:int, weapon:WeaponData, resolved:int}


var params : CombatParams
var actors : Dictionary = {}

func _init(p : CombatParams) -> void:
	params = p

func add_actor(id : String, max_hp : int, pos : Vector2, radius : float, team : int, weapon : WeaponData = null, actor_params : CombatParams = null) -> bool:
	if id == "" or actors.has(id) or max_hp < 1 or not pos.is_finite() or not is_finite(radius) or radius < 0.0:
		return false
	var p : CombatParams = actor_params if actor_params != null else params
	actors[id] = {"c": Combatant.new(p, max_hp), "pos": pos, "radius": radius, "team": team, "weapon": weapon, "resolved": 0, "parked": false}
	return true

func set_pos(id : String, pos : Vector2) -> bool:
	if not actors.has(id) or not pos.is_finite():
		return false
	actors[id]["pos"] = pos
	return true

func set_parked(id : String, v : bool) -> bool:
	if not actors.has(id):
		return false
	actors[id]["parked"] = v
	return true

func hp_of(id : String) -> int:
	return actors[id]["c"].hp if actors.has(id) else -1

func attack(id : String, now : float, aim : Vector2) -> Dictionary:
	if not actors.has(id):
		return CombatResult.make(CombatResult.UNKNOWN_ACTOR, 1, 0)
	var a : Dictionary = actors[id]
	var w : WeaponData = a["weapon"]
	if w == null or w.damage <= 0 or not is_finite(w.attack_range) or w.attack_range <= 0.0:
		return CombatResult.make(CombatResult.BAD_WEAPON, 1, 0)
	return a["c"].start_attack(now, aim, w.attack_speed)

# เรียกทุกครั้งที่ host รับคำขอ/ทุก tick: เลื่อนเวลาทุกตัว แล้ว resolve swing ที่ยังไม่ resolve
# คืน events: [{attacker, target, result}] เรียงตาม attacker id แล้ว target (deterministic)
func resolve_swings(now : float) -> Array:
	var events : Array = []
	var ids : Array = actors.keys()
	ids.sort()
	for id in ids:
		actors[id]["c"].advance(now)
	for id in ids:
		var a : Dictionary = actors[id]
		var c : Combatant = a["c"]
		if c.swing_id <= a["resolved"]:
			continue
		a["resolved"] = c.swing_id   # resolve ครั้งเดียว ก่อนคำนวณ กันซ้ำแม้เกิด error กลางทาง
		var w : WeaponData = a["weapon"]
		if w == null:
			continue
		var targets : Array = []
		for tid in ids:
			var t : Dictionary = actors[tid]
			if tid == id or t["team"] == a["team"] or t["c"].state == Combatant.State.DEAD or t.get("parked", false):
				continue
			targets.append({"id": tid, "pos": t["pos"], "radius": t["radius"]})
		for tid in HitCheck.cone(a["pos"], c.aim, w.attack_range, c.p.cone_half_angle, targets):
			events.append({"attacker": id, "target": tid, "result": actors[tid]["c"].apply_damage(w.damage, now)})
	return events
	
	# จุดดาเมจของ pattern บอส: เรขาคณิตล้วน แล้ว apply_damage ตัวเดิม; หนึ่ง pattern โดนเป้าละครั้ง
# blockers: [{pos, radius}] บังเฉพาะ line3 (cone/ring ไม่ดูเสา ตามที่ตัดสินไว้)
func resolve_pattern(id : String, pat : BossPattern, aim : Vector2, blockers : Array, now : float) -> Array:
	var events : Array = []
	if not actors.has(id) or pat == null or pat.damage <= 0 or not aim.is_finite() or aim.length() < 0.0001:
		return events
	var a : Dictionary = actors[id]
	if a["c"].state == Combatant.State.DEAD:
		return events
	var ids : Array = actors.keys()
	ids.sort()
	for k in ids:
		actors[k]["c"].advance(now)
	var targets : Array = []
	for tid in ids:
		var t : Dictionary = actors[tid]
		if tid == id or t["team"] == a["team"] or t["c"].state == Combatant.State.DEAD or t.get("parked", false):
			continue
		targets.append({"id": tid, "pos": t["pos"], "radius": t["radius"]})
	var hit : Dictionary = {}
	if pat.shape == &"cone":
		for h in HitCheck.cone(a["pos"], aim, pat.reach, pat.half_angle, targets):
			hit[h] = true
	elif pat.shape == &"line3":
		for deg in [0.0, -pat.spread_deg, pat.spread_deg]:
			for h in HitCheck.line(a["pos"], aim.rotated(deg_to_rad(deg)), pat.reach, pat.width, blockers, targets):
				hit[h] = true
	elif pat.shape == &"ring":
		for h in HitCheck.ring(a["pos"], pat.inner, pat.outer, targets):
			hit[h] = true
	else:
		return events
	var order : Array = hit.keys()
	order.sort()
	for tid in order:
		events.append({"attacker": id, "target": tid, "result": actors[tid]["c"].apply_damage(pat.damage, now)})
	return events
