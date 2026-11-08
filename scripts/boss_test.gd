extends Node2D
# WASD เดิน | เมาส์เล็ง | คลิกซ้ายฟัน | Space dodge | R เริ่มใหม่ | 1/2/3 ตัวเลือก feel
const PLAYER_SPEED : float = 220.0
const DODGE_DIST : float = 96.0
const P : String = "p1"
const B : String = "boss"
const WARN : Color = Color(1.0, 0.35, 0.1)

var world : CombatWorld
var params : CombatParams
var arena : ArenaData
var bdata : BossData
var brain : BossBrain
var sword : WeaponData
var feel_s : FeelSettings = FeelSettings.new()
var feel : FeelState
var hud : Label
var _t0 : int = 0
var _dodge_dir : Vector2 = Vector2.ZERO
var _kb : Dictionary = {}
var _msg : String = ""
var _msg_until : float = 0.0
var _origin : Vector2 = Vector2(480, 330)   # จุดกึ่งกลาง arena บนจอ

func _now() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0

func _ready() -> void:
	_ensure_actions()
	params = load("res://data/combat/player_params.tres") as CombatParams
	arena = ArenaData.new()
	arena.id = &"grove"
	bdata = BossData.grove()
	if params == null or BossData.validate(bdata) != BossData.OK:
		push_error("โหลด data บอสไม่ได้")
		return
	sword = WeaponData.new()
	sword.id = &"test_sword"
	feel_s.load_file()
	var layer : CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(10, 10)
	layer.add_child(hud)
	_start()

func _start() -> void:
	_t0 = Time.get_ticks_msec()
	world = CombatWorld.new(params)
	world.add_actor(B, bdata.max_hp, arena.boss_pos, bdata.radius, 1)
	world.add_actor(P, 100, arena.entry_point(), 12.0, 0, sword)
	brain = BossBrain.new(B, bdata)
	feel = FeelState.new(feel_s)
	_kb.clear()

func _ensure_actions() -> void:
	var keys : Dictionary = {"move_left": KEY_A, "move_right": KEY_D, "move_up": KEY_W, "move_down": KEY_S}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev : InputEventKey = InputEventKey.new()
			ev.physical_keycode = keys[a]
			InputMap.action_add_event(a, ev)

func _w(p : Vector2) -> Vector2:
	return _origin + p

func _aim() -> Vector2:
	var d : Vector2 = get_global_mouse_position() - _w(world.actors[P]["pos"])
	return d if d.length() > 1.0 else Vector2.RIGHT

func _say(reason : StringName) -> void:
	_msg = CombatText.of(reason)
	_msg_until = _now() + 1.0

func _unhandled_input(e : InputEvent) -> void:
	if world == null:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_R:
			_start()
		elif e.keycode == KEY_SPACE:
			var mv : Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
			var dir : Vector2 = mv if mv != Vector2.ZERO else -_aim()
			var res : Dictionary = world.actors[P]["c"].start_dodge(_now(), dir)
			if res["ok"]:
				_dodge_dir = dir.normalized()
			else:
				_say(res["reason"])
		elif e.keycode == KEY_1:
			feel_s.flash = not feel_s.flash
			feel_s.save()
		elif e.keycode == KEY_2:
			feel_s.hitstop = not feel_s.hitstop
			feel_s.save()
		elif e.keycode == KEY_3:
			feel_s.shake = not feel_s.shake
			feel_s.save()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var r2 : Dictionary = world.attack(P, _now(), _aim())
		if not r2["ok"]:
			_say(r2["reason"])

func _physics_process(delta : float) -> void:
	if world == null:
		return
	if feel.in_hitstop(_now()):
		return
	var now : float = _now()
	var pc : Combatant = world.actors[P]["c"]
	var bc : Combatant = world.actors[B]["c"]
	pc.advance(now)
	var pos : Vector2 = world.actors[P]["pos"]
	if pc.state == Combatant.State.IDLE:
		pos += Input.get_vector("move_left", "move_right", "move_up", "move_down") * PLAYER_SPEED * delta
	elif pc.state == Combatant.State.DODGE:
		pos += _dodge_dir * (DODGE_DIST / params.dodge_time) * delta
	world.set_pos(P, arena.clamp_pos(pos, 12.0))
	# บอสเริ่มทำงานเมื่อผู้เล่นเข้าลึกกว่าปากทางเข้า (Arena Entry)
	if not brain.engaged and (world.actors[P]["pos"] - arena.entry_point()).length() > 40.0:
		brain.engaged = true
	var ev : Array = brain.step(now, world, arena.pillars())
	ev.append_array(world.resolve_swings(now))
	for e in ev:
		feel.on_event(e, P, now)
		if e["result"]["ok"] and e["target"] == P:
			var ap : Vector2 = world.actors[e["attacker"]]["pos"]
			_kb[P] = feel.knock(ap, world.actors[P]["pos"], true) * 8.0
		if e["target"] == P:
			_say(e["result"]["reason"] if not e["result"]["ok"] else &"ok")
	for id in _kb.keys():
		world.set_pos(id, arena.clamp_pos(world.actors[id]["pos"] + _kb[id] * delta, 12.0))
		_kb[id] = _kb[id] * maxf(0.0, 1.0 - delta * 8.0)
		if _kb[id].length() < 1.0:
			_kb.erase(id)
	var status : String = ""
	if pc.state == Combatant.State.DEAD:
		status = "ล้มแล้ว กด R เริ่มใหม่"
	elif bc.state == Combatant.State.DEAD:
		status = "ชนะบอส! กด R เริ่มใหม่"
	elif _msg != "" and now < _msg_until:
		status = _msg
	hud.text = "HP %d/%d  stamina %d\nบอส HP %d/%d  เฟส %d  %s\n%s\n1 flash:%s 2 hitstop:%s 3 shake:%s" % [pc.hp, pc.max_hp, int(pc.stamina_at(now)), bc.hp, bc.max_hp, brain.phase_of(bc), "(ยังไม่เริ่ม เดินเข้าไป)" if not brain.engaged else "", status, feel_s.flash, feel_s.hitstop, feel_s.shake]
	queue_redraw()

func _draw() -> void:
	if world == null:
		return
	var now : float = _now()
	var sh : float = feel.shake_amount(now)
	position = Vector2(randf_range(-sh, sh), randf_range(-sh, sh))
	draw_arc(_origin, arena.radius, 0.0, TAU, 96, Color(0.6, 0.6, 0.6), 3.0)
	for pl in arena.pillars():
		draw_circle(_w(pl["pos"]), pl["radius"], Color(0.45, 0.45, 0.5))
	_draw_boss_telegraph(now)
	for id in world.actors:
		var a : Dictionary = world.actors[id]
		var c : Combatant = a["c"]
		var r : float = a["radius"]
		var col : Color = Color(0.4, 0.8, 1.0) if id == P else Color(0.35, 0.65, 0.3)
		if c.state == Combatant.State.DEAD:
			col = Color(0.3, 0.3, 0.3)
		var sc : float = 1.0
		if id == B:
			var v : Dictionary = BossTelegraphView.of(brain, world, now, arena.pillars())
			if v["phase"] == &"telegraph":
				sc = 1.0 - 0.12 * v["progress"]   # anticipation: บอสหดลง
			elif v["phase"] == &"recovery":
				sc = 1.08
		if c.is_invulnerable(now):
			col = col.lightened(0.5)
		if feel.is_flashing(id, now):
			col = Color.WHITE
		draw_rect(Rect2(_w(a["pos"]) - Vector2(r, r) * sc, Vector2(r, r) * 2.0 * sc), col)
		if id == P:
			draw_line(_w(a["pos"]), _w(a["pos"]) + c.aim * (r + 10.0), Color.WHITE, 2.0)
	# กรวยฟันของผู้เล่น (ใช้ TelegraphView เดิม)
	var pv : Dictionary = TelegraphView.of(world, P, now)
	if pv["phase"] != &"none":
		var cn : Dictionary = pv["cone"]
		_fan(_w(cn["origin"]), cn["aim"], cn["half_angle"], cn["reach"], Color(1, 1, 1, 0.25 if pv["phase"] == &"windup" else 0.6))

func _fan(o : Vector2, aim : Vector2, half_deg : float, reach : float, col : Color) -> void:
	var pts : PackedVector2Array = [o]
	var a0 : float = aim.angle() - deg_to_rad(half_deg)
	var a1 : float = aim.angle() + deg_to_rad(half_deg)
	for i in 17:
		pts.append(o + Vector2.from_angle(lerpf(a0, a1, i / 16.0)) * reach)
	draw_colored_polygon(pts, col)

func _dashed(a : Vector2, b : Vector2, w : float) -> void:
	var n : int = maxi(1, int(a.distance_to(b) / 10.0))
	for k in range(0, n, 2):
		draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), WARN, w)

func _draw_boss_telegraph(now : float) -> void:
	var v : Dictionary = BossTelegraphView.of(brain, world, now, arena.pillars())
	if v["phase"] != &"telegraph":
		return
	var o : Vector2 = _w(v["origin"])
	var prog : float = v["progress"]
	if v["shape"] == &"cone":
		var a0 : float = v["aim"].angle() - deg_to_rad(v["half_angle"])
		var a1 : float = v["aim"].angle() + deg_to_rad(v["half_angle"])
		var rim : PackedVector2Array = [o]
		var fill : PackedVector2Array = [o]
		for i in 17:
			var ang : float = lerpf(a0, a1, i / 16.0)
			rim.append(o + Vector2.from_angle(ang) * v["reach"])
			fill.append(o + Vector2.from_angle(ang) * v["reach"] * prog)
		draw_colored_polygon(fill, Color(WARN, 0.35))
		for i in rim.size():
			_dashed(rim[i], rim[(i + 1) % rim.size()], 2.0)
	elif v["shape"] == &"line3":
		for ln in v["lines"]:
			var end : Vector2 = o + ln["dir"] * ln["length"]
			_dashed(o, end, v["width"] * 0.4)
			draw_circle(end, 4.0 + 12.0 * prog, Color(WARN, 0.8))   # เมล็ดพองที่ปลายเส้น
	elif v["shape"] == &"ring":
		draw_arc(o, v["inner"], 0.0, TAU, 64, WARN, 2.0)
		draw_arc(o, v["outer"], 0.0, TAU, 64, WARN, 2.0)
		var mid : float = lerpf(v["inner"], v["outer"], prog)
		draw_arc(o, mid, 0.0, TAU, 64, Color(WARN, 0.5), 8.0)   # วงเติมจากในออกนอก
