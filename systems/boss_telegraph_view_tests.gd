extends RefCounted
class_name BossTelegraphViewTests

var passed : int = 0
var failed : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func setup(d : BossData) -> Array:
	var cw : CombatWorld = CombatWorld.new(CombatParams.new())
	cw.add_actor("boss", d.max_hp, Vector2.ZERO, d.radius, 1)
	cw.add_actor("p1", 100000, Vector2(200, 0), 12.0, 0)
	var b : BossBrain = BossBrain.new("boss", d)
	b.engaged = true
	return [cw, b]

func only(pid : StringName) -> BossData:
	var d : BossData = BossData.grove()
	d.seq_early.assign([pid])
	d.seq_late.assign([pid])
	return d

func run_all() -> void:
	var s : Array = setup(BossData.grove())
	t("not started: none", BossTelegraphView.of(s[1], s[0], 0.0)["phase"] == &"none")
	t("null brain: none", BossTelegraphView.of(null, s[0], 0.0)["phase"] == &"none")
	# cone
	var c : Array = setup(only(&"root_sweep"))
	c[1].step(0.0, c[0])
	var v : Dictionary = BossTelegraphView.of(c[1], c[0], 0.35)
	t("cone telegraph", v["phase"] == &"telegraph" and v["shape"] == &"cone" and is_equal_approx(v["progress"], 0.5))
	t("cone matches resolve params", v["reach"] == 110.0 and v["half_angle"] == 80.0 and v["aim"].x > 0.0)
	# line3 + เสาตัดเส้น
	var l : Array = setup(only(&"seed_volley"))
	var a : ArenaData = ArenaData.new()
	var pil : Vector2 = a.pillars()[0]["pos"]
	l[0].set_pos("p1", pil.normalized() * 200.0)
	l[1].step(0.0, l[0], a.pillars())
	v = BossTelegraphView.of(l[1], l[0], 0.4, a.pillars())
	t("line3 has 3 lines", v["shape"] == &"line3" and v["lines"].size() == 3)
	var open : Dictionary = BossTelegraphView.of(l[1], l[0], 0.4, [])
	t("no blockers: full length", open["lines"].all(func(x): return is_equal_approx(x["length"], 400.0)))
	var blocked : Array = v["lines"].filter(func(x): return x["length"] < 400.0)
	t("pillar shortens the centre line", blocked.size() >= 1)
	t("blocked line stops before pillar", blocked.size() >= 1 and blocked.all(func(x): return x["length"] < 150.0))
	# ring
	var r : Array = setup(only(&"root_ring"))
	r[1].step(0.0, r[0])
	v = BossTelegraphView.of(r[1], r[0], 0.45)
	t("ring telegraph", v["shape"] == &"ring" and v["inner"] == 90.0 and v["outer"] == 170.0)
	# recovery / done
	c[1].step(0.7, c[0])
	t("recovery phase", BossTelegraphView.of(c[1], c[0], 0.8)["phase"] == &"recovery")
	c[0].actors["boss"]["c"].apply_damage(99999, 0.9)
	t("boss dead: none", BossTelegraphView.of(c[1], c[0], 0.9)["phase"] == &"none")
	# line_stop ตรงกับ line()
	var tgt : Array = [{"id": "x", "pos": Vector2(300, 0), "radius": 8.0}]
	var bl : Array = [{"pos": Vector2(150, 0), "radius": 20.0}]
	t("line_stop = 150-28", is_equal_approx(HitCheck.line_stop(Vector2.ZERO, Vector2.RIGHT, 400.0, 16.0, bl), 122.0))
	t("line_stop agrees with line()", HitCheck.line(Vector2.ZERO, Vector2.RIGHT, 400.0, 16.0, bl, tgt).is_empty())
	t("line_stop bad input safe", HitCheck.line_stop(Vector2.ZERO, Vector2.ZERO, 400.0, 16.0, bl) == 0.0)
	print("BossTelegraphView: Passed ", passed, " / Failed ", failed)
