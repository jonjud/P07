extends RefCounted
class_name EncounterTests

var passed : int = 0
var failed : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func w() -> CombatWorld:
	var cw : CombatWorld = CombatWorld.new(CombatParams.new())
	cw.add_actor("boss", 200, Vector2.ZERO, 40.0, 1)
	cw.add_actor("p1", 100, Vector2(100, 0), 12.0, 0)
	cw.add_actor("p2", 100, Vector2(-100, 0), 12.0, 0)
	return cw

func run_all() -> void:
	var cw : CombatWorld = w()
	t("ongoing", EncounterState.result(cw, "boss") == EncounterState.R.ONGOING)
	cw.actors["p1"]["c"].apply_damage(100, 0.0)
	t("one player dead: ongoing", EncounterState.result(cw, "boss") == EncounterState.R.ONGOING)
	cw.actors["p2"]["c"].apply_damage(100, 0.0)
	t("all players dead: lost", EncounterState.result(cw, "boss") == EncounterState.R.LOST)
	var c2 : CombatWorld = w()
	c2.actors["boss"]["c"].apply_damage(200, 0.0)
	t("boss dead: won", EncounterState.result(c2, "boss") == EncounterState.R.WON)
	c2.actors["p1"]["c"].apply_damage(100, 0.0)
	c2.actors["p2"]["c"].apply_damage(100, 0.0)
	t("both dead: won wins", EncounterState.result(c2, "boss") == EncounterState.R.WON)
	t("unknown boss: ongoing", EncounterState.result(cw, "ghost") == EncounterState.R.ONGOING)
	var solo : CombatWorld = CombatWorld.new(CombatParams.new())
	solo.add_actor("boss", 10, Vector2.ZERO, 40.0, 1)
	t("no players: ongoing", EncounterState.result(solo, "boss") == EncounterState.R.ONGOING)
	# reset: world ใหม่ + brain ใหม่ สะอาด
	var d : BossData = BossData.grove()
	var r : CombatWorld = CombatWorld.new(CombatParams.new())
	r.add_actor("boss", d.max_hp, Vector2.ZERO, d.radius, 1)
	r.add_actor("p1", 100, Vector2(80, 0), 12.0, 0)
	var b : BossBrain = BossBrain.new("boss", d)
	b.engaged = true
	b.step(0.0, r)
	b.step(0.7, r)
	r.actors["boss"]["c"].apply_damage(d.max_hp, 1.0)
	b.step(1.1, r)
	t("brain done after boss dies", b.state == BossBrain.S.DONE)
	var r2 : CombatWorld = CombatWorld.new(CombatParams.new())
	r2.add_actor("boss", d.max_hp, Vector2.ZERO, d.radius, 1)
	r2.add_actor("p1", 100, Vector2(80, 0), 12.0, 0)
	var b2 : BossBrain = BossBrain.new("boss", d)
	t("fresh encounter clean", b2.state == BossBrain.S.IDLE and not b2.engaged and b2.seq_pos == 0 and r2.hp_of("boss") == d.max_hp and EncounterState.result(r2, "boss") == EncounterState.R.ONGOING)
	print("Encounter: Passed ", passed, " / Failed ", failed)
