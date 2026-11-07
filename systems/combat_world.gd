extends RefCounted
class_name CombatWorld
# pure logic: จุดเดียวที่ดาเมจเกิด request -> validate -> compute -> apply -> result
# actors: id -> {c:Combatant, pos:Vector2, radius:float, team:int, weapon:WeaponData, resolved:int}

const HALF_ANGLE_DEG : float = 60.0   # EXPERIMENTAL (P07-06 ย้ายเป็น config)

var params : CombatParams
var actors : Dictionary = {}

func _init(p : CombatParams) -> void:
	params = p

func add_actor(id : String, max_hp : int, pos : Vector2, radius : float, team : int, weapon : WeaponData = null) -> bool:
	if id == "" or actors.has(id) or max_hp < 1 or not pos.is_finite() or not is_finite(radius) or radius < 0.0:
		return false
	actors[id] = {"c": Combatant.new(params, max_hp), "pos": pos, "radius": radius, "team": team, "weapon": weapon, "resolved": 0}
	return true

func set_pos(id : String, pos : Vector2) -> bool:
	if not actors.has(id) or not pos.is_finite():
		return false
	actors[id]["pos"] = pos
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
			if tid == id or t["team"] == a["team"] or t["c"].state == Combatant.State.DEAD:
				continue
			targets.append({"id": tid, "pos": t["pos"], "radius": t["radius"]})
		for tid in HitCheck.cone(a["pos"], c.aim, w.attack_range, HALF_ANGLE_DEG, targets):
			events.append({"attacker": id, "target": tid, "result": actors[tid]["c"].apply_damage(w.damage, now)})
	return events
