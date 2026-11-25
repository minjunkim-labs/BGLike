extends SceneTree
## 실제 몬스터 수치와 #702의 규칙 변경(새끼 거미 상한, 보스 기름 면역, 독 틱 피해)을 검사한다.
## 다른 검사는 MonsterBaseline으로 튜닝 이전 값을 가정하므로, 지금 쓰는 값은 이 파일만 확인한다.
## 값의 근거는 docs/planning/monster-tuning-draft-2026-11.md 9장이다.

const ScriptedDice = preload("res://tests/scripted_dice.gd")

var _checks: int = 0
var _failures: int = 0
var _created: Array[CombatUnit] = []


func _initialize() -> void:
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("Combat monster stats: test timeout")
		quit(1)
	)
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	_test_stat_table()
	_test_overload_thresholds()
	_test_slip_chances()
	_test_rule_constants()
	_test_boss_oil_immunity()
	_test_spiderling_cap()
	for unit: CombatUnit in _created:
		if is_instance_valid(unit):
			unit.free()
	print("Combat monster stats: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _enemy(kind: CombatUnit.Kind, cell: Vector2i = Vector2i.ZERO) -> CombatUnit:
	var unit: CombatUnit = CombatUnit.new()
	unit.kind = kind
	unit.is_ally = false
	unit.cell = cell
	unit.hit_points = unit.get_max_hit_points()
	_created.append(unit)
	return unit


func _sides(unit: CombatUnit) -> Array[int]:
	var sides: Array[int] = []
	for ability: CombatUnit.Ability in CombatUnit.Ability.values():
		sides.append(unit.get_ability_sides(ability))
	return sides


## 몬스터마다 [종류, HP, AC, 공격 가산, 피해 보정, 이동력, 능력치 주사위(힘·민첩·솜씨·지능·의지·건강)].
func _test_stat_table() -> void:
	var table: Array = [
		[CombatUnit.Kind.SPIDERLING, 1, 4, 3, 4, 12, [4, 4, 8, 4, 4, 4]],
		[CombatUnit.Kind.WARRIOR, 44, 7, 3, 6, 8, [10, 6, 8, 4, 4, 4]],
		[CombatUnit.Kind.ARCHER, 28, 7, 2, 6, 8, [4, 10, 8, 4, 4, 4]],
		[CombatUnit.Kind.MOTHER_SPIDER, 40, 6, 3, 7, 6, [8, 6, 8, 4, 6, 8]],
		[CombatUnit.Kind.FOG_SPIDER, 24, 5, 3, 6, 6, [6, 6, 8, 4, 4, 8]],
		[CombatUnit.Kind.SCRAP_ROBOT_1000, 160, 6, 3, 8, 6, [12, 4, 8, 4, 12, 4]],
		[CombatUnit.Kind.SCRAP_ROBOT_2000, 180, 7, 3, 8, 6, [12, 4, 8, 4, 12, 4]],
		[CombatUnit.Kind.SCRAP_ROBOT_3000, 200, 8, 3, 8, 6, [12, 4, 8, 4, 12, 4]],
	]
	for row: Array in table:
		var unit: CombatUnit = _enemy(row[0])
		var label: String = unit.get_display_name()
		_check(unit.get_max_hit_points() == row[1] and unit.hit_points == row[1], "%s HP %d" % [label, row[1]])
		_check(unit.get_armor_class() == row[2], "%s AC %d (실제 %d)" % [label, row[2], unit.get_armor_class()])
		_check(unit.get_attack_bonus() == row[3], "%s 공격 가산 %d" % [label, row[3]])
		_check(unit.get_damage_bonus() == row[4], "%s 피해 보정 %d" % [label, row[4]])
		_check(unit.get_movement() == row[5], "%s 이동력 %d (실제 %d)" % [label, row[5], unit.get_movement()])
		_check(_sides(unit) == Array(row[6], TYPE_INT, "", null), "%s 능력치 주사위 %s (실제 %s)" % [label, row[6], _sides(unit)])


## 과부하는 최대 HP의 절반 이하에서 켜진다. 값 80·90·100.
func _test_overload_thresholds() -> void:
	for pair: Array in [[CombatUnit.Kind.SCRAP_ROBOT_1000, 80], [CombatUnit.Kind.SCRAP_ROBOT_2000, 90],
			[CombatUnit.Kind.SCRAP_ROBOT_3000, 100]]:
		var boss: CombatUnit = _enemy(pair[0])
		_check(boss.is_boss() and boss.overload_threshold() == pair[1], "%s 과부하 기준 HP %d" % [boss.get_display_name(), pair[1]])


## 기름 미끌거림 버팀 확률(DC 4). 일반 몬스터는 솜씨 d8이라 62.5%, 엄마 거미는 방어 가산 +1로 75%다.
func _test_slip_chances() -> void:
	for pair: Array in [[CombatUnit.Kind.SPIDERLING, 0.625], [CombatUnit.Kind.WARRIOR, 0.625],
			[CombatUnit.Kind.ARCHER, 0.625], [CombatUnit.Kind.FOG_SPIDER, 0.625], [CombatUnit.Kind.MOTHER_SPIDER, 0.75]]:
		var unit: CombatUnit = _enemy(pair[0])
		var chance: float = CombatChecks.save_chance(unit.get_ability_sides(CombatUnit.Ability.FINESSE),
			unit.get_defense_bonus(), CombatOil.SLIP_DC, CombatChecks.RollMode.NORMAL)
		_check(is_equal_approx(chance, pair[1]), "%s 미끌거림 버팀 %.3f (실제 %.3f)" % [unit.get_display_name(), pair[1], chance])


func _test_rule_constants() -> void:
	_check(CombatActionRules.poison_tick_damage == 3, "독 중첩 하나의 틱 피해는 3")
	_check(CombatActionRules.MAX_SPIDERLINGS == 10, "맵 전체 새끼 거미 상한은 10")


func _fixture(extra_spiderlings: int) -> Dictionary:
	var units: Array[CombatUnit] = []
	for index: int in range(2):
		var ally: CombatUnit = CombatUnit.new()
		ally.kind = CombatUnit.Kind.WARRIOR if index == 0 else CombatUnit.Kind.ARCHER
		ally.is_ally = true
		ally.cell = [Vector2i(1, 1), Vector2i(1, 3)][index]
		ally.hit_points = ally.get_max_hit_points()
		_created.append(ally)
		units.append(ally)
	var mother: CombatUnit = _enemy(CombatUnit.Kind.MOTHER_SPIDER, Vector2i(6, 6))
	units.append(mother)
	for index: int in range(extra_spiderlings):
		units.append(_enemy(CombatUnit.Kind.SPIDERLING, Vector2i(9 + index % 4, 2 + index / 4 * 2)))
	var turns: CombatTurns = CombatTurns.new()
	var actions: CombatActions = CombatActions.new()
	ScriptedDice.arrange_turns(turns, units, units)
	actions.initialize(units, turns)
	turns.end_turn()
	turns.end_turn()
	return {"units": units, "turns": turns, "actions": actions, "mother": mother}


func _test_spiderling_cap() -> void:
	var nine: Dictionary = _fixture(9)
	var actions: CombatActions = nine.actions
	var mother: CombatUnit = nine.mother
	_check(nine.turns.current_unit == mother and actions.living_spiderling_count() == 9
		and actions.can_use(mother, "spawn"), "새끼 거미 9마리면 엄마 거미는 새끼를 낳을 수 있음")
	var ten: Dictionary = _fixture(10)
	actions = ten.actions
	mother = ten.mother
	_check(ten.turns.current_unit == mother and actions.living_spiderling_count() == 10
		and not actions.can_use(mother, "spawn") and not actions.spawn_spiderling(mother)
		and mother.action_left == 1 and ten.units.size() == 13, "새끼 거미가 10마리면 낳지 못하고 행동을 쓰지 않음")
	(ten.units[3] as CombatUnit).hit_points = 0
	_check(actions.living_spiderling_count() == 9 and actions.can_use(mother, "spawn"),
		"전투 불능인 새끼 거미는 상한에 세지 않음")


func _test_boss_oil_immunity() -> void:
	var fixture: Dictionary = _fixture(0)
	var actions: CombatActions = fixture.actions
	var boss: CombatUnit = fixture.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	boss.hit_points = boss.get_max_hit_points()
	_check(actions.call("_slip_roll", boss) == true and not boss.fallen and not boss.oil_slipped,
		"보스는 기름 미끌거림에 굴림 없이 면역")
