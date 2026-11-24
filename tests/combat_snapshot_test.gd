extends SceneTree
## CombatSnapshot과 CombatActProgress.is_valid_state의 직렬화·교차 불변식 검증·복원 적용을 장면 없이 검사한다.

const ScriptedDice = preload("res://tests/scripted_dice.gd")

var _failures: int = 0
var _checks: int = 0
var _created_units: Array[CombatUnit] = []


func _initialize() -> void:
	create_timer(30.0).timeout.connect(_on_timeout)
	_run.call_deferred()


func _on_timeout() -> void:
	push_error("Combat snapshot: test did not finish within 30 seconds")
	quit(1)


func _run() -> void:
	_test_act_progress_validation()
	_test_capture_and_valid_roundtrip()
	_test_cross_invariants()
	_test_replay_and_staging_invariants()
	_test_parse_save_and_preparation()
	_test_apply_combat_with_spawned_spiderling()
	for unit: CombatUnit in _created_units:
		unit.free()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat snapshot: %d checks, %d failures" % [_checks, _failures])
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


func _fixture() -> Dictionary:
	var warrior: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, true, Vector2i(1, 2))
	var archer: CombatUnit = _make_unit(CombatUnit.Kind.ARCHER, true, Vector2i(1, 3))
	var enemy: CombatUnit = _make_unit(CombatUnit.Kind.WARRIOR, false, Vector2i(5, 2))
	var units: Array[CombatUnit] = [warrior, archer, enemy]
	var turns: CombatTurns = CombatTurns.new()
	ScriptedDice.arrange_turns(turns, units, units)
	var actions: CombatActions = CombatActions.new()
	actions.initialize(units, turns)
	actions.grid.map_size = Vector2i(10, 10)
	actions.grid.trees = [Vector2i(4, 4)]
	actions.grid.blocked_cells = [Vector2i(4, 4)]
	var crate: CombatGrid.Prop = actions.create_prop(Vector2i(3, 3), "crate")
	var progress: CombatActProgress = CombatActProgress.new(9)
	var loot: CombatLoot = CombatLoot.new()
	var meta: CombatSnapshot.StageMeta = CombatSnapshot.StageMeta.new()
	meta.map_size = Vector2i(10, 10)
	meta.identities = [[warrior.kind, true], [archer.kind, true], [enemy.kind, false]]
	meta.tree_cells = [Vector2i(4, 4)]
	meta.crate_count = 1
	var lookup: Callable = func(_index: int) -> CombatSnapshot.StageMeta: return meta
	return {
		"units": units, "turns": turns, "actions": actions, "progress": progress,
		"loot": loot, "meta": meta, "lookup": lookup, "crate": crate,
	}


func _test_act_progress_validation() -> void:
	var loot: CombatLoot = CombatLoot.new()
	var valid: Dictionary = {"stage": 2, "rewarded": true, "rewards": [], "level": 1}
	_check(CombatActProgress.is_valid_state(valid, 9, loot), "1막 마지막 스테이지 승리 후 레벨 1 허용")
	var unrewarded_level: Dictionary = valid.duplicate(true)
	unrewarded_level.rewarded = false
	_check(not CombatActProgress.is_valid_state(unrewarded_level, 9, loot), "막 마지막 스테이지 미승리 시 다음 레벨 거부")
	var over_level: Dictionary = valid.duplicate(true)
	over_level.level = 2
	_check(not CombatActProgress.is_valid_state(over_level, 9, loot), "깬 막 수를 넘는 레벨 거부")
	var bad_stage: Dictionary = valid.duplicate(true)
	bad_stage.stage = 9
	_check(not CombatActProgress.is_valid_state(bad_stage, 9, loot), "스테이지 범위 밖 거부")


func _test_capture_and_valid_roundtrip() -> void:
	var f: Dictionary = _fixture()
	var state: Dictionary = CombatSnapshot.capture_combat(
		f.progress, false, f.actions, f.loot, f.units, f.turns, f.units[0])
	_check(CombatSnapshot.is_valid_combat(state, 9, f.lookup, f.loot),
		"장면·템플릿 없이 캡처한 전투 상태 검증 통과")
	var sections: Dictionary = CombatSnapshot.capture_sections(state, false, false)
	_check(sections.keys() == ["combat"], "정비 숨김 시 combat 섹션만 포함")
	var prep_sections: Dictionary = CombatSnapshot.capture_sections(state, true, true)
	_check(prep_sections.get("preparation") == {"maintaining": true}, "정비 표시 시 maintaining 저장")


func _test_cross_invariants() -> void:
	var f: Dictionary = _fixture()
	var base: Dictionary = CombatSnapshot.capture_combat(
		f.progress, false, f.actions, f.loot, f.units, f.turns, f.units[0])
	# 1. 턴 순서에 쓰러진 유닛 포함 거부
	var dead_in_order: Dictionary = base.duplicate(true)
	dead_in_order.units[2].hit_points = 0
	_check(not CombatSnapshot.is_valid_combat(dead_in_order, 9, f.lookup, f.loot),
		"쓰러진 유닛이 턴 순서에 남으면 거부")
	# 2. 시계 슬롯에 살아 있는 시전자 거부
	var alive_clock: Dictionary = base.duplicate(true)
	alive_clock.clock_slots = [[0, 1, false]]
	_check(not CombatSnapshot.is_valid_combat(alive_clock, 9, f.lookup, f.loot),
		"살아 있는 시전자의 시계 슬롯 거부")
	# 3. 쓰러진 시전자의 기절 거부
	var dead_stun_source: Dictionary = base.duplicate(true)
	dead_stun_source.units[2].hit_points = 0
	dead_stun_source.turns.order = [0, 1]
	dead_stun_source.units[0].stunned = true
	dead_stun_source.units[0].stun_source = 2
	_check(not CombatSnapshot.is_valid_combat(dead_stun_source, 9, f.lookup, f.loot),
		"쓰러진 시전자의 기절 거부")
	# 4. 남은 상자 칸과 겹치는 바닥 아이템 거부
	var overlap_loot: Dictionary = base.duplicate(true)
	var potion: Dictionary = f.loot.roll_item(CombatDice.new(), 1)
	overlap_loot.floor_loot = {"drops": [[Vector2i(3, 3), potion]], "picked": []}
	_check(not CombatSnapshot.is_valid_combat(overlap_loot, 9, f.lookup, f.loot),
		"남은 상자 칸에 떨어진 바닥 아이템 거부")
	# 5. 적이 물약을 가진 저장 거부
	var enemy_potion: Dictionary = base.duplicate(true)
	enemy_potion.units[2].potions = ["healing_potion"]
	_check(not CombatSnapshot.is_valid_combat(enemy_potion, 9, f.lookup, f.loot),
		"적 유닛의 물약 보유 거부")
	# 6. last_ally가 적 인덱스면 거부
	var bad_last_ally: Dictionary = base.duplicate(true)
	bad_last_ally.last_ally = 2
	_check(not CombatSnapshot.is_valid_combat(bad_last_ally, 9, f.lookup, f.loot),
		"last_ally가 적을 가리키면 거부")


func _test_replay_and_staging_invariants() -> void:
	var f: Dictionary = _fixture()
	var base: Dictionary = CombatSnapshot.capture_combat(
		f.progress, false, f.actions, f.loot, f.units, f.turns, f.units[0])
	# 아군 턴에는 replay.actions > 0 거부
	var ally_replay: Dictionary = base.duplicate(true)
	ally_replay["replay"] = {"actions": 1, "reactions": []}
	_check(not CombatSnapshot.is_valid_combat(ally_replay, 9, f.lookup, f.loot),
		"아군 턴의 적 리플레이 거부")
	# 적 턴에는 유효한 bool/맵 안 Vector2i 반응 답 허용, 맵 밖 Vector2i 거부
	var enemy_replay: Dictionary = base.duplicate(true)
	enemy_replay.turns = {"order": [0, 1, 2], "current": 2, "round": 1, "group": Vector2i(2, 2),
		"finished": [], "pending": [], "started": [2], "activated": [2], "deferred": []}
	enemy_replay["replay"] = {"actions": 1, "reactions": [true, Vector2i(2, 2)]}
	_check(CombatSnapshot.is_valid_combat(enemy_replay, 9, f.lookup, f.loot),
		"적 턴 리플레이와 맵 안 반사신경 답 허용")
	var oob_reaction: Dictionary = enemy_replay.duplicate(true)
	oob_reaction.replay.reactions = [Vector2i(99, 99)]
	_check(not CombatSnapshot.is_valid_combat(oob_reaction, 9, f.lookup, f.loot),
		"맵 밖 반사신경 반응 답 거부")
	# waiting_for_start와 rewarded 동시 참 거부, 라운드 2 거부
	var bad_staging: Dictionary = base.duplicate(true)
	bad_staging.waiting_for_start = true
	bad_staging.rewarded = true
	_check(not CombatSnapshot.is_valid_combat(bad_staging, 9, f.lookup, f.loot),
		"전투 준비 중 승리 기록 거부")
	var late_staging: Dictionary = base.duplicate(true)
	late_staging.waiting_for_start = true
	late_staging.turns.round = 2
	_check(not CombatSnapshot.is_valid_combat(late_staging, 9, f.lookup, f.loot),
		"2라운드 전투 준비 상태 거부")


func _test_parse_save_and_preparation() -> void:
	var f: Dictionary = _fixture()
	var base: Dictionary = CombatSnapshot.capture_combat(
		f.progress, false, f.actions, f.loot, f.units, f.turns, f.units[0])
	# 전투 중 정비 섹션 거부
	var mid_prep: CombatSnapshot.SavePlan = CombatSnapshot.parse_save(
		{"combat": base, "preparation": {"maintaining": true}}, 9, f.lookup, f.loot)
	_check(not mid_prep.valid, "적이 살아 있는데 정비 섹션이 있으면 거부")
	# 승리 후 정비 섹션 허용
	var won: Dictionary = base.duplicate(true)
	won.rewarded = true
	won.units[2].hit_points = 0
	won.turns.order = [0, 1]
	var won_plan: CombatSnapshot.SavePlan = CombatSnapshot.parse_save(
		{"combat": won, "preparation": {"maintaining": true}}, 9, f.lookup, f.loot)
	_check(won_plan.valid and won_plan.open_preparation and won_plan.maintaining,
		"승리 후 정비 섹션은 정비 화면 열기로 파싱")
	# 옛 지도 준비 정비(before_battle)는 전투 준비 중일 때만 허용하고 정비 화면은 열지 않음
	var staging: Dictionary = base.duplicate(true)
	staging.waiting_for_start = true
	var legacy_plan: CombatSnapshot.SavePlan = CombatSnapshot.parse_save(
		{"combat": staging, "preparation": {"maintaining": true, "before_battle": true}}, 9, f.lookup, f.loot)
	_check(legacy_plan.valid and not legacy_plan.open_preparation,
		"옛 지도 준비 정비 저장은 정비 화면 없이 전투 준비로 이어함")


func _test_apply_combat_with_spawned_spiderling() -> void:
	var f: Dictionary = _fixture()
	var spiderling: CombatUnit = _make_unit(CombatUnit.Kind.SPIDERLING, false, Vector2i(6, 2))
	spiderling.initiative_roll = 0
	var with_child: Array[CombatUnit] = f.units.duplicate()
	with_child.append(spiderling)
	f.turns.load_state({"order": [0, 1, 2, 3], "current": 0, "round": 2, "group": Vector2i(0, 1),
		"finished": [], "pending": [], "started": [0, 1], "activated": [0], "deferred": []}, with_child)
	var state: Dictionary = CombatSnapshot.capture_combat(
		f.progress, false, f.actions, f.loot, with_child, f.turns, with_child[1])
	_check(CombatSnapshot.is_valid_combat(state, 9, f.lookup, f.loot),
		"소환된 새끼 거미(initiative_roll 0) 포함 상태 검증 통과")
	var target: Dictionary = _fixture()
	var synced: Array[int] = [0]
	var restored: Dictionary = CombatSnapshot.apply_combat(
		state, target.progress, target.loot, target.units, target.actions, target.turns,
		func(saved: Dictionary) -> CombatUnit: return _make_unit(saved.kind, false, saved.cell),
		func() -> void: synced[0] += 1)
	_check(target.units.size() == 4 and target.units[3].kind == CombatUnit.Kind.SPIDERLING
		and synced[0] == 1 and restored.last_ally == target.units[1] and target.turns.round_number == 2,
		"apply_combat가 소환 유닛·레벨 동기화·last_ally·턴을 순서대로 복원")
