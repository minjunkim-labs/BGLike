extends SceneTree
## CombatSelection의 조준·미리보기·실행 연결과 CombatActionRules 통합 규칙을 헤드리스로 검사한다.

const ScriptedDice = preload("res://tests/scripted_dice.gd")

var _failures: int = 0
var _checks: int = 0
var _created_units: Array[CombatUnit] = []


func _initialize() -> void:
	create_timer(30.0).timeout.connect(_on_timeout)
	_run.call_deferred()


func _on_timeout() -> void:
	push_error("Combat selection: test did not finish within 30 seconds")
	quit(1)


func _run() -> void:
	_test_action_rule_specs()
	await _test_self_target_and_stand_up()
	await _test_move_jump_and_moving_shot()
	await _test_unit_and_shove_targeting()
	await _test_facing_actions()
	await _test_aim_actions_and_snapping()
	await _test_prop_executor_and_occlusion()
	_test_floor_loot_and_reflex_preview()
	for unit: CombatUnit in _created_units:
		unit.free()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat selection: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _make_unit(kind: CombatUnit.Kind, is_ally: bool, cell: Vector2i) -> CombatUnit:
	var unit: CombatUnit = CombatUnit.new()
	unit.kind = kind
	unit.is_ally = is_ally
	unit.cell = cell
	unit.hit_points = unit.get_max_hit_points()
	unit.refill_turn_resources()
	_created_units.append(unit)
	return unit


func _setup(units: Array[CombatUnit], props: Array[CombatGrid.Prop] = [],
		trees: Array[Vector2i] = []) -> Dictionary:
	var turns: CombatTurns = CombatTurns.new()
	ScriptedDice.arrange_turns(turns, units, units)
	var actions: CombatActions = CombatActions.new()
	actions.initialize(units, turns)
	actions.grid.map_size = Vector2i(10, 10)
	actions.grid.props = props
	actions.grid.trees = trees
	actions.grid.blocked_cells = trees.duplicate()
	var selection: CombatSelection = CombatSelection.new()
	selection.bind(actions)
	return {"turns": turns, "grid": actions.grid, "actions": actions, "selection": selection}


func _test_action_rule_specs() -> void:
	var archer: CombatUnit = _make_unit(CombatUnit.Kind.ARCHER, true, Vector2i(1, 1))
	_check(CombatActionRules.target_mode("attack") == CombatActionRules.TargetMode.UNIT, "기본 공격은 UNIT 조준")
	_check(CombatActionRules.allows_prop_target("attack") and not CombatActionRules.allows_prop_target("shove"),
		"기본 공격만 환경 오브젝트 대상 허용")
	_check(CombatActionRules.allows_ally_target("shove") and not CombatActionRules.allows_ally_target("attack"),
		"밀치기만 아군 대상 허용")
	_check(CombatActionRules.is_self_target("holy_veil") and CombatActionRules.is_self_target("stealth"),
		"자기 대상 동작 분류")
	_check(CombatActionRules.is_facing_action("sweep") and CombatActionRules.is_facing_action("whistle"),
		"방향 동작 분류")
	_check(CombatActionRules.is_move_action("move") and CombatActionRules.is_move_action("jump")
		and CombatActionRules.is_move_action("moving_shot"), "이동 계열 동작 분류")
	_check(CombatActionRules.is_aim_action("oil_throw") and not CombatActionRules.aim_snaps_entity("oil_throw"),
		"기름병 던지기는 엔티티 스냅 없음")
	_check(CombatActionRules.is_aim_action("trick_arrow") and CombatActionRules.aim_snaps_entity("trick_arrow")
		and CombatActionRules.aim_radius("trick_arrow") < 0, "장난스러운 화살은 단일 칸·엔티티 스냅")
	_check(CombatActionRules.is_aim_action("firework_arrow") and CombatActionRules.aim_radius("firework_arrow") == 1
		and CombatActionRules.is_fire_action("firework_arrow"), "폭죽 화살은 반경 1·화염 속성")
	_check(CombatActionRules.aim_range(archer, "oil_throw") > 0 and CombatActionRules.aim_min_range("oil_throw") == 1,
		"기름병 던지기 사거리는 힘 기준·최소 1")
	_check(CombatActionRules.is_melee_action("bow_bash") and CombatActionRules.breaks_stealth("bow_bash"),
		"활 후려치기는 근접·은신 해제")


func _test_self_target_and_stand_up() -> void:
	var warrior: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, true, Vector2i(2, 2))
	var enemy: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, false, Vector2i(7, 7))
	var f: Dictionary = _setup([warrior, enemy])
	var selection: CombatSelection = f.selection
	var actions: CombatActions = f.actions
	actions.dice = ScriptedDice.new([6])
	_check(selection.choose_action(warrior, "holy_veil") and selection.selected_action == "holy_veil"
		and warrior.shield_points == 0, "자기 대상 첫 클릭은 선택만")
	_check(selection.choose_action(warrior, "holy_veil") and selection.selected_action == "attack"
		and warrior.shield_points > 0, "자기 대상 두 번째 클릭은 실행 후 기본 공격으로 복귀")
	_check(not selection.choose_action(warrior, "holy_veil"), "보조 행동이 없으면 선택 거부")
	warrior.fallen = true
	warrior.refill_turn_resources()
	_check(selection.choose_action(warrior, "stand_up") and not warrior.fallen, "일어나기는 즉시 실행")


func _test_move_jump_and_moving_shot() -> void:
	var archer: CombatUnit = _make_unit(CombatUnit.Kind.ARCHER, true, Vector2i(2, 2))
	var enemy: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, false, Vector2i(5, 2))
	var f: Dictionary = _setup([archer, enemy])
	var selection: CombatSelection = f.selection
	var actions: CombatActions = f.actions
	# 이동 2회 우클릭
	await selection.right_click_cell(archer, Vector2i(3, 2))
	var preview: CombatSelection.Preview = selection.build_preview(archer, [archer, enemy])
	_check(selection.selected_action == "move" and preview.path == [Vector2i(3, 2)] and preview.show_move_mode,
		"첫 우클릭은 이동 경로 미리보기")
	_check(enemy in preview.previewed_units, "도착 후 공격 가능한 적은 미리보기 대상에 포함")
	await selection.right_click_cell(archer, Vector2i(3, 2))
	_check(archer.cell == Vector2i(3, 2) and selection.selected_action == "attack", "같은 칸 재우클릭은 이동 확정")
	# 점프 미리보기 문구와 확정
	_check(selection.choose_action(archer, "jump"), "점프 선택")
	await selection.right_click_cell(archer, Vector2i(3, 4))
	var jump_preview: CombatSelection.Preview = selection.build_preview(archer, [archer, enemy])
	_check(not jump_preview.show_move_mode and jump_preview.target_note.contains("점프"), "점프 미리보기 안내 생성")
	await selection.right_click_cell(archer, Vector2i(3, 4))
	_check(archer.cell == Vector2i(3, 4) and selection.selected_action == "attack", "점프 재우클릭 확정")
	# 원거리 공격 후 무빙샷 자동 전환 및 도약
	actions.dice = ScriptedDice.new([18, 4])
	await selection.left_click_field(archer, enemy.cell, enemy)
	await selection.left_click_field(archer, enemy.cell, enemy)
	_check(selection.selected_action == "moving_shot" and archer.moving_shot_ready,
		"원거리 첫 공격 뒤 무빙샷 도약으로 자동 전환")
	var leap_cell: Vector2i = Vector2i(2, 4)
	await selection.right_click_cell(archer, leap_cell)
	await selection.right_click_cell(archer, leap_cell)
	_check(archer.cell == leap_cell and selection.selected_action == "attack", "무빙샷 도약 2회 우클릭 확정")


func _test_unit_and_shove_targeting() -> void:
	var warrior: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, true, Vector2i(2, 2))
	var ally: CombatUnit = _make_unit(CombatUnit.Kind.ARCHER, true, Vector2i(2, 3))
	var enemy: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, false, Vector2i(3, 2))
	var f: Dictionary = _setup([warrior, ally, enemy])
	var selection: CombatSelection = f.selection
	# 기본 공격으로 아군 클릭은 미리보기 비움
	await selection.left_click_field(warrior, enemy.cell, enemy)
	var atk_preview: CombatSelection.Preview = selection.build_preview(warrior, [warrior, ally, enemy])
	_check(atk_preview.attack_preview_target == enemy and atk_preview.attack_preview != null,
		"적 첫 좌클릭은 공격 미리보기")
	await selection.left_click_field(warrior, ally.cell, ally)
	_check(selection.preview_target == null, "기본 공격 중 아군 클릭은 미리보기 해제")
	# 밀치기는 아군 대상 허용 및 안내 문구 생성
	_check(selection.choose_action(warrior, "shove"), "밀치기 선택")
	await selection.left_click_field(warrior, ally.cell, ally)
	var shove_preview: CombatSelection.Preview = selection.build_preview(warrior, [warrior, ally, enemy])
	_check(shove_preview.attack_preview_target == ally and shove_preview.target_note.contains("밀려날 칸"),
		"밀치기 아군 미리보기 문구")
	await selection.left_click_field(warrior, ally.cell, ally)
	_check(ally.cell == Vector2i(2, 4) and selection.selected_action == "attack", "밀치기 재클릭으로 아군 밀침")


func _test_facing_actions() -> void:
	var warrior: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, true, Vector2i(4, 4))
	var enemy: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, false, Vector2i(5, 4))
	var f: Dictionary = _setup([warrior, enemy])
	var selection: CombatSelection = f.selection
	var actions: CombatActions = f.actions
	_check(selection.choose_action(warrior, "sweep"), "휩쓸기 선택")
	var initial_preview: CombatSelection.Preview = selection.build_preview(warrior, [warrior, enemy])
	_check(Vector2i(5, 4) in initial_preview.movement_cells and initial_preview.target_note.contains("정면"),
		"방향 선택 전 인접 칸과 안내 표시")
	await selection.left_click_field(warrior, Vector2i(5, 4), enemy, null, Vector2i(5, 4))
	var aimed_preview: CombatSelection.Preview = selection.build_preview(warrior, [warrior, enemy])
	_check(enemy in aimed_preview.previewed_units and aimed_preview.target_note.contains("시계방향 명중률"),
		"방향 첫 클릭은 영향 대상과 명중률 안내")
	actions.dice = ScriptedDice.new([20, 6])
	await selection.left_click_field(warrior, Vector2i(5, 4), enemy, null, Vector2i(5, 4))
	_check(enemy.hit_points < enemy.get_max_hit_points() and selection.selected_action == "attack",
		"방향 재클릭으로 휩쓸기 실행")


func _test_aim_actions_and_snapping() -> void:
	var archer: CombatUnit = _make_unit(CombatUnit.Kind.ARCHER, true, Vector2i(2, 2))
	var enemy: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, false, Vector2i(4, 2))
	var f: Dictionary = _setup([archer, enemy], [], [Vector2i(4, 3)])
	var selection: CombatSelection = f.selection
	var actions: CombatActions = f.actions
	# 기름병 던지기는 cell 그대로 사용 (target.cell로 스냅하지 않음)
	_check(selection.choose_action(archer, "oil_throw"), "기름병 던지기 선택")
	await selection.left_click_field(archer, Vector2i(4, 4), enemy)
	_check(selection.preview_cell == Vector2i(4, 4), "기름병 던지기는 클릭한 칸 유지")
	var oil_preview: CombatSelection.Preview = selection.build_preview(archer, [archer, enemy])
	_check(oil_preview.target_note.contains("십자 5칸 기름 3턴") and oil_preview.movement_cells.size() >= 4,
		"기름병 던지기 범위와 안내")
	# 장난스러운 화살은 target.cell로 스냅
	_check(selection.choose_action(archer, "trick_arrow"), "장난스러운 화살 선택")
	await selection.left_click_field(archer, Vector2i(1, 1), enemy)
	_check(selection.preview_cell == enemy.cell, "장난스러운 화살은 대상 몸통 칸으로 스냅")
	var trick_preview: CombatSelection.Preview = selection.build_preview(archer, [archer, enemy])
	_check(trick_preview.movement_cells == [enemy.cell] and trick_preview.target_note.contains("삐끗"),
		"장난스러운 화살 단일 칸 강조와 안내")
	actions.dice = ScriptedDice.new([4, 18])
	await selection.left_click_field(archer, Vector2i(1, 1), enemy)
	_check(enemy.hit_points < enemy.get_max_hit_points() and selection.selected_action == "moving_shot",
		"장난스러운 화살 재클릭 실행 뒤 무빙샷 도약으로 전환")


func _test_prop_executor_and_occlusion() -> void:
	var warrior: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, true, Vector2i(2, 2))
	var enemy: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, false, Vector2i(3, 2))
	var crate: CombatGrid.Prop = CombatGrid.Prop.new(Vector2i(2, 3), "crate")
	var f: Dictionary = _setup([warrior, enemy], [crate])
	var selection: CombatSelection = f.selection
	# 중단된 prop_executor(false 반환)는 새 세대의 selected_action을 덮어쓰지 않는다.
	var called: Array[int] = [0]
	selection.bind(f.actions, func(_actor: CombatUnit, _prop: CombatGrid.Prop) -> bool:
		called[0] += 1
		selection.selected_action = "move"
		return false)
	await selection.left_click_field(warrior, crate.cell, null, crate, Vector2i(-1, -1), true)
	var crate_preview: CombatSelection.Preview = selection.build_preview(warrior, [warrior, enemy])
	_check(crate_preview.preview_prop == crate and crate_preview.target_note.contains("나무 상자"),
		"상자 첫 클릭은 미리보기와 피해 범위 안내")
	await selection.left_click_field(warrior, crate.cell, null, crate, Vector2i(-1, -1), true)
	_check(called[0] == 1 and selection.selected_action == "move",
		"prop_executor가 false면 finish_execution으로 새 세대 선택을 덮지 않음")
	# 가려진 적은 앞 사물보다 우선 선택
	selection.reset()
	enemy.is_occluded = true
	await selection.left_click_field(warrior, crate.cell, enemy, crate, Vector2i(-1, -1), true)
	_check(selection.preview_target == enemy and selection.preview_prop == null,
		"윤곽이 보이는 가린 적은 앞 사물보다 우선 선택")


func _test_floor_loot_and_reflex_preview() -> void:
	var archer: CombatUnit = _make_unit(CombatUnit.Kind.ARCHER, true, Vector2i(2, 2))
	var enemy: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, false, Vector2i(6, 6))
	var f: Dictionary = _setup([archer, enemy])
	var selection: CombatSelection = f.selection
	var actions: CombatActions = f.actions
	actions.floor_loot.drops[Vector2i(4, 4)] = {"id": "healing_potion", "kind": "potion", "name": "회복 물약", "stats": {}}
	var hover_preview: CombatSelection.Preview = selection.build_preview(archer, [archer, enemy], Vector2i(4, 4))
	_check(hover_preview.target_note.contains("바닥 아이템") and not hover_preview.show_move_mode,
		"기본 공격 상태에서 바닥 아이템 호버 안내 표시")
	selection.choose_action(archer, "trick_arrow")
	var aim_preview: CombatSelection.Preview = selection.build_preview(archer, [archer, enemy], Vector2i(4, 4))
	_check(not aim_preview.target_note.contains("바닥 아이템"), "칸 조준 중에는 바닥 아이템 안내 숨김")
	# 반사신경 대기 중에는 회피 후보 칸으로 이동 강조를 덮어쓴다.
	actions.pending_kind = "reflex"
	actions.pending_reactor = archer
	actions.pending_cells = [Vector2i(2, 1), Vector2i(1, 2)]
	var reflex_preview: CombatSelection.Preview = selection.build_preview(archer, [archer, enemy])
	_check(reflex_preview.movement_cells == [Vector2i(2, 1), Vector2i(1, 2)] and reflex_preview.origin == archer.cell,
		"반사신경 대기 중에는 회피 후보 칸을 강조")
