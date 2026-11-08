extends Node2D
class_name TelegraphDraw
# วาดอย่างเดียว ไม่มีกฎเกม อ่านจาก TelegraphView
signal telegraph_started(actor_id : String)   # hook เสียง (ART-14)

const WARN : Color = Color(1.0, 0.35, 0.1)    # สีเตือนชุดเดียวทั้งเกม (DOC-13 §1)
var world : CombatWorld
var now_fn : Callable = func() -> float: return Time.get_ticks_msec() / 1000.0
var _was : Dictionary = {}

func _process(_d : float) -> void:
	queue_redraw()

func _draw() -> void:
	if world == null:
		return
	var now : float = now_fn.call()
	for id in world.actors:
		var v : Dictionary = TelegraphView.of(world, id, now)
		var was : bool = _was.get(id, false)
		var on : bool = v["phase"] == &"windup"
		if on and not was:
			telegraph_started.emit(id)
		_was[id] = on
		if v["phase"] == &"none":
			continue
		var cn : Dictionary = v["cone"]
		var o : Vector2 = cn["origin"]
		var a0 : float = cn["aim"].angle() - deg_to_rad(cn["half_angle"])
		var a1 : float = cn["aim"].angle() + deg_to_rad(cn["half_angle"])
		var reach : float = cn["reach"]
		var pts : PackedVector2Array = [o]
		for i in 13:
			pts.append(o + Vector2.from_angle(lerpf(a0, a1, i / 12.0)) * reach)
		var filled : PackedVector2Array = [o]
		for i in 13:
			filled.append(o + Vector2.from_angle(lerpf(a0, a1, i / 12.0)) * reach * v["progress"])
		if v["phase"] == &"windup":
			draw_colored_polygon(filled, Color(WARN, 0.35))
			_dashed(pts, WARN)
		else:
			draw_colored_polygon(pts, Color(WARN, 0.6))
			draw_polyline(pts + PackedVector2Array([o]), WARN, 4.0)   # ทึบหนา = impact

func _dashed(pts : PackedVector2Array, col : Color) -> void:
	var closed : PackedVector2Array = pts + PackedVector2Array([pts[0]])
	for i in closed.size() - 1:
		var a : Vector2 = closed[i]
		var b : Vector2 = closed[i + 1]
		var n : int = int(a.distance_to(b) / 8.0)
		for k in range(0, n, 2):
			draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), col, 2.0)
