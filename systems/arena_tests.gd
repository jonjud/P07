extends RefCounted
class_name ArenaTests

var passed : int = 0
var failed : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func run_all() -> void:
	var a : ArenaData = ArenaData.new()
	a.id = &"grove"
	var ps : Array = a.pillars()
	t("4 pillars", ps.size() == 4)
	var ring_ok : bool = true
	for p in ps:
		if not is_equal_approx(p["pos"].length(), a.pillar_ring):
			ring_ok = false
	t("pillars on ring", ring_ok)
	t("pillars not on axes", absf(ps[0]["pos"].x) > 1.0 and absf(ps[0]["pos"].y) > 1.0)
	t("pillars inside arena", ps.all(func(p): return p["pos"].length() + p["radius"] < a.radius))
	t("entry inside rim", is_equal_approx(a.entry_point().length(), a.radius - 24.0))
	t("entry not inside pillar", a.entry_point() == a.clamp_pos(a.entry_point(), 12.0))
	t("clamp inside unchanged", a.clamp_pos(Vector2(10, 10), 12.0) == Vector2(10, 10))
	var out : Vector2 = a.clamp_pos(Vector2(1000, 0), 12.0)
	t("clamp rim", is_equal_approx(out.length(), a.radius - 12.0))
	var pp : Vector2 = ps[0]["pos"]
	var c : Vector2 = a.clamp_pos(pp, 12.0)
	t("clamp out of pillar", (c - pp).length() >= 20.0 + 12.0 - 0.001)
	t("clamp idempotent", a.clamp_pos(c, 12.0).is_equal_approx(c))
	t("clamp nan-free", a.clamp_pos(Vector2(5, -3), 12.0).is_finite())
	# เสาต้องบังเส้นจริงจากบอสไปหาผู้เล่นหลังเสา
	var dir : Vector2 = ps[0]["pos"].normalized()
	var behind : Dictionary = {"id": "p", "pos": ps[0]["pos"] + dir * 40.0, "radius": 12.0}
	var shot : Array = HitCheck.line(a.boss_pos, dir, 400.0, 16.0, a.pillars(), [behind])
	t("pillar shields player from boss line", shot.is_empty())
	var open : Dictionary = {"id": "p", "pos": Vector2.from_angle(deg_to_rad(0)) * 120.0, "radius": 12.0}
	t("open ground still hit", HitCheck.line(a.boss_pos, Vector2.RIGHT, 400.0, 16.0, a.pillars(), [open]) == ["p"])
	print("Arena: Passed ", passed, " / Failed ", failed)
