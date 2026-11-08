extends RefCounted
class_name CombatHostTests

var passed : int = 0
var failed : int = 0
var _rid : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func r(op : String, src : String = "1000,0", item : String = "", qty : int = 0, dst : String = "") -> Dictionary:
	_rid += 1
	return {"pv": 1, "rid": _rid, "op": op, "item": item, "qty": qty, "src": src, "dst": dst}

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
	return h

func snap(h : HostLogic) -> Dictionary:
	var w : Dictionary = {}
	for id in h.world.actors:
		w[id] = h.world.actors[id]["c"].to_dict()
	var inv : Dictionary = {}
	for o in h.invs:
		inv[o] = h.invs[o].to_dict()
	return {"w": w, "flags": h.flags.duplicate(), "inv": inv, "nodes": h.nodes.duplicate(true)}

func run_all() -> void:
	test_basic()
	test_forge()
	test_reward_flow()
	test_fuzz()
	print("CombatHost: Passed ", passed, " / Failed ", failed)

func test_basic() -> void:
	var h : HostLogic = mk()
	t("encounter started", h.world != null and h.world.actors.has("boss"))
	h.combat_now = 1.0
	var a : Dictionary = h.host_handle(1, r("attack"))
	t("attack accepted", a["accepted"] and a["result"]["ok"])
	t("attack during swing: not_idle", h.host_handle(1, r("attack"))["result"]["reason"] == CombatResult.NOT_IDLE)
	t("dodge by other player ok", h.host_handle(2, r("dodge", "0,-1000"))["result"]["ok"])
	t("no encounter: rejected", HostLogic.new().host_handle(1, r("attack")).get("net_reason", &"x") == &"not_joined")
	var h2 : HostLogic = HostLogic.new()
	h2.join(1, "p_a")
	t("no encounter started", h2.host_handle(1, r("attack"))["net_reason"] == &"no_encounter")

func test_forge() -> void:
	var h : HostLogic = mk()
	h.combat_now = 1.0
	var b : Dictionary = snap(h)
	var cases : Array = [
		["damage op", r("damage", "1000,0", "boss", 999)],
		["grant op", r("grant", "grove_guardian_defeated", "forest_heart_00", 1)],
		["flag op", r("set_flag", "grove_guardian_defeated", "", 1)],
		["boss hp via remove", r("remove", "boss", "stone_00", 1, "")],
		["aim zero", r("attack", "0,0")],
		["aim text", r("attack", "x,y")],
		["aim float", r("attack", "1.5,0")],
		["aim huge", r("attack", "99999999999,0")],
		["aim long", r("attack", "1".repeat(30) + ",0")],
	]
	for c in cases:
		var res : Dictionary = h.host_handle(1, c[1])
		t("forge rejected: " + c[0], not res["accepted"])
	t("forge: state unchanged", snap(h) == b)
	var bad_shape : Dictionary = r("attack")
	bad_shape["qty"] = 1.0
	t("qty float rejected", h.host_handle(1, bad_shape)["net_reason"] == &"bad_request" and snap(h) == b)
	var bad_pv : Dictionary = r("attack")
	bad_pv["pv"] = 99
	t("bad protocol", h.host_handle(1, bad_pv)["net_reason"] == &"bad_protocol")
	var dup : Dictionary = r("attack")
	h.host_handle(1, dup)
	var after : Dictionary = snap(h)
	t("dup rid rejected, state same", h.host_handle(1, dup)["net_reason"] == &"duplicate_request" and snap(h) == after)
	t("not joined", h.host_handle(77, r("attack"))["net_reason"] == &"not_joined")
	# client ส่ง hp/ผลมาใน payload เพิ่ม: ถูกเมินหมด
	var extra : Dictionary = r("attack")
	extra["hp"] = 99999
	extra["damage"] = 999
	extra["target"] = "boss"
	extra["now"] = 0.0
	h.combat_now = 2.0
	h.host_handle(2, extra)
	t("extra fields ignored: boss hp untouched", h.world.hp_of("boss") == BossData.grove().max_hp)
	# เวลาย้อน: host เป็นเจ้าของเวลา client ย้อนไม่ได้
	h.combat_now = 2.0
	h.tick(0.1)
	t("tick with older time never rewinds combat_now", h.combat_now == 2.0)
	h.tick(3.0)
	t("tick advances combat_now", h.combat_now == 3.0)

func test_reward_flow() -> void:
	var h : HostLogic = mk()
	h.world.actors["boss"]["c"].apply_damage(BossData.grove().max_hp, 0.0)
	h.tick(1.0)
	t("boss dead -> reward once", h.flags.get("grove_guardian_defeated", false) and h.invs["p_a"].count_of(&"forest_heart_00") == 1 and h.invs["p_b"].count_of(&"forest_heart_00") == 1)
	var b : Dictionary = snap(h)
	b.erase("w")
	for i in 5:
		h.tick(2.0 + i)
	var a2 : Dictionary = snap(h)
	a2.erase("w")
	t("repeat ticks: no second reward", a2 == b and h.conserved() and h.minted[&"forest_heart_00"] == 2)
	# reconnect: ไม่ได้ซ้ำ
	h.leave(1)
	h.join(9, "p_a")
	h.tick(10.0)
	t("reconnect: no regrant", h.invs["p_a"].count_of(&"forest_heart_00") == 1 and h.conserved())
	# client ขอ "attack" หลังบอสตายไม่ทำให้รางวัลซ้ำ
	h.host_handle(9, r("attack"))
	h.tick(11.0)
	t("attack after win: still once", h.minted[&"forest_heart_00"] == 2)

func test_fuzz() -> void:
	var h : HostLogic = mk()
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1357
	var now : float = 0.0
	var bad : int = 0
	var ops : Array = ["attack", "dodge", "damage", "grant", "bogus"]
	for i in 600:
		now += rng.randf_range(0.0, 0.2)
		h.combat_now = maxf(h.combat_now, now)
		var s : int = rng.randi_range(1, 3)
		if rng.randi() % 4 == 0:
			h.positions[s] = Vector2(rng.randf_range(-250, 250), rng.randf_range(-250, 250))
		var src : String = "%d,%d" % [rng.randi_range(-1000, 1000), rng.randi_range(-1000, 1000)] if rng.randi() % 5 != 0 else "junk"
		var before_boss : int = h.world.hp_of("boss")
		var res : Dictionary = h.host_handle(s, r(ops[rng.randi() % ops.size()], src))
		if res["accepted"] and res["result"] != null and res["result"]["reason"] == CombatResult.INTERNAL:
			bad += 1
		if h.world.hp_of("boss") != before_boss:   # บอสเสีย HP ได้จาก tick เท่านั้น ไม่ใช่จากคำขอ
			bad += 1
		h.tick(now)
		if rng.randi() % 50 == 0 and h.world.hp_of("boss") > 0:
			h.world.actors["boss"]["c"].apply_damage(h.world.hp_of("boss"), h.combat_now)
		if not h.conserved():
			bad += 1
		if h.minted.get(&"forest_heart_00", 0) > 2:
			bad += 1
	t("fuzz: requests never hurt boss, conserved, reward bounded", bad == 0)
