extends RefCounted
class_name HitCheckTests

var passed : int = 0
var failed : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func tg(id : String, x : float, y : float, r : float = 0.0) -> Dictionary:
	return {"id": id, "pos": Vector2(x, y), "radius": r}

func hit(targets : Array, aim : Vector2 = Vector2.RIGHT) -> Array:
	return HitCheck.cone(Vector2.ZERO, aim, 48.0, 60.0, targets)

func run_all() -> void:
	t("front", hit([tg("a", 30, 0)]) == ["a"])
	t("behind", hit([tg("a", -30, 0)]).is_empty())
	t("side 90deg", hit([tg("a", 0, 30)]).is_empty())
	t("angle 59 in", hit([tg("a", 30 * cos(deg_to_rad(59)), 30 * sin(deg_to_rad(59)))]) == ["a"])
	t("angle 61 out", hit([tg("a", 30 * cos(deg_to_rad(61)), 30 * sin(deg_to_rad(61)))]).is_empty())
	t("range 48 in", hit([tg("a", 48, 0)]) == ["a"])
	t("range 49 out", hit([tg("a", 49, 0)]).is_empty())
	t("radius extends range", hit([tg("a", 49, 0, 2)]) == ["a"])
	t("radius widens angle", hit([tg("a", 30 * cos(deg_to_rad(65)), 30 * sin(deg_to_rad(65)), 8)]) == ["a"])
	t("overlap origin", hit([tg("a", -1, 0, 5)]) == ["a"])
	t("ignore self", HitCheck.cone(Vector2.ZERO, Vector2.RIGHT, 48.0, 60.0, [tg("me", 5, 0), tg("a", 30, 0)], "me") == ["a"])
	t("order near->far", hit([tg("far", 40, 0), tg("near", 10, 0)]) == ["near", "far"])
	t("tie by id", hit([tg("b", 20, 0), tg("a", 20, 0)]) == ["a", "b"])
	t("multi in cone", hit([tg("a", 20, 5), tg("b", 30, -5), tg("c", -20, 0)]) == ["a", "b"])
	t("aim not normalized", hit([tg("a", 30, 0)], Vector2(100, 0)) == ["a"])
	t("aim diagonal", hit([tg("a", 20, 20)], Vector2(1, 1)) == ["a"])
	t("origin offset", HitCheck.cone(Vector2(100, 100), Vector2.RIGHT, 48.0, 60.0, [tg("a", 130, 100)]) == ["a"])
	t("aim zero", hit([tg("a", 30, 0)], Vector2.ZERO).is_empty())
	t("aim nan", hit([tg("a", 30, 0)], Vector2(NAN, 0)).is_empty())
	t("reach 0", HitCheck.cone(Vector2.ZERO, Vector2.RIGHT, 0.0, 60.0, [tg("a", 1, 0)]).is_empty())
	t("half 0", HitCheck.cone(Vector2.ZERO, Vector2.RIGHT, 48.0, 0.0, [tg("a", 1, 0)]).is_empty())
	t("half 180 all", HitCheck.cone(Vector2.ZERO, Vector2.RIGHT, 48.0, 180.0, [tg("a", -30, 0)]) == ["a"])
	t("target nan pos", hit([tg("a", NAN, 0)]).is_empty())
	t("target neg radius", hit([tg("a", 30, 0, -1)]).is_empty())
	t("target bad shape", hit([5, {"id": "x"}, {"id": 1, "pos": Vector2(1, 0), "radius": 0}]).is_empty())
	t("empty targets", hit([]).is_empty())
	var ts : Array = [tg("a", 20, 5), tg("b", 30, -5)]
	t("deterministic", hit(ts) == hit(ts))
	print("HitCheck: Passed ", passed, " / Failed ", failed)
