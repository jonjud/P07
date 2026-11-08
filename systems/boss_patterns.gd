extends Resource
class_name BossPattern
# shape: cone | line3 | ring (ค่าทั้งหมด EXPERIMENTAL)

@export var id : StringName
@export var shape : StringName = &"cone"
@export var telegraph : float = 0.70
@export var recovery : float = 0.90
@export var damage : int = 12
@export var reach : float = 110.0       # cone / line3
@export var half_angle : float = 80.0   # cone
@export var width : float = 16.0        # line3
@export var spread_deg : float = 30.0   # line3: ทิศเป้า และ +-spread
@export var inner : float = 0.0         # ring
@export var outer : float = 0.0         # ring
