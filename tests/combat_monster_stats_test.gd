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
	_test_spiderling_cap()
	await _test_boss_oil_immunity()
	await _test_poison_tick_damage()
	await _test_poison_tooltip()
	await _test_act2_stage1_spiderling_movement()
	var dice_problems: Array[String] = ScriptedDice.finish()
	for problem: String in dice_problems:
		_check(false, "주사위 기대와 다름: " + problem)
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
			unit.get_defense_bonus(), CombatGrounds.SLIP_DC, CombatChecks.RollMode.NORMAL)
		_check(is_equal_approx(chance, pair[1]), "%s 미끌거림 버팀 %.3f (실제 %.3f)" % [unit.get_display_name(), pair[1], chance])


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
	actions.initialize(units, turns)
	ScriptedDice.arrange_turns(turns, units, units)
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
	actions.dice = ScriptedDice.new([1], [4])
	_check(actions.spawn_spiderling(mother) and actions.living_spiderling_count() == 10
		and not actions.can_use(mother, "spawn"), "1마리 전투 불능 뒤 다시 새끼를 낳으면 10마리로 상한 도달")
	for unit: CombatUnit in ten.units:
		if is_instance_valid(unit) and unit not in _created:
			_created.append(unit)
	nine.turns.turn_started.disconnect(nine.actions._on_turn_started)
	ten.turns.turn_started.disconnect(ten.actions._on_turn_started)


## 고철로봇 1000/2000/3000은 기름 칸에 들어가거나 떠날 때 미끌거림 굴림 없이 넘어짐 면역이다.
func _test_boss_oil_immunity() -> void:
	for boss_kind: CombatUnit.Kind in [CombatUnit.Kind.SCRAP_ROBOT_1000,
			CombatUnit.Kind.SCRAP_ROBOT_2000, CombatUnit.Kind.SCRAP_ROBOT_3000]:
		var fixture: Dictionary = _fixture(0)
		var actions: CombatActions = fixture.actions
		var turns: CombatTurns = fixture.turns
		var boss: CombatUnit = fixture.mother
		boss.kind = boss_kind
		boss.hit_points = boss.get_max_hit_points()
		boss.cell = Vector2i(5, 6)
		actions.grounds.add(fixture.units[0], Vector2i(6, 6), "oil")
		actions.dice = ScriptedDice.new([], [])
		var entered: bool = await actions.move_to(boss, Vector2i(6, 6))
		_check(entered and boss.cell == Vector2i(6, 6) and not boss.fallen and not boss.oil_slipped,
			"%s는 기름 칸에 들어가도 굴림 없이 넘어짐 면역" % boss.get_display_name())
		_check(actions.slip_note(boss, [Vector2i(7, 6)]).is_empty(),
			"%s의 기름 이동 미리보기에는 미끌거림 안내가 없음" % boss.get_display_name())
		var left: bool = await actions.move_to(boss, Vector2i(7, 6))
		_check(left and boss.cell == Vector2i(7, 6) and not boss.fallen and not boss.oil_slipped,
			"%s는 기름 칸을 떠나도 굴림 없이 넘어짐 면역" % boss.get_display_name())
		turns.turn_started.disconnect(actions._on_turn_started)


## 독안개에서 부여된 독 중첩 1개당 대상 턴 시작 피해는 3이다.
func _test_poison_tick_damage() -> void:
	# 독안개에서 부여된 독 중첩 1개의 턴 시작 피해 = 3.
	var fog_warrior: CombatUnit = CombatUnit.new()
	fog_warrior.kind = CombatUnit.Kind.WARRIOR
	fog_warrior.is_ally = true
	fog_warrior.cell = Vector2i(1, 1)
	fog_warrior.hit_points = fog_warrior.get_max_hit_points()
	var fog_spider: CombatUnit = _enemy(CombatUnit.Kind.FOG_SPIDER, Vector2i(5, 1))
	_created.append(fog_warrior)
	var fog_units: Array[CombatUnit] = [fog_warrior, fog_spider]
	var f_turns: CombatTurns = CombatTurns.new()
	var f_actions: CombatActions = CombatActions.new()
	f_actions.initialize(fog_units, f_turns)
	ScriptedDice.arrange_turns(f_turns, fog_units, [fog_spider, fog_warrior])
	f_actions.dice = ScriptedDice.new([1], [12])
	_check(f_actions.cast_fog(fog_spider, Vector2i(1, 1)) and fog_warrior.get_status_count("poison") == 1,
		"독안개 시전으로 독 1중첩 부여")
	f_actions.dice = ScriptedDice.new([12, 1], [12, 12])
	f_turns.end_turn()
	_check(f_turns.current_unit == fog_warrior and fog_warrior.hit_points == fog_warrior.get_max_hit_points() - 3,
		"독안개 독 1중첩의 턴 시작 피해는 3 (실제 HP %d / %d)" % [fog_warrior.hit_points, fog_warrior.get_max_hit_points()])
	f_turns.turn_started.disconnect(f_actions._on_turn_started)


func _test_poison_tooltip() -> void:
	var main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	battle.call("start_battle")
	var units: Array[CombatUnit] = battle.get("units")
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var ally: CombatUnit = units[0]
	ally.status_effects.append(CombatUnit.StatusEffect.new("poison", units[2], 4, CombatGrounds.POISON_DC))
	hud.show_unit(ally)
	await process_frame
	var poison_buttons: Array[Button] = hud.status_buttons().filter(
		func(button: Button) -> bool: return button.text == "독1")
	_check(poison_buttons.size() == 1 and "중첩당 피해 3." in poison_buttons[0].tooltip_text,
		"독 상태 호버 툴팁은 상향된 틱 피해 3을 표시한다: %s" % ["" if poison_buttons.is_empty() else poison_buttons[0].tooltip_text])
	main.queue_free()
	await process_frame


## 실제 2-1에서 새끼 거미 이동력 12와 새 배치가 아군 첫 턴 위협을 만들고, 엄마 거미는 첫 턴에 닿지 않음을 확인한다.
func _test_act2_stage1_spiderling_movement() -> void:
	var main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	battle.call("start_battle")
	(battle.get("progress") as CombatActProgress).stage_index = 3
	battle.call("_start_stage", true)
	battle.call("start_battle")
	var actions: CombatActions = battle.get("actions") as CombatActions
	var party: Array[CombatUnit] = battle.get("party")
	var units: Array[CombatUnit] = battle.get("units")
	var spiderling_reach_count: int = 0
	var mother_reaches: bool = false
	for unit: CombatUnit in units:
		if unit.is_ally:
			continue
		var reach: Dictionary[Vector2i, int] = actions.grid.reachable_cells(unit)
		var cells: Array[Vector2i] = [unit.cell]
		cells.append_array(reach.keys())
		var hits_ally: bool = cells.any(func(cell: Vector2i) -> bool:
			return party.any(func(ally: CombatUnit) -> bool:
				return actions.grid.can_target(unit, ally, "attack", cell)))
		if unit.kind == CombatUnit.Kind.SPIDERLING and hits_ally:
			spiderling_reach_count += 1
		elif unit.kind == CombatUnit.Kind.MOTHER_SPIDER:
			mother_reaches = hits_ally
	_check(spiderling_reach_count > 0 and not mother_reaches,
		"2-1 실수치(새끼 이동력 12)에서 새끼 거미는 첫 턴 위협에 닿고 엄마 거미는 닿지 않음 (%d마리 도달)" % spiderling_reach_count)
	main.queue_free()
	await process_frame
