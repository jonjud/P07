extends RefCounted
class_name EnemyBrain
# AI state machine ง่าย ๆ ไม่แก้ world: think() คืนเจตนา ผู้เรียก (host) เป็นคนสั่ง
enum S { IDLE, CHASE, COOLDOWN }

var data : EnemyData
var id : String
var state : int = S.IDLE
var cooldown_until : float = 0.0

func _init(enemy_id : String, d : EnemyData) -> void:
	id = enemy_id
	data = d

static func make_params(d : EnemyData) -> CombatParams:
	var p : CombatParams = CombatParams.new()
	p.windup = d.telegraph
	p.active = d.active
	p.recovery = d.recovery
	return p

static func make_weapon(d : EnemyData) -> WeaponData:
	var w : WeaponData = WeaponData.new()
	w.id = StringName(String(d.id) + "_attack")
	w.damage = d.damage
	w.attack_range = d.attack_range
	w.attack_speed = 1.0
	return w

func _nearest(world : CombatWorld) -> String:
	var me : Dictionary = world.actors[id]
	var best : String = ""
	var best_d : float = INF
	var ids : Array = world.actors.keys()
	ids.sort()
	for tid in ids:
		var t : Dictionary = world.actors[tid]
		if t["team"] == me["team"] or t["c"].state == Combatant.State.DEAD:
			continue
		var d : float = (t["pos"] - me["pos"]).length()
		if d < best_d:
			best_d = d
			best = tid
	return best

# คืน {move:Vector2, attack:bool, aim:Vector2, target:String}
func think(now : float, world : CombatWorld) -> Dictionary:
	var idle : Dictionary = {"move": Vector2.ZERO, "attack": false, "aim": Vector2.ZERO, "target": ""}
	if not world.actors.has(id):
		return idle
	var me : Combatant = world.actors[id]["c"]
	me.advance(now)
	if me.state == Combatant.State.DEAD:
		return idle
	if me.state != Combatant.State.IDLE:   # กำลัง telegraph/ฟัน/พัก: ห้ามขยับ ห้ามเปลี่ยนทิศ (อ่านได้ ยุติธรรม)
		return idle
	var tid : String = _nearest(world)
	if tid == "":
		state = S.IDLE
		return idle
	var off : Vector2 = world.actors[tid]["pos"] - world.actors[id]["pos"]
	var dist : float = off.length()
	if dist > data.aggro_range:
		state = S.IDLE
		return idle
	if state == S.COOLDOWN and now < cooldown_until:
		state = S.COOLDOWN
		return {"move": Vector2.ZERO, "attack": false, "aim": off, "target": tid}
	state = S.CHASE
	var reach : float = data.attack_range * 0.8   # เข้าใกล้กว่าระยะฟันเล็กน้อย
	if dist <= reach + world.actors[tid]["radius"]:
		state = S.COOLDOWN
		cooldown_until = now + data.telegraph + data.active + data.recovery + data.cooldown
		return {"move": Vector2.ZERO, "attack": true, "aim": off, "target": tid}
	return {"move": off.normalized() * data.move_speed, "attack": false, "aim": off, "target": tid}
