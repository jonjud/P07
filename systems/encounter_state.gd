extends RefCounted
class_name EncounterState
# pure: ตัดสินผลของ encounter จากสถานะ world ไม่แก้ world
enum R { ONGOING, WON, LOST }

static func result(world : CombatWorld, boss_id : String) -> int:
	if not world.actors.has(boss_id):
		return R.ONGOING
	if world.actors[boss_id]["c"].state == Combatant.State.DEAD:
		return R.WON   # ชนะก่อนแพ้ถ้าตายพร้อมกัน (ตัดสินแล้ว: ให้ผู้เล่น)
	var any_player : bool = false
	for id in world.actors:
		if world.actors[id]["team"] != world.actors[boss_id]["team"]:
			any_player = true
			if world.actors[id]["c"].state != Combatant.State.DEAD:
				return R.ONGOING
	return R.LOST if any_player else R.ONGOING
