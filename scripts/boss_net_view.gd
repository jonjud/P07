extends Node2D
class_name BossNetView
# วาดบอส/arena/telegraph จาก snapshot (host: อ่านจาก logic ตรง ๆ, client: จาก combat_view)
# ส่งเจตนา attack/dodge ผ่าน NetSession: คลิกซ้าย = ฟัน, Space = dodge
# ไม่มีกฎเกมที่นี่ ภาพไม่ใช่หลักฐานว่าโดน

const WARN : Color = Color(1.0, 0.35, 0.1)
const B : String = "boss"
var net : NetSession
var local : CharacterBody2D
var bf : BuildField
var bdata : BossData = BossData.grove()
var arena : ArenaData = BossNetView.make_arena()
var hud : Label
var msg : String = ""
var _mine : Dictionary = {}

static func make_arena() -> ArenaData:
	var a : ArenaData = ArenaData.new()
	a.id = &"grove"
	a.boss_pos = Vector2(820, 320)
	return a

func setup(n : NetSession, player : CharacterBody2D, build_field : BuildField) -> void:
	net = n
	local = player
	bf = build_field
	var layer : CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(10, 110)
	layer.add_child(hud)
	net.result_received.connect(_on_result)

func _view() -> Dictionary:
	if net.logic != null and net.logic.world != null:
		return CombatSnapshot.to_dict(net.logic.world, net.logic.boss, net.logic.flags)
	return net.combat_view

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0 + (0.0 if net.logic != null else net.clock_off)

func _on_result(res : Dictionary) -> void:
	if not _mine.erase(res["rid"]):
		return
	var why : String = String(res["net_reason"]) if not res["accepted"] else String(res["result"]["reason"])
	msg = CombatText.of(StringName(why))

static func _enc(v : Vector2) -> String:
	return "%d,%d" % [roundi(v.x * 1000.0), roundi(v.y * 1000.0)]

func _aim() -> Vector2:
	var d : Vector2 = get_global_mouse_position() - local.global_position
	return d.normalized() if d.length() > 1.0 else Vector2.RIGHT

func _send(op : String, dir : Vector2) -> void:
	_mine[net.next_rid()] = true
	net.send_request(op, &"", 0, BossNetView._enc(dir), "")

func _unhandled_input(e : InputEvent) -> void:
	if net == null or local == null:
		return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_SPACE:
		var mv : Vector2 = Vector2(
			int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A)),
			int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W)))
		_send("dodge", mv.normalized() if mv != Vector2.ZERO else -_aim())
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not (bf != null and bf.build_mode):
		_send("attack", _aim())

func _process(_d : float) -> void:
	if net == null:
		return
	var s : Dictionary = _view()
	var t : String = "บอส: ยังไม่มีข้อมูล"
	if not s.is_empty() and s["actors"].has(B):
		var bc : Dictionary = s["actors"][B]["c"]
		t = "บอส HP %d/%d" % [bc["hp"], bc["max_hp"]]
		if s["actors"].has(net.my_pid):
			var me : Dictionary = s["actors"][net.my_pid]["c"]
			t += "   ฉัน HP %d/%d" % [me["hp"], me["max_hp"]]
		if not s["boss"].is_empty() and not s["boss"]["engaged"]:
			t += "   (เดินเข้าไปในวง)"
		if s["flags"].get("grove_guardian_defeated", false):
			t += "   ชนะแล้ว!"
	var inv : Inventory = net.my_inv()
	var heart : int = inv.count_of(&"forest_heart_00") if inv != null else 0
	var bag : Inventory = net.logic.invs.get("reward_" + net.my_pid) if net.logic != null else net.replicas.get("reward_" + net.my_pid)
	hud.text = "%s\nHeart x%d (ถุงรอ x%d)  %s\nคลิกซ้าย ฟัน | Space dodge | B สร้าง" % [t, heart, bag.count_of(&"forest_heart_00") if bag != null else 0, msg]
	queue_redraw()

func _dashed(a : Vector2, b : Vector2, w : float) -> void:
	var n : int = maxi(1, int(a.distance_to(b) / 10.0))
	for k in range(0, n, 2):
		draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), WARN, w)

func _draw() -> void:
	if net == null:
		return
	var s : Dictionary = _view()
	draw_arc(arena.boss_pos, arena.radius, 0.0, TAU, 96, Color(0.6, 0.6, 0.6), 3.0)
	for pl in arena.pillars():
		draw_circle(pl["pos"], pl["radius"], Color(0.45, 0.45, 0.5))
	if s.is_empty() or not s["actors"].has(B):
		return
	var now : float = _now()
	var sc : float = 1.0
	var bs : Dictionary = s["boss"]
	if not bs.is_empty() and bs["state"] == BossBrain.S.TELEGRAPH and bs["cur"] != "":
		sc = 1.0 - 0.12 * _draw_tele(s, now)
	elif not bs.is_empty() and bs["state"] == BossBrain.S.RECOVERY:
		sc = 1.08
	var bp : Vector2 = Vector2(s["actors"][B]["x"], s["actors"][B]["y"])
	var dead : bool = s["actors"][B]["c"]["hp"] <= 0
	draw_rect(Rect2(bp - Vector2(bdata.radius, bdata.radius) * sc, Vector2(bdata.radius, bdata.radius) * 2.0 * sc), Color(0.3, 0.3, 0.3) if dead else Color(0.35, 0.65, 0.3))
	for id in s["actors"]:
		if id == B:
			continue
		var a : Dictionary = s["actors"][id]
		var p : Vector2 = Vector2(a["x"], a["y"])
		draw_string(ThemeDB.fallback_font, p + Vector2(-16, -26), "%s%d" % ["(พัก) " if a["parked"] else "", a["c"]["hp"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 12)

# คืน progress 0..1 และวาด telegraph ของ pattern ปัจจุบัน
func _draw_tele(s : Dictionary, now : float) -> float:
	var b : Dictionary = s["boss"]
	var p : BossPattern = bdata.pattern(StringName(b["cur"]))
	if p == null:
		return 0.0
	var o : Vector2 = Vector2(s["actors"][B]["x"], s["actors"][B]["y"])
	var aim : Vector2 = Vector2(float(b["aim_x"]), float(b["aim_y"]))
	var prog : float = clampf((now - float(b["t_start"])) / p.telegraph, 0.0, 1.0)
	if p.shape == &"cone":
		var a0 : float = aim.angle() - deg_to_rad(p.half_angle)
		var a1 : float = aim.angle() + deg_to_rad(p.half_angle)
		var rim : PackedVector2Array = [o]
		var fill : PackedVector2Array = [o]
		for i in 17:
			var ang : float = lerpf(a0, a1, i / 16.0)
			rim.append(o + Vector2.from_angle(ang) * p.reach)
			fill.append(o + Vector2.from_angle(ang) * p.reach * prog)
		draw_colored_polygon(fill, Color(WARN, 0.35))
		for i in rim.size():
			_dashed(rim[i], rim[(i + 1) % rim.size()], 2.0)
	elif p.shape == &"line3":
		for deg in [0.0, -p.spread_deg, p.spread_deg]:
			var dir : Vector2 = aim.rotated(deg_to_rad(deg))
			var end : Vector2 = o + dir.normalized() * HitCheck.line_stop(o, dir, p.reach, p.width, arena.pillars())
			_dashed(o, end, p.width * 0.4)
			draw_circle(end, 4.0 + 12.0 * prog, Color(WARN, 0.8))
	elif p.shape == &"ring":
		draw_arc(o, p.inner, 0.0, TAU, 64, WARN, 2.0)
		draw_arc(o, p.outer, 0.0, TAU, 64, WARN, 2.0)
		draw_arc(o, lerpf(p.inner, p.outer, prog), 0.0, TAU, 64, Color(WARN, 0.5), 8.0)
	return prog
