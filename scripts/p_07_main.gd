extends Node2D

func _ready() -> void:
	CombatantTests.new().run_all()
	HitCheckTests.new().run_all()
	CombatWorldTests.new().run_all()
	EnemyTests.new().run_all()
	CombatDataTests.new().run_all()
	TelegraphViewTests.new().run_all()
	FeelTests.new().run_all()
	HitShapesTests.new().run_all()
	ArenaTests.new().run_all()
	BossTests.new().run_all()
	BossTelegraphViewTests.new().run_all()
	EncounterTests.new().run_all()
	RewardTests.new().run_all()
	CombatHostTests.new().run_all()
