extends SceneTree
## CombatSelection 심화 interface 헤드리스 검사(#771): 2클릭 확정, 명령 반환, 미리보기 스냅샷, 엄폐·바닥 아이템 호버.

class Fixture extends RefCounted:
	var units: Array[CombatUnit] = []
	var turns: CombatTurns = CombatTurns.new()
	var actions: CombatActions = CombatActions.new()
	var selection: CombatSelection = CombatSelection.new()


const ScriptedDice = preload("res://tests/scripted_dice.gd")

var _checks: int = 0
var _failures: int = 0
var _created: Array[CombatUnit] = []


func _initialize() -> void:
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("Combat selection: test timeout")
		quit(1)
	)
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _fixture() -> Fixture:
	var f: Fixture = Fixture.new()
	var specs: Array[Array] = [
		[CombatUnit.Kind.WARRIOR, true, Vector2i(3, 4)],
		[CombatUnit.Kind.ARCHER, true, Vector2i(3, 6)],
		[CombatUnit.Kind.WARRIOR, false, Vector2i(4, 4)],
		[CombatUnit.Kind.ARCHER, false, Vector2i(7, 6)]
	]
	for spec: Array in specs:
		var unit: CombatUnit = CombatUnit.new()
		unit.kind = spec[0]
		unit.is_ally = spec[1]
		unit.cell = spec[2]
		unit.hit_points = unit.get_max_hit_points()
		f.units.append(unit)
		_created.append(unit)
	ScriptedDice.arrange_turns(f.turns, f.units, f.units)
	f.actions.initialize(f.units, f.turns)
	return f


func _run() -> void:
	_test_target_mode_classification()
	_test_self_action_two_click()
	_test_move_and_jump_preview_and_confirm()
	_test_target_unit_and_shove_preview()
	_test_aim_and_facing_commands()
	_test_cover_blocking_and_hover()
	_test_floor_loot_hover_priority()
	_test_prop_preview_and_confirm()
	_test_inspection_and_reset_invariants()
	for unit: CombatUnit in _created:
		unit.free()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat selection: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_target_mode_classification() -> void:
	_check(CombatActionRules.target_mode("attack") == CombatActionRules.TargetMode.TARGET_UNIT, "기본 공격은 TARGET_UNIT")
	_check(CombatActionRules.target_mode("shove") == CombatActionRules.TargetMode.TARGET_UNIT, "밀치기는 TARGET_UNIT")
	_check(CombatActionRules.target_mode("oil_throw") == CombatActionRules.TargetMode.AIM_CELL, "기름병 던지기는 AIM_CELL")
	_check(CombatActionRules.target_mode("firework_arrow") == CombatActionRules.TargetMode.AIM_CELL, "폭죽 화살은 AIM_CELL")
	_check(CombatActionRules.target_mode("sweep") == CombatActionRules.TargetMode.FACING, "휩쓸기는 FACING")
	_check(CombatActionRules.target_mode("whistle") == CombatActionRules.TargetMode.FACING, "효시는 FACING")
	_check(CombatActionRules.target_mode("holy_veil") == CombatActionRules.TargetMode.SELF, "성스러운 장막은 SELF")
	_check(CombatActionRules.target_mode("jump") == CombatActionRules.TargetMode.MOVE, "점프는 MOVE")
	_check(CombatActionRules.target_mode("moving_shot") == CombatActionRules.TargetMode.MOVE, "무빙샷은 MOVE")


func _test_self_action_two_click() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	var first: CombatSelection.Command = f.selection.choose_action(warrior, f.actions, "holy_veil")
	_check(first.is_empty() and f.selection.selected_action == "holy_veil", "자기 대상 동작 첫 선택은 대기")
	var second: CombatSelection.Command = f.selection.choose_action(warrior, f.actions, "holy_veil")
	_check(second.kind == CombatSelection.Command.Kind.SELF and second.action == "holy_veil",
		"자기 대상 동작 재선택은 SELF 명령 반환")
	f.selection.finish_execution()
	_check(f.selection.selected_action == "attack", "실행 완료 후 기본 공격으로 복귀")


func _test_move_and_jump_preview_and_confirm() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	var dest: Vector2i = Vector2i(2, 4)
	f.actions.grid.water_cells.append(dest)
	var first: CombatSelection.Command = f.selection.choose_move(warrior, f.actions, dest)
	_check(first.is_empty() and f.selection.selected_action == "move" and f.selection.preview_cell == dest,
		"이동 첫 우클릭은 경로 미리보기")
	var preview: CombatSelection.Preview = f.selection.build_preview(warrior, f.actions, f.units)
	_check(not preview.show_move_mode and "물:" in preview.target_note,
		"물 칸 도착 미리보기는 안내 표시를 켜고 물 규칙을 적는다: " + preview.target_note)
	var second: CombatSelection.Command = f.selection.choose_move(warrior, f.actions, dest)
	_check(second.kind == CombatSelection.Command.Kind.MOVE and second.cell == dest
		and f.selection.preview_path.is_empty(), "같은 칸 재우클릭은 MOVE 명령 반환 후 미리보기 해제")

	f.selection.choose_action(warrior, f.actions, "jump")
	var jump_preview: CombatSelection.Preview = f.selection.build_preview(warrior, f.actions, f.units)
	_check(not jump_preview.show_move_mode and "점프" in jump_preview.target_note and not jump_preview.movement_cells.is_empty(),
		"점프 선택 시 착지 후보 칸과 사용 안내가 스냅샷에 담긴다")
	var jump_cell: Vector2i = jump_preview.movement_cells[0]
	var jump_first: CombatSelection.Command = f.selection.choose_move(warrior, f.actions, jump_cell)
	_check(jump_first.is_empty() and f.selection.preview_cell == jump_cell, "점프 첫 우클릭은 착지 미리보기")
	var jump_second: CombatSelection.Command = f.selection.choose_move(warrior, f.actions, jump_cell)
	_check(jump_second.kind == CombatSelection.Command.Kind.JUMP and jump_second.cell == jump_cell,
		"점프 재우클릭은 JUMP 명령 반환")


func _test_target_unit_and_shove_preview() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	var ally: CombatUnit = f.units[1]
	var enemy: CombatUnit = f.units[2]
	var ally_cmd: CombatSelection.Command = f.selection.choose_unit(warrior, f.actions, ally)
	_check(ally_cmd.is_empty() and f.selection.preview_target == null, "기본 공격은 아군을 미리보기 대상으로 삼지 않음")
	var first: CombatSelection.Command = f.selection.choose_unit(warrior, f.actions, enemy)
	_check(first.is_empty() and f.selection.preview_target == enemy, "적 첫 좌클릭은 대상 미리보기")
	var preview: CombatSelection.Preview = f.selection.build_preview(warrior, f.actions, f.units)
	_check(preview.preview_target == enemy and preview.attack_preview != null and enemy in preview.previewed_units,
		"대상 미리보기 스냅샷에 명중 예측과 강조 대상이 담긴다")
	var second: CombatSelection.Command = f.selection.choose_unit(warrior, f.actions, enemy)
	_check(second.kind == CombatSelection.Command.Kind.TARGET and second.action == "attack" and second.target == enemy,
		"적 재좌클릭은 TARGET 명령 반환")

	f.selection.choose_action(warrior, f.actions, "shove")
	f.selection.choose_unit(warrior, f.actions, enemy)
	var shove_preview: CombatSelection.Preview = f.selection.build_preview(warrior, f.actions, f.units)
	_check("밀려날 칸:" in shove_preview.target_note and "밀칠 확률" in shove_preview.target_note,
		"밀치기 미리보기 안내에 도착 칸과 확률이 담긴다: " + shove_preview.target_note)


func _test_aim_and_facing_commands() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	f.selection.choose_action(warrior, f.actions, "sweep")
	var before_face: CombatSelection.Preview = f.selection.build_preview(warrior, f.actions, f.units)
	_check(not before_face.movement_cells.is_empty() and "휩쓸기" in before_face.target_note,
		"휩쓸기 방향 선택 전에는 인접 칸과 안내를 보인다")
	var face_cell: Vector2i = Vector2i(4, 4)
	var face_first: CombatSelection.Command = f.selection.choose_facing(warrior, f.actions, face_cell)
	_check(face_first.is_empty() and f.selection.preview_cell == face_cell, "휩쓸기 첫 좌클릭은 방향 미리보기")
	var face_preview: CombatSelection.Preview = f.selection.build_preview(warrior, f.actions, f.units)
	_check(f.units[2] in face_preview.previewed_units and "시계방향 명중률" in face_preview.target_note,
		"휩쓸기 방향 미리보기에 대상과 명중률이 담긴다")
	var face_second: CombatSelection.Command = f.selection.choose_facing(warrior, f.actions, face_cell)
	_check(face_second.kind == CombatSelection.Command.Kind.FACING and face_second.action == "sweep"
		and face_second.cell == face_cell, "휩쓸기 재좌클릭은 FACING 명령 반환")

	f.selection.finish_execution()
	var archer: CombatUnit = f.units[1]
	f.turns.select_unit(archer)
	f.selection.choose_action(archer, f.actions, "trick_arrow")
	var aim_cell: Vector2i = Vector2i(5, 6)
	var aim_first: CombatSelection.Command = f.selection.choose_aim(archer, f.actions, aim_cell)
	_check(aim_first.is_empty() and f.selection.preview_cell == aim_cell, "장난스러운 화살 첫 클릭은 칸 미리보기")
	var aim_preview: CombatSelection.Preview = f.selection.build_preview(archer, f.actions, f.units)
	_check(aim_preview.movement_cells == [aim_cell] and "장난스러운 화살" in aim_preview.target_note,
		"장난스러운 화살 스냅샷에 목표 칸과 확률 안내가 담긴다")
	var aim_second: CombatSelection.Command = f.selection.choose_aim(archer, f.actions, aim_cell)
	_check(aim_second.kind == CombatSelection.Command.Kind.AIM and aim_second.action == "trick_arrow"
		and aim_second.cell == aim_cell, "장난스러운 화살 재클릭은 AIM 명령 반환")


func _test_cover_blocking_and_hover() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[1]
	var far_enemy: CombatUnit = f.units[3]
	f.turns.select_unit(archer)
	# (3,6) 궁수와 (7,6) 적 사이에 높이 2 지형으로 완전 엄폐를 만든다.
	f.actions.grid.heights[Vector2i(5, 6)] = 2
	var hover: CombatSelection.CoverHover = f.selection.evaluate_cover_hover(archer, f.actions, f.units, far_enemy, null)
	_check(hover.active and hover.result != null and hover.result.blocked,
		"직사 기본 공격 호버 시 엄폐 차단 판정을 돌려준다")
	var preview: CombatSelection.Preview = f.selection.build_preview(archer, f.actions, f.units)
	_check(preview.direct_fire and far_enemy in preview.blocked_units,
		"미리보기 스냅샷에 엄폐로 막힌 적이 기록된다")
	var blocked_cmd: CombatSelection.Command = f.selection.choose_unit(archer, f.actions, far_enemy)
	_check(blocked_cmd.is_empty() and f.selection.preview_target == null,
		"엄폐로 막힌 적은 클릭해도 미리보기·실행되지 않는다")


func _test_floor_loot_hover_priority() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	var loot_cell: Vector2i = Vector2i(2, 5)
	f.actions.floor_loot.drop(loot_cell, {"id": "healing_potion", "kind": "potion", "name": "회복 물약", "stats": {}})
	var changed: bool = f.selection.set_hover_cell(loot_cell, f.actions)
	_check(changed, "바닥 아이템 칸에 마우스가 올라가면 갱신 필요를 알린다")
	var preview: CombatSelection.Preview = f.selection.build_preview(warrior, f.actions, f.units)
	_check("바닥 아이템 ·" in preview.target_note and not preview.show_move_mode,
		"다른 미리보기가 없을 때 바닥 아이템 안내를 보인다: " + preview.target_note)
	f.selection.choose_action(warrior, f.actions, "jump")
	var jump_preview: CombatSelection.Preview = f.selection.build_preview(warrior, f.actions, f.units)
	_check("점프" in jump_preview.target_note and "바닥 아이템" not in jump_preview.target_note,
		"점프 모드에서는 바닥 아이템 안내가 점프 안내를 덮어쓰지 않는다")


func _test_prop_preview_and_confirm() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	var crate: CombatGrid.Prop = CombatGrid.Prop.new(Vector2i(3, 5), "crate")
	f.actions.grid.props.append(crate)
	var first: CombatSelection.Command = f.selection.choose_prop(warrior, f.actions, crate)
	_check(first.is_empty() and f.selection.preview_prop == crate, "상자 첫 좌클릭은 미리보기")
	var preview: CombatSelection.Preview = f.selection.build_preview(warrior, f.actions, f.units)
	_check(preview.preview_prop == crate and "나무 상자" in preview.target_note and "자동 명중" in preview.target_note,
		"상자 미리보기 스냅샷에 내구도와 피해 범위 안내가 담긴다")
	var second: CombatSelection.Command = f.selection.choose_prop(warrior, f.actions, crate)
	_check(second.kind == CombatSelection.Command.Kind.PROP and second.prop == crate,
		"상자 재좌클릭은 PROP 명령 반환")


func _test_inspection_and_reset_invariants() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	var enemy: CombatUnit = f.units[2]
	f.selection.choose_move(warrior, f.actions, Vector2i(2, 4))
	f.selection.choose_move(warrior, f.actions, Vector2i(9, 9))
	_check(f.selection.selected_action == "move" and f.selection.preview_path.is_empty(),
		"유효하지 않은 목적지 우클릭은 이동 경로만 취소")
	f.selection.begin_field_input(true)
	_check(f.selection.selected_action == "attack", "좌클릭 시작 시 이동 모드에서 기본 공격으로 복귀")
	f.selection.choose_move(warrior, f.actions, Vector2i(2, 4))
	f.selection.inspect(enemy)
	_check(f.selection.selected_action == "attack" and f.selection.preview_path.is_empty()
		and f.selection.inspected_unit == enemy, "초상 조회는 이동·대상 미리보기를 취소")
	enemy.hit_points = 0
	var after_down: CombatSelection.Preview = f.selection.build_preview(warrior, f.actions, f.units)
	_check(f.selection.inspected_unit == null and after_down.inspected_unit == null,
		"전투 불능 유닛 조회는 스냅샷 계산 시 자동 해제")
	f.selection.choose_action(warrior, f.actions, "shove")
	f.selection.preview_unit(f.units[3])
	f.selection.reset()
	_check(f.selection.selected_action == "attack" and f.selection.preview_target == null
		and f.selection.preview_path.is_empty() and f.selection.inspected_unit == null,
		"reset은 선택·미리보기·조회 전체를 초기화")
