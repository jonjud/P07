extends Node2D
# scene ทดลอง solo: CombatWorld เป็น source of truth, scene อ่านและส่งเจตนาเท่านั้น
# WASD เดิน | เมาส์เล็ง | คลิกซ้าย ฟัน | Space dodge | R รีเซ็ต

const PLAYER_SPEED : float = 220.0
const DODGE_DIST : float = 96.0
const PLAYER_ID : String = "p1"
const ENEMY_ID : String = "e1"

var world : CombatWorld
var params : CombatParams
var enemy_data : EnemyData
var brain : EnemyBrain
var sword : WeaponData
var td : TelegraphDraw
var hud : Label
var _t0 : int = 0
var _dodge_dir : Vector2 = Vector2.ZERO
var _msg : String = ""
var _msg_until : float = 0.0
var feel_s : FeelSettings = FeelSettings.new()
var feel : FeelState
var _hs_prev : float = 0.0
var _kb : Dictionary = {}   # id -> Vector2 ความเร็วผลักที่เหลือ

func _now() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0

func _ready() -> void:
	_ensure_actions()
	params = load("res://data/combat/player_params.tres") as CombatParams
	var r : Dictionary = EnemyLoader.load_dir("res://data/enemies/")
	if params == null or not r["ok"]:
		push_error("โหลด data combat ไม่ได้")
		return
	enemy_data = r["enemies"][&"grunt"]
	sword = WeaponData.new()
	sword.id = &"test_sword"
	_start()
	var layer : CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(10, 10)
	layer.add_child(hud)
	feel_s.load_file()
	feel = FeelState.new(feel_s)

func _start() -> void:
	_t0 = Time.get_ticks_msec()
	world = CombatWorld.new(params)
	world.add_actor(PLAYER_ID, 100, Vector2(300, 300), 12.0, 0, sword)
	world.add_actor(ENEMY_ID, enemy_data.max_hp, Vector2(650, 300), enemy_data.radius, 1, EnemyBrain.make_weapon(enemy_data), EnemyBrain.make_params(enemy_data))
	brain = EnemyBrain.new(ENEMY_ID, enemy_data)
	if td != null:
		td.queue_free()
	td = TelegraphDraw.new()
	td.world = world
	td.now_fn = _now
	add_child(td)
	feel = FeelState.new(feel_s) if feel_s != null else null
	_kb.clear()

func _ensure_actions() -> void:
	var keys : Dictionary = {"move_left": KEY_A, "move_right": KEY_D, "move_up": KEY_W, "move_down": KEY_S}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev : InputEventKey = InputEventKey.new()
			ev.physical_keycode = keys[a]
			InputMap.action_add_event(a, ev)

func _aim() -> Vector2:
	var p : Vector2 = world.actors[PLAYER_ID]["pos"]
	var d : Vector2 = get_global_mouse_position() - p
	return d if d.length() > 1.0 else Vector2.RIGHT

func _unhandled_input(e : InputEvent) -> void:
	if world == null:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_R:
			_start()
		elif e.keycode == KEY_SPACE:
			var mv : Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
			var dir : Vector2 = mv if mv != Vector2.ZERO else -_aim()   # ไม่กดเดิน = ถอยจากทิศ aim
			var res : Dictionary = world.actors[PLAYER_ID]["c"].start_dodge(_now(), dir)
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
		var res2 : Dictionary = world.attack(PLAYER_ID, _now(), _aim())
		if not res2["ok"]:
			_say(res2["reason"])

func _say(reason : StringName) -> void:
	_msg = CombatText.of(reason)
	_msg_until = _now() + 1.0

func _physics_process(delta : float) -> void:
	if feel != null and feel.in_hitstop(_now()):
		return
	var now : float = _now()
	var pc : Combatant = world.actors[PLAYER_ID]["c"]
	var ec : Combatant = world.actors[ENEMY_ID]["c"]
	pc.advance(now)
	# ผู้เล่นขยับได้ตอน IDLE เท่านั้น (commitment) dodge ขยับตามทิศที่ล็อก
	var pos : Vector2 = world.actors[PLAYER_ID]["pos"]
	if pc.state == Combatant.State.IDLE:
		pos += Input.get_vector("move_left", "move_right", "move_up", "move_down") * PLAYER_SPEED * delta
	elif pc.state == Combatant.State.DODGE:
		pos += _dodge_dir * (DODGE_DIST / params.dodge_time) * delta
	world.set_pos(PLAYER_ID, pos)
	# ศัตรู: think คืนเจตนา scene เป็นคนสั่งและขยับ
	var th : Dictionary = brain.think(now, world)
	if th["attack"]:
		world.attack(ENEMY_ID, now, th["aim"])
	if th["move"] != Vector2.ZERO:
		world.set_pos(ENEMY_ID, world.actors[ENEMY_ID]["pos"] + th["move"] * delta)
	for ev in world.resolve_swings(now):
		feel.on_event(ev, PLAYER_ID, now)
		if ev["result"]["ok"]:
			var ap : Vector2 = world.actors[ev["attacker"]]["pos"]
			var tp : Vector2 = world.actors[ev["target"]]["pos"]
			_kb[ev["target"]] = feel.knock(ap, tp, ev["target"] == PLAYER_ID) * 8.0
		if ev["target"] == PLAYER_ID:
			_say(ev["result"]["reason"] if not ev["result"]["ok"] else &"ok")
	for id in _kb.keys():   # ผลักสลายใน ~0.12s
		world.set_pos(id, world.actors[id]["pos"] + _kb[id] * delta)
		_kb[id] = _kb[id] * maxf(0.0, 1.0 - delta * 8.0)
		if _kb[id].length() < 1.0:
			_kb.erase(id)
	if pc.state == Combatant.State.DEAD:
		_msg = "ล้มแล้ว กด R เริ่มใหม่"
		_msg_until = now + 1.0
	elif ec.state == Combatant.State.DEAD:
		_msg = "ชนะ! กด R เริ่มใหม่"
		_msg_until = now + 1.0
	hud.text = "HP %d/%d   stamina %d\nศัตรู HP %d   %s" % [pc.hp, pc.max_hp, int(pc.stamina_at(now)), ec.hp, _msg if now < _msg_until else ""]
	queue_redraw()

func _draw() -> void:
	if world == null:
		return
	var now : float = _now()
	var sh : float = feel.shake_amount(now) if feel != null else 0.0
	position = Vector2(randf_range(-sh, sh), randf_range(-sh, sh))
	for id in world.actors:
		var a : Dictionary = world.actors[id]
		var c : Combatant = a["c"]
		var r : float = a["radius"]
		var col : Color = Color(0.4, 0.8, 1.0) if id == PLAYER_ID else Color(0.8, 0.6, 0.3)
		if c.state == Combatant.State.DEAD:
			col = Color(0.3, 0.3, 0.3)
		var scale : float = 1.0
		if id == ENEMY_ID:   # anticipation: หดตอน windup แล้วพุ่งขยายตอน active
			var v : Dictionary = TelegraphView.of(world, id, now)
			if v["phase"] == &"windup":
				scale = 1.0 - 0.15 * v["progress"]
			elif v["phase"] == &"active":
				scale = 1.3
		if c.is_invulnerable(now):
			col = col.lightened(0.5)
		if feel != null and feel.is_flashing(id, now):
			col = Color.WHITE
		draw_rect(Rect2(a["pos"] - Vector2(r, r) * scale, Vector2(r, r) * 2.0 * scale), col)
		draw_line(a["pos"], a["pos"] + c.aim * (r + 10.0), Color.WHITE, 2.0)
