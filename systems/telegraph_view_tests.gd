extends RefCounted
class_name TelegraphViewTests

var passed : int = 0
var failed : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func run_all() -> void:
	var d : EnemyData = EnemyData.new()
	d.id = &"grunt"
	var cw : CombatWorld = CombatWorld.new(CombatParams.new())
	cw.add_actor("e1", d.max_hp, Vector2(10, 20), d.radius, 1, EnemyBrain.make_weapon(d), EnemyBrain.make_params(d))
	t("idle: none", TelegraphView.of(cw, "e1", 0.0)["phase"] == &"none")
	t("unknown: none", TelegraphView.of(cw, "ghost", 0.0)["phase"] == &"none")
	cw.attack("e1", 1.0, Vector2.RIGHT)
	var v : Dictionary = TelegraphView.of(cw, "e1", 1.0)
	t("windup start: progress 0", v["phase"] == &"windup" and is_equal_approx(v["progress"], 0.0))
	cw.resolve_swings(1.35)
	v = TelegraphView.of(cw, "e1", 1.35)
	t("windup half: progress 0.5", v["phase"] == &"windup" and is_equal_approx(v["progress"], 0.5))
	t("cone matches hit params", v["cone"]["reach"] == d.attack_range and v["cone"]["half_angle"] == 60.0 and v["cone"]["origin"] == Vector2(10, 20) and v["cone"]["aim"] == Vector2.RIGHT)
	cw.resolve_swings(1.0 + d.telegraph + 0.01)
	v = TelegraphView.of(cw, "e1", 1.0 + d.telegraph + 0.01)
	t("active phase", v["phase"] == &"active" and v["progress"] == 1.0)
	cw.resolve_swings(1.0 + d.telegraph + d.active + 0.01)
	t("recovery: none", TelegraphView.of(cw, "e1", 1.0 + d.telegraph + d.active + 0.01)["phase"] == &"none")
	cw.actors["e1"]["c"].apply_damage(999, 5.0)
	t("dead: none", TelegraphView.of(cw, "e1", 5.0)["phase"] == &"none")
	# progress ถึง 1.0 พอดีตอนจุด resolve
	var cw2 : CombatWorld = CombatWorld.new(CombatParams.new())
	cw2.add_actor("e1", 40, Vector2.ZERO, 12.0, 1, EnemyBrain.make_weapon(d), EnemyBrain.make_params(d))
	cw2.attack("e1", 0.0, Vector2.LEFT)
	cw2.resolve_swings(d.telegraph - 0.001)
	t("progress < 1 until resolve", TelegraphView.of(cw2, "e1", d.telegraph - 0.001)["progress"] < 1.0)
	print("TelegraphView: Passed ", passed, " / Failed ", failed)
