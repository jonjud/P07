extends RefCounted
class_name CombatResult
# {ok, reason, requested, done, remaining} ตาม D-12 ตัดสินว่า state เปลี่ยนจาก done > 0 เท่านั้น

const OK : StringName = &"ok"
const BAD_TIME : StringName = &"bad_time"
const TIME_REVERSED : StringName = &"time_reversed"
const DEAD : StringName = &"dead"
const NOT_IDLE : StringName = &"not_idle"
const BAD_AIM : StringName = &"bad_aim"
const BAD_SPEED : StringName = &"bad_speed"
const NOT_ENOUGH_STAMINA : StringName = &"not_enough_stamina"
const INVALID_QUANTITY : StringName = &"invalid_quantity"
const INVULNERABLE : StringName = &"invulnerable"
const INTERNAL : StringName = &"internal"
# from_dict
const INCOMPLETE_DATA : StringName = &"incomplete_data"
const BAD_SCHEMA : StringName = &"bad_schema"
const BAD_DATA : StringName = &"bad_data"
const NULL_PARAMS : StringName = &"null_params"

const UNKNOWN_ACTOR : StringName = &"unknown_actor"
const BAD_WEAPON : StringName = &"bad_weapon"
const FRIENDLY : StringName = &"friendly"

static func make(reason : StringName, requested : int, done : int) -> Dictionary:
	return {"ok": reason == OK, "reason": reason, "requested": requested, "done": done, "remaining": maxi(0, requested - done)}
