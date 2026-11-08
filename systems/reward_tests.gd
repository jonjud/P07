extends RefCounted
class_name RewardTests

const F : String = "grove_guardian_defeated"
const H : StringName = &"forest_heart_00"
var passed : int = 0
var failed : int = 0
var _rid : int = 0

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
	return h

func r(op : String, item : StringName, q : int, src : String, dst : String = "") -> Dictionary:
	_rid += 1
	return {"pv": 1, "rid": _rid, "op": op, "item": String(item), "qty": q, "src": src, "dst": dst}

func snap(h : HostLogic) -> Dictionary:
	var d : Dictionary = {}
	for o in h.invs:
		d[o] = h.invs[o].to_dict()
	return {"inv": d, "flags": h.flags.duplicate(), "nodes": h.nodes.duplicate(true), "minted": h.minted.duplicate()}

func run_all() -> void:
	t("reward item in db", mk().db.has_item(H))
	test_once()
	test_bag()
	test_guards()
	test_reconnect()
	test_claim_rules()
	test_flags()
	test_bonus()
	test_fuzz()
	print("Reward: Passed ", passed, " / Failed ", failed)

func test_once() -> void:
	var h : HostLogic = mk()
	h.join(1, "p_a")
	h.join(2, "p_b")
	var g : Dictionary = h.grant_boss_reward(F, H, 1)
	t("grant ok both inventory", g["ok"] and g["given"]["p_a"] == &"inventory" and g["given"]["p_b"] == &"inventory")
	t("each got 1", h.invs["p_a"].count_of(H) == 1 and h.invs["p_b"].count_of(H) == 1)
	t("flag set, conserved", h.flags[F] and h.conserved() and h.minted[H] == 2)
	var before : Dictionary = snap(h)
	var g2 : Dictionary = h.grant_boss_reward(F, H, 1)
	t("second grant rejected, state same", not g2["ok"] and g2["reason"] == &"already_granted" and snap(h) == before)
	t("different flag gives again (separate boss)", h.grant_boss_reward("other_boss", H, 1)["ok"] and h.conserved())

func test_bag() -> void:
	var h : HostLogic = mk()
	h.join(1, "p_a")
	h.join(2, "p_b")
	h.invs["p_b"].max_slots = 1
	h.invs["p_b"].add_to_existing_stacks(h.db, &"stone_00", 99)
	h.minted[&"stone_00"] = 99
	var g : Dictionary = h.grant_boss_reward(F, H, 1)
	t("full inventory -> bag", g["ok"] and g["given"]["p_a"] == &"inventory" and g["given"]["p_b"] == &"bag")
	t("bag holds it, inventory untouched", h.invs["reward_p_b"].count_of(H) == 1 and h.invs["p_b"].count_of(H) == 0 and h.invs["p_b"].count_of(&"stone_00") == 99)
	t("bag conserved", h.conserved())
	# เคลียร์ช่องแล้วรับจากถุง
	t("claim denied while full", h.host_handle(2, r("transfer", H, 1, "reward_p_b", "p_b"))["result"]["reason"] == OpResult.DESTINATION_FULL and h.invs["reward_p_b"].count_of(H) == 1)
	h.invs["p_b"].remove_item(h.db, &"stone_00", 99)
	h.minted[&"stone_00"] = 0
	var c : Dictionary = h.host_handle(2, r("transfer", H, 1, "reward_p_b", "p_b"))
	t("claim ok after space", c["accepted"] and c["result"]["ok"] and h.invs["p_b"].count_of(H) == 1 and h.invs["reward_p_b"].count_of(H) == 0 and h.conserved())

func test_guards() -> void:
	var h : HostLogic = mk()
	var b : Dictionary = snap(h)
	t("no recipients", h.grant_boss_reward(F, H, 1)["reason"] == &"no_recipients" and not h.flags.has(F) and snap(h) == b)
	h.join(1, "p_a")
	b = snap(h)
	t("unknown item", h.grant_boss_reward(F, &"nope", 1)["reason"] == &"unknown_item" and snap(h) == b)
	t("qty 0", h.grant_boss_reward(F, H, 0)["reason"] == &"bad_request" and snap(h) == b)
	t("empty flag", h.grant_boss_reward("", H, 1)["reason"] == &"bad_request" and snap(h) == b)
	t("flag unset after failures", not h.flags.has(F))
	t("then works", h.grant_boss_reward(F, H, 1)["ok"])

func test_reconnect() -> void:
	var h : HostLogic = mk()
	h.join(1, "p_a")
	h.invs["p_a"].max_slots = 1
	h.invs["p_a"].add_to_existing_stacks(h.db, &"stone_00", 99)
	h.minted[&"stone_00"] = 99
	h.grant_boss_reward(F, H, 1)
	h.leave(1)
	t("leave keeps bag", h.invs["reward_p_a"].count_of(H) == 1)
	h.join(7, "p_a")
	t("reconnect keeps bag, no regrant", h.invs["reward_p_a"].count_of(H) == 1 and not h.grant_boss_reward(F, H, 1)["ok"] and h.conserved())
	h.join(8, "p_late")
	t("late joiner gets nothing", h.invs["p_late"].count_of(H) == 0 and not h.invs.has("reward_p_late"))

func test_claim_rules() -> void:
	var h : HostLogic = mk()
	h.join(1, "p_a")
	h.join(2, "p_b")
	h.invs["p_a"].max_slots = 1
	h.invs["p_a"].add_to_existing_stacks(h.db, &"stone_00", 99)
	h.minted[&"stone_00"] = 99
	h.grant_boss_reward(F, H, 1)
	var b : Dictionary = snap(h)
	var x : Dictionary = h.host_handle(2, r("transfer", H, 1, "reward_p_a", "p_b"))
	t("other player cannot open my bag", x["net_reason"] == &"denied" and snap(h) == b)
	x = h.host_handle(2, r("transfer", H, 1, "p_b", "reward_p_a"))
	t("bag cannot be a destination", x["net_reason"] == &"player_transfer_denied" and snap(h) == b)
	x = h.host_handle(2, r("remove", H, 1, "reward_p_a"))
	t("remove from bag denied", x["net_reason"] == &"denied" and snap(h) == b)
	x = h.host_handle(1, r("transfer", H, 1, "reward_p_a", "shared_01"))
	t("bag -> shared denied (must be own)", x["net_reason"] == &"denied" and snap(h) == b)
	for bad in ["reward_x", "reward_", "reward_p_a"]:
		t("pid '%s' rejected" % bad, not HostLogic.valid_player_id(bad))
	t("normal pid still ok", HostLogic.valid_player_id("p_a") and HostLogic.valid_player_id("rewardx"))

func test_flags() -> void:
	var h : HostLogic = mk()
	h.join(1, "p_a")
	h.grant_boss_reward(F, H, 1)
	var d : Dictionary = h.flags_to_dict()
	var x : Dictionary = HostLogic.flags_from_dict(d)
	t("flags round-trip", x["ok"] and x["flags"] == h.flags)
	var bad : Dictionary = d.duplicate(true)
	bad["flags"]["x"] = 1
	t("flag value type", HostLogic.flags_from_dict(bad)["reason"] == &"bad_data")
	bad = d.duplicate(true)
	bad["schema_version"] = 9
	t("flags schema", HostLogic.flags_from_dict(bad)["reason"] == &"bad_schema")
	bad = d.duplicate(true)
	bad.erase("flags")
	t("flags missing", HostLogic.flags_from_dict(bad)["reason"] == &"incomplete_data")
	bad = d.duplicate(true)
	bad["flags"] = "x"
	t("flags type", HostLogic.flags_from_dict(bad)["reason"] == &"bad_data")
	t("empty flag key rejected", HostLogic.flags_from_dict({"schema_version": 1, "flags": {"": true}})["reason"] == &"bad_data")

func test_bonus() -> void:
	var h : HostLogic = mk()
	h.join(1, "p_a")
	var bonus : Dictionary = {"id": "grove_bloom", "item": &"fiber_00", "amount": 30, "pos": Vector2(100, 100)}
	t("bad bonus: nothing happens", h.grant_boss_reward(F, H, 1, {"id": "x", "amount": 0, "item": &"fiber_00"})["reason"] == &"bad_request" and not h.flags.has(F) and h.invs["p_a"].count_of(H) == 0)
	t("bonus ok", h.grant_boss_reward(F, H, 1, bonus)["ok"] and h.nodes.has("grove_bloom") and h.conserved())
	h.grant_boss_reward(F, H, 1, bonus)
	t("bonus not duplicated", h.nodes["grove_bloom"]["amount"] == 30 and h.minted[&"fiber_00"] == 30)

func test_fuzz() -> void:
	var h : HostLogic = mk()
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2468
	var granted : Dictionary = {}
	var bad : int = 0
	for i in 400:
		var k : int = rng.randi() % 5
		var s : int = rng.randi_range(1, 3)
		var pid : String = "p_%d" % s
		if k == 0:
			h.join(s, pid)
		elif k == 1:
			h.leave(s)
		elif k == 2:
			var f : String = "boss_%d" % rng.randi_range(0, 3)
			var res : Dictionary = h.grant_boss_reward(f, H, 1)
			if res["ok"]:
				if granted.has(f):
					bad += 1   # ให้ซ้ำ
				granted[f] = true
		elif k == 3:
			h.host_handle(s, r("transfer", H, 1, "reward_" + pid, pid))
		else:
			h.invs[pid].add_to_existing_stacks(h.db, &"stone_00", 0) if h.invs.has(pid) else null
		if not h.conserved():
			bad += 1
		for f in granted:
			if not h.flags.get(f, false):
				bad += 1
	t("fuzz: never regrant, always conserved", bad == 0)
	t("fuzz: exercised", granted.size() >= 2)
