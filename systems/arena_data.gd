extends Resource
class_name ArenaData
# พื้นที่บอส: ข้อมูลล้วน serialize ได้ ไม่อ้าง node

@export var id : StringName
@export var radius : float = 260.0              # ขอบสนามแข็ง
@export var boss_pos : Vector2 = Vector2.ZERO   # ศูนย์กลาง
@export var pillar_count : int = 4
@export var pillar_ring : float = 150.0         # รัศมีที่วางเสา
@export var pillar_radius : float = 20.0
@export var pillar_phase_deg : float = 45.0     # หมุนเสาไม่ให้ตรงแกน (เส้นตรงสามทิศของ boss ไม่ทับเสาพอดี)
@export var entry_deg : float = 90.0            # ทิศทางเข้า (องศา จากแกน x) ผู้เล่นเริ่มที่ขอบทิศนี้
@export var entry_gate : float = 30.0           # ความกว้างช่องเข้า

func pillars() -> Array:
	var out : Array = []
	for i in pillar_count:
		var a : float = deg_to_rad(pillar_phase_deg + 360.0 * i / maxf(1.0, pillar_count))
		out.append({"pos": boss_pos + Vector2.from_angle(a) * pillar_ring, "radius": pillar_radius})
	return out

func entry_point() -> Vector2:
	return boss_pos + Vector2.from_angle(deg_to_rad(entry_deg)) * (radius - 24.0)   # 2 เท่ารัศมีผู้เล่น (12) อยู่ในขอบแข็งเสมอ

# ขอบแข็ง: คืนตำแหน่งที่ถูกจำกัดในสนาม (เป้า radius รวมแล้ว) ไม่ผ่านเสา
func clamp_pos(p : Vector2, body_r : float) -> Vector2:
	var q : Vector2 = p
	var off : Vector2 = q - boss_pos
	var maxd : float = radius - body_r
	if off.length() > maxd:
		q = boss_pos + off.normalized() * maxd
	for pl in pillars():
		var d : Vector2 = q - pl["pos"]
		var need : float = pl["radius"] + body_r
		if d.length() < need:
			q = pl["pos"] + (d.normalized() if d.length() > 0.0001 else Vector2.RIGHT) * need
	return q
