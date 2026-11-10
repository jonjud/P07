extends RefCounted
class_name HostLogic

const PROTOCOL_VERSION : int = 1
const SHARED_ID : String = "shared_01"
const MAX_PLAYERS : int = 2
const GATHER_RANGE : float = 80.0
const CHEST_RANGE : float = 96.0
const CELL_LIMIT : int = 100000
const REWARD_PREFIX : String = "reward_"
const DEATH_PREFIX : String = "death_"
const MAX_OP_QTY : int = 99
var db : ItemDatabase
var invs : Dictionary = {}       # owner_id -> Inventory (ผู้เล่น + shared)
var peers : Dictionary = {}      # sender -> player_id (D-23)
var nodes : Dictionary = {}      # node_id -> {item, amount, pos?}
var positions : Dictionary = {}  # sender -> Vector2 (PlayerSync เขียน)
var grid : BuildGrid = BuildGrid.new()   # โครงสร้าง + chest (host ถือของจริง)
var starter : Dictionary = {}    # test-only: ของเริ่มต้นของ inventory ใหม่
var minted : Dictionary = {}     # item -> จำนวนสุทธิที่ host สร้าง (ไว้ตรวจ conservation)
var flags : Dictionary = {}      # world flag: String -> bool (serialize ได้ ไม่อ้าง node)
var world : CombatWorld = null
var boss : BossBrain = null
var arena : ArenaData = null
var combat_now : float = 0.0
var boss_id : String = "boss"
var rewarded : Array = []   # ผลของ grant ล่าสุด (ให้ NetSession ส่งต่อใน P07-17)
var dead_at : Dictionary = {}        # pid -> เวลาตาย (ถุงสร้างแล้ว รอเกิดใหม่)
var respawn_delay : float = 3.0
var death_drop : float = 1.0         # สัดส่วนที่ทิ้งเข้าถุง (ตั้งได้)
var respawned : Array = []           # [{pid, sender, pos}] ให้ NetSession ส่งต่อ
var changes : Array = []             # changed dict ที่ NetSession ต้องส่งให้ client
var allow_client_add : bool = false
var rdb : RecipeDatabase                 # สูตร (host ถือ)
var rng : RandomNumberGenerator = null   # ฉีดได้เพื่อเทสต์ซ้ำ (null = สุ่มใหม่ทุกครั้ง)
var bound_fail : int = 0                 # salvage ได้ของนอกช่วง core..max (ต้องเป็น 0)
var _seen : Dictionary = {}


func _err(rid : int, why : StringName) -> Dictionary:
	return {"rid": rid, "accepted": false, "net_reason": why, "result": null, "changed": {}}

func _shape_ok(r : Dictionary) -> bool:
	for k in ["op", "item", "src", "dst"]:
		if typeof(r.get(k)) != TYPE_STRING:
			return false
	return typeof(r.get("qty")) == TYPE_INT

static func valid_player_id(pid : Variant) -> bool:
	if typeof(pid) != TYPE_STRING:
		return false
	var s : String = pid
	if s == SHARED_ID or s.begins_with("chest_") or s.begins_with(REWARD_PREFIX) or s.begins_with(DEATH_PREFIX):
		return false
	var re : RegEx = RegEx.new()
	re.compile("^[a-z0-9_]{1,40}$")
	return re.search(s) != null

# "x,y" -> Vector2i หรือ null (ไม่เพิ่มรูปแบบ envelope: cell อยู่ใน src)
static func parse_cell(s : String) -> Variant:
	if s.length() > 24:
		return null
	var p : PackedStringArray = s.split(",")
	if p.size() != 2 or not p[0].is_valid_int() or not p[1].is_valid_int():
		return null
	var x : int = int(p[0])
	var y : int = int(p[1])
	if absi(x) > CELL_LIMIT or absi(y) > CELL_LIMIT:
		return null
	return Vector2i(x, y)

static func piece_center(p : BuildingPieceData, cell : Vector2i, rot : int) -> Vector2:
	return BuildConst.cell_to_world(cell) + Vector2(BuildGrid.footprint(p, rot) * BuildConst.CELL_SIZE) / 2.0

func _join_res(ok : bool, reason : StringName, pid : String = "") -> Dictionary:
	return {"ok": ok, "reason": reason, "player_id": pid}

func join(sender : int, pid : Variant) -> Dictionary:
	if not valid_player_id(pid):
		return _join_res(false, &"bad_player_id")
	var p : String = pid
	if peers.has(sender):
		return _join_res(false, &"already_joined")
	if peers.values().has(p):
		return _join_res(false, &"player_already_connected")
	if peers.size() >= MAX_PLAYERS:
		return _join_res(false, &"host_full")
	if not invs.has(p):
		var inv : Inventory = Inventory.new()
		inv.owner_id = p
		invs[p] = inv
		for it in starter:   # ให้เฉพาะ inventory ใหม่ reconnect ไม่ได้ซ้ำ
			var r : Dictionary = inv.add_to_existing_stacks(db, it, starter[it])
			minted[it] = minted.get(it, 0) + r["done"]
	if world != null and world.actors.has(p):
		world.set_parked(p, false)
	peers[sender] = p
	return _join_res(true, &"ok", p)

func add_node(node_id : String, item : StringName, amount : int, pos : Variant = null) -> bool:
	if node_id == "" or amount <= 0 or db == null or db.get_item(item) == null or nodes.has(node_id):
		return false
	nodes[node_id] = {"item": item, "amount": amount}
	if typeof(pos) == TYPE_VECTOR2:
		nodes[node_id]["pos"] = pos
	minted[item] = minted.get(item, 0) + amount
	return true

func leave(sender : int) -> void:
	var pid : String = peers.get(sender, "")
	if world != null and pid != "" and world.actors.has(pid):
		world.set_parked(pid, true)
	peers.erase(sender)
	positions.erase(sender)
	_seen.erase(sender)

func total_of(it : StringName) -> int:
	var t : int = grid.count_placed(it) + grid.count_in_chests(it)
	for o in invs:
		t += invs[o].count_of(it)
	for k in nodes:
		if nodes[k]["item"] == it:
			t += nodes[k]["amount"]
	return t

func conserved() -> bool:
	for it in minted:
		if total_of(it) != minted[it]:
			return false
	return true

func _get_for(sender : int, owner : String) -> Inventory:
	if owner == SHARED_ID or owner == peers.get(sender, ""):
		return invs.get(owner)
	return null

func _xfer_inv(sender : int, owner : String) -> Inventory:
	var i : Inventory = _get_for(sender, owner)
	if i != null:
		return i
	if peers.has(sender) and (owner == reward_bag_id(peers[sender]) or owner == death_bag_id(peers[sender])):
		return invs.get(owner)
	return grid.chest(owner)

func _chest_pos(sid : String) -> Variant:
	if not sid.begins_with("chest_") or not sid.substr(6).is_valid_int():
		return null
	var s : Dictionary = grid.get_struct(int(sid.substr(6)))
	if s.is_empty():
		return null
	var p : BuildingPieceData = db.get_item(StringName(s["piece"])) as BuildingPieceData
	return piece_center(p, s["cell"], s["rot"]) if p != null else null

func _near(sender : int, pos : Variant, rng : float) -> bool:
	var pp : Variant = positions.get(sender)
	return typeof(pp) == TYPE_VECTOR2 and typeof(pos) == TYPE_VECTOR2 and (pp as Vector2).distance_to(pos) <= rng

# สถานีที่ผู้ขอใช้ได้: คำนวณฝั่ง host จากตำแหน่งที่ host เชื่อ + grid
func _stations_for(sender : int) -> Array:
	var pp : Variant = positions.get(sender)
	if typeof(pp) != TYPE_VECTOR2:
		return [&"hand"]
	return StationFinder.available(db, grid, pp)

func host_handle(sender : int, req : Dictionary) -> Dictionary:
	var rid = req.get("rid")
	if typeof(rid) != TYPE_INT or rid < 0 or not _shape_ok(req):
		return _err(-1, &"bad_request")
	if typeof(req.get("pv")) != TYPE_INT or req["pv"] != PROTOCOL_VERSION:
		return _err(rid, &"bad_protocol")
	if not peers.has(sender):
		return _err(rid, &"not_joined")
	var seen : Dictionary = _seen.get_or_add(sender, {})
	if seen.has(rid):
		return _err(rid, &"duplicate_request")
	seen[rid] = true
	var me : String = peers[sender]
	var id : StringName = StringName(req["item"])
	var q : int = req["qty"]
	var res : Dictionary
	var touched : Array = []
	match req["op"]:
		"add":    # D-24: production ปิด host ให้ของเองจากการเก็บ
			if not allow_client_add:
				return _err(rid, &"add_disabled")
			var inv : Inventory = _get_for(sender, req["dst"])
			if inv == null: return _err(rid, &"denied")
			res = inv.add_to_existing_stacks(db, id, q)
			if res["done"] > 0: minted[id] = minted.get(id, 0) + res["done"]
			touched = [req["dst"]]
		"remove":
			var inv : Inventory = _get_for(sender, req["src"])
			if inv == null: return _err(rid, &"denied")
			res = inv.remove_item(db, id, q)
			if res["done"] > 0: minted[id] = minted.get(id, 0) - res["done"]
			touched = [req["src"]]
		"transfer":    # D-22: ต้องมีฝั่งเป็นตัวเอง; ปลายทาง/ต้นทางเป็น shared หรือ chest ได้
			var src : String = req["src"]
			var dst : String = req["dst"]
			var a : Inventory = _xfer_inv(sender, src)
			if a == null: return _err(rid, &"denied")
			if dst != SHARED_ID and dst != me and invs.has(dst):
				return _err(rid, &"player_transfer_denied")
			var b : Inventory = _xfer_inv(sender, dst)
			if b == null or (src != me and dst != me): return _err(rid, &"denied")
			for o in [src, dst]:
				if grid.chest(o) != null and not _near(sender, _chest_pos(o), CHEST_RANGE):
					return _err(rid, &"too_far")
			res = a.transfer_to(b, db, id, q)
			touched = [src, dst]
		"gather":    # D-24: host ให้ของเอง ไม่เชื่อ item/qty จาก client
			var n : Dictionary = nodes.get(req["src"], {})
			if n.is_empty(): return _err(rid, &"no_node")
			if n.has("pos") and not _near(sender, n["pos"], GATHER_RANGE):
				return _err(rid, &"too_far")
			res = invs[me].add_to_existing_stacks(db, n["item"], n["amount"])
			if res["done"] > 0:
				n["amount"] -= res["done"]
				if n["amount"] <= 0: nodes.erase(req["src"])
			touched = [me]
		"place":    # item=ชิ้น, qty=rot, src="x,y"
			var c : Variant = parse_cell(req["src"])
			if c == null: return _err(rid, &"bad_request")
			res = grid.place(db, invs[me], id, c, q)
			touched = [me]
		"demolish":    # src="x,y" ทุกคนรื้อได้ (D-25) ของคืนผู้รื้อ
			var c : Variant = parse_cell(req["src"])
			if c == null: return _err(rid, &"bad_request")
			res = grid.remove_at(db, invs[me], c)
			touched = [me]
		"craft":    # item=recipe_id, qty=จำนวนครั้ง; สถานีคำนวณฝั่ง host
			if rdb == null: return _err(rid, &"no_recipes")
			if q > MAX_OP_QTY: return _err(rid, &"bad_request")
			var recipe : CraftingRecipe = rdb.get_recipe(id)
			res = Crafter.craft(db, invs[me], recipe, _stations_for(sender), q)
			if res["done"] > 0:
				for i in recipe.inputs:
					minted[i.item_id] = minted.get(i.item_id, 0) - i.quantity * q
				for o in recipe.outputs:
					minted[o.item_id] = minted.get(o.item_id, 0) + o.quantity * q
			touched = [me]
		"salvage":    # item=item_id, qty=จำนวนชิ้น
			if q > MAX_OP_QTY: return _err(rid, &"bad_request")
			var it : ItemData = db.get_item(id)
			var gids : Dictionary = {}
			var before : Dictionary = {}
			if it != null:
				for e in it.salvage_yield:
					if e != null:
						gids[e.item_id] = true
			for g in gids:
				before[g] = invs[me].count_of(g)
			res = Salvager.salvage(db, invs[me], id, _stations_for(sender), q, rng)
			if res["done"] > 0:
				minted[id] = minted.get(id, 0) - q
				for g in gids:
					var gain : int = invs[me].count_of(g) - before[g] + (q if g == id else 0)
					var lo : int = 0
					var hi : int = 0
					for e in it.salvage_yield:
						if e != null and e.item_id == g:
							hi += e.max_quantity * q
							if not e.is_bonus:
								lo += e.min_quantity * q
					if gain < lo or gain > hi:
						bound_fail += 1
						push_error("P-10: salvage gain นอกช่วง %s %d (%d..%d)" % [String(g), gain, lo, hi])
					minted[g] = minted.get(g, 0) + gain
			touched = [me]
		"attack", "dodge":
			return combat_handle(sender, rid, req["op"], req["src"])
		_:
			return _err(rid, &"bad_op")
	if res["reason"] == OpResult.INTERNAL:
		push_error("P-05: INTERNAL ถือเป็นบั๊ก หยุดและรายงาน")
	var changed : Dictionary = {}
	if res["done"] > 0:
		for o in touched:
			if invs.has(o):    # chest อยู่ใน grid ส่งผ่าน grid ทั้งก้อน
				changed[o] = invs[o].to_dict()
	return {"rid": rid, "accepted": true, "net_reason": &"", "result": res, "changed": changed}

static func reward_bag_id(pid : String) -> String:
	return REWARD_PREFIX + pid

func _gfail(why : StringName) -> Dictionary:
	return {"ok": false, "reason": why, "given": {}, "changed": {}}

# จุดเดียวที่ให้รางวัลบอส: ตรวจครบก่อนเขียน ให้ครั้งเดียวต่อ flag
# bonus (ไม่บังคับ): {id:String, item:StringName, amount:int, pos:Vector2} node ที่ปรากฏเป็นผลต่อโลก
func grant_boss_reward(flag : String, item : StringName, qty : int = 1, bonus : Dictionary = {}) -> Dictionary:
	if flag == "" or db == null or qty <= 0:
		return _gfail(&"bad_request")
	var it : ItemData = db.get_item(item)
	if it == null:
		return _gfail(&"unknown_item")
	if it.max_stack < 1:
		return _gfail(&"bad_request")
	if flags.get(flag, false):
		return _gfail(&"already_granted")
	var pids : Array = peers.values()
	pids.sort()
	if pids.is_empty():
		return _gfail(&"no_recipients")
	if not bonus.is_empty():
		if typeof(bonus.get("id")) != TYPE_STRING or typeof(bonus.get("amount")) != TYPE_INT or bonus["amount"] <= 0:
			return _gfail(&"bad_request")
		if bonus["id"] == "" or nodes.has(bonus["id"]) or db.get_item(StringName(bonus["item"])) == null:
			return _gfail(&"bad_request")
	for pid in pids:
		if not invs.has(pid):
			return _gfail(&"bad_request")
	flags[flag] = true   # ตั้งก่อนเขียน: ต่อให้พลาดกลางทางก็ไม่ให้ซ้ำ
	var given : Dictionary = {}
	var changed : Dictionary = {}
	for pid in pids:
		var target : Inventory = invs[pid]
		var where : StringName = &"inventory"
		if target.free_space_for(it) < qty:
			var bid : String = reward_bag_id(pid)
			var bag : Inventory = invs.get(bid)
			if bag == null:
				bag = Inventory.new()
				bag.owner_id = bid
				bag.max_slots = 1
				invs[bid] = bag
			while bag.free_space_for(it) < qty:
				bag.max_slots += 1
			target = bag
			where = &"bag"
		var r : Dictionary = target.add_to_existing_stacks(db, item, qty)
		minted[item] = minted.get(item, 0) + r["done"]
		if r["done"] != qty:
			push_error("P-07: grant_boss_reward add ไม่ครบ ถือเป็นบั๊ก")
		given[pid] = where
		changed[target.owner_id] = target.to_dict()
	if not bonus.is_empty():
		add_node(bonus["id"], StringName(bonus["item"]), bonus["amount"], bonus.get("pos"))
	return {"ok": true, "reason": &"ok", "given": given, "changed": changed}

func flags_to_dict() -> Dictionary:
	return {"schema_version": 1, "flags": flags.duplicate()}

static func flags_from_dict(d : Dictionary) -> Dictionary:
	if not d.has("schema_version") or not d.has("flags"):
		return {"ok": false, "flags": {}, "reason": &"incomplete_data"}
	if d["schema_version"] != 1:
		return {"ok": false, "flags": {}, "reason": &"bad_schema"}
	if typeof(d["flags"]) != TYPE_DICTIONARY:
		return {"ok": false, "flags": {}, "reason": &"bad_data"}
	var out : Dictionary = {}
	for k in d["flags"]:
		if typeof(k) != TYPE_STRING or k == "" or typeof(d["flags"][k]) != TYPE_BOOL:
			return {"ok": false, "flags": {}, "reason": &"bad_data"}
		out[k] = d["flags"][k]
	return {"ok": true, "flags": out, "reason": &"ok"}

func start_encounter(bdata : BossData, ar : ArenaData, params : CombatParams) -> bool:
	if BossData.validate(bdata) != BossData.OK or ar == null or params == null:
		return false
	world = CombatWorld.new(params)
	arena = ar
	world.add_actor(boss_id, bdata.max_hp, ar.boss_pos, bdata.radius, 1)
	boss = BossBrain.new(boss_id, bdata)
	return true

static func parse_aim(s : String) -> Variant:
	if s.length() > 24:
		return null
	var p : PackedStringArray = s.split(",")
	if p.size() != 2 or not p[0].is_valid_int() or not p[1].is_valid_int():
		return null
	var x : int = int(p[0])
	var y : int = int(p[1])
	if absi(x) > 100000 or absi(y) > 100000 or (x == 0 and y == 0):
		return null
	return Vector2(x, y) / 1000.0

func _sync_actor(sender : int) -> String:
	var pid : String = peers[sender]
	var pos : Variant = positions.get(sender)
	if not world.actors.has(pid):
		var w : WeaponData = WeaponData.new()
		w.id = &"starter_sword"
		world.add_actor(pid, 100, pos if typeof(pos) == TYPE_VECTOR2 else arena.entry_point(), 12.0, 0, w)
	elif typeof(pos) == TYPE_VECTOR2:
		world.set_pos(pid, pos)
	return pid

func combat_handle(sender : int, rid : int, op : String, src : String) -> Dictionary:
	if world == null:
		return _err(rid, &"no_encounter")
	var aim : Variant = parse_aim(src)
	if aim == null:
		return _err(rid, &"bad_request")
	var pid : String = _sync_actor(sender)
	var res : Dictionary
	if op == "attack":
		res = world.attack(pid, combat_now, aim)
	else:
		res = world.actors[pid]["c"].start_dodge(combat_now, aim)
	return {"rid": rid, "accepted": true, "net_reason": &"", "result": res, "changed": {}}

# host เรียกทุก tick; คืน events; ให้รางวัลเมื่อบอสตาย (ครั้งเดียวด้วย flag)
func tick(now : float) -> Array:
	if world == null:
		return []
	combat_now = maxf(combat_now, now)
	for s in peers:
		_sync_actor(s)
	if not boss.engaged:
		for s in peers:
			if world.actors[peers[s]]["pos"].distance_to(arena.boss_pos) < arena.radius - 40.0:
				boss.engaged = true
	var ev : Array = boss.step(combat_now, world, arena.pillars())
	ev.append_array(world.resolve_swings(combat_now))
	if EncounterState.result(world, boss_id) == EncounterState.R.WON and not flags.get("grove_guardian_defeated", false):
		var g : Dictionary = grant_boss_reward("grove_guardian_defeated", &"forest_heart_00", 1)
		if g["ok"]:
			rewarded = [g]
	_death_pass(combat_now)
	return ev

static func death_bag_id(pid : String) -> String:
	return DEATH_PREFIX + pid

func on_player_died(pid : String, now : float) -> Dictionary:
	var fail : Dictionary = {"ok": false, "reason": &"bad_request", "changed": {}}
	if world == null or not world.actors.has(pid) or not invs.has(pid) or dead_at.has(pid):
		return fail
	if world.actors[pid]["c"].state != Combatant.State.DEAD:
		return fail
	var inv : Inventory = invs[pid]
	var counts : Dictionary = {}
	for s in inv.slots:
		if s != null and s.item_data != null and s.quantity > 0:
			var k : String = String(s.item_data.id)
			counts[k] = counts.get(k, 0) + s.quantity
	var ids : Array = counts.keys()
	ids.sort()
	var bid : String = death_bag_id(pid)
	var bag : Inventory = invs.get(bid)
	for k in ids:
		var id : StringName = StringName(k)
		var it : ItemData = db.get_item(id)
		var n : int = mini(counts[k], int(floor(counts[k] * death_drop + 0.0001)))
		if it == null or n <= 0:
			continue
		if bag == null:
			bag = Inventory.new()
			bag.owner_id = bid
			bag.max_slots = 1
			invs[bid] = bag
		while bag.free_space_for(it) < n:
			bag.max_slots += 1
		var r : Dictionary = inv.transfer_to(bag, db, id, n)
		if r["done"] != n:
			push_error("P-07: on_player_died transfer ไม่ครบ ถือเป็นบั๊ก")
	dead_at[pid] = now
	var changed : Dictionary = {pid: inv.to_dict()}
	if bag != null:
		changed[bid] = bag.to_dict()
	changes.append(changed)
	return {"ok": true, "reason": &"ok", "changed": changed}

func respawn(pid : String, sender : int) -> bool:
	if world == null or not dead_at.has(pid) or not world.actors.has(pid):
		return false
	var a : Dictionary = world.actors[pid]
	if a["c"].state != Combatant.State.DEAD:
		dead_at.erase(pid)
		return false
	var old : Combatant = a["c"]
	a["c"] = Combatant.new(old.p, old.max_hp)
	a["resolved"] = 0   # swing_id ของ Combatant ใหม่เริ่มที่ 0
	a["pos"] = arena.entry_point()
	positions[sender] = arena.entry_point()
	dead_at.erase(pid)
	respawned.append({"pid": pid, "sender": sender, "pos": arena.entry_point()})
	return true

func _death_pass(now : float) -> void:
	var fresh : Array = []
	for id in world.actors:
		var a : Dictionary = world.actors[id]
		if id != boss_id and a["team"] == 0 and a["c"].state == Combatant.State.DEAD and not dead_at.has(id):
			fresh.append(id)
	fresh.sort()
	for pid in fresh:
		on_player_died(pid, now)
	var connected : Dictionary = {}
	for s in peers:
		connected[peers[s]] = s
	var due : Array = dead_at.keys()
	due.sort()
	for pid in due:
		if connected.has(pid) and now >= dead_at[pid] + respawn_delay:
			respawn(pid, connected[pid])
