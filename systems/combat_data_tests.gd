extends RefCounted
class_name CombatDataTests

var passed : int = 0
var failed : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func run_all() -> void:
	var r : Dictionary = EnemyLoader.load_dir("res://data/enemies/")
	t("enemies load", r["ok"] and r["enemies"].has(&"grunt"))
	var g : EnemyData = r["enemies"].get(&"grunt")
	t("grunt valid", g != null and EnemyLoader.validate(g) == EnemyLoader.OK)
	t("missing dir", EnemyLoader.load_dir("res://nope/")["reason"] == EnemyLoader.BAD_DIR)
	var p : CombatParams = load("res://data/combat/player_params.tres") as CombatParams
	t("player params load", p != null and p.cone_half_angle == 60.0 and p.windup == 0.15)
	# data ผิดต้องถูกปฏิเสธ
	var bad : EnemyData = EnemyData.new()
	bad.id = &"x"
	bad.telegraph = 0.30
	t("telegraph too short rejected", EnemyLoader.validate(bad) == EnemyLoader.BAD_VALUE)
	bad.telegraph = 0.70
	bad.max_hp = 0
	t("max_hp 0 rejected", EnemyLoader.validate(bad) == EnemyLoader.BAD_VALUE)
	bad.max_hp = 10
	bad.aggro_range = 10.0
	t("aggro <= attack range rejected", EnemyLoader.validate(bad) == EnemyLoader.BAD_VALUE)
	bad.aggro_range = 220.0
	bad.id = &""
	t("empty id rejected", EnemyLoader.validate(bad) == EnemyLoader.BAD_VALUE)
	# ItemDatabase ยังโหลดได้ปกติ ไม่เห็น enemy
	var db : ItemDatabase = ItemDatabase.new()
	t("ItemDatabase unaffected", db.load_from_directory("res://data/") and not db.has_item(&"grunt"))
	# ข้อความ
	t("text lookup", CombatText.of(&"invulnerable") != "" and CombatText.of(&"unknown_x") == "unknown_x")
	# ปรับ cone ผ่าน data มีผลจริง
	var cw : CombatWorld = CombatWorld.new(p)
	var w : WeaponData = WeaponData.new()
	w.id = &"s"
	cw.add_actor("a", 100, Vector2.ZERO, 8.0, 0, w)
	cw.add_actor("b", 50, Vector2(20, 30), 0.0, 1)
	cw.attack("a", 0.0, Vector2.RIGHT)
	t("60deg cone misses 56deg-off target? (hit)", cw.resolve_swings(0.2).size() == 1)
	var narrow : CombatParams = CombatParams.new()
	narrow.cone_half_angle = 20.0
	var cw2 : CombatWorld = CombatWorld.new(narrow)
	cw2.add_actor("a", 100, Vector2.ZERO, 8.0, 0, w)
	cw2.add_actor("b", 50, Vector2(20, 30), 0.0, 1)
	cw2.attack("a", 0.0, Vector2.RIGHT)
	t("20deg cone misses same target", cw2.resolve_swings(0.2).is_empty())
	print("CombatData: Passed ", passed, " / Failed ", failed)
