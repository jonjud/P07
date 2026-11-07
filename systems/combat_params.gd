extends RefCounted
class_name CombatParams
# ค่าทั้งหมด EXPERIMENTAL ปรับที่จุดเดียว (P07-06) ภายหลังย้ายเป็น Resource ได้

var windup : float = 0.15
var active : float = 0.10
var recovery : float = 0.25
var dodge_time : float = 0.25
var iframe : float = 0.15
var dodge_cost : float = 20.0
var stamina_max : float = 100.0
var stamina_regen : float = 30.0   # ต่อวินาที
var regen_delay : float = 0.5      # หน่วงหลัง dodge จบ
