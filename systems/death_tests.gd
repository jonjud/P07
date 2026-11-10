extends RefCounted
class_name DeathTests

const S : StringName = &"stone_00"
const W : StringName = &"wood_00"
const SW : StringName = &"wooden_sword_00"
var passed : int = 0
var failed : int = 0
var _rid : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func give(h : HostLogic, pid : String, id : StringName, n : int) -> void:
	var r : Dictionary = h.invs[pid].add_to_existing_stacks(h.db, id, n)
	h.minted[id] = h.minted.get(id, 0) + r["done"]

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
	h.positions[1] = Vector2(900, 900)   # ไกลบอส ไม่เริ่มสู้
	h.positions[2] = Vector2(900, 950)
	h.tick(0.1)
	return h

func kill(h : HostLogic, pid : String) -> void:
	h.world.actors[pid]["c"].apply_damage(h.world.hp_of(pid), h.combat_now)

func r(op : String, item : StringName, q : int, src : String, dst : String = "") -> Dictionary:
	_rid += 1
	return {"pv": 1, "rid": _rid, "op": op, "item": String(item), "qty": q, "src": src, "dst": dst}

func run_all() -> void:
	test_drop()
	test_respawn()
	test_claim()
	test_merge()
	test_multi()
	test_disconnect()
	test_partial()
	test_fuzz()
	print("Death: Passed ", passed, " / Failed ", failed)

func test_drop() -> void:
	var h : HostLogic = mk()
	give(h, "p_a", S, 150)
	give(h, "p_a", W, 20)
	give(h, "p_a", SW, 1)
	kill(h, "p_a")
	h.tick(1.0)
	var bag : Inventory = h.invs["death_p_a"]
	t("all items in bag", bag.count_of(S) == 150 and bag.count_of(W) == 20 and bag.count_of(SW) == 1)
	t("inventory empty", h.invs["p_a"].count_of(S) == 0 and h.invs["p_a"].count_of(W) == 0 and h.invs["p_a"].count_of(SW) == 0)
	t("conserved", h.conserved())
	t("dead_at set, change queued", h.dead_at.has("p_a") and h.changes.size() == 1)
	var n : int = h.changes.size()
	h.tick(1.1)
	t("no second drop", h.changes.size() == n and bag.count_of(S) == 150)
	var e : Dictionary = mk().on_player_died("p_a", 0.0)
	t("alive player: refused", not e["ok"])
	t("pid prefix reserved", not HostLogic.valid_player_id("death_x") and HostLogic.valid_player_id("deathx"))
	var h2 : HostLogic = mk()
	kill(h2, "p_b")
	h2.tick(1.0)
	t("empty inventory: no bag", not h2.invs.has("death_p_b") and h2.dead_at.has("p_b"))

func test_respawn() -> void:
	var h : HostLogic = mk()
	give(h, "p_a", S, 10)
	kill(h, "p_a")
	h.tick(1.0)
	h.tick(3.9)
	t("not respawned before delay", h.world.actors["p_a"]["c"].state == Combatant.State.DEAD)
	h.tick(4.1)
	var c : Combatant = h.world.actors["p_a"]["c"]
	t("respawned full hp, idle", c.state == Combatant.State.IDLE and c.hp == c.max_hp and h.world.actors["p_a"]["resolved"] == 0)
	t("respawn pos + notice", h.positions[1] == h.arena.entry_point() and h.respawned.size() == 1 and h.respawned[0]["pid"] == "p_a")
	t("bag kept after respawn", h.invs["death_p_a"].count_of(S) == 10 and h.invs["p_a"].count_of(S) == 0)
	h.combat_now = 5.0
	t("can act again", h.host_handle(1, r("attack", &"", 0, "1000,0"))["result"]["ok"])
	kill(h, "p_a")
	h.tick(6.0)
	t("dies again: dead_at again", h.dead_at.has("p_a"))
	var d : Dictionary = h.host_handle(1, r("attack", &"", 0, "1000,0"))
	t("dead cannot attack", d["result"]["reason"] == CombatResult.DEAD)

func test_claim() -> void:
	var h : HostLogic = mk()
	give(h, "p_a", S, 150)
	kill(h, "p_a")
	h.tick(1.0)
	var before_a : Dictionary = h.invs["death_p_a"].to_dict()
	var x : Dictionary = h.host_handle(2, r("transfer", S, 10, "death_p_a", "p_b"))
	t("other player denied", x["net_reason"] == &"denied" and h.invs["death_p_a"].to_dict() == before_a)
	x = h.host_handle(1, r("transfer", S, 10, "p_a", "death_p_a"))
	t("bag not a destination", x["net_reason"] == &"player_transfer_denied")
	x = h.host_handle(1, r("transfer", S, 150, "death_p_a", "p_a"))
	t("owner claims all", x["accepted"] and x["result"]["ok"] and h.invs["p_a"].count_of(S) == 150 and h.invs["death_p_a"].count_of(S) == 0 and h.conserved())
	# กระเป๋าเต็ม: ปฏิเสธ ของไม่หาย
	var f : HostLogic = mk()
	give(f, "p_a", S, 150)
	kill(f, "p_a")
	f.tick(1.0)
	f.invs["p_a"].max_slots = 1
	give(f, "p_a", W, 99)
	var snap : Dictionary = f.invs["death_p_a"].to_dict()
	x = f.host_handle(1, r("transfer", S, 150, "death_p_a", "p_a"))
	t("claim into full inventory refused", x["result"]["reason"] == OpResult.DESTINATION_FULL and f.invs["death_p_a"].to_dict() == snap and f.conserved())

func test_merge() -> void:
	var h : HostLogic = mk()
	give(h, "p_a", S, 50)
	kill(h, "p_a")
	h.tick(1.0)
	h.tick(4.5)
	give(h, "p_a", S, 70)
	give(h, "p_a", W, 5)
	h.combat_now = 5.0
	kill(h, "p_a")
	h.tick(6.0)
	t("second death merges into same bag", h.invs["death_p_a"].count_of(S) == 120 and h.invs["death_p_a"].count_of(W) == 5 and h.conserved())
	var bags : int = 0
	for o in h.invs:
		if String(o).begins_with("death_"):
			bags += 1
	t("only one bag", bags == 1)

func test_multi() -> void:
	var h : HostLogic = mk()
	give(h, "p_a", S, 30)
	give(h, "p_b", S, 40)
	kill(h, "p_a")
	kill(h, "p_b")
	h.tick(1.0)
	t("both bags, conserved", h.invs["death_p_a"].count_of(S) == 30 and h.invs["death_p_b"].count_of(S) == 40 and h.conserved())
	h.tick(4.5)
	t("both respawn", h.world.actors["p_a"]["c"].state == Combatant.State.IDLE and h.world.actors["p_b"]["c"].state == Combatant.State.IDLE and h.respawned.size() == 2)
	t("boss not reset by wipe", h.world.hp_of("boss") == BossData.grove().max_hp)

func test_disconnect() -> void:
	var h : HostLogic = mk()
	give(h, "p_a", S, 25)
	kill(h, "p_a")
	h.tick(1.0)
	h.leave(1)
	h.tick(10.0)
	t("disconnected: stays dead, bag kept", h.world.actors["p_a"]["c"].state == Combatant.State.DEAD and h.invs["death_p_a"].count_of(S) == 25)
	h.join(7, "p_a")
	h.positions[7] = Vector2(900, 900)
	h.tick(10.1)
	t("rejoin: respawns, no second drop", h.world.actors["p_a"]["c"].state == Combatant.State.IDLE and h.invs["death_p_a"].count_of(S) == 25 and h.conserved())
	# ตายแล้วหลุดทันทีก่อน tick: ยังได้ถุง
	var g : HostLogic = mk()
	give(g, "p_a", S, 9)
	kill(g, "p_a")
	g.leave(1)
	g.tick(1.0)
	t("died then left before tick: bag still made", g.invs["death_p_a"].count_of(S) == 9 and g.conserved())

func test_partial() -> void:
	var h : HostLogic = mk()
	h.death_drop = 0.5
	give(h, "p_a", S, 101)
	give(h, "p_a", SW, 1)
	kill(h, "p_a")
	h.tick(1.0)
	t("half dropped (floor)", h.invs["death_p_a"].count_of(S) == 50 and h.invs["p_a"].count_of(S) == 51)
	t("single sword floor 0: kept", h.invs["p_a"].count_of(SW) == 1 and h.invs["death_p_a"].count_of(SW) == 0 and h.conserved())

func test_fuzz() -> void:
	var h : HostLogic = mk()
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 8642
	var now : float = 1.0
	var bad : int = 0
	for i in 600:
		now += rng.randf_range(0.0, 1.5)
		var s : int = rng.randi_range(1, 3)
		var pid : String = "p_%d" % s
		match rng.randi() % 6:
			0:
				if h.invs.has(pid):
					give(h, pid, [S, W, SW][rng.randi() % 3], rng.randi_range(1, 120))
			1:
				if h.world.actors.has(pid) and h.world.hp_of(pid) > 0:
					h.combat_now = maxf(h.combat_now, now)
					kill(h, pid)
			2:
				h.leave(s)
			3:
				h.join(s, pid)
				h.positions[s] = Vector2(900, 900 + s * 40)
			4:
				h.host_handle(s, r("transfer", [S, W, SW][rng.randi() % 3], rng.randi_range(0, 150), "death_" + pid, pid))
			_:
				pass
		h.tick(now)
		if not h.conserved():
			bad += 1
		for o in h.invs:
			for sl in h.invs[o].slots:
				if sl != null and sl.item_data != null and sl.quantity <= 0:
					bad += 1
		h.respawned = []
		h.changes = []
	t("fuzz: conserved, no corrupt slots", bad == 0)
