extends RefCounted
class_name CombatSnapshotTests

var passed : int = 0
var failed : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func mk() -> HostLogic:
	var h : HostLogic = HostLogic.new()
	h.db = ItemDatabase.new()
	h.db.load_from_directory("res://data/")
	var sh : Inventory = Inventory.new()
	sh.owner_id = HostLogic.SHARED_ID
	h.invs[HostLogic.SHARED_ID] = sh
	h.join(1, "p_a")
	h.join(2, "p_b")
	h.start_encounter(BossData.grove(), ArenaData.new(), CombatParams.new())
	h.positions[1] = Vector2(0, 200)
	h.positions[2] = Vector2(40, 200)
	h.tick(0.1)
	return h

func run_all() -> void:
	var p : CombatParams = CombatParams.new()
	var h : HostLogic = mk()
	var d : Dictionary = CombatSnapshot.to_dict(h.world, h.boss, h.flags)
	t("validate ok", CombatSnapshot.validate(d, p)["ok"])
	t("deterministic hash", CombatSnapshot.hash_of(d) == CombatSnapshot.hash_of(CombatSnapshot.to_dict(h.world, h.boss, h.flags)))
	var d2 : Dictionary = d.duplicate(true)
	d2["actors"]["p_a"]["c"]["hp"] = 1
	t("hash changes with hp", CombatSnapshot.hash_of(d) != CombatSnapshot.hash_of(d2))
	t("snapshot is a copy", d["actors"]["p_a"]["c"]["hp"] == 100)
	var bads : Array = [
		["schema", func(x): x["schema_version"] = 9],
		["missing actors", func(x): x.erase("actors")],
		["actors type", func(x): x["actors"] = 5],
		["actor hp bad", func(x): x["actors"]["p_a"]["c"]["hp"] = -1],
		["actor x nan", func(x): x["actors"]["p_a"]["x"] = NAN],
		["parked type", func(x): x["actors"]["p_a"]["parked"] = 1],
		["boss state", func(x): x["boss"]["state"] = 99],
		["boss seq neg", func(x): x["boss"]["seq_pos"] = -1],
		["boss id unknown", func(x): x["boss"]["id"] = "ghost"],
		["flag type", func(x): x["flags"]["f"] = 1],
		["flag empty key", func(x): x["flags"][""] = true],
	]
	for b in bads:
		var x : Dictionary = d.duplicate(true)
		b[1].call(x)
		var r : Dictionary = CombatSnapshot.validate(x, p)
		t("bad: " + b[0], not r["ok"] and r["snap"].is_empty())
	t("null boss ok", CombatSnapshot.validate(CombatSnapshot.to_dict(h.world, null, {}), p)["ok"])
	# parked
	var h2 : HostLogic = mk()
	h2.world.actors["p_a"]["c"].apply_damage(30, 0.5)
	h2.leave(1)
	t("leave parks, hp kept", h2.world.actors["p_a"]["parked"] and h2.world.hp_of("p_a") == 70)
	var cw : CombatWorld = h2.world
	var ev : Array = cw.resolve_pattern("boss", BossData.grove().pattern(&"root_sweep"), Vector2(0, 1), [], 1.0)
	t("parked actor not hit", ev.all(func(e): return e["target"] != "p_a") and cw.hp_of("p_a") == 70)
	h2.join(5, "p_a")
	t("rejoin unparks, same hp", not cw.actors["p_a"]["parked"] and cw.hp_of("p_a") == 70)
	# encounter with parked
	var w : CombatWorld = CombatWorld.new(p)
	w.add_actor("boss", 100, Vector2.ZERO, 40.0, 1)
	w.add_actor("a", 100, Vector2(50, 0), 12.0, 0)
	w.add_actor("b", 100, Vector2(-50, 0), 12.0, 0)
	w.actors["a"]["c"].apply_damage(100, 0.0)
	w.set_parked("b", true)
	t("all active dead, other parked: lost (no softlock)", EncounterState.result(w, "boss") == EncounterState.R.LOST)
	var wp : CombatWorld = CombatWorld.new(p)
	wp.add_actor("boss", 100, Vector2.ZERO, 40.0, 1)
	wp.add_actor("b", 100, Vector2(-50, 0), 12.0, 0)
	wp.set_parked("b", true)
	t("only parked players: ongoing", EncounterState.result(wp, "boss") == EncounterState.R.ONGOING)
	w.set_parked("b", false)
	w.actors["b"]["c"].apply_damage(100, 0.0)
	t("all dead: lost", EncounterState.result(w, "boss") == EncounterState.R.LOST)
	var wb : BossBrain = BossBrain.new("boss", BossData.grove())
	wb.engaged = true
	var w2 : CombatWorld = CombatWorld.new(p)
	w2.add_actor("boss", 100, Vector2.ZERO, 40.0, 1)
	w2.add_actor("a", 100, Vector2(50, 0), 12.0, 0)
	w2.set_parked("a", true)
	wb.step(0.0, w2)
	t("boss ignores parked: stays idle", wb.state == BossBrain.S.IDLE)
	t("set_parked unknown id", not w2.set_parked("ghost", true))
	print("CombatSnapshot: Passed ", passed, " / Failed ", failed)
