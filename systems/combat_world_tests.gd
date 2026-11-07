extends RefCounted
class_name CombatWorldTests

var passed : int = 0
var failed : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func sword(dmg : int = 10, rng : float = 48.0, spd : float = 1.0) -> WeaponData:
	var w : WeaponData = WeaponData.new()
	w.id = &"test_sword"
	w.damage = dmg
	w.attack_range = rng
	w.attack_speed = spd
	return w

func world() -> CombatWorld:
	var cw : CombatWorld = CombatWorld.new(CombatParams.new())
	cw.add_actor("p1", 100, Vector2.ZERO, 8.0, 0, sword())
	cw.add_actor("e1", 50, Vector2(30, 0), 8.0, 1)
	return cw

func total_hp(cw : CombatWorld) -> int:
	var n : int = 0
	for id in cw.actors:
		n += cw.hp_of(id)
	return n

func run_all() -> void:
	test_basic()
	test_once_per_swing()
	test_multi()
	test_guards()
	test_dodge_and_death()
	test_fuzz()
	print("CombatWorld: Passed ", passed, " / Failed ", failed)

func test_basic() -> void:
	var cw : CombatWorld = world()
	t("attack ok", cw.attack("p1", 0.0, Vector2.RIGHT)["ok"])
	t("no hit in windup", cw.resolve_swings(0.1).is_empty() and cw.hp_of("e1") == 50)
	var ev : Array = cw.resolve_swings(0.16)
	t("hit at active", ev.size() == 1 and ev[0]["attacker"] == "p1" and ev[0]["target"] == "e1" and ev[0]["result"]["ok"])
	t("hp reduced", cw.hp_of("e1") == 40)
	var miss : CombatWorld = world()
	miss.attack("p1", 0.0, Vector2.LEFT)
	t("miss: wrong direction", miss.resolve_swings(0.2).is_empty() and miss.hp_of("e1") == 50)
	var far : CombatWorld = world()
	far.set_pos("e1", Vector2(100, 0))
	far.attack("p1", 0.0, Vector2.RIGHT)
	t("miss: out of range", far.resolve_swings(0.2).is_empty())
	var jump : CombatWorld = world()
	jump.attack("p1", 0.0, Vector2.RIGHT)
	t("swing skipped by lag still resolves", jump.resolve_swings(5.0).size() == 1 and jump.hp_of("e1") == 40)

func test_once_per_swing() -> void:
	var cw : CombatWorld = world()
	cw.attack("p1", 0.0, Vector2.RIGHT)
	cw.resolve_swings(0.16)
	t("repeat resolve: no extra hit", cw.resolve_swings(0.17).is_empty() and cw.resolve_swings(0.2).is_empty() and cw.hp_of("e1") == 40)
	t("second swing hits again", cw.attack("p1", 0.6, Vector2.RIGHT)["ok"] and cw.resolve_swings(0.8).size() == 1 and cw.hp_of("e1") == 30)

func test_multi() -> void:
	var cw : CombatWorld = world()
	cw.add_actor("e2", 50, Vector2(25, 6), 8.0, 1)
	cw.add_actor("e3", 50, Vector2(-30, 0), 8.0, 1)
	cw.attack("p1", 0.0, Vector2.RIGHT)
	var ev : Array = cw.resolve_swings(0.2)
	t("hits both in cone, not behind", ev.size() == 2 and cw.hp_of("e1") == 40 and cw.hp_of("e2") == 40 and cw.hp_of("e3") == 50)
	t("events deterministic order", ev[0]["target"] == "e2" and ev[1]["target"] == "e1")   # e2 ใกล้กว่า

func test_guards() -> void:
	var cw : CombatWorld = world()
	cw.add_actor("p2", 100, Vector2(15, 0), 8.0, 0, sword())
	cw.attack("p1", 0.0, Vector2.RIGHT)
	t("friendly fire off", cw.resolve_swings(0.2).size() == 1 and cw.hp_of("p2") == 100)
	t("unknown actor", cw.attack("ghost", 1.0, Vector2.RIGHT)["reason"] == CombatResult.UNKNOWN_ACTOR)
	t("no weapon", cw.attack("e1", 1.0, Vector2.LEFT)["reason"] == CombatResult.BAD_WEAPON)
	var bad : CombatWorld = CombatWorld.new(CombatParams.new())
	bad.add_actor("a", 10, Vector2.ZERO, 8.0, 0, sword(0))
	t("zero damage weapon", bad.attack("a", 0.0, Vector2.RIGHT)["reason"] == CombatResult.BAD_WEAPON)
	t("dup actor id", not cw.add_actor("p1", 10, Vector2.ZERO, 8.0, 0))
	t("bad actor", not cw.add_actor("z", 0, Vector2.ZERO, 8.0, 0) and not cw.add_actor("", 5, Vector2.ZERO, 8.0, 0))
	var b : int = total_hp(cw)
	cw.attack("p1", 0.1, Vector2.RIGHT)   # ยังอยู่ใน swing เดิม = NOT_IDLE
	t("attack mid-swing rejected, hp same", total_hp(cw) == b)

func test_dodge_and_death() -> void:
	var cw : CombatWorld = world()
	cw.actors["e1"]["weapon"] = sword(10)
	cw.attack("p1", 0.0, Vector2.RIGHT)
	cw.actors["e1"]["c"].start_dodge(0.1, Vector2.UP)   # i-frame 0.1..0.25 คลุม 0.15
	var ev : Array = cw.resolve_swings(0.16)
	t("dodged: event shows INVULNERABLE, hp same", ev.size() == 1 and ev[0]["result"]["reason"] == CombatResult.INVULNERABLE and cw.hp_of("e1") == 50)
	var k : CombatWorld = world()
	k.attack("p1", 0.0, Vector2.RIGHT)
	k.actors["e1"]["c"].apply_damage(50, 0.01)
	t("dead target not hit", k.resolve_swings(0.2).is_empty() and k.hp_of("e1") == 0)
	var d : CombatWorld = world()
	d.attack("p1", 0.0, Vector2.RIGHT)
	d.resolve_swings(0.16)
	d.actors["p1"]["c"].apply_damage(100, 0.17)
	t("attacker dead after swing resolved: hit stays", d.hp_of("e1") == 40 and d.actors["p1"]["c"].state == Combatant.State.DEAD)
	var m : CombatWorld = world()
	m.attack("p1", 0.0, Vector2.RIGHT)
	m.actors["p1"]["c"].apply_damage(100, 0.05)
	t("attacker dead in windup: no swing", m.resolve_swings(1.0).is_empty() and m.hp_of("e1") == 50)

func test_fuzz() -> void:
	var cw : CombatWorld = world()
	cw.add_actor("e2", 80, Vector2(-30, 10), 8.0, 1, sword(7))
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 909
	var now : float = 0.0
	var bad : int = 0
	var dealt : int = 0
	var swings : Dictionary = {}
	for i in 400:
		now += rng.randf_range(0.0, 0.3)
		var id : String = ["p1", "e1", "e2"][rng.randi() % 3]
		if rng.randi() % 2 == 0:
			cw.attack(id, now, Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
		else:
			cw.actors[id]["c"].start_dodge(now, Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
		var before : int = total_hp(cw)
		for e in cw.resolve_swings(now):
			if e["result"]["ok"]:
				dealt += e["result"]["done"]
		if before - total_hp(cw) != dealt - swings.get("d", 0):
			bad += 1
		swings["d"] = dealt
		for aid in cw.actors:
			var c : Combatant = cw.actors[aid]["c"]
			if c.hp < 0 or c.hp > c.max_hp or cw.actors[aid]["resolved"] > c.swing_id:
				bad += 1
	t("fuzz: hp loss == damage dealt, invariants", bad == 0)
	t("fuzz: something happened", dealt > 0)
