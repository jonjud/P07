extends RefCounted
class_name BossTests

const BOSS : String = "boss"
const BIG : int = 100000
var passed : int = 0
var failed : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func mk(d : BossData, ppos : Vector2, php : int = BIG) -> Array:
	var cw : CombatWorld = CombatWorld.new(CombatParams.new())
	cw.add_actor(BOSS, d.max_hp, Vector2.ZERO, d.radius, 1)
	cw.add_actor("p1", php, ppos, 12.0, 0)
	var b : BossBrain = BossBrain.new(BOSS, d)
	b.engaged = true
	return [cw, b]

func only(pid : StringName) -> BossData:
	var d : BossData = BossData.grove()
	d.seq_early.assign([pid])
	d.seq_late.assign([pid])
	return d

func run_all() -> void:
	test_validate()
	test_flow()
	test_sequence()
	test_dodge()
	test_shapes()
	test_interactions()
	test_fuzz()
	print("Boss: Passed ", passed, " / Failed ", failed)

func test_validate() -> void:
	t("grove valid", BossData.validate(BossData.grove()) == BossData.OK)
	var d : BossData = BossData.grove()
	d.patterns[0].telegraph = 0.5
	t("telegraph too short", BossData.validate(d) == BossData.BAD_VALUE)
	d = BossData.grove()
	d.seq_early.assign([&"nope"])
	t("unknown id in seq", BossData.validate(d) == BossData.BAD_VALUE)
	d = BossData.grove()
	d.patterns[2].inner = 200.0
	t("ring inner >= outer", BossData.validate(d) == BossData.BAD_VALUE)
	d = BossData.grove()
	d.seq_late.assign([])
	t("empty seq", BossData.validate(d) == BossData.BAD_VALUE)
	d = BossData.grove()
	d.phase3_at = 0.9
	t("bad thresholds", BossData.validate(d) == BossData.BAD_VALUE)
	d = BossData.grove()
	d.patterns[0].shape = &"laser"
	t("unknown shape", BossData.validate(d) == BossData.BAD_VALUE)
	d = BossData.grove()
	d.patterns[1].id = &"root_sweep"
	t("dup pattern id", BossData.validate(d) == BossData.BAD_VALUE)
	d = BossData.grove()
	d.patterns[0].damage = 0
	t("damage 0", BossData.validate(d) == BossData.BAD_VALUE)
	t("null data", BossData.validate(null) == BossData.BAD_VALUE)

func test_flow() -> void:
	var d : BossData = BossData.grove()
	var r : Array = mk(d, Vector2(80, 0))
	var cw : CombatWorld = r[0]
	var b : BossBrain = r[1]
	b.engaged = false
	for i in 10:
		b.step(i * 0.01, cw)
	t("not engaged: idle, no damage", b.state == BossBrain.S.IDLE and cw.hp_of("p1") == BIG)
	b.engaged = true
	b.step(0.1, cw)
	t("telegraph begins, aim locked to player", b.state == BossBrain.S.TELEGRAPH and b.cur.id == &"root_sweep" and b.aim.x > 0.0)
	t("no damage before telegraph ends", b.step(0.79, cw).is_empty() and cw.hp_of("p1") == BIG)
	var ev : Array = b.step(0.801, cw)
	t("resolve after telegraph", ev.size() == 1 and ev[0]["target"] == "p1" and ev[0]["result"]["ok"] and cw.hp_of("p1") == BIG - 15)
	t("recovery then no re-hit", b.state == BossBrain.S.RECOVERY and b.step(0.9, cw).is_empty())
	# aim ล็อก: ผู้เล่นย้ายออกนอกกรวยระหว่าง telegraph = รอด
	var r2 : Array = mk(d, Vector2(80, 0))
	var cw2 : CombatWorld = r2[0]
	var b2 : BossBrain = r2[1]
	b2.step(0.0, cw2)
	cw2.set_pos("p1", Vector2(0, 100))
	t("moving out of locked cone survives", b2.step(0.701, cw2).is_empty() and cw2.hp_of("p1") == BIG)

func begins(d : BossData, n : int, boss_dmg : int) -> Array:
	var r : Array = mk(d, Vector2(200, 0))
	var cw : CombatWorld = r[0]
	var b : BossBrain = r[1]
	if boss_dmg > 0:
		cw.actors[BOSS]["c"].apply_damage(boss_dmg, 0.0)
	var out : Array = []
	var now : float = 0.0
	var guard : int = 0
	while out.size() < n and guard < 100000:
		var before : int = b.state
		b.step(now, cw)
		if before == BossBrain.S.IDLE and b.state == BossBrain.S.TELEGRAPH:
			out.append([b.cur.id, now])
		now += 0.01
		guard += 1
	return out

func ids_of(l : Array) -> Array:
	return l.map(func(x): return String(x[0]))

func test_sequence() -> void:
	var d : BossData = BossData.grove()
	t("phase1 sequence", ids_of(begins(d, 3, 0)) == ["root_sweep", "seed_volley", "root_sweep"])
	t("phase2 sequence adds ring", ids_of(begins(d, 4, 80)) == ["root_sweep", "seed_volley", "root_ring", "root_sweep"])
	var p1 : Array = begins(only(&"root_sweep"), 2, 0)
	var p3 : Array = begins(only(&"root_sweep"), 2, 140)   # hp 60/200 = 0.3 -> phase 3
	t("phase3 faster cooldown", (p3[1][1] - p3[0][1]) < (p1[1][1] - p1[0][1]) - 0.2)

func test_dodge() -> void:
	var a : ArenaData = ArenaData.new()
	var iframe : float = CombatParams.new().iframe
	var pos : Dictionary = {&"root_sweep": Vector2(80, 0), &"seed_volley": Vector2(150, 0), &"root_ring": Vector2(120, 0)}
	for pid in pos:
		var d : BossData = only(pid)
		var tele : float = d.pattern(pid).telegraph
		t("telegraph >= min " + String(pid), tele >= BossData.MIN_TELEGRAPH)
		t("dodge window after reaction budget " + String(pid), tele - iframe >= 0.45 - 0.0001)
		for dt in [tele - iframe + 0.002, tele - 0.001]:
			var r : Array = mk(d, pos[pid])
			var cw : CombatWorld = r[0]
			var b : BossBrain = r[1]
			b.step(0.0, cw, a.pillars())
			cw.actors["p1"]["c"].start_dodge(dt, Vector2.UP)
			var ev : Array = b.step(tele, cw, a.pillars())
			t("dodge at %.3f saves %s" % [dt, String(pid)], ev.size() == 1 and ev[0]["result"]["reason"] == CombatResult.INVULNERABLE and cw.hp_of("p1") == BIG)
		var r2 : Array = mk(d, pos[pid])
		var cw2 : CombatWorld = r2[0]
		var b2 : BossBrain = r2[1]
		b2.step(0.0, cw2, a.pillars())
		cw2.actors["p1"]["c"].start_dodge(tele - iframe - 0.03, Vector2.UP)
		var ev2 : Array = b2.step(tele, cw2, a.pillars())
		t("early dodge still hit " + String(pid), ev2.size() == 1 and ev2[0]["result"]["ok"])

func fire(pid : StringName, ppos : Vector2, blockers : Array) -> Array:
	var d : BossData = only(pid)
	var r : Array = mk(d, ppos)
	r[1].step(0.0, r[0], blockers)
	return r[1].step(d.pattern(pid).telegraph, r[0], blockers)

func test_shapes() -> void:
	var a : ArenaData = ArenaData.new()
	var behind : Vector2 = Vector2.from_angle(deg_to_rad(45.0)) * 200.0
	t("pillar shields from volley", fire(&"seed_volley", behind, a.pillars()).is_empty())
	t("same spot without pillars is hit", fire(&"seed_volley", behind, []).size() == 1)
	t("open ground hit with pillars", fire(&"seed_volley", Vector2(200, 0), a.pillars()).size() == 1)
	var close : Array = fire(&"seed_volley", Vector2(30, 0), [])
	t("multi-line overlap = one hit", close.size() == 1 and close[0]["result"]["done"] == 10)
	t("sweep ignores pillars", fire(&"root_sweep", Vector2(80, 0), a.pillars()).size() == 1)
	t("ring: hugging boss safe", fire(&"root_ring", Vector2(60, 0), a.pillars()).is_empty())
	t("ring: far away safe", fire(&"root_ring", Vector2(190, 0), a.pillars()).is_empty())
	t("ring: middle hit", fire(&"root_ring", Vector2(120, 0), a.pillars()).size() == 1)

func test_interactions() -> void:
	var d : BossData = BossData.grove()
	# ตีบอสได้ปกติ ไม่ขัด pattern
	var r : Array = mk(d, Vector2(70, 0))
	var cw : CombatWorld = r[0]
	var b : BossBrain = r[1]
	var sword : WeaponData = WeaponData.new()
	sword.id = &"test_sword"
	cw.actors["p1"]["weapon"] = sword
	b.step(0.0, cw)
	cw.attack("p1", 0.0, Vector2.LEFT)
	cw.resolve_swings(0.2)
	t("player damages boss during telegraph", cw.hp_of(BOSS) == d.max_hp - 10)
	var ev : Array = b.step(0.7, cw)
	t("pattern not interrupted", ev.size() == 1 and cw.hp_of("p1") == BIG - 15)
	# บอสตายกลาง telegraph = ไม่ resolve
	var r2 : Array = mk(d, Vector2(80, 0))
	r2[1].step(0.0, r2[0])
	r2[0].actors[BOSS]["c"].apply_damage(d.max_hp, 0.1)
	t("boss dead mid-telegraph: no resolve", r2[1].step(0.7, r2[0]).is_empty() and r2[0].hp_of("p1") == BIG and r2[1].state == BossBrain.S.DONE)
	# ไม่มีเป้าที่ยังมีชีวิต = ไม่เริ่ม
	var r3 : Array = mk(d, Vector2(80, 0), 50)
	r3[0].actors["p1"]["c"].apply_damage(50, 0.0)
	r3[1].step(0.1, r3[0])
	t("no living target: stays idle", r3[1].state == BossBrain.S.IDLE)
	# อ้างอิง actor หาย
	t("unknown boss id safe", BossBrain.new("ghost", d).step(0.0, r3[0]).is_empty())

func test_fuzz() -> void:
	var d : BossData = BossData.grove()
	var a : ArenaData = ArenaData.new()
	var r : Array = mk(d, Vector2(100, 0))
	var cw : CombatWorld = r[0]
	var b : BossBrain = r[1]
	cw.actors[BOSS]["c"].apply_damage(80, 0.0)   # phase 2: ครบ 3 pattern
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5150
	var now : float = 0.0
	var bad : int = 0
	var fired : int = 0
	var seen : Dictionary = {}
	for i in 4000:
		now += rng.randf_range(0.005, 0.1)
		if rng.randi() % 3 == 0:
			cw.set_pos("p1", Vector2(rng.randf_range(-250, 250), rng.randf_range(-250, 250)))
		var before : int = cw.hp_of("p1")
		var was_tele : bool = b.state == BossBrain.S.TELEGRAPH
		var ev : Array = b.step(now, cw, a.pillars())
		if was_tele and b.state == BossBrain.S.RECOVERY:
			fired += 1
			seen[b.cur.id] = true
			if now - b.t_start < b.cur.telegraph - 0.000001:
				bad += 1
		var dealt : int = 0
		for e in ev:
			if e["result"]["ok"]:
				dealt += e["result"]["done"]
		if before - cw.hp_of("p1") != dealt:
			bad += 1
		if b.state < 0 or b.state > BossBrain.S.DONE:
			bad += 1
	t("fuzz: hp loss == damage, resolve only after telegraph", bad == 0)
	t("fuzz: exercised all patterns", fired > 20 and seen.size() == 3)
