extends RefCounted
class_name FeelState
# pure: เวลาส่งเข้าเป็น now; คำนวณ flash/shake/hitstop จาก event โดยเคารพตัวเลือก

var s : FeelSettings
var flash_until : Dictionary = {}   # actor id -> เวลา
var shake_until : float = 0.0
var stop_until : float = 0.0

func _init(settings : FeelSettings) -> void:
	s = settings

# event = ผลจาก resolve_swings; ok = โดนจริง (INVULNERABLE = หลบ ไม่มี feedback โดน)
func on_event(ev : Dictionary, player_id : String, now : float) -> void:
	if not ev["result"]["ok"]:
		return
	if s.flash:
		flash_until[ev["target"]] = now + FeelSettings.FLASH_TIME
	var player_involved : bool = ev["target"] == player_id or ev["attacker"] == player_id
	if s.hitstop and player_involved:
		stop_until = now + FeelSettings.HITSTOP_TIME
	if s.shake and ev["target"] == player_id:
		shake_until = now + FeelSettings.SHAKE_TIME

func is_flashing(id : String, now : float) -> bool:
	return flash_until.get(id, 0.0) > now

func in_hitstop(now : float) -> bool:
	return stop_until > now

# แรงสั่นลดลงเชิงเส้น คืน 0 เมื่อปิด/หมดเวลา
func shake_amount(now : float) -> float:
	if not s.shake or shake_until <= now:
		return 0.0
	return FeelSettings.SHAKE_AMP * (shake_until - now) / FeelSettings.SHAKE_TIME

func knock(attacker_pos : Vector2, target_pos : Vector2, target_is_player : bool) -> Vector2:
	var d : Vector2 = target_pos - attacker_pos
	if d.length() < 0.0001:
		d = Vector2.RIGHT
	return d.normalized() * (FeelSettings.KNOCK_PLAYER if target_is_player else FeelSettings.KNOCK_ENEMY)
