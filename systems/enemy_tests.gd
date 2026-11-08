extends RefCounted
class_name EnemyTests

const MIN_TELEGRAPH_ENEMY : float = 0.60   # เกณฑ์ตั้งไว้ก่อน playtest (หลักฐานข้อ 3)
const REACTION_BUDGET : float = 0.45       # reaction 0.25 + input 0.10 + RTT 0.10

var passed : int = 0
var failed : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func grunt() -> EnemyData:
	var d : EnemyData = EnemyData.new()
	d.id = &"grunt"
	return d

func world(d : EnemyData) -> Array:
	var cw : CombatWorld = CombatWorld.new(CombatParams.new())
	var pw : WeaponData = WeaponData.new()
	pw.id = &"test_sword"
	cw.add_actor("p1", 100, Vector2.ZERO, 8.0, 0, pw)
	cw.add_actor("e1", d.max_hp, Vector2(150, 0), d.radius, 1, EnemyBrain.make_weapon(d), EnemyBrain.make_params(d))
	return [cw, EnemyBrain.new("e1", d)]

func run_all() -> void:
	test_fairness_data()
	test_ai()
	test_fair_dodge()
	test_fuzz()
	print("Enemy: Passed ", passed, " / Failed ", failed)

func test_fairness_data() -> void:
	var d : EnemyData = grunt()
	t("telegraph >= min", d.telegraph >= MIN_TELEGRAPH_ENEMY)
	t("telegraph > reaction budget", d.telegraph > REACTION_BUDGET)
	t("data sane", d.max_hp > 0 and d.damage > 0 and d.attack_range > 0.0 and d.aggro_range > d.attack_range)
	var p : CombatParams = EnemyBrain.make_params(d)
	t("windup is telegraph", is_equal_approx(p.windup, d.telegraph))
	t("dodge window reachable (telegraph - iframe >= budget)", d.telegraph - CombatParams.new().iframe >= REACTION_BUDGET - 0.0001)

func test_ai() -> void:
	var d : EnemyData = grunt()
	var w : Array = world(d)
	var cw : CombatWorld = w[0]
	var b : EnemyBrain = w[1]
	var r : Dictionary = b.think(0.0, cw)
	t("chase when in aggro", not r["attack"] and r["move"].x < 0.0 and b.state == EnemyBrain.S.CHASE)
	cw.set_pos("e1", Vector2(500, 0))
	r = b.think(0.1, cw)
	t("idle out of aggro", r["move"] == Vector2.ZERO and b.state == EnemyBrain.S.IDLE)
	cw.set_pos("e1", Vector2(30, 0))
	r = b.think(0.2, cw)
	t("attack in reach", r["attack"] and r["aim"].x < 0.0 and b.state == EnemyBrain.S.COOLDOWN)
	t("attack starts telegraph", cw.attack("e1", 0.2, r["aim"])["ok"] and cw.actors["e1"]["c"].state == Combatant.State.WINDUP)
	t("frozen during telegraph", b.think(0.5, cw)["move"] == Vector2.ZERO and not b.think(0.5, cw)["attack"])
	var dead : EnemyBrain = EnemyBrain.new("ghost", d)
	t("unknown actor idle", dead.think(0.0, cw)["attack"] == false)
	cw.actors["p1"]["c"].apply_damage(100, 0.6)
	t("no living target: idle", b.think(5.0, cw)["target"] == "" and b.state == EnemyBrain.S.IDLE)

func test_fair_dodge() -> void:
	var d : EnemyData = grunt()
	var iframe : float = CombatParams.new().iframe
	var resolve_at : float = d.telegraph
	var window_start : float = resolve_at - iframe
	t("window starts after reaction budget", window_start >= REACTION_BUDGET - 0.0001)
	# dodge ที่ต้น window และปลาย window ต้องรอด
	for dt in [window_start + 0.002, resolve_at - 0.001]:
		var w : Array = world(d)
		var cw : CombatWorld = w[0]
		cw.set_pos("e1", Vector2(30, 0))
		cw.attack("e1", 0.0, Vector2(-1, 0))
		cw.actors["p1"]["c"].start_dodge(dt, Vector2.UP)
		var ev : Array = cw.resolve_swings(resolve_at + 0.0005)
		t("dodge at %.3f saves" % dt, ev.size() == 1 and ev[0]["result"]["reason"] == CombatResult.INVULNERABLE and cw.hp_of("p1") == 100)
	# dodge เร็วเกินไป (i-frame หมดก่อน resolve) ต้องโดนจริง: เกณฑ์ไม่หลวมเกินไป
	var w2 : Array = world(d)
	var cw2 : CombatWorld = w2[0]
	cw2.set_pos("e1", Vector2(30, 0))
	cw2.attack("e1", 0.0, Vector2(-1, 0))
	cw2.actors["p1"]["c"].start_dodge(window_start - 0.03, Vector2.UP)
	t("early dodge: hit lands", cw2.resolve_swings(resolve_at + 0.0005).size() == 1 and cw2.hp_of("p1") == 100 - d.damage)

func test_fuzz() -> void:
	var d : EnemyData = grunt()
	var w : Array = world(d)
	var cw : CombatWorld = w[0]
	var b : EnemyBrain = w[1]
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 321
	var now : float = 0.0
	var bad : int = 0
	var moved_during_telegraph : int = 0
	for i in 600:
		now += rng.randf_range(0.02, 0.2)
		if rng.randi() % 4 == 0:
			cw.set_pos("p1", Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100)))
		var was_busy : bool = cw.actors["e1"]["c"].state != Combatant.State.IDLE
		var r : Dictionary = b.think(now, cw)
		if was_busy and (r["move"] != Vector2.ZERO or r["attack"]):
			moved_during_telegraph += 1
		if r["attack"]:
			var res : Dictionary = cw.attack("e1", now, r["aim"])
			if not res["ok"] and res["reason"] != CombatResult.NOT_IDLE:
				bad += 1
		cw.resolve_swings(now)
		if cw.hp_of("p1") <= 0:
			cw.actors["p1"]["c"] = Combatant.new(CombatParams.new(), 100)
			cw.actors["p1"]["resolved"] = 0
	t("fuzz: enemy never moves/attacks while busy", moved_during_telegraph == 0)
	t("fuzz: no bad attack results", bad == 0)
