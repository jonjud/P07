extends RefCounted
class_name HitShapesTests

var passed : int = 0
var failed : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func tg(id : String, x : float, y : float, r : float = 8.0) -> Dictionary:
	return {"id": id, "pos": Vector2(x, y), "radius": r}

func bl(x : float, y : float, r : float = 20.0) -> Dictionary:
	return {"pos": Vector2(x, y), "radius": r}

func ln(targets : Array, blockers : Array = [], aim : Vector2 = Vector2.RIGHT) -> Array:
	return HitCheck.line(Vector2.ZERO, aim, 300.0, 16.0, blockers, targets)

func run_all() -> void:
	# line
	t("line hits in front", ln([tg("a", 100, 0)]) == ["a"])
	t("line behind origin", ln([tg("a", -100, 0)]).is_empty())
	t("line off to side", ln([tg("a", 100, 40)]).is_empty())
	t("line width edge in", ln([tg("a", 100, 15)]) == ["a"])   # 15 <= 8 + 8
	t("line width edge out", ln([tg("a", 100, 17)]).is_empty())
	t("line too far", ln([tg("a", 320, 0)]).is_empty())
	t("line far edge via radius", ln([tg("a", 305, 0)]) == ["a"])
	t("line passes multiple, ordered", ln([tg("far", 200, 0), tg("near", 80, 0)]) == ["near", "far"])
	t("line blocked: target behind pillar safe", ln([tg("a", 200, 0)], [bl(100, 0)]).is_empty())
	t("line blocked: target before pillar hit", ln([tg("a", 50, 0)], [bl(100, 0)]) == ["a"])
	t("line blocked: pillar off-axis no block", ln([tg("a", 200, 0)], [bl(100, 60)]).is_empty() == false)
	t("line pillar width-expanded blocks", ln([tg("a", 200, 0)], [bl(100, 25)]).is_empty())
	t("line pillar just outside expanded radius", ln([tg("a", 200, 0)], [bl(100, 30)]) == ["a"])
	t("line nearest pillar wins", ln([tg("n", 60, 0), tg("a", 150, 0), tg("b", 250, 0)], [bl(200, 0), bl(120, 0)]) == ["n"])
	t("line origin inside pillar: all blocked", ln([tg("a", 100, 0)], [bl(0, 0)]).is_empty())
	t("line diagonal", HitCheck.line(Vector2.ZERO, Vector2(1, 1), 300.0, 16.0, [], [tg("a", 100, 100)]) == ["a"])
	t("line aim not normalized", ln([tg("a", 100, 0)], [], Vector2(50, 0)) == ["a"])
	t("line aim zero", ln([tg("a", 100, 0)], [], Vector2.ZERO).is_empty())
	t("line aim nan", ln([tg("a", 100, 0)], [], Vector2(NAN, 0)).is_empty())
	t("line length 0", HitCheck.line(Vector2.ZERO, Vector2.RIGHT, 0.0, 16.0, [], [tg("a", 1, 0)]).is_empty())
	t("line width neg", HitCheck.line(Vector2.ZERO, Vector2.RIGHT, 300.0, -1.0, [], [tg("a", 100, 0)]).is_empty())
	t("line bad blocker ignored", ln([tg("a", 100, 0)], [5, {"pos": Vector2(50, 0)}, bl(NAN, 0)]) == ["a"])
	t("line bad target", ln([5, {"id": "x"}, tg("n", NAN, 0)]).is_empty())
	t("line ignore", HitCheck.line(Vector2.ZERO, Vector2.RIGHT, 300.0, 16.0, [], [tg("me", 5, 0), tg("a", 100, 0)], "me") == ["a"])
	var ts : Array = [tg("a", 100, 5), tg("b", 100, -5)]
	t("line deterministic ties", ln(ts) == ["a", "b"] and ln(ts) == ln(ts))
	# ring
	var rg : Callable = func(ts2 : Array) -> Array: return HitCheck.ring(Vector2.ZERO, 40.0, 80.0, ts2)
	t("ring inside band", rg.call([tg("a", 60, 0)]) == ["a"])
	t("ring any angle", rg.call([tg("a", 0, -60), tg("b", -60, 0)]) == ["a", "b"])
	t("ring center safe", rg.call([tg("a", 0, 0, 8)]).is_empty())
	t("ring far safe", rg.call([tg("a", 200, 0)]).is_empty())
	t("ring inner edge radius touches", rg.call([tg("a", 33, 0, 8)]) == ["a"])
	t("ring inner just safe", rg.call([tg("a", 30, 0, 8)]).is_empty())
	t("ring outer edge radius touches", rg.call([tg("a", 87, 0, 8)]) == ["a"])
	t("ring outer just safe", rg.call([tg("a", 90, 0, 8)]).is_empty())
	t("ring ignores pillars (design)", rg.call([tg("a", 60, 0)]) == ["a"])
	t("ring bad band", HitCheck.ring(Vector2.ZERO, 50.0, 50.0, [tg("a", 50, 0)]).is_empty() and HitCheck.ring(Vector2.ZERO, -1.0, 10.0, [tg("a", 5, 0)]).is_empty())
	t("ring nan origin", HitCheck.ring(Vector2(NAN, 0), 10.0, 50.0, [tg("a", 20, 0)]).is_empty())
	t("ring bad target", rg.call([5, {"id": 1}, tg("n", NAN, 0)]).is_empty())
	t("ring ordered near->far, tie id", rg.call([tg("far", 70, 0), tg("b", 50, 0), tg("a", 0, 50)]) == ["a", "b", "far"])
	print("HitShapes: Passed ", passed, " / Failed ", failed)
