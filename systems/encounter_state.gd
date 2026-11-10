extends RefCounted
class_name EncounterState
# pure: ตัดสินผลของ encounter จากสถานะ world ไม่แก้ world
enum R { ONGOING, WON, LOST }

static func result(world : CombatWorld, boss_id : String) -> int:
	if not world.actors.has(boss_id):
		return R.ONGOING
	if world.actors[boss_id]["c"].state == Combatant.State.DEAD:
		return R.WON
	var active : int = 0
	for id in world.actors:
		var a : Dictionary = world.actors[id]
		if a["team"] == world.actors[boss_id]["team"] or a.get("parked", false):
			continue
		active += 1
		if a["c"].state != Combatant.State.DEAD:
			return R.ONGOING
	return R.LOST if active > 0 else R.ONGOING
