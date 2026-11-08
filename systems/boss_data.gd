extends Resource
class_name BossData

const OK : StringName = &"ok"
const BAD_VALUE : StringName = &"bad_value"
const MIN_TELEGRAPH : float = 0.70   # เกณฑ์ fairness ของบอส (หน้าต่าง dodge = telegraph - iframe >= 0.45)

@export var id : StringName
@export var max_hp : int = 200
@export var radius : float = 40.0
@export var cooldown : float = 1.0
@export var patterns : Array[BossPattern] = []
@export var seq_early : Array[StringName] = []   # HP > phase2_at
@export var seq_late : Array[StringName] = []    # HP <= phase2_at
@export var phase2_at : float = 0.66
@export var phase3_at : float = 0.33             # phase 3: cooldown x enrage_cooldown_scale
@export var enrage_cooldown_scale : float = 0.7

func pattern(pid : StringName) -> BossPattern:
	for p in patterns:
		if p != null and p.id == pid:
			return p
	return null

static func _pat(pid : StringName, shape : StringName, tele : float, rec : float, dmg : int) -> BossPattern:
	var p : BossPattern = BossPattern.new()
	p.id = pid
	p.shape = shape
	p.telegraph = tele
	p.recovery = rec
	p.damage = dmg
	return p

# ค่าตั้งต้นในโค้ด (ยังไม่ทำ .tres) ใช้ทั้งเทสต์และ scene
static func grove() -> BossData:
	var d : BossData = BossData.new()
	d.id = &"grove_guardian"
	var sweep : BossPattern = _pat(&"root_sweep", &"cone", 0.70, 0.90, 15)
	sweep.reach = 110.0
	sweep.half_angle = 80.0
	var volley : BossPattern = _pat(&"seed_volley", &"line3", 0.80, 0.90, 10)
	volley.reach = 400.0
	volley.width = 16.0
	volley.spread_deg = 30.0
	var ring : BossPattern = _pat(&"root_ring", &"ring", 0.90, 1.00, 12)
	ring.inner = 90.0
	ring.outer = 170.0
	d.patterns.append(sweep)
	d.patterns.append(volley)
	d.patterns.append(ring)
	d.seq_early.assign([&"root_sweep", &"seed_volley"])
	d.seq_late.assign([&"root_sweep", &"seed_volley", &"root_ring"])
	return d

static func validate(d : BossData) -> StringName:
	if d == null or String(d.id) == "" or d.max_hp < 1 or d.radius < 0.0 or d.cooldown < 0.0:
		return BAD_VALUE
	if not (d.phase3_at > 0.0 and d.phase3_at < d.phase2_at and d.phase2_at < 1.0) or d.enrage_cooldown_scale <= 0.0:
		return BAD_VALUE
	var seen : Dictionary = {}
	for p in d.patterns:
		if p == null or String(p.id) == "" or seen.has(p.id):
			return BAD_VALUE
		seen[p.id] = true
		if not is_finite(p.telegraph) or p.telegraph < MIN_TELEGRAPH or p.recovery < 0.0 or p.damage <= 0:
			return BAD_VALUE
		if p.shape == &"cone":
			if p.reach <= 0.0 or p.half_angle <= 0.0 or p.half_angle > 180.0:
				return BAD_VALUE
		elif p.shape == &"line3":
			if p.reach <= 0.0 or p.width < 0.0 or p.spread_deg < 0.0:
				return BAD_VALUE
		elif p.shape == &"ring":
			if p.inner < 0.0 or p.outer <= p.inner:
				return BAD_VALUE
		else:
			return BAD_VALUE
	if d.seq_early.is_empty() or d.seq_late.is_empty():
		return BAD_VALUE
	for sid in d.seq_early + d.seq_late:
		if not seen.has(sid):
			return BAD_VALUE
	return OK
