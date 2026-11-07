extends RefCounted
class_name CombatantTests

var passed : int = 0
var failed : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func mk() -> Combatant:
	return Combatant.new(CombatParams.new(), 100)

func near(a : float, b : float) -> bool:
	return absf(a - b) < 0.0001

func run_all() -> void:
	test_attack_flow()
	test_reject()
	test_dodge()
	test_stamina()
	test_dead()
	test_time()
	test_serialize()
	test_fuzz()
	print("Combatant: Passed ", passed, " / Failed ", failed)

func test_attack_flow() -> void:
	var c : Combatant = mk()
	t("attack ok", c.start_attack(1.0, Vector2(3, 4))["ok"] and c.state == Combatant.State.WINDUP)
	t("aim normalized", near(c.aim.length(), 1.0))
	c.advance(1.149)
	t("still windup", c.state == Combatant.State.WINDUP)
	c.advance(1.151)
	t("active", c.state == Combatant.State.ACTIVE and c.in_active(1.151))
	c.advance(1.251)
	t("recovery", c.state == Combatant.State.RECOVERY)
	c.advance(1.501)
	t("idle", c.state == Combatant.State.IDLE)
	var a : Combatant = mk()
	var b : Combatant = mk()
	a.start_attack(0.0, Vector2.RIGHT)
	b.start_attack(0.0, Vector2.RIGHT)
	a.advance(0.6)
	for i in range(1, 7):
		b.advance(0.1 * i)
	t("jump == stepwise", a.state == b.state and near(a.phase_start, b.phase_start))
	var f : Combatant = mk()
	f.start_attack(0.0, Vector2.RIGHT, 2.0)
	f.advance(0.249)
	t("speed 2 halves time: idle at 0.25", f.state == Combatant.State.RECOVERY)
	f.advance(0.251)
	t("speed 2 idle", f.state == Combatant.State.IDLE)

func test_reject() -> void:
	var c : Combatant = mk()
	c.start_attack(0.0, Vector2.RIGHT)
	for step in [[0.05, "windup"], [0.2, "active"], [0.3, "recovery"]]:
		c.advance(step[0])
		var b : Dictionary = c.to_dict()
		t("attack during " + step[1], c.start_attack(step[0], Vector2.RIGHT)["reason"] == CombatResult.NOT_IDLE and c.to_dict() == b)
		t("dodge during " + step[1], c.start_dodge(step[0], Vector2.LEFT)["reason"] == CombatResult.NOT_IDLE and c.to_dict() == b)
	var d : Combatant = mk()
	d.advance(1.0)
	var b2 : Dictionary = d.to_dict()
	t("bad aim zero", d.start_attack(1.0, Vector2.ZERO)["reason"] == CombatResult.BAD_AIM and d.to_dict() == b2)
	t("bad aim nan", d.start_attack(1.0, Vector2(NAN, 1))["reason"] == CombatResult.BAD_AIM and d.to_dict() == b2)
	t("bad speed", d.start_attack(1.0, Vector2.RIGHT, 0.0)["reason"] == CombatResult.BAD_SPEED and d.to_dict() == b2)
	t("bad dodge dir", d.start_dodge(1.0, Vector2.ZERO)["reason"] == CombatResult.BAD_AIM and d.to_dict() == b2)
	t("damage 0", d.apply_damage(0, 1.0)["reason"] == CombatResult.INVALID_QUANTITY and d.to_dict() == b2)
	t("damage neg", d.apply_damage(-5, 1.0)["reason"] == CombatResult.INVALID_QUANTITY and d.hp == 100)

func test_dodge() -> void:
	var c : Combatant = mk()
	t("dodge ok", c.start_dodge(1.0, Vector2.LEFT)["ok"] and c.state == Combatant.State.DODGE)
	t("stamina -20", near(c.stamina_at(1.0), 80.0))
	t("iframe at start", c.is_invulnerable(1.0))
	t("iframe before end", c.is_invulnerable(1.149))
	t("iframe over", not c.is_invulnerable(1.151))
	var r : Dictionary = c.apply_damage(10, 1.1)
	t("damage in iframe rejected", r["reason"] == CombatResult.INVULNERABLE and r["done"] == 0 and c.hp == 100)
	r = c.apply_damage(10, 1.2)
	t("damage after iframe (still dodge state) hits", r["ok"] and c.hp == 90)
	c.advance(1.26)
	t("dodge ends", c.state == Combatant.State.IDLE)

func test_stamina() -> void:
	var c : Combatant = mk()
	for i in 5:
		t("dodge %d ok" % i, c.start_dodge(0.3 * i, Vector2.RIGHT)["ok"])
	t("stamina 0", near(c.stamina_at(1.2), 0.0))
	var b : Dictionary = c.to_dict()
	var r : Dictionary = c.start_dodge(1.5, Vector2.RIGHT)
	c.advance(1.5)
	t("dodge #6 rejected (delay)", r["reason"] == CombatResult.NOT_ENOUGH_STAMINA)
	t("no regen during delay", near(c.stamina_at(1.9), 0.0))   # regen_from = 1.2+0.25+0.5 = 1.95
	t("regen after delay", near(c.stamina_at(2.95), 30.0))
	t("regen capped", near(c.stamina_at(100.0), 100.0))
	t("dodge again after regen", c.start_dodge(3.0, Vector2.RIGHT)["ok"])

func test_dead() -> void:
	var c : Combatant = mk()
	var r : Dictionary = c.apply_damage(150, 0.5)
	t("overkill ok, hp 0, dead", r["ok"] and c.hp == 0 and c.state == Combatant.State.DEAD)
	var b : Dictionary = c.to_dict()
	t("dead: attack", c.start_attack(1.0, Vector2.RIGHT)["reason"] == CombatResult.DEAD)
	t("dead: dodge", c.start_dodge(1.0, Vector2.RIGHT)["reason"] == CombatResult.DEAD)
	t("dead: damage", c.apply_damage(5, 1.0)["reason"] == CombatResult.DEAD)
	c.advance(1.0)
	t("dead stays dead", c.state == Combatant.State.DEAD and not c.is_invulnerable(1.0))
	var d : Combatant = mk()
	d.start_attack(0.0, Vector2.RIGHT)
	d.apply_damage(100, 0.05)
	d.advance(2.0)
	t("die mid-windup stays dead", d.state == Combatant.State.DEAD)
	var e : Combatant = mk()
	e.start_dodge(0.0, Vector2.RIGHT)
	e.apply_damage(100, 0.2)
	t("die during dodge: dead, no iframe", e.state == Combatant.State.DEAD and not e.is_invulnerable(0.21))

func test_time() -> void:
	var c : Combatant = mk()
	c.advance(5.0)
	var b : Dictionary = c.to_dict()
	t("reversed attack", c.start_attack(4.0, Vector2.RIGHT)["reason"] == CombatResult.TIME_REVERSED and c.to_dict() == b)
	t("reversed dodge", c.start_dodge(4.0, Vector2.RIGHT)["reason"] == CombatResult.TIME_REVERSED and c.to_dict() == b)
	t("reversed damage", c.apply_damage(5, 4.0)["reason"] == CombatResult.TIME_REVERSED and c.to_dict() == b)
	t("reversed advance", c.advance(4.0)["reason"] == CombatResult.TIME_REVERSED and c.to_dict() == b)
	t("nan time", c.advance(NAN)["reason"] == CombatResult.BAD_TIME and c.to_dict() == b)
	t("negative time", c.advance(-1.0)["reason"] == CombatResult.BAD_TIME)
	t("same time ok", c.advance(5.0)["ok"])

func test_serialize() -> void:
	var p : CombatParams = CombatParams.new()
	var c : Combatant = mk()
	c.start_attack(1.0, Vector2(1, 1), 1.5)
	c.advance(1.1)
	var d : Dictionary = c.to_dict()
	var r : Dictionary = Combatant.from_dict(d, p)
	t("ser ok", r["ok"] and r["combatant"].to_dict() == d)
	d["hp"] = 1
	t("ser no reference", c.hp == 100)
	var bads : Array = [
		["schema", "schema_version", 99, CombatResult.BAD_SCHEMA],
		["hp type", "hp", "5", CombatResult.BAD_DATA],
		["hp neg", "hp", -1, CombatResult.BAD_DATA],
		["hp > max", "hp", 101, CombatResult.BAD_DATA],
		["max 0", "max_hp", 0, CombatResult.BAD_DATA],
		["state unknown", "state", 9, CombatResult.BAD_DATA],
		["state neg", "state", -1, CombatResult.BAD_DATA],
		["dead with hp", "state", Combatant.State.DEAD, CombatResult.BAD_DATA],
		["speed 0", "speed", 0.0, CombatResult.BAD_DATA],
		["aim nan", "aim_x", NAN, CombatResult.BAD_DATA],
		["stamina > max", "stamina_base", 999.0, CombatResult.BAD_DATA],
		["stamina neg", "stamina_base", -1.0, CombatResult.BAD_DATA],
		["last_now type", "last_now", "x", CombatResult.BAD_DATA],
		["swing neg", "swing_id", -1, CombatResult.BAD_DATA],
		["swing type", "swing_id", "1", CombatResult.BAD_DATA],
	]
	for b in bads:
		var x : Dictionary = c.to_dict()
		x[b[1]] = b[2]
		var rr : Dictionary = Combatant.from_dict(x, p)
		t("ser bad " + b[0], not rr["ok"] and rr["combatant"] == null and rr["reason"] == b[3])
	var m : Dictionary = c.to_dict()
	m.erase("hp")
	t("ser missing key", Combatant.from_dict(m, p)["reason"] == CombatResult.INCOMPLETE_DATA)
	t("ser null params", Combatant.from_dict(c.to_dict(), null)["reason"] == CombatResult.NULL_PARAMS)
	var dead : Combatant = mk()
	dead.apply_damage(100, 0.0)
	t("ser dead round-trip", Combatant.from_dict(dead.to_dict(), p)["combatant"].state == Combatant.State.DEAD)

func test_fuzz() -> void:
	var c : Combatant = mk()
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 777
	var now : float = 0.0
	var bad : int = 0
	var rev_changed : int = 0
	var seen : Dictionary = {}
	for i in 500:
		now = maxf(0.0, now + rng.randf_range(-0.1, 0.3))
		var before : Dictionary = c.to_dict()
		var r : Dictionary
		match rng.randi() % 4:
			0: r = c.start_attack(now, Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)), rng.randf_range(0.5, 2.0))
			1: r = c.start_dodge(now, Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
			2: r = c.apply_damage(rng.randi_range(-2, 30), now)
			_: r = c.advance(now)
		seen[r["reason"]] = true
		if r["ok"] != (r["reason"] == CombatResult.OK) or (r["done"] != 0 and r["done"] != r["requested"]):
			bad += 1
		if r["reason"] == CombatResult.TIME_REVERSED and c.to_dict() != before:
			rev_changed += 1
		if c.hp < 0 or c.hp > c.max_hp or c.stamina_at(now) < -0.0001 or c.stamina_at(now) > c.p.stamina_max + 0.0001 or c.state < 0 or c.state > Combatant.State.DEAD or (c.state == Combatant.State.DEAD) != (c.hp == 0):
			bad += 1
		if not Combatant.from_dict(c.to_dict(), c.p)["ok"]:
			bad += 1
		if c.state == Combatant.State.DEAD:
			c = mk()   # เกิดใหม่เพื่อให้ fuzz ครอบคลุมต่อ
			now = 0.0
	t("fuzz invariants", bad == 0)
	t("fuzz reversed never mutates", rev_changed == 0)
	t("fuzz exercised", seen.has(CombatResult.OK) and seen.has(CombatResult.NOT_IDLE) and seen.size() >= 4)
