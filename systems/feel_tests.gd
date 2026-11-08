extends RefCounted
class_name FeelTests

var passed : int = 0
var failed : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func ev(att : String, tgt : String, ok : bool) -> Dictionary:
	return {"attacker": att, "target": tgt, "result": {"ok": ok, "reason": &"ok" if ok else &"invulnerable"}}

func run_all() -> void:
	var s : FeelSettings = FeelSettings.new()
	var f : FeelState = FeelState.new(s)
	f.on_event(ev("e1", "p1", true), "p1", 1.0)
	t("player hit: flash", f.is_flashing("p1", 1.05) and not f.is_flashing("p1", 1.09))
	t("player hit: hitstop", f.in_hitstop(1.03) and not f.in_hitstop(1.05))
	t("player hit: shake decays", f.shake_amount(1.0) > f.shake_amount(1.1) and f.shake_amount(1.13) == 0.0)
	var g : FeelState = FeelState.new(s)
	g.on_event(ev("p1", "e1", true), "p1", 2.0)
	t("player swing hits: flash+stop, no shake", g.is_flashing("e1", 2.05) and g.in_hitstop(2.03) and g.shake_amount(2.0) == 0.0)
	var h : FeelState = FeelState.new(s)
	h.on_event(ev("e1", "p1", false), "p1", 3.0)
	t("dodged: no feedback", not h.is_flashing("p1", 3.01) and not h.in_hitstop(3.01) and h.shake_amount(3.0) == 0.0)
	var o : FeelSettings = FeelSettings.new()
	o.flash = false
	o.hitstop = false
	o.shake = false
	var k : FeelState = FeelState.new(o)
	k.on_event(ev("e1", "p1", true), "p1", 4.0)
	t("all off: nothing", not k.is_flashing("p1", 4.01) and not k.in_hitstop(4.01) and k.shake_amount(4.0) == 0.0)
	var one : FeelSettings = FeelSettings.new()
	one.shake = false
	var m : FeelState = FeelState.new(one)
	m.on_event(ev("e1", "p1", true), "p1", 5.0)
	t("shake off only", m.shake_amount(5.0) == 0.0 and m.is_flashing("p1", 5.01) and m.in_hitstop(5.01))
	var kb : Vector2 = f.knock(Vector2.ZERO, Vector2(10, 0), false)
	t("knockback direction+size", kb.x > 0.0 and is_equal_approx(kb.length(), FeelSettings.KNOCK_ENEMY))
	t("knockback player larger", f.knock(Vector2.ZERO, Vector2(0, 5), true).length() > kb.length())
	t("knockback same pos safe", f.knock(Vector2.ONE, Vector2.ONE, false).is_finite())
	# ตัวเลือกคงค่า (round-trip ไฟล์จริง)
	var w : FeelSettings = FeelSettings.new()
	w.shake = false
	w.flash = false
	t("save", w.save())
	var r : FeelSettings = FeelSettings.new()
	t("load", r.load_file() and r.shake == false and r.flash == false and r.hitstop == true)
	FeelSettings.new().save()   # คืนค่าเริ่มต้นหลังเทสต์
	print("Feel: Passed ", passed, " / Failed ", failed)
