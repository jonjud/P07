extends Node2D

func _ready() -> void:
	CombatantTests.new().run_all()
	HitCheckTests.new().run_all()
	CombatWorldTests.new().run_all()
