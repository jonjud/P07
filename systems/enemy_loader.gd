extends RefCounted
class_name EnemyLoader

const MIN_TELEGRAPH : float = 0.60   # เกณฑ์ fairness จุดเดียว (หน้าต่าง dodge = telegraph - iframe >= 0.45)
const BAD_DIR : StringName = &"bad_dir"
const NOT_ENEMY : StringName = &"not_enemy"
const DUP_ID : StringName = &"dup_id"
const BAD_VALUE : StringName = &"bad_value"
const OK : StringName = &"ok"

static func validate(d : EnemyData) -> StringName:
	if String(d.id) == "":
		return BAD_VALUE
	if d.max_hp < 1 or d.damage <= 0 or d.radius < 0.0 or not is_finite(d.radius):
		return BAD_VALUE
	if not is_finite(d.move_speed) or d.move_speed < 0.0:
		return BAD_VALUE
	if d.attack_range <= 0.0 or d.aggro_range <= d.attack_range:
		return BAD_VALUE
	if d.active <= 0.0 or d.recovery < 0.0 or d.cooldown < 0.0:
		return BAD_VALUE
	if d.telegraph < MIN_TELEGRAPH:
		return BAD_VALUE
	return OK

# โหลดลงตัวชั่วคราวก่อน เปลี่ยนผลจริงเมื่อไม่มี error ทั้งหมด
static func load_dir(path : String) -> Dictionary:
	var dir : DirAccess = DirAccess.open(path)
	if dir == null:
		return {"ok": false, "enemies": {}, "reason": BAD_DIR}
	var loaded : Dictionary = {}
	var reason : StringName = OK
	dir.list_dir_begin()
	var f : String = dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.get_extension() == "tres":
			var res : Resource = ResourceLoader.load(path.path_join(f))
			if not (res is EnemyData):
				push_error("ไม่ใช่ EnemyData: " + f)
				reason = NOT_ENEMY
			else:
				var v : StringName = validate(res)
				if v != OK:
					push_error("EnemyData ผิด: %s (%s)" % [f, v])
					reason = v
				elif loaded.has(res.id):
					push_error("id ซ้ำ: " + str(res.id))
					reason = DUP_ID
				else:
					loaded[res.id] = res
		f = dir.get_next()
	dir.list_dir_end()
	if reason != OK:
		return {"ok": false, "enemies": {}, "reason": reason}
	return {"ok": true, "enemies": loaded, "reason": OK}
