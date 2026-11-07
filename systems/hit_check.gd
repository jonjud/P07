extends RefCounted
class_name HitCheck
# geometry ล้วน ไม่มี Node ไม่มีเอฟเฟกต์ ผลลัพธ์ = id ที่โดน (ภาพไม่ใช่หลักฐาน)
# targets: [{id:String, pos:Vector2, radius:float}]
# คืน Array[String] เรียงใกล้→ไกล เท่ากันเรียงตาม id (deterministic)
# input ผิด = ไม่โดนใคร (ไม่ crash ไม่เดา)

const ANGLE_EPS : float = 0.0001   # ชดเชยความต่าง float32/double ที่ขอบกรวย (~0.006°)

static func cone(origin : Vector2, aim : Vector2, reach : float, half_angle_deg : float, targets : Array, ignore : String = "") -> Array:
	if not origin.is_finite() or not aim.is_finite() or aim.length() < 0.0001:
		return []
	if not is_finite(reach) or reach <= 0.0 or not is_finite(half_angle_deg) or half_angle_deg <= 0.0 or half_angle_deg > 180.0:
		return []
	var dir : Vector2 = aim.normalized()
	var half : float = deg_to_rad(half_angle_deg)
	var hits : Array = []
	for t in targets:
		if typeof(t) != TYPE_DICTIONARY or not t.has("id") or not t.has("pos") or not t.has("radius"):
			continue
		if typeof(t["id"]) != TYPE_STRING or typeof(t["pos"]) != TYPE_VECTOR2:
			continue
		if typeof(t["radius"]) != TYPE_FLOAT and typeof(t["radius"]) != TYPE_INT:
			continue
		var id : String = t["id"]
		var pos : Vector2 = t["pos"]
		var r : float = float(t["radius"])
		if id == ignore or not pos.is_finite() or not is_finite(r) or r < 0.0:
			continue
		var off : Vector2 = pos - origin
		var d : float = off.length()
		if d - r > reach:
			continue
		if d > r and half_angle_deg < 180.0:   # 180 = รอบทิศ ไม่ต้องดูมุม
			var slack : float = asin(clampf(r / d, 0.0, 1.0))
			if absf(dir.angle_to(off)) - slack > half + ANGLE_EPS:
				continue
		hits.append([d, id])
	hits.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return hits.map(func(h): return h[1])
