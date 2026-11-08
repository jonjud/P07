extends Resource
class_name CombatParams
# ค่าทั้งหมด EXPERIMENTAL ปรับที่จุดเดียว: data/combat/player_params.tres

@export var windup : float = 0.15
@export var active : float = 0.10
@export var recovery : float = 0.25
@export var dodge_time : float = 0.25
@export var iframe : float = 0.15
@export var dodge_cost : float = 20.0
@export var stamina_max : float = 100.0
@export var stamina_regen : float = 30.0   # ต่อวินาที
@export var regen_delay : float = 0.5      # หน่วงหลัง dodge จบ
@export var cone_half_angle : float = 60.0 # ครึ่งมุมกรวยโจมตี (องศา)
