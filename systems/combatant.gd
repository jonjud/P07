extends RefCounted
class_name Combatant
# pure logic: ไม่มี Node ไม่อ่านนาฬิกา เวลาเข้าเป็น now (วินาที) เสมอ
# ทุกคำสั่งเรียก advance(now) ก่อน (เลื่อน phase ตามเวลา ซึ่งเป็นฟังก์ชันของเวลาล้วน ไม่นับเป็นการเปลี่ยนจากคำขอ)
# คำขอที่ล้ม (done == 0) ไม่แก้ state อื่นนอกจากผลของ advance
# now ย้อนหลัง/ไม่ finite/ติดลบ ถูกปฏิเสธก่อนแตะอะไรทั้งสิ้น

const SCHEMA_VERSION : int = 1
enum State { IDLE, WINDUP, ACTIVE, RECOVERY, DODGE, DEAD }

var p : CombatParams
var hp : int
var max_hp : int
var state : int = State.IDLE
var phase_start : float = 0.0
var aim : Vector2 = Vector2.RIGHT      # ล็อกตอนเริ่ม windup / ทิศ dodge
var speed : float = 1.0                # attack_speed ของอาวุธ หารเวลา windup/active/recovery
var iframe_until : float = 0.0
var stamina_base : float
var regen_from : float = 0.0           # stamina ฟื้นตั้งแต่เวลานี้
var last_now : float = 0.0
var swing_id : int = 0   # นับเพิ่มทุกครั้งที่เข้า ACTIVE

func _init(params : CombatParams, max_hp_value : int = 100) -> void:
	p = params
	max_hp = max_hp_value
	hp = max_hp_value
	stamina_base = params.stamina_max

func _check_time(now : float) -> StringName:
	if not is_finite(now) or now < 0.0:
		return CombatResult.BAD_TIME
	if now < last_now:
		return CombatResult.TIME_REVERSED
	return CombatResult.OK

func _phase_end() -> float:   # -1 = ไม่มี phase ที่ต้องจบ (IDLE/DEAD)
	match state:
		State.WINDUP: return phase_start + p.windup / speed
		State.ACTIVE: return phase_start + p.active / speed
		State.RECOVERY: return phase_start + p.recovery / speed
		State.DODGE: return phase_start + p.dodge_time
	return -1.0

func _next_state() -> int:
	match state:
		State.WINDUP: return State.ACTIVE
		State.ACTIVE: return State.RECOVERY
	return State.IDLE   # RECOVERY, DODGE

func advance(now : float) -> Dictionary:
	var tr : StringName = _check_time(now)
	if tr != CombatResult.OK:
		return CombatResult.make(tr, 1, 0)
	while true:
		var end : float = _phase_end()
		if end < 0.0 or now < end:
			break
		phase_start = end   # ต่อเนื่องจากขอบเดิม ข้ามหลาย phase ได้ผลเท่าเลื่อนทีละนิด
		state = _next_state()
		if state == State.ACTIVE:
			swing_id += 1
	last_now = now
	return CombatResult.make(CombatResult.OK, 1, 1)

func stamina_at(now : float) -> float:
	return minf(p.stamina_max, stamina_base + p.stamina_regen * maxf(0.0, now - regen_from))

func is_invulnerable(now : float) -> bool:
	return state != State.DEAD and now < iframe_until

func in_active(now : float) -> bool:   # ใช้กับ hit detection (P07-03) หลัง advance(now)
	return state == State.ACTIVE

# เตรียมคำสั่ง: คืน reason ที่ล้ม หรือ OK (advance แล้ว)
func _begin(now : float) -> StringName:
	var r : Dictionary = advance(now)
	if not r["ok"]:
		return r["reason"]
	if state == State.DEAD:
		return CombatResult.DEAD
	if state != State.IDLE:
		return CombatResult.NOT_IDLE
	return CombatResult.OK

static func _good_vec(v : Vector2) -> bool:
	return v.is_finite() and v.length() > 0.0001

func start_attack(now : float, aim_dir : Vector2, atk_speed : float = 1.0) -> Dictionary:
	var why : StringName = _begin(now)
	if why != CombatResult.OK:
		return CombatResult.make(why, 1, 0)
	if not _good_vec(aim_dir):
		return CombatResult.make(CombatResult.BAD_AIM, 1, 0)
	if not is_finite(atk_speed) or atk_speed <= 0.0:
		return CombatResult.make(CombatResult.BAD_SPEED, 1, 0)
	aim = aim_dir.normalized()
	speed = atk_speed
	state = State.WINDUP
	phase_start = now
	return CombatResult.make(CombatResult.OK, 1, 1)

func start_dodge(now : float, dir : Vector2) -> Dictionary:
	var why : StringName = _begin(now)
	if why != CombatResult.OK:
		return CombatResult.make(why, 1, 0)
	if not _good_vec(dir):
		return CombatResult.make(CombatResult.BAD_AIM, 1, 0)
	var s : float = stamina_at(now)
	if s < p.dodge_cost:
		return CombatResult.make(CombatResult.NOT_ENOUGH_STAMINA, 1, 0)
	stamina_base = s - p.dodge_cost
	regen_from = now + p.dodge_time + p.regen_delay
	aim = dir.normalized()
	state = State.DODGE
	phase_start = now
	iframe_until = now + p.iframe
	return CombatResult.make(CombatResult.OK, 1, 1)

# ทางเดียวที่ hp ลด (pipeline P07-03/04 จะเรียกที่นี่) ดาเมจเกิน hp = ตาย (done = amount ผู้เรียกอ่าน hp/state เอง)
func apply_damage(amount : int, now : float) -> Dictionary:
	var r : Dictionary = advance(now)
	if not r["ok"]:
		return CombatResult.make(r["reason"], maxi(amount, 0), 0)
	if amount <= 0:
		return CombatResult.make(CombatResult.INVALID_QUANTITY, maxi(amount, 0), 0)
	if state == State.DEAD:
		return CombatResult.make(CombatResult.DEAD, amount, 0)
	if is_invulnerable(now):
		return CombatResult.make(CombatResult.INVULNERABLE, amount, 0)
	hp = maxi(0, hp - amount)
	if hp == 0:
		state = State.DEAD
		iframe_until = 0.0
	return CombatResult.make(CombatResult.OK, amount, amount)

# ---------- serialize (ไม่เก็บ params: เป็นค่า config ไม่ใช่ state) ----------
func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "hp": hp, "max_hp": max_hp, "state": state,
		"phase_start": phase_start, "aim_x": aim.x, "aim_y": aim.y, "speed": speed,
		"iframe_until": iframe_until, "stamina_base": stamina_base, "regen_from": regen_from,
		"last_now": last_now, "swing_id": swing_id}

static func _fail(reason : StringName) -> Dictionary:
	return {"ok": false, "combatant": null, "reason": reason}

static func _num(v : Variant) -> bool:   # JSON/RPC อาจเปลี่ยน float เป็น int ได้
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v))

static func from_dict(data : Dictionary, params : CombatParams) -> Dictionary:
	if params == null:
		return _fail(CombatResult.NULL_PARAMS)
	for k in ["schema_version", "hp", "max_hp", "state", "swing_id", "phase_start", "aim_x", "aim_y", "speed", "iframe_until", "stamina_base", "regen_from", "last_now"]:
		if not data.has(k):
			return _fail(CombatResult.INCOMPLETE_DATA)
	if data["schema_version"] != SCHEMA_VERSION:
		return _fail(CombatResult.BAD_SCHEMA)
	for k in ["hp", "max_hp", "state", "swing_id"]:
		if typeof(data[k]) != TYPE_INT:
			return _fail(CombatResult.BAD_DATA)
	for k in ["phase_start", "aim_x", "aim_y", "speed", "iframe_until", "stamina_base", "regen_from", "last_now"]:
		if not _num(data[k]):
			return _fail(CombatResult.BAD_DATA)
	if data["swing_id"] < 0:
		return _fail(CombatResult.BAD_DATA)
	if data["max_hp"] < 1 or data["hp"] < 0 or data["hp"] > data["max_hp"]:
		return _fail(CombatResult.BAD_DATA)
	if data["state"] < 0 or data["state"] > State.DEAD or (data["state"] == State.DEAD) != (data["hp"] == 0):
		return _fail(CombatResult.BAD_DATA)
	if float(data["speed"]) <= 0.0 or float(data["last_now"]) < 0.0:
		return _fail(CombatResult.BAD_DATA)
	if float(data["stamina_base"]) < 0.0 or float(data["stamina_base"]) > params.stamina_max:
		return _fail(CombatResult.BAD_DATA)
	var c : Combatant = Combatant.new(params, data["max_hp"])
	c.hp = data["hp"]
	c.state = data["state"]
	c.swing_id = data["swing_id"]
	c.phase_start = float(data["phase_start"])
	c.aim = Vector2(float(data["aim_x"]), float(data["aim_y"]))
	c.speed = float(data["speed"])
	c.iframe_until = float(data["iframe_until"])
	c.stamina_base = float(data["stamina_base"])
	c.regen_from = float(data["regen_from"])
	c.last_now = float(data["last_now"])
	return {"ok": true, "combatant": c, "reason": CombatResult.OK}
