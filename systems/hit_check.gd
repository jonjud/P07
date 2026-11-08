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

# ระยะที่เส้นตรงจาก origin ทิศ dir (unit) ชนวงกลม (c, r) ครั้งแรก; คืน INF ถ้าไม่ชนภายใน max_len
static func _ray_circle(origin : Vector2, dir : Vector2, max_len : float, c : Vector2, r : float) -> float:
	var oc : Vector2 = c - origin
	var proj : float = oc.dot(dir)
	var perp2 : float = oc.length_squared() - proj * proj
	var r2 : float = r * r
	if perp2 > r2:
		return INF
	var half : float = sqrt(maxf(0.0, r2 - perp2))
	var t0 : float = proj - half
	var t1 : float = proj + half
	if t1 < 0.0:
		return INF
	var t : float = maxf(t0, 0.0)   # เริ่มอยู่ในวงกลม = ชนที่ 0
	return t if t <= max_len else INF

# เส้นหนา width ยาว length จาก origin ทิศ aim ถูกตัดที่ blocker แรก
# blockers: [{pos:Vector2, radius:float}]  targets: [{id,pos,radius}] คืน Array[String] ใกล้→ไกล
static func line(origin : Vector2, aim : Vector2, length : float, width : float, blockers : Array, targets : Array, ignore : String = "") -> Array:
	if not origin.is_finite() or not aim.is_finite() or aim.length() < 0.0001:
		return []
	if not is_finite(length) or length <= 0.0 or not is_finite(width) or width < 0.0:
		return []
	var dir : Vector2 = aim.normalized()
	var stop : float = length
	for b in blockers:
		if typeof(b) != TYPE_DICTIONARY or not b.has("pos") or not b.has("radius"):
			continue
		if typeof(b["pos"]) != TYPE_VECTOR2 or not b["pos"].is_finite():
			continue
		var br : float = float(b["radius"])
		if not is_finite(br) or br < 0.0:
			continue
		# เส้นหนา: ขยายเสาด้วยครึ่งความกว้าง
		stop = minf(stop, _ray_circle(origin, dir, length, b["pos"], br + width * 0.5))
	var hits : Array = []
	for t in targets:
		if typeof(t) != TYPE_DICTIONARY or not t.has("id") or not t.has("pos") or not t.has("radius"):
			continue
		if typeof(t["id"]) != TYPE_STRING or typeof(t["pos"]) != TYPE_VECTOR2:
			continue
		var id : String = t["id"]
		var pos : Vector2 = t["pos"]
		var r : float = float(t["radius"])
		if id == ignore or not pos.is_finite() or not is_finite(r) or r < 0.0:
			continue
		var off : Vector2 = pos - origin
		var along : float = off.dot(dir)
		var side : float = absf(off.cross(dir))
		if side > r + width * 0.5:
			continue
		if along + r < 0.0 or along - r > stop:
			continue
		hits.append([maxf(along, 0.0), id])
	hits.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return hits.map(func(h): return h[1])

# วงแหวนรอบ origin: โดนเมื่อช่วงระยะของเป้า [d-r, d+r] ซ้อนกับ [inner, outer]
static func ring(origin : Vector2, inner : float, outer : float, targets : Array, ignore : String = "") -> Array:
	if not origin.is_finite() or not is_finite(inner) or not is_finite(outer) or inner < 0.0 or outer <= inner:
		return []
	var hits : Array = []
	for t in targets:
		if typeof(t) != TYPE_DICTIONARY or not t.has("id") or not t.has("pos") or not t.has("radius"):
			continue
		if typeof(t["id"]) != TYPE_STRING or typeof(t["pos"]) != TYPE_VECTOR2:
			continue
		var id : String = t["id"]
		var pos : Vector2 = t["pos"]
		var r : float = float(t["radius"])
		if id == ignore or not pos.is_finite() or not is_finite(r) or r < 0.0:
			continue
		var d : float = (pos - origin).length()
		if d + r < inner or d - r > outer:
			continue
		hits.append([d, id])
	hits.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return hits.map(func(h): return h[1])

# ความยาวที่เส้นไปถึงก่อนชนเสาแรก (ตรงกับที่ line() ใช้ตัดสิน)
static func line_stop(origin : Vector2, aim : Vector2, length : float, width : float, blockers : Array) -> float:
	if not origin.is_finite() or not aim.is_finite() or aim.length() < 0.0001 or length <= 0.0:
		return 0.0
	var dir : Vector2 = aim.normalized()
	var stop : float = length
	for b in blockers:
		if typeof(b) != TYPE_DICTIONARY or not b.has("pos") or not b.has("radius"):
			continue
		if typeof(b["pos"]) != TYPE_VECTOR2 or not b["pos"].is_finite():
			continue
		var br : float = float(b["radius"])
		if not is_finite(br) or br < 0.0:
			continue
		stop = minf(stop, _ray_circle(origin, dir, length, b["pos"], br + width * 0.5))
	return stop
