extends Resource
class_name EnemyData
# เล็กที่สุด ตาม Brief: id, max_hp, พารามิเตอร์โจมตี/เวลา

@export var id : StringName
@export var max_hp : int = 40
@export var radius : float = 12.0
@export var move_speed : float = 90.0
@export var aggro_range : float = 220.0
@export var attack_range : float = 48.0
@export var damage : int = 12
@export var telegraph : float = 0.70      # = windup ของ enemy (เกณฑ์ >= 0.60)
@export var active : float = 0.10
@export var recovery : float = 0.60
@export var cooldown : float = 0.80       # พักก่อนเริ่ม telegraph ครั้งถัดไป
