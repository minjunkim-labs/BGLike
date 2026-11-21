extends SceneTree
## 은/엄폐(#358) 회귀 검사: cover.md 4-2 테스트 케이스 20개, 갱신, 곡사 예외, 적 원거리 AI 5기준, UI 미리보기, 9개 스테이지 배치.

var failures: int = 0
var checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_cover_20_cases()
	_test_prop_target_and_dynamic_updates()
	_test_direct_vs_indirect_actions()
	await _test_enemy_archer_ai()
	await _test_ui_preview_and_selection_block()
	await _test_all_nine_stages_opening_cover()
	print("Combat cover: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _make_unit(kind: CombatUnit.Kind, is_ally: bool, cell: Vector2i) -> CombatUnit:
	var unit: CombatUnit = CombatUnit.new()
	unit.kind = kind
	unit.is_ally = is_ally
	unit.cell = cell
	unit.hit_points = unit.get_max_hit_points()
	return unit


func _test_cover_20_cases() -> void:
	# 1. 장애물 없음
	var g: CombatGrid = CombatGrid.new()
	var r: CombatCover.Result = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 2, true)
	_check(not r.blocked and r.blocking_cells.is_empty(), "케이스 1: 장애물 없음 -> 통과")

	# 2. 바위가 중간
	g = CombatGrid.new()
	g.props.append(CombatGrid.Prop.new(Vector2i(2, 0), "rock"))
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 2, true)
	_check(r.blocked and r.blocking_cells == [Vector2i(2, 0)] and r.reason == "바위에 가려짐", "케이스 2: 바위가 중간 -> 막힘 (2,0)")

	# 3. 박스가 중간(대상 키 2)
	g = CombatGrid.new()
	g.props.append(CombatGrid.Prop.new(Vector2i(2, 0), "crate"))
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 2, true)
	_check(not r.blocked, "케이스 3: 박스가 중간(대상 키 2) -> 통과")

	# 4. 박스가 대상 바로 앞, 대상 새끼거미 -> 막힘; 박스 파괴 시 통과
	g = CombatGrid.new()
	var crate: CombatGrid.Prop = CombatGrid.Prop.new(Vector2i(3, 0), "crate")
	g.props.append(crate)
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 1, true)
	_check(r.blocked and r.blocking_cells == [Vector2i(3, 0)], "케이스 4: 박스가 새끼거미 바로 앞 -> 막힘 (3,0)")
	g.props.erase(crate)
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 1, true)
	_check(not r.blocked, "케이스 4(갱신): 박스 파괴 뒤 -> 통과")

	# 5. 박스가 공격자 바로 앞, 대상 새끼거미 -> 통과
	g = CombatGrid.new()
	g.props.append(CombatGrid.Prop.new(Vector2i(1, 0), "crate"))
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 1, true)
	_check(not r.blocked, "케이스 5: 박스가 공격자 바로 앞(대상 새끼거미) -> 통과")

	# 6. 공격자 바닥 2, 박스가 중간 -> 통과
	g = CombatGrid.new()
	g.heights[Vector2i(0, 0)] = 2
	g.props.append(CombatGrid.Prop.new(Vector2i(2, 0), "crate"))
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 2, true)
	_check(not r.blocked, "케이스 6: 공격자 바닥 2, 박스 중간 -> 통과")

	# 7. 공격자 바닥 2, 바위가 대상 바로 앞 -> 막힘 (3,0)
	g = CombatGrid.new()
	g.heights[Vector2i(0, 0)] = 2
	g.props.append(CombatGrid.Prop.new(Vector2i(3, 0), "rock"))
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 2, true)
	_check(r.blocked and r.blocking_cells == [Vector2i(3, 0)], "케이스 7: 공격자 바닥 2, 바위 대상 바로 앞 -> 막힘 (3,0)")

	# 8. 대상 바닥 2, 바위가 중간(낮은 곳) -> 통과
	g = CombatGrid.new()
	g.heights[Vector2i(4, 0)] = 2
	g.props.append(CombatGrid.Prop.new(Vector2i(2, 0), "rock"))
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 2, true)
	_check(not r.blocked, "케이스 8: 대상 바닥 2, 바위 중간 -> 통과")

	# 9. 중간 칸 바닥 2(언덕) -> 막힘 (2,0)
	g = CombatGrid.new()
	g.heights[Vector2i(2, 0)] = 2
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 2, true)
	_check(r.blocked and r.blocking_cells == [Vector2i(2, 0)] and r.reason == "지형에 가려짐", "케이스 9: 중간 칸 바닥 2 -> 막힘 (2,0)")

	# 10. 중간 칸 바닥 1 -> 통과
	g = CombatGrid.new()
	g.heights[Vector2i(2, 0)] = 1
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 2, true)
	_check(not r.blocked, "케이스 10: 중간 칸 바닥 1 -> 통과")

	# 11. 모서리 통과: 닿는 칸 (2,0)만 바위 -> 통과
	g = CombatGrid.new()
	g.props.append(CombatGrid.Prop.new(Vector2i(2, 0), "rock"))
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(3, 1), 2, true)
	_check(not r.blocked, "케이스 11: 모서리 닿는 칸 (2,0)만 바위 -> 통과")

	# 12. 모서리 통과: 닿는 칸 (2,0)과 (1,1) 모두 바위 -> 막힘 (1,1), (2,0)
	g = CombatGrid.new()
	g.props.append(CombatGrid.Prop.new(Vector2i(2, 0), "rock"))
	g.props.append(CombatGrid.Prop.new(Vector2i(1, 1), "rock"))
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(3, 1), 2, true)
	_check(r.blocked and r.blocking_cells == [Vector2i(1, 1), Vector2i(2, 0)], "케이스 12: 모서리 두 칸 모두 바위 -> 막힘 (1,1),(2,0)")

	# 13. 정대각선, 지나는 칸 (1,1)이 바위 -> 막힘 (1,1)
	g = CombatGrid.new()
	g.props.append(CombatGrid.Prop.new(Vector2i(1, 1), "rock"))
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(3, 3), 2, true)
	_check(r.blocked and r.blocking_cells == [Vector2i(1, 1)], "케이스 13: 정대각선 지나는 칸 (1,1) 바위 -> 막힘 (1,1)")

	# 14. 정대각선, 닿는 칸 (1,0)과 (0,1)이 바위 -> 막힘 (0,1), (1,0)
	g = CombatGrid.new()
	g.props.append(CombatGrid.Prop.new(Vector2i(1, 0), "rock"))
	g.props.append(CombatGrid.Prop.new(Vector2i(0, 1), "rock"))
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(2, 2), 2, true)
	_check(r.blocked and r.blocking_cells == [Vector2i(0, 1), Vector2i(1, 0)], "케이스 14: 정대각선 닿는 두 칸 바위 -> 막힘 (0,1),(1,0)")

	# 15. 적 유닛(키 2)이 중간 -> 막힘 (2,0)
	g = CombatGrid.new()
	var mid_enemy: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, false, Vector2i(2, 0))
	g.units = [mid_enemy]
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 2, true)
	_check(r.blocked and r.blocking_cells == [Vector2i(2, 0)] and r.reason == "적에게 가려짐", "케이스 15: 적 키 2 중간 -> 막힘 (2,0)")
	mid_enemy.free()

	# 16. 아군 유닛(키 2)이 중간 -> 통과
	g = CombatGrid.new()
	var mid_ally: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, true, Vector2i(2, 0))
	g.units = [mid_ally]
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 2, true)
	_check(not r.blocked, "케이스 16: 아군 키 2 중간 -> 통과")
	mid_ally.free()

	# 17. 적 새끼거미(키 1)가 중간 -> 통과
	g = CombatGrid.new()
	var mid_spider: CombatUnit = _make_unit(CombatUnit.Kind.SPIDERLING, false, Vector2i(2, 0))
	g.units = [mid_spider]
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 2, true)
	_check(not r.blocked, "케이스 17: 적 새끼거미 중간(대상 키 2) -> 통과")
	mid_spider.free()

	# 18. 낭떠러지(바닥 없음)가 중간 -> 통과
	g = CombatGrid.new()
	g.pits = [Vector2i(2, 0)]
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 2, true)
	_check(not r.blocked, "케이스 18: 낭떠러지 중간 -> 통과")

	# 19. 물 칸(바닥 0)이 중간 -> 통과
	g = CombatGrid.new()
	g.water_cells = [Vector2i(2, 0)]
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 2, true)
	_check(not r.blocked, "케이스 19: 물 칸 중간 -> 통과")

	# 20. 나무(높이 3)가 중간, 공격자 바닥 3 -> 막힘 (2,0)
	g = CombatGrid.new()
	g.heights[Vector2i(0, 0)] = 3
	g.blocked_cells = [Vector2i(2, 0)]
	g.trees = [Vector2i(2, 0)]
	r = CombatCover.evaluate(g, Vector2i(0, 0), 2, Vector2i(4, 0), 2, true)
	_check(r.blocked and r.blocking_cells == [Vector2i(2, 0)] and r.reason == "나무에 가려짐", "케이스 20: 나무 중간·공격자 바닥 3 -> 막힘 (2,0)")


func _test_prop_target_and_dynamic_updates() -> void:
	var g: CombatGrid = CombatGrid.new()
	var archer: CombatUnit = _make_unit(CombatUnit.Kind.ARCHER, true, Vector2i(0, 0))
	var target_crate: CombatGrid.Prop = CombatGrid.Prop.new(Vector2i(4, 0), "crate")
	var front_crate: CombatGrid.Prop = CombatGrid.Prop.new(Vector2i(3, 0), "crate")
	var near_crate: CombatGrid.Prop = CombatGrid.Prop.new(Vector2i(1, 0), "crate")
	g.props = [target_crate, front_crate]
	_check(CombatCover.check_prop(g, archer, target_crate).blocked,
		"박스 대상 끝 높이 0.5: 대상 바로 앞 박스에 가려짐")
	g.props = [target_crate, near_crate]
	_check(not CombatCover.check_prop(g, archer, target_crate).blocked,
		"박스 대상 끝 높이 0.5: 공격자 바로 앞 박스는 넘어 쏨")
	# 막고 있던 적이 이동하거나 쓰러지면 즉시 통과
	var blocker: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, false, Vector2i(2, 0))
	var rear_enemy: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, false, Vector2i(4, 0))
	g.props.clear()
	g.units = [archer, blocker, rear_enemy]
	_check(CombatCover.check_unit(g, archer, rear_enemy).blocked, "중간 적에 가려짐")
	blocker.cell = Vector2i(2, 1)
	_check(not CombatCover.check_unit(g, archer, rear_enemy).blocked, "막던 적이 이동하면 즉시 통과")
	blocker.cell = Vector2i(2, 0)
	blocker.hit_points = 0
	_check(not CombatCover.check_unit(g, archer, rear_enemy).blocked, "막던 적이 전투 불능이면 즉시 통과")
	archer.free()
	blocker.free()
	rear_enemy.free()


func _test_direct_vs_indirect_actions() -> void:
	var g: CombatGrid = CombatGrid.new()
	var turns: CombatTurns = CombatTurns.new()
	var actions: CombatActions = CombatActions.new()
	actions.grid = g
	var archer: CombatUnit = _make_unit(CombatUnit.Kind.ARCHER, true, Vector2i(0, 0))
	var enemy: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, false, Vector2i(4, 0))
	var units: Array[CombatUnit] = [archer, enemy]
	var dice: CombatDice = CombatDice.new()
	dice.seed = 358
	turns.start(units, dice)
	actions.initialize(units, turns)
	g.props.append(CombatGrid.Prop.new(Vector2i(2, 0), "rock"))
	_check(not actions.can_target(archer, enemy, "attack"), "바위 뒤 적은 궁수 기본 공격(직사) 대상 불가")
	_check(actions.can_aim(archer, "trick_arrow", enemy.cell), "장난스러운 화살(곡사)은 바위 뒤 칸 조준 가능")
	_check(actions.can_aim(archer, "firework_arrow", enemy.cell), "폭죽 화살(곡사)은 바위 뒤 칸 조준 가능")
	_check(actions.can_aim(archer, "oil_throw", Vector2i(3, 0)), "기름병 던지기(곡사)는 바위 뒤 칸 조준 가능")
	archer.free()
	enemy.free()


func _setup_ai_fixture(archer_cell: Vector2i, ally_cells: Array[Vector2i], rocks: Array[Vector2i],
		walls: Array[Vector2i] = []) -> Dictionary:
	var g: CombatGrid = CombatGrid.new()
	g.map_size = Vector2i(10, 10)
	g.blocked_cells = walls.duplicate()
	var turns: CombatTurns = CombatTurns.new()
	var actions: CombatActions = CombatActions.new()
	actions.grid = g
	actions.dice = CombatDice.new()
	actions.dice.seed = 358
	var units: Array[CombatUnit] = []
	for c: Vector2i in ally_cells:
		units.append(_make_unit(CombatUnit.Kind.WARRIOR, true, c))
	var enemy_archer: CombatUnit = _make_unit(CombatUnit.Kind.ARCHER, false, archer_cell)
	units.append(enemy_archer)
	turns.start(units, actions.dice)
	actions.initialize(units, turns)
	for r: Vector2i in rocks:
		g.props.append(CombatGrid.Prop.new(r, "rock"))
	turns.current_unit = enemy_archer
	return {"grid": g, "turns": turns, "actions": actions, "units": units, "archer": enemy_archer}


func _free_fixture(f: Dictionary) -> void:
	for u: CombatUnit in f["units"]:
		u.free()


func _test_enemy_archer_ai() -> void:
	var ai: CombatEnemyAi = CombatEnemyAi.new()
	# 1) 가장 가까운 대상이 가려져도 현재 칸에서 다른 대상을 쏠 수 있으면 이동하지 않고 그 대상을 쏜다.
	var f1: Dictionary = _setup_ai_fixture(Vector2i(5, 5), [Vector2i(2, 5), Vector2i(5, 1)], [Vector2i(3, 5)])
	var archer1: CombatUnit = f1["archer"]
	await ai.play_turn(archer1, f1["actions"])
	_check(archer1.cell == Vector2i(5, 5) and archer1.action_left == 0,
		"AI 기준 2: 가장 가까운 대상이 가려져도 현재 칸에서 다른 대상을 쏠 수 있으면 제자리 공격")
	_free_fixture(f1)

	# 2) 현재 칸에서 쏠 수 있는 대상이 없고 이동 범위 안에 쏠 수 있는 칸이 있으면 이동해 쏜다.
	var f2: Dictionary = _setup_ai_fixture(Vector2i(5, 5), [Vector2i(1, 5)], [Vector2i(3, 5)])
	var archer2: CombatUnit = f2["archer"]
	await ai.play_turn(archer2, f2["actions"])
	_check(archer2.cell != Vector2i(5, 5) and archer2.action_left == 0,
		"AI 기준 1: 현재 칸에서 가려지면 이동 범위 안 사격 가능한 칸으로 이동해 쏨")
	_free_fixture(f2)

	# 3) 긴 벽을 돌아가느라 여러 턴이 걸려도 매 턴 경로를 따라 진행하며 두 칸을 왕복하지 않는다.
	var walls: Array[Vector2i] = []
	for y: int in range(0, 8):
		walls.append(Vector2i(5, y))
	var f3: Dictionary = _setup_ai_fixture(Vector2i(7, 1), [Vector2i(2, 1)], [], walls)
	var archer3: CombatUnit = f3["archer"]
	var visited: Array[Vector2i] = [archer3.cell]
	var oscillated: bool = false
	for _turn: int in range(6):
		archer3.refill_turn_resources()
		(f3["turns"] as CombatTurns).current_unit = archer3
		await ai.play_turn(archer3, f3["actions"])
		if archer3.action_left == 0:
			break
		if visited.size() >= 2 and archer3.cell == visited[visited.size() - 2]:
			oscillated = true
		visited.append(archer3.cell)
	_check(not oscillated and visited.size() > 1 and (archer3.action_left == 0 or archer3.cell.y > 1),
		"AI 기준 3·5: 여러 턴이 걸려도 제자리 종료·왕복 없이 사격 가능한 칸 경로로 진행")
	_free_fixture(f3)

	# 4) 사격 가능한 칸으로 가는 경로가 없고 이동 가능한 칸도 없으면 제자리 종료 예외 허용.
	var box_walls: Array[Vector2i] = [Vector2i(4, 5), Vector2i(6, 5), Vector2i(5, 4), Vector2i(5, 6),
		Vector2i(4, 4), Vector2i(6, 4), Vector2i(4, 6), Vector2i(6, 6)]
	var f4: Dictionary = _setup_ai_fixture(Vector2i(5, 5), [Vector2i(1, 5)], [], box_walls)
	var archer4: CombatUnit = f4["archer"]
	await ai.play_turn(archer4, f4["actions"])
	_check(archer4.cell == Vector2i(5, 5) and archer4.action_left == 1,
		"AI 기준 4: 이동 가능한 칸이 전혀 없는 불가피한 경우 제자리 종료 허용")
	_free_fixture(f4)


func _test_ui_preview_and_selection_block() -> void:
	var battle: Node2D = (load("res://scenes/combat/battle.tscn") as PackedScene).instantiate() as Node2D
	battle.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(battle)
	battle.set_process(false)
	battle.call("start_battle")
	(battle.get_node("Camera") as CombatCamera).set_process(false)
	await process_frame
	var units: Array[CombatUnit] = battle.get("units")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var actions: CombatActions = battle.get("actions") as CombatActions
	var map: CombatMap = battle.get_node("Map") as CombatMap
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var selection: CombatSelection = battle.get("selection") as CombatSelection
	var archer: CombatUnit = units[1]
	var enemy: CombatUnit = units[2]
	archer.cell = Vector2i(1, 4)
	enemy.cell = Vector2i(5, 4)
	actions.grid.props.clear()
	actions.create_prop(Vector2i(3, 4), "rock")
	turns.current_unit = archer
	battle.call("_update_turn_ui")
	await process_frame
	_check(enemy.is_cover_blocked, "직사 엄폐에 막힌 적은 회색 표시(is_cover_blocked)")
	# 막힌 적 클릭 시 선택·미리보기 없음
	var enemy_screen: Vector2 = map.get_global_transform_with_canvas() * map.map_to_surface(enemy.cell)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.position = enemy_screen
	click.global_position = enemy_screen
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	battle.call("_unhandled_input", click)
	await process_frame
	_check(selection.preview_target == null and archer.action_left == 1,
		"엄폐에 막힌 적은 좌클릭으로 선택·미리보기 불가")
	# 호버 시 초록·빨강 선분 + 사유 툴팁 표시
	battle.call("_hover_cover", enemy_screen,
		battle.get_canvas_transform().affine_inverse() * enemy_screen, enemy)
	var lines: Array = map.get("_cover_lines")
	var tip: PanelContainer = hud.get("_cover_tooltip") as PanelContainer
	var tip_label: Label = hud.get("_cover_tooltip_label") as Label
	_check(lines.size() == 2 and tip.visible and tip_label.text == "바위에 가려짐",
		"막힌 대상 호버 시 통과(초록)·차단(빨강) 2구간 선분과 사유 툴팁 표시")
	# 바위 제거 뒤 즉시 해제
	actions.grid.props.clear()
	battle.call("_update_turn_ui")
	await process_frame
	_check(not enemy.is_cover_blocked and (map.get("_cover_lines") as Array).size() == 1 and not tip.visible,
		"바위가 없어지면 회색·툴팁이 풀리고 초록 단일 선분으로 갱신")
	battle.queue_free()
	await process_frame


func _test_all_nine_stages_opening_cover() -> void:
	var stage_paths: Array[String] = [
		"res://scenes/combat/stages/act1_stage1.tres",
		"res://scenes/combat/stages/act1_stage2.tres",
		"res://scenes/combat/stages/act1_stage3.tres",
		"res://scenes/combat/stages/act2_stage1.tres",
		"res://scenes/combat/stages/act2_stage2.tres",
		"res://scenes/combat/stages/act2_stage3.tres",
		"res://scenes/combat/stages/act3_stage1.tres",
		"res://scenes/combat/stages/act3_stage2.tres",
		"res://scenes/combat/stages/act3_stage3.tres",
	]
	for path: String in stage_paths:
		var stage: CombatStage = load(path) as CombatStage
		var g: CombatGrid = CombatGrid.new()
		g.map_size = stage.map_size
		g.heights = stage.heights.duplicate()
		g.pits = stage.pits.duplicate()
		g.blocked_cells = stage.get_blocked_cells()
		g.trees = stage.tree_cells()
		g.scenery_kinds = stage.scenery_cell_kinds()
		g.water_cells = stage.water_cells.duplicate()
		for c: Vector2i in stage.crate_cells:
			g.props.append(CombatGrid.Prop.new(c, "crate"))
		for c: Vector2i in stage.rock_cells:
			g.props.append(CombatGrid.Prop.new(c, "rock"))
		var warrior: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, true, stage.ally_cells[0])
		var archer: CombatUnit = _make_unit(CombatUnit.Kind.ARCHER, true, stage.ally_cells[1])
		var enemy_root: Node = stage.enemies.instantiate()
		var enemies: Array[CombatUnit] = []
		for child: Node in enemy_root.get_children():
			var u: CombatUnit = child as CombatUnit
			u.cell = u.start_cell
			u.hit_points = u.get_max_hit_points()
			enemies.append(u)
		g.units.assign([warrior, archer] + enemies)
		var stands: Array[Vector2i] = [archer.cell]
		stands.append_array(g.reachable_cells(archer, archer.get_movement()).keys())
		var in_range_any: bool = false
		var clear_any: bool = false
		for stand: Vector2i in stands:
			for enemy: CombatUnit in enemies:
				if g.in_range(stand, enemy.cell, archer.get_attack_range()):
					in_range_any = true
					if not CombatCover.check_unit(g, archer, enemy, stand).blocked:
						clear_any = true
						break
			if clear_any:
				break
		_check(not in_range_any or clear_any,
			"스테이지 %s: 1턴 이동 범위 안 사거리 내 적이 엄폐로 전원 차단되지 않음" % path.get_file())
		warrior.free()
		archer.free()
		enemy_root.free()
