extends ItemData
class_name WeaponData
# DOC-07 §2.4 ใช้เฉพาะฟิลด์ที่มี use case ตอนนี้ (P07-04)

@export var damage : int = 10
@export var attack_range : float = 48.0
@export var attack_speed : float = 1.0    # ตัวหารเวลา windup/active/recovery
