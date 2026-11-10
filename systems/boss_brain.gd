extends RefCounted
class_name BossBrain
# ต่างจาก EnemyBrain: step() ลงมือ resolve เองผ่าน CombatWorld.resolve_pattern (จุดดาเมจเดียวเดิม)
# host เรียก step ทุก tick; ผู้เรียกตั้ง engaged = true เมื่อผู้เล่นเข้าสนาม
# ลำดับ pattern ตายตัวตามเฟส (เรียนรู้ได้) aim ล็อกตอนเริ่ม telegraph
enum S { IDLE, TELEGRAPH, RECOVERY, DONE }

var data : BossData
var id : String
var state : int = S.IDLE
var engaged : bool = false
var cur : BossPattern = null
var aim : Vector2 = Vector2.RIGHT
var t_start : float = 0.0
var recover_until : float = 0.0
var cooldown_until : float = 0.0
var seq_pos : int = 0

func _init(boss_id : String, d : BossData) -> void:
	id = boss_id
	data = d

func phase_of(bc : Combatant) -> int:
	var ratio : float = float(bc.hp) / float(bc.max_hp)
	if ratio <= data.phase3_at:
		return 3
	if ratio <= data.phase2_at:
		return 2
	return 1

func _begin(now : float, world : CombatWorld, bc : Combatant) -> void:
	var me : Dictionary = world.actors[id]
	var best : String = ""
	var best_d : float = INF
	var ids : Array = world.actors.keys()
	ids.sort()
	for tid in ids:
		var t : Dictionary = world.actors[tid]
		if t["team"] == me["team"] or t["c"].state == Combatant.State.DEAD or t.get("parked", false):
			continue
		var d : float = (t["pos"] - me["pos"]).length()
		if d < best_d:
			best_d = d
			best = tid
	if best == "":
		return
	var seq : Array = data.seq_early if phase_of(bc) == 1 else data.seq_late
	var p : BossPattern = data.pattern(seq[seq_pos % seq.size()])
	seq_pos += 1
	if p == null:
		return
	var off : Vector2 = world.actors[best]["pos"] - me["pos"]
	aim = off if off.length() > 0.0001 else Vector2.RIGHT
	cur = p
	t_start = now
	state = S.TELEGRAPH

# คืน events ของ resolve (รูปเดียวกับ resolve_swings) หรือ [] ; เปลี่ยน state ได้ครั้งละหนึ่งขั้นต่อการเรียก
func step(now : float, world : CombatWorld, blockers : Array = []) -> Array:
	if not world.actors.has(id) or state == S.DONE:
		return []
	var bc : Combatant = world.actors[id]["c"]
	bc.advance(now)
	if bc.state == Combatant.State.DEAD:
		state = S.DONE   # ตายกลาง telegraph = ไม่ resolve
		return []
	if not engaged:
		return []
	if state == S.IDLE:
		if now >= cooldown_until:
			_begin(now, world, bc)
	elif state == S.TELEGRAPH:
		if now >= t_start + cur.telegraph:
			var ev : Array = world.resolve_pattern(id, cur, aim, blockers, now)
			state = S.RECOVERY
			recover_until = now + cur.recovery
			return ev
	elif state == S.RECOVERY:
		if now >= recover_until:
			state = S.IDLE
			cooldown_until = now + data.cooldown * (data.enrage_cooldown_scale if phase_of(bc) == 3 else 1.0)
	return []
