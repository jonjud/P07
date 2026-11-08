extends RefCounted
class_name FeelSettings
# ตัวเลือกความรู้สึก (OQ-09-07) บันทึกลงไฟล์ผู้ใช้ มีผลจริงและคงค่า
# ค่า tuning อยู่ตัวแปรต้นไฟล์ ปรับที่เดียว

const PATH : String = "user://settings.cfg"
const FLASH_TIME : float = 0.08
const KNOCK_ENEMY : float = 24.0
const KNOCK_PLAYER : float = 32.0
const HITSTOP_TIME : float = 0.04
const SHAKE_AMP : float = 3.0
const SHAKE_TIME : float = 0.12

var flash : bool = true
var hitstop : bool = true
var shake : bool = true

func save() -> bool:
	var cf : ConfigFile = ConfigFile.new()
	cf.set_value("feel", "flash", flash)
	cf.set_value("feel", "hitstop", hitstop)
	cf.set_value("feel", "shake", shake)
	return cf.save(PATH) == OK

# ไฟล์หาย/เสีย = ใช้ค่าเริ่มต้น (เปิดทั้งหมด) ไม่ crash
func load_file() -> bool:
	var cf : ConfigFile = ConfigFile.new()
	if cf.load(PATH) != OK:
		return false
	var f : Variant = cf.get_value("feel", "flash", true)
	var h : Variant = cf.get_value("feel", "hitstop", true)
	var s : Variant = cf.get_value("feel", "shake", true)
	if typeof(f) != TYPE_BOOL or typeof(h) != TYPE_BOOL or typeof(s) != TYPE_BOOL:
		return false
	flash = f
	hitstop = h
	shake = s
	return true
