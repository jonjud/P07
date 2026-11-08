extends RefCounted
class_name CombatText
# ข้อความ UI ของ combat ที่เดียว (reason -> ข้อความ) ห้าม hardcode กระจายใน scene

const MSG : Dictionary = {
	&"ok": "",
	&"not_idle": "ยังทำอย่างอื่นอยู่",
	&"not_enough_stamina": "stamina ไม่พอ",
	&"dead": "ล้มแล้ว",
	&"invulnerable": "หลบได้!",
	&"bad_weapon": "ไม่มีอาวุธ",
	&"friendly": "โดนพวกเดียวกันไม่ได้",
}

static func of(reason : StringName) -> String:
	return MSG.get(reason, String(reason))
