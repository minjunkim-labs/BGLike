extends Node2D
## 전투 화면과 3막 진행. 적 묶음은 이니셔티브 순서대로 실행한다.

const ENEMY_PAUSE_TIME: float = 0.35
## 적 턴에 Space를 누르고 있는 동안의 시간 배율. 규칙이 아니라 표시 속도다.
const ENEMY_FAST_SPEED: float = 4.0
## 마지막 적 처치 슬로우모션 길이(실제 초, #799). 일시정지 메뉴를 열면 함께 멈춘다.
const LAST_KILL_SLOWMO_DURATION: float = 1.0
## 한 프레임 지연으로 슬로우모션 전체가 건너뛰어지지 않도록 한 프레임에 줄이는 최대 실제 시간(초, #799).
const LAST_KILL_SLOWMO_MAX_STEP: float = 0.1
## 마지막 적 처치 슬로우모션 배율(#799). 적 턴 4배속보다 우선해 0.2배속으로 고정한다.
const LAST_KILL_SLOWMO_SCALE: float = 0.2
## 마지막 적 처치 시 전투 불능(사라짐) 애니메이션이 끝난 뒤 승리 화면을 띄우기 전 기다리는 게임 시간(초, #728).
const VICTORY_DELAY: float = 0.4

## 자동 저장을 마친 뒤. 검사가 저장한 순간의 상태를 비교한다.
signal autosaved

@export var stages: Array[CombatStage] = []

var progress: CombatActProgress
## 처음 열 스테이지 번호(0부터). 타이틀의 디버그 테스트 진입(#512)이 장면을 트리에 넣기 전에 정한다.
var start_stage: int = 0
var map_size: Vector2i
var party: Array[CombatUnit] = []

var units: Array[CombatUnit] = []
var turns: CombatTurns = CombatTurns.new()
var actions: CombatActions = CombatActions.new()
var enemy_ai: CombatEnemyAi = CombatEnemyAi.new()
var _enemy_turn_running: bool = false
var _enemy_shown: bool = false
var _enemy_acted: bool = false
var selection: CombatSelection = CombatSelection.new()
var movement_cells: Array[Vector2i] = []
var attack_reach_cells: Array[Vector2i] = []
var action_range_cells: Array[Vector2i] = []
var _last_ally: CombatUnit
var loot: CombatLoot = CombatLoot.new()
var preparation: CombatPreparation
var _save_pending: bool = false
## 진행 중인 적 턴이 시작한 순간의 상태와 그 뒤 끝낸 적 행동 수. 적 턴 중간 저장에 쓴다.
var _turn_start: Dictionary = {}
var _turn_actions: int = 0
## 이어하기가 연출 없이 다시 실행할 적 행동 수.
var _replay_actions: int = 0
## #345: 지도를 보고 명시적으로 전투를 시작한다. 적 선공도 이때까지 기다린다.
## #395: 지도 준비에서는 정비를 열지 않는다. 정비는 승리 뒤 보상 확인 다음에만 연다.
var waiting_for_start: bool = true
## 발밑 칸 표시가 지금 따라가는 유닛(#623). 숨김이면 null이다. 바뀔 때만 나타남을 다시 돌린다.
var _turn_tile_unit: CombatUnit
## 마지막 적 처치 시 사라짐 애니메이션과 승리 여운을 기다리는 중인지(#728).
var _victory_waiting: bool = false
## 마지막 적 처치 슬로우모션이 진행 중인지(#799).
var _last_kill_slowmo: bool = false
var _last_kill_slowmo_left: float = 0.0
var _victory_revision: int = 0
var staging: HBoxContainer
var start_button: Button

var hit_effects: CombatHitEffects
var sounds: CombatSounds
var presentation: CombatPresentation
@onready var map: CombatMap = $Map
@onready var camera: CombatCamera = $Camera
@onready var hud: CombatTurnHud = $UI/TurnHud
@onready var pause_menu: PauseMenu = $Pause/PauseMenu
@onready var dice_view: CombatDiceRollView = $UI/DiceRollView


func _ready() -> void:
	assert(stages.size() == 9, "전투 진행에는 스테이지 데이터9개가 필요합니다.")
	progress = CombatActProgress.new(stages.size())
	progress.stage_index = start_stage
	# 파티 노드를 유지해 같은 막의 HP와 스킬 횟수를 이어 간다.
	for child: Node in $Units.get_children():
		party.append(child as CombatUnit)
	sounds = CombatSounds.new()
	sounds.name = "Sounds"
	add_child(sounds)
	preparation = CombatPreparation.new()
	preparation.name = "Preparation"
	$UI.add_child(preparation)
	preparation.finished.connect(_finish_preparation)
	preparation.changed.connect(func() -> void: _save_pending = true)
	staging = HBoxContainer.new()
	staging.name = "Staging"
	staging.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	staging.offset_left = 8
	staging.offset_right = -8
	staging.offset_top = -58
	staging.offset_bottom = -8
	staging.add_theme_constant_override("separation", 8)
	hud.add_child(staging)
	var hint: Label = Label.new()
	hint.text = tr("전투 준비 · 지형과 적을 확인하고 전투를 시작합니다.")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	staging.add_child(hint)
	start_button = Button.new()
	start_button.name = "StartBattle"
	start_button.text = tr("전투 시작")
	start_button.custom_minimum_size.x = 96
	start_button.add_theme_font_size_override("font_size", 14)
	start_button.pressed.connect(start_battle)
	staging.add_child(start_button)

	hud.unit_selected.connect(_on_unit_selected)
	hud.unit_hovered.connect(_on_unit_hovered)
	hud.end_turn_requested.connect(_end_turn)
	hud.action_selected.connect(_on_action_selected)
	hud.reaction_selected.connect(actions.resolve_reaction)
	hud.restart_requested.connect(_restart)
	pause_menu.give_up_confirmed.connect(_give_up)
	actions.changed.connect(_on_actions_changed)
	actions.logged.connect(hud.add_log)
	hit_effects = CombatHitEffects.new()
	hit_effects.name = "HitEffects"
	hit_effects.z_index = 5
	add_child(hit_effects)
	presentation = CombatPresentation.new()
	presentation.name = "Presentation"
	add_child(presentation)
	presentation.bind(actions, turns, map, hud, dice_view, sounds, hit_effects, {
		"is_replaying": _replaying,
		"is_waiting_for_start": func() -> bool: return waiting_for_start,
		"get_units": func() -> Array[CombatUnit]: return units,
		"get_stage": func() -> CombatStage: return stages[progress.stage_index],
		"show_enemy_action": _show_enemy_action,
		"follow_turn_tile": _follow_turn_tile,
		"on_victory_downed": _on_victory_downed,
	})
	actions.reaction_requested.connect(_on_reaction_requested)
	hud.grid = actions.grid
	turns.changed.connect(_on_turn_changed)
	turns.order_rotated.connect(hud.prepare_order_rotation)
	_start_stage(true)


func _on_victory_downed(unit: CombatUnit) -> void:
	if (is_processing() and not _victory_waiting and not unit.is_ally
			and actions.is_over() and actions.is_victory()):
		_begin_victory_wait()


## 반응 확인 창을 띄운다. 반사신경이면 후보 칸을 맵에 보인다.
func _on_reaction_requested(kind: String, prompt: String) -> void:
	hud.show_reaction(kind, prompt, actions.pending_cells)
	if kind == "reflex":
		_update_turn_ui()


func _on_reflex_selected(cell: Vector2i) -> void:
	actions.resolve_reflex(cell)
	_update_turn_ui()


## 후보 칸에 올린 칸으로 가는 경로를 미리 보인다. 벗어나면 후보 칸만 보인다.
func _on_reflex_previewed(cell: Vector2i) -> void:
	if actions.pending_kind != "reflex" or actions.pending_reactor == null:
		return
	var path: Array[Vector2i] = []
	if cell != Vector2i(-1, -1):
		path.append(cell)
	map.show_movement(actions.pending_cells, [], path, actions.pending_reactor.cell)


func _exit_tree() -> void:
	_cancel_victory_wait()
	if sounds != null:
		sounds.stop_ambient()
	actions.movement_animation = Callable()
	actions.jump_animation = Callable()
	actions.attack_animation = Callable()
	actions.cell_attack_animation = Callable()
	actions.roll_animation = Callable()
	Engine.time_scale = 1.0


func _start_stage(restore_act: bool) -> void:
	waiting_for_start = true
	sounds.stop_ambient()
	_replay_actions = 0
	actions.replay_answers.clear()
	for unit: CombatUnit in party:
		unit.begin_stage(restore_act)
	var stage: CombatStage = _build_stage()
	for index: int in range(party.size()):
		party[index].cell = stage.ally_cells[index]
		party[index].facing_left = false
	var dice: CombatDice = CombatDice.new()
	dice.randomize()
	var living: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if unit.hit_points > 0:
			living.append(unit)
	_last_ally = living[0]
	turns.start(living, dice)
	for cell: Vector2i in stage.crate_cells:
		var prop: CombatGrid.Prop = actions.create_prop(cell, "crate")
		assert(prop != null, "나무 상자 시작 칸이 유효하지 않습니다: %s %s" % [stage.resource_path, cell])
	for cell: Vector2i in stage.rock_cells:
		var prop: CombatGrid.Prop = actions.create_prop(cell, "rock")
		assert(prop != null, "바위 시작 칸이 유효하지 않습니다: %s %s" % [stage.resource_path, cell])
	_update_turn_ui()
	start_button.grab_focus()


func start_battle() -> void:
	if not waiting_for_start:
		return
	# 시작 전 정비 화면에서 장비가 바뀌면 최대 이동이 달라진다. 아직 아무 행동도 없었으므로 다시 채운다(3-3).
	for unit: CombatUnit in party:
		unit.refill_turn_resources()
	waiting_for_start = false
	_save_pending = true
	get_viewport().gui_release_focus()
	sounds.start_ambient(actions.grid)
	presentation.on_turn_started(turns.current_unit)
	_update_turn_ui()


## 지금 스테이지의 지도와 처음 배치의 적을 새로 만든다. 아군 상태와 턴 순서는 건드리지 않는다.
func _build_stage() -> CombatStage:
	_cancel_victory_wait()
	progress.begin_stage()
	var stage: CombatStage = stages[progress.stage_index]
	assert(stage != null, "스테이지 데이터가 비어 있습니다: %d" % (progress.stage_index + 1))
	assert(stage.ally_cells.size() == party.size(),
		"아군 시작 칸 수가 파티 크기와 다릅니다: " + stage.resource_path)
	for unit: CombatUnit in units:
		if not unit.is_ally:
			unit.free()
	presentation.clear_feedback()
	units = party.duplicate()
	map_size = stage.map_size
	actions.grid.map_size = map_size
	actions.grid.heights = stage.heights.duplicate()
	actions.grid.pits = stage.pits.duplicate()
	actions.grid.blocked_cells = stage.get_blocked_cells()
	actions.grid.trees = stage.tree_cells()
	actions.grid.scenery_kinds = stage.scenery_cell_kinds()
	actions.grid.water_cells = stage.water_cells.duplicate()
	map.build_grid(actions.grid, stage.tile_set, stage)
	var enemies: Node = stage.enemies.instantiate()
	$Units.add_child(enemies)
	for child: Node in enemies.get_children():
		var unit: CombatUnit = child as CombatUnit
		unit.reparent($Units, false)
		units.append(unit)
	enemies.free()
	camera.frame(map, map_size)
	selection.reset()
	hud.begin_stage(progress.act_number(), progress.stage_in_act())
	actions.loot = loot
	actions.act_number = progress.act_number()
	actions.initialize(units, turns)
	return stage


## 이어하기에 필요한 전투 상태 전체. Object 없이 GameSave에 그대로 쓸 수 있는 값이다 (docs/adr/0003).
func combat_state() -> Dictionary:
	return CombatSnapshot.capture_combat(progress, waiting_for_start, actions, loot, units, turns, _last_ally)


## combat_state()로 저장한 전투로 되돌린다. 저장이 맞지 않으면 아무것도 바꾸지 않고 false다.
## 값은 GameSave.read()의 sections.combat을 그대로 받는다.
## 적 턴 중간의 저장이면 그 적 턴이 시작한 상태로 되돌리고, 다음 프레임에 끝낸 적 행동까지 연출 없이 다시 실행한다.
func restore_combat(state: Variant) -> bool:
	if (actions.busy or _enemy_turn_running or _victory_waiting or preparation.visible
			or not CombatSnapshot.is_valid_combat(state, stages.size(), _stage_meta, loot, party[0])):
		push_warning("전투 저장을 읽을 수 없음")
		return false
	progress.stage_index = state.stage
	_build_stage()
	var restored: Dictionary = CombatSnapshot.apply_combat(state, progress, loot, units, actions, turns,
		_spawn_saved_enemy, _sync_party_level)
	waiting_for_start = restored.waiting_for_start
	_last_ally = restored.last_ally
	_replay_actions = restored.replay_actions
	selection.reset()
	_update_turn_ui()
	# 방금 읽은 저장과 같은 상태다. 적 턴 중간 저장을 시작 상태로 덮지 않는다.
	_save_pending = false
	return true


## 이어하기. GameSave.read()의 sections를 그대로 받는다. 정비·보상 확인 화면 중의 저장이면 그 화면과 단계를 다시 연다.
## 저장이 맞지 않으면 아무것도 바꾸지 않고 false다.
func restore_save(sections: Variant) -> bool:
	var plan: CombatSnapshot.SavePlan = CombatSnapshot.parse_save(sections, stages.size(), _stage_meta, loot, party[0])
	if not plan.valid:
		push_warning(plan.error_message)
		return false
	if not restore_combat(plan.combat):
		return false
	if plan.open_preparation:
		preparation.open_rewards(loot, party, progress.rewards, progress.is_final_stage(),
			progress.is_last_in_act(), plan.maintaining, actions.floor_loot.cells().size())
		hud.hide_result()
		_sync_music()
		# 방금 읽은 저장과 같은 상태다.
		_save_pending = false
	return true


func _stage_meta(index: int) -> CombatSnapshot.StageMeta:
	return CombatSnapshot.StageMeta.from_stage(stages[index], party)


func _spawn_saved_enemy(saved: Dictionary) -> CombatUnit:
	var child: CombatUnit = (preload("res://scenes/combat/unit.tscn") as PackedScene).instantiate() as CombatUnit
	child.kind = saved.kind
	child.is_ally = false
	$Units.add_child(child)
	return child


func _restart() -> void:
	if not actions.is_over() or actions.busy or _enemy_turn_running or _victory_waiting:
		return
	if actions.is_victory():
		# 졸업 화면의 버튼은 `타이틀로` 하나다 (#209 9번).
		if progress.graduated:
			get_tree().change_scene_to_file(PauseMenu.TITLE_SCENE)
			return
		if preparation.visible:
			return
		preparation.open_rewards(loot, party, progress.rewards, progress.is_final_stage(),
			progress.is_last_in_act(), false, actions.floor_loot.cells().size())
		hud.hide_result()
		_sync_music()
		return
	progress.restart_act()
	_start_stage(progress.starts_act())


## 일시정지 메뉴의 `전투 포기`(#286). 전멸과 같은 패배라 결과 화면에서 이 막을 처음부터 다시 한다.
## 확정한 순간을 행동 하나로 바로 저장한다. 적 턴·연출 중이어도 강제 종료로 포기를 되돌릴 수 없다(#220 3번).
func _give_up() -> void:
	actions.give_up()
	if GameSave.autosave:
		# 진행 중이던 적 행동이 끝나며 적 턴 시작 상태로 덮어쓰지 않게 한다.
		_turn_start = {}
		_autosave(combat_state())


func _finish_preparation() -> void:
	if not actions.is_over() or actions.busy or _enemy_turn_running or _victory_waiting or not actions.is_victory():
		return
	progress.advance()
	if progress.graduated:
		# 졸업 화면이 뜨는 순간 저장을 지운다. 이어하기로 마지막 정비 화면에 돌아가지 않는다 (#209 9번).
		# 스위치가 꺼진 검사·장면 직접 실행은 사용자의 저장을 건드리지 않는다.
		if GameSave.autosave:
			GameSave.delete()
		_update_turn_ui()
		return
	_start_stage(progress.starts_act())


func _process(delta: float) -> void:
	if _last_kill_slowmo:
		var unscaled_delta: float = delta / Engine.time_scale if Engine.time_scale > 0.0 else delta
		_last_kill_slowmo_left = maxf(0.0, _last_kill_slowmo_left - minf(unscaled_delta, LAST_KILL_SLOWMO_MAX_STEP))
		if _last_kill_slowmo_left <= 0.0:
			_last_kill_slowmo = false
	if _save_pending and GameSave.autosave and _can_save():
		_autosave(combat_state())
	_sync_time_scale()
	var actor: CombatUnit = turns.current_unit
	if (not waiting_for_start and actor != null and not actor.is_ally and not actions.busy
		and not actions.is_over() and not _enemy_turn_running):
		_play_enemy_turn(actor)


func _desired_time_scale() -> float:
	if _last_kill_slowmo:
		return LAST_KILL_SLOWMO_SCALE
	# 반응 확인 창과 전투 종료·승리 대기 중에는 가속하지 않고 보통 속도로 둔다.
	if (_enemy_turn_running and not actions.is_over() and not _victory_waiting
			and not hud.is_reaction_open() and Input.is_key_pressed(KEY_SPACE)):
		return ENEMY_FAST_SPEED
	return 1.0


func _sync_time_scale() -> void:
	Engine.time_scale = _desired_time_scale()


func _play_enemy_turn(actor: CombatUnit) -> void:
	_enemy_turn_running = true
	_enemy_shown = false
	_enemy_acted = false
	_turn_actions = 0
	actions.reaction_answers.clear()
	if GameSave.autosave:
		_turn_start = combat_state()
	await enemy_ai.play_turn(actor, actions, _pause_enemy_action)
	_replay_actions = 0
	actions.replay_answers.clear()
	_turn_start = {}
	if not actions.is_over() and turns.current_unit == actor:
		turns.end_turn()
	_enemy_turn_running = false
	_update_turn_ui()


## 적 행동 하나가 끝날 때마다 AI가 부른다. 저장한 뒤, 이동·공격하지 않은 적 행동 뒤에는 기다리지 않는다.
func _pause_enemy_action() -> void:
	_turn_actions += 1
	if _turn_actions < _replay_actions:
		return
	_replay_actions = 0
	if GameSave.autosave and not _turn_start.is_empty():
		# AI는 턴 안의 진행을 지역 값으로 들고 있어 중간 상태에서 다시 시작하면 다른 선택을 할 수 있다.
		# 그래서 턴 시작 상태와 끝낸 행동 수, 아군의 반응 답을 저장하고 이어하기가 같은 난수로 다시 실행한다.
		var state: Dictionary = _turn_start.duplicate()
		state["replay"] = {"actions": _turn_actions, "reactions": actions.reaction_answers.duplicate()}
		_autosave(state)
	if actions.is_over() or not _enemy_acted:
		return
	_enemy_acted = false
	# 연출 타이머는 일시정지 메뉴가 열린 동안 멈춘다.
	await get_tree().create_timer(CombatPresentation.duration(ENEMY_PAUSE_TIME), false).timeout


## 적 턴의 첫 이동·공격 연출 전에 한 번 멈춰 행동할 적을 보여 준다.
func _show_enemy_action() -> void:
	if not _enemy_turn_running:
		return
	_enemy_acted = true
	if not _enemy_shown:
		_enemy_shown = true
		await get_tree().create_timer(CombatPresentation.duration(ENEMY_PAUSE_TIME), false).timeout
		# 턴 이동(#516 2절)이 멈춤보다 길면 카메라가 닿을 때까지 더 기다린다. 일시정지 중에는 게임 시간이 멈춘다.
		while camera.is_turning():
			await get_tree().process_frame


## 행동이 끝나 연출·반응 확인 창을 기다리지 않는 순간. 확정 전 입력(선택·미리보기)은 상태를 바꾸지 않는다.
func _can_save() -> bool:
	return not actions.busy and not _enemy_turn_running and actions.pending_reactor == null and not progress.graduated


## 쓰기에 실패하면 이전 저장이 남고 다음 행동이 끝날 때 다시 쓴다. 매 프레임 다시 쓰지 않는다.
func _autosave(state: Dictionary) -> void:
	_save_pending = false
	var sections: Dictionary = CombatSnapshot.capture_sections(state, preparation.visible, preparation.maintaining)
	if GameSave.write(progress.act_number(), progress.stage_in_act(), sections) == OK:
		autosaved.emit()


## 이어하기가 끝낸 적 행동을 다시 실행하는 중인지. 연출·팝업·소리를 건너뛴다.
func _replaying() -> bool:
	return _turn_actions < _replay_actions


func _on_unit_selected(unit: CombatUnit) -> void:
	if actions.busy or actions.is_over() or _victory_waiting or unit not in units or unit.hit_points <= 0:
		return
	selection.clear_preview()
	if waiting_for_start:
		hud.show_unit(unit)
		return
	# 조작 가능한 아군만 전환한다. 다른 초상은 정보만 표시한다.
	turns.select_unit(unit)
	selection.inspect(unit)
	_update_turn_ui()


func _end_turn() -> void:
	if (not waiting_for_start and turns.current_unit != null and turns.current_unit.is_ally
		and not actions.busy and not actions.is_over() and not _victory_waiting):
		turns.end_turn()


func _on_action_selected(action: String) -> void:
	var actor: CombatUnit = turns.current_unit
	if waiting_for_start or actor == null or not actor.is_ally or actions.busy or actions.is_over() or _victory_waiting:
		return
	if action == "stand_up":
		actions.stand_up(actor)
		_update_turn_ui()
		return
	var command: CombatSelection.Command = selection.choose_action(actor, actions, action)
	if not command.is_empty():
		await _execute_command(actor, command)
		return
	_update_turn_ui()


func _hover_floor_loot(screen_position: Vector2) -> void:
	var world_position: Vector2 = get_canvas_transform().affine_inverse() * screen_position
	var cell: Vector2i = map.surface_to_map(map.to_local(world_position))
	if selection.set_hover_cell(cell, actions):
		_update_turn_ui()


## 적 위협 범위(#556). T로 켜고 끄며 기본은 꺼짐이다. 저장하지 않는다.
var threat_visible: bool = false
## 마우스가 올라간 적(몸통 또는 턴 순서 초상). 있으면 그 적의 범위만 보인다.
var _threat_unit: CombatUnit
var _body_hover_unit: CombatUnit
var _portrait_hover_unit: CombatUnit
var _cover_hover_screen: Vector2 = Vector2.INF
var _cover_hover_unit: CombatUnit
var _cover_hover_prop: CombatGrid.Prop


func _on_unit_hovered(unit: CombatUnit) -> void:
	_portrait_hover_unit = unit
	_sync_threat_hover()


## 칸 윗면 마름모(`contains_surface`) 안에 local_point가 들어가는 살아 있는 유닛을 화면 앞쪽부터 돌려준다(#735).
func _units_at_point(local_point: Vector2, visible_only: bool = false) -> Array[CombatUnit]:
	var found: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if unit.hit_points > 0 and (not visible_only or unit.visible) and map.contains_surface(unit.cell, local_point):
			found.append(unit)
	found.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		if a.position.y != b.position.y:
			return a.position.y > b.position.y
		return a.get_index() > b.get_index())
	return found


func _hovered_unit_at(world_position: Vector2) -> CombatUnit:
	var local_point: Vector2 = map.to_local(world_position)
	var candidates: Array[CombatUnit] = _units_at_point(local_point, true)
	return candidates[0] if not candidates.is_empty() else actions.grid.unit_at(
		map.surface_to_map(local_point))


func _hover_enemy_body(screen_position: Vector2) -> void:
	var world_position: Vector2 = get_canvas_transform().affine_inverse() * screen_position
	var found: CombatUnit = _hovered_unit_at(world_position)
	_body_hover_unit = found
	_sync_threat_hover()
	_hover_cover(screen_position, world_position, found)


func _direct_fire_active() -> bool:
	return (not waiting_for_start and not preparation.visible and not actions.is_over()
		and selection.is_direct_fire_active(turns.current_unit))


func _hover_cover(screen_position: Vector2, world_position: Vector2, hovered_unit: CombatUnit) -> void:
	_cover_hover_screen = screen_position
	_cover_hover_unit = hovered_unit
	_cover_hover_prop = map.prop_at_point(map.to_local(world_position))
	_refresh_cover_hover()


func _refresh_cover_hover() -> void:
	if not _direct_fire_active() or _cover_hover_screen == Vector2.INF:
		_cover_hover_unit = null
		_cover_hover_prop = null
		map.clear_cover_line()
		hud.hide_cover_reason()
		return
	var world_position: Vector2 = get_canvas_transform().affine_inverse() * _cover_hover_screen
	_cover_hover_unit = _hovered_unit_at(world_position)
	_cover_hover_prop = map.prop_at_point(map.to_local(world_position))
	var hover: CombatSelection.CoverHover = selection.evaluate_cover_hover(
		turns.current_unit, actions, units, _cover_hover_unit, _cover_hover_prop)
	if hover.active:
		map.show_cover_line(hover.origin, hover.target_cell, hover.result)
		if hover.result.blocked:
			hud.show_cover_reason(hover.result.reason, _cover_hover_screen)
		else:
			hud.hide_cover_reason()
		return
	map.clear_cover_line()
	hud.hide_cover_reason()


func _sync_threat_hover() -> void:
	var picked: CombatUnit = _portrait_hover_unit if _portrait_hover_unit != null else _body_hover_unit
	if picked != null and (picked.is_ally or picked.hit_points <= 0 or picked not in units):
		picked = null
	if picked == _threat_unit:
		return
	_threat_unit = picked
	_refresh_threat()


func _refresh_threat() -> void:
	var cells: Array[Vector2i] = []
	if not preparation.visible and not actions.is_over():
		var shown: Array[CombatUnit] = []
		if _threat_unit != null and _threat_unit.hit_points > 0 and _threat_unit in units:
			shown.append(_threat_unit)
		elif threat_visible:
			for unit: CombatUnit in units:
				if not unit.is_ally and unit.visible and unit.hit_points > 0 and not unit.stealthed:
					shown.append(unit)
		for enemy: CombatUnit in shown:
			for cell: Vector2i in actions.threat_cells(enemy):
				if cell not in cells:
					cells.append(cell)
	map.show_threat(cells)


func _input(event: InputEvent) -> void:
	if actions.pending_kind == "reflex" and hud.reflex_banner.visible:
		if event is InputEventMouseMotion:
			var world_pos: Vector2 = get_canvas_transform().affine_inverse() * event.position
			var hovered: Vector2i = map.surface_to_map(map.to_local(world_pos))
			_on_reflex_previewed(hovered if hovered in actions.pending_cells else Vector2i(-1, -1))
			return
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			hud.hide_reaction()
			actions.resolve_reaction(false)
			_update_turn_ui()
			return
		# 패드 Start 등 pause 입력은 반응 대기 중 일시정지 창을 열지 않고 소비만 한다.
		if event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and not preparation.visible:
		_hover_floor_loot(event.position)
		_hover_enemy_body(event.position)
	if (event is InputEventKey and event.physical_keycode == KEY_T and not preparation.visible
			and not event.is_command_or_control_pressed()):
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo:
			threat_visible = not threat_visible
			_refresh_threat()
		return
	# 반응·정비 확인 창이 떠 있으면 그 창이 Esc·Start를 먼저 받는다. Esc는 지금처럼 반응을 넘긴다.
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if get_viewport().gui_is_dragging():
			get_viewport().gui_cancel_drag()
			return
		# 졸업 화면에는 `타이틀로`만 둔다.
		if progress.graduated:
			return
		# 멈추면 _process가 돌지 않는다. 메뉴에서 바로 타이틀로·종료해도 끝난 행동이 남게 먼저 쓴다.
		if _save_pending and GameSave.autosave and _can_save():
			_autosave(combat_state())
		pause_menu.open(not actions.is_over() and not waiting_for_start)
		return
	if event is InputEventKey and event.keycode == KEY_SPACE and not actions.is_over():
		# Space는 적 턴 가속 키다. 포커스된 버튼(턴 종료 등)을 누르지 않게 소비한다.
		get_viewport().set_input_as_handled()
		return
	# 숫자 키 1~9는 스킬 바의 버튼을 왼쪽부터 고른다. 자판 배열과 관계없이 윗줄 숫자 자리를 쓴다.
	if event is InputEventKey and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
		if event.pressed and not event.echo and _ally_input_open():
			get_viewport().set_input_as_handled()
			hud.focus_action_slot(event.physical_keycode - KEY_1, true)
		return
	# 포커스가 없으면 좌우 방향키·D-pad가 스킬 바의 첫 버튼으로 들어간다.
	if ((event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"))
		and get_viewport().gui_get_focus_owner() == null and _ally_input_open()):
		get_viewport().set_input_as_handled()
		hud.focus_action_slot(0, false)
		return
	if event is not InputEventKey or event.keycode != KEY_TAB or preparation.visible or waiting_for_start:
		return
	# GUI보다 먼저 소비해 전투 중 기본 Tab 포커스 이동을 막는다.
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo or not _ally_input_open():
		return
	var actor: CombatUnit = turns.current_unit
	var group: Array[CombatUnit] = turns.get_current_group()
	var index: int = group.find(actor)
	var direction: int = -1 if event.shift_pressed else 1
	for step: int in range(1, group.size() + 1):
		var unit: CombatUnit = group[wrapi(index + step * direction, 0, group.size())]
		if turns.select_unit(unit):
			selection.inspect(unit)
			_update_turn_ui()
			return


## 아군 턴의 키보드 조작을 받을 수 있는지. 연출·반응 확인·결과·정비 화면에서는 잠근다.
func _ally_input_open() -> bool:
	var actor: CombatUnit = turns.current_unit
	return (not waiting_for_start and actor != null and actor.is_ally and not actions.busy and not actions.is_over()
		and not _victory_waiting
		and not hud.is_reaction_open() and not hud.get_node("Result").visible and not preparation.visible)


## 방향 동작(휩쓸기·효시)의 클릭이 가리키는 방향 칸. 인접 칸의 몸통이나 사물을 눌러도 그 칸을 방향으로 고른다.
## 인접하지 않은 몸통(자기 자신 등)이 가린 칸은 격자 위치로 고르고, 그래도 인접하지 않거나 맵 밖이면 호출자가 미리보기만 지운다.
func _facing_at(actor: CombatUnit, cell: Vector2i, candidates: Array[CombatUnit], prop: CombatGrid.Prop,
		world_position: Vector2) -> Vector2i:
	var facing: Vector2i = cell
	if not candidates.is_empty() and CombatGrid.distance(actor.cell, candidates[0].cell) == 1:
		facing = candidates[0].cell
	elif prop != null and CombatGrid.distance(actor.cell, prop.cell) == 1:
		facing = prop.cell
	elif not actions.grid.is_inside(cell):
		# 낭떠러지 칸은 바닥 타일이 없어 격자 위치로 잡히지 않으므로 인접한 낭떠러지의 윗면으로 찾는다.
		# 높이 때문에 윗면이 겹쳐도 맵 안 칸이 잡혔으면 그 칸을 방향으로 둔다.
		for neighbor: Vector2i in CombatGrid.neighbors(actor.cell):
			if actions.grid.pits.has(neighbor) and map.contains_surface(neighbor, map.to_local(world_position)):
				facing = neighbor
	return facing


func _unhandled_input(event: InputEvent) -> void:
	if (event is not InputEventMouseButton or not event.pressed
		or event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]):
		return
	if actions.pending_kind == "reflex" and hud.reflex_banner.visible:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var reflex_world: Vector2 = get_canvas_transform().affine_inverse() * event.position
			var reflex_cell: Vector2i = map.surface_to_map(map.to_local(reflex_world))
			if reflex_cell in actions.pending_cells:
				get_viewport().set_input_as_handled()
				hud.hide_reaction()
				_on_reflex_selected(reflex_cell)
		return
	if actions.busy or actions.is_over() or _victory_waiting:
		return
	var world_position: Vector2 = get_canvas_transform().affine_inverse() * event.position
	var local_point: Vector2 = map.to_local(world_position)
	var cell: Vector2i = map.surface_to_map(local_point)
	if waiting_for_start:
		var shown: Array[CombatUnit] = _units_at_point(local_point, true)
		if not shown.is_empty():
			hud.show_unit(shown[0])
			get_viewport().set_input_as_handled()
		return
	var actor: CombatUnit = turns.current_unit
	if actor == null or not actor.is_ally:
		return
	selection.begin_field_input(event.button_index == MOUSE_BUTTON_LEFT)
	# 우클릭은 격자 칸의 윗면 마름모로 이동 판정한다.
	if event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		await _select_move_cell(cell)
		return
	var candidates: Array[CombatUnit] = _units_at_point(local_point)
	var prop: CombatGrid.Prop = map.prop_at_point(local_point)
	var mode: CombatActionRules.TargetMode = CombatActionRules.target_mode(selection.selected_action)
	if selection.selected_action in CombatActionRules.OIL_ACTIONS:
		get_viewport().set_input_as_handled()
		await _select_aim_cell(cell)
		return
	if mode == CombatActionRules.TargetMode.AIM_CELL:
		get_viewport().set_input_as_handled()
		# 유닛 칸이나 사물 칸을 눌러도 그 칸을 고른다.
		var aimed_cell: Vector2i = cell
		if not candidates.is_empty():
			aimed_cell = candidates[0].cell
		elif prop != null:
			aimed_cell = prop.cell
		await _select_aim_cell(aimed_cell)
		return
	if mode == CombatActionRules.TargetMode.FACING:
		get_viewport().set_input_as_handled()
		var facing: Vector2i = _facing_at(actor, cell, candidates, prop, world_position)
		var command: CombatSelection.Command = selection.choose_facing(actor, actions, facing)
		if not command.is_empty():
			await _execute_command(actor, command)
			return
		_update_turn_ui()
		return
	# 윤곽이 보이는 가린 유닛은 동작할 수 있을 때만 앞 사물보다 우선한다.
	var unit_first: bool = not candidates.is_empty() and candidates[0].is_occluded and (
		not candidates[0].is_ally or selection.selected_action == "shove")
	if prop != null and not unit_first and (candidates.is_empty()
			or map.map_to_local(prop.cell).y >= candidates[0].position.y):
		get_viewport().set_input_as_handled()
		var prop_command: CombatSelection.Command = selection.choose_prop(actor, actions, prop)
		if not prop_command.is_empty():
			await _execute_command(actor, prop_command)
			return
		_update_turn_ui()
		return
	if not candidates.is_empty():
		get_viewport().set_input_as_handled()
		var unit_command: CombatSelection.Command = selection.choose_unit(actor, actions, candidates[0])
		if not unit_command.is_empty():
			await _execute_command(actor, unit_command)
			return
		_update_turn_ui()
		return
	selection.cancel_field_selection()
	_update_turn_ui()


## 칸 조준 동작(기름병 던지기, 장난스러운 화살, 폭죽 화살). 한 번 눌러 범위를 보고, 같은 칸을 다시 누르면 실행한다.
func _select_aim_cell(cell: Vector2i) -> void:
	var actor: CombatUnit = turns.current_unit
	var command: CombatSelection.Command = selection.choose_aim(actor, actions, cell)
	if not command.is_empty():
		await _execute_command(actor, command)
		return
	_update_turn_ui()


func _select_move_cell(cell: Vector2i) -> void:
	var actor: CombatUnit = turns.current_unit
	var command: CombatSelection.Command = selection.choose_move(actor, actions, cell)
	if not command.is_empty():
		await _execute_command(actor, command)
		return
	_update_turn_ui()


func _execute_command(actor: CombatUnit, command: CombatSelection.Command) -> void:
	match command.kind:
		CombatSelection.Command.Kind.SELF:
			actions.use_self(actor, command.action)
			selection.finish_execution()
		CombatSelection.Command.Kind.MOVE:
			if await actions.move_to(actor, command.cell):
				selection.finish_execution()
		CombatSelection.Command.Kind.JUMP:
			if await actions.jump_to(actor, command.cell):
				selection.finish_execution()
		CombatSelection.Command.Kind.MOVING_SHOT:
			if await actions.moving_shot(actor, command.cell):
				selection.finish_execution()
		CombatSelection.Command.Kind.AIM:
			match command.action:
				"oil_throw", "oil_bottle":
					actions.throw_oil(actor, command.cell, command.action)
				"trick_arrow":
					await actions.trick_arrow(actor, command.cell)
				"firework_arrow":
					await actions.firework_arrow(actor, command.cell)
			selection.finish_execution()
			selection.offer_moving_shot(actor, turns.current_unit)
		CombatSelection.Command.Kind.FACING:
			if command.action == "sweep":
				await actions.sweep(actor, command.cell)
			else:
				await actions.whistle(actor, command.cell)
			selection.finish_execution()
		CombatSelection.Command.Kind.PROP:
			var prop: CombatGrid.Prop = command.prop
			var origin: Vector2i = prop.cell
			var generation: int = map.revision
			if await actions.attack_prop(actor, prop):
				if generation != map.revision:
					return
				map.prop_impact(prop.cell, prop.hit_points == 0)
				if prop.cell != origin:
					map.prop_impact(origin, false)
			elif generation != map.revision:
				return
			selection.finish_execution()
			selection.offer_moving_shot(actor, turns.current_unit)
		CombatSelection.Command.Kind.TARGET:
			match command.action:
				"attack":
					await actions.attack(actor, command.target)
				"cross_slash":
					await actions.cross_slash(actor, command.target)
				"steel_charge":
					await actions.steel_charge(actor, command.target)
				"bow_bash":
					await actions.bow_bash(actor, command.target)
				"shove":
					actions.shove(actor, command.target)
			selection.finish_execution()
			selection.offer_moving_shot(actor, turns.current_unit)
	_update_turn_ui()


func preview_enemy(target: CombatUnit) -> bool:
	if (turns.current_unit == null or not turns.current_unit.is_ally
		or target not in units or target.is_ally or target.hit_points <= 0):
		return false
	selection.preview_unit(target)
	_update_turn_ui()
	return true


func _on_actions_changed() -> void:
	_save_pending = true
	if actions.is_over():
		sounds.stop_ambient()
	if actions.is_over() and actions.is_victory():
		var monster_count: int = 0
		for unit: CombatUnit in units:
			if unit.can_drop_extra_reward():
				monster_count += 1
		# 전투 주사위로 굴려 이어하기가 마지막 공격을 다시 해도 드랍이 바뀌지 않는다.
		progress.record_victory(loot, monster_count, actions.dice, actions.floor_loot.picked)
		_sync_party_level()
	_update_turn_ui()


## 파티 레벨을 아군 모두에 맞춘다. 몬스터는 늘 레벨 0이다 (#477).
func _sync_party_level() -> void:
	for unit: CombatUnit in party:
		unit.dice_level = progress.level


## 마지막 적 처치 시 슬로우모션(#799)과 사라짐 애니메이션·짧은 여운(#728)을 기다린 뒤 승리 화면과 승리곡을 연다.
func _begin_victory_wait() -> void:
	_victory_revision += 1
	var revision: int = _victory_revision
	_victory_waiting = true
	_last_kill_slowmo = true
	_last_kill_slowmo_left = LAST_KILL_SLOWMO_DURATION
	_sync_time_scale()
	var victory_timer: SceneTreeTimer = get_tree().create_timer(
		CombatHitEffects.down_duration() + VICTORY_DELAY, false)
	while _last_kill_slowmo and is_inside_tree() and revision == _victory_revision:
		await get_tree().process_frame
	if not is_inside_tree() or revision != _victory_revision:
		return
	_sync_time_scale()
	if victory_timer.time_left > 0.0:
		await victory_timer.timeout
	if not is_inside_tree() or revision != _victory_revision:
		return
	_victory_waiting = false
	_update_turn_ui()


func _cancel_victory_wait() -> void:
	_victory_revision += 1
	_victory_waiting = false
	_last_kill_slowmo = false
	_last_kill_slowmo_left = 0.0
	_sync_time_scale()


## 화면에 맞는 배경음을 고른다(#629). 정비·보상 확인은 차분한 곡, 끝난 전투는 승리·패배 곡(승리 연출 대기 중에는 전투 곡 유지, #728), 그 밖은 전투 곡이다.
func _sync_music() -> void:
	if preparation.visible:
		GameMusic.play(get_tree(), GameMusic.CALM)
	elif actions.is_over() and not _victory_waiting:
		GameMusic.play(get_tree(), GameMusic.VICTORY if actions.is_victory() else GameMusic.DEFEAT)
	else:
		GameMusic.play(get_tree(), GameMusic.BATTLE)


func _on_turn_changed() -> void:
	_save_pending = true
	selection.reset()
	_update_turn_ui()


## 발밑 칸 표시와 카메라가 따라가는 행동 유닛. 전투 시작 전·전투 끝·전투 불능이면 null이다.
func _acting_unit() -> CombatUnit:
	var unit: CombatUnit = turns.current_unit
	if unit == null or unit.hit_points <= 0 or waiting_for_start or actions.is_over():
		return null
	return unit


## 행동 유닛이 선 칸에 발밑 표시를 둔다(#516 1절). 전투 시작 전·전투 끝·전투 불능이면 숨긴다.
func _refresh_turn_tile() -> void:
	var unit: CombatUnit = _acting_unit()
	if unit == null:
		_turn_tile_unit = null
		map.show_turn_tile(Vector2i(-1, -1), false)
		return
	map.show_turn_tile(unit.cell, unit != _turn_tile_unit)
	_turn_tile_unit = unit


## 카메라가 따라갈 행동 유닛을 알린다(#516 2절). 유닛이나 순환이 바뀔 때만 카메라가 새로 시작한다.
func _refresh_camera_follow() -> void:
	camera.follow_turn(_acting_unit(), turns.round_number)


## 이동·점프 한 칸이 도착하면 행동 유닛의 표시를 도착한 칸으로 옮긴다. 나타남은 다시 돌리지 않는다.
func _follow_turn_tile(unit: CombatUnit, cell: Vector2i) -> void:
	if unit == _turn_tile_unit:
		map.show_turn_tile(cell, false)


func _update_turn_ui() -> void:
	var preview: CombatSelection.Preview = selection.build_preview(
		turns.current_unit, actions, units,
		not waiting_for_start and not preparation.visible and not actions.is_over())
	for unit: CombatUnit in units:
		if not unit.is_moving:
			unit.position = map.map_to_local(unit.cell)
			unit.floor_offset_y = map.map_to_surface(unit.cell).y - unit.position.y
		unit.visible = unit.hit_points > 0
		unit.is_selected = unit == turns.current_unit
		unit.is_previewed = unit in preview.previewed_units
		unit.queue_redraw()
	if turns.current_unit != null and turns.current_unit.is_ally:
		_last_ally = turns.current_unit
	var can_act: bool = actions.has_available_action(turns.current_unit)
	hud.refresh(turns, can_act)
	movement_cells.assign(preview.movement_cells)
	attack_reach_cells.assign(preview.attack_reach_cells)
	action_range_cells.assign(preview.action_range_cells)
	map.show_movement(preview.movement_cells, preview.attack_reach_cells, preview.path, preview.origin,
		preview.warning_cells, preview.action_range_cells)
	map.show_grounds(actions.get_grounds())
	map.show_trees(actions.grid.trees)
	map.show_floor_loot(actions.floor_loot.drops)
	map.show_props(actions.get_props(), preview.preview_prop, preview.blocked_props)
	_refresh_threat()
	_refresh_turn_tile()
	_refresh_camera_follow()
	map.reveal_units(units)
	# 가림 판정은 방금 그린 사물 위치를 사용한다.
	for unit: CombatUnit in units:
		unit.is_occluded = map.occludes(unit.cell,
			map.to_local(unit.to_global(Vector2(0, unit.floor_offset_y - 10))))
		unit.is_cover_blocked = unit in preview.blocked_units
	_refresh_cover_hover()
	if preview.preview_target != null:
		hud.show_attack_preview(preview.preview_target, preview.attack_preview)
	elif preview.rock_roll != null:
		map.show_rock_roll(preview.preview_prop.cell, preview.rock_roll)
	elif preview.inspected_unit != null:
		hud.show_unit(preview.inspected_unit)
	hud.refresh_actions(actions, "" if selection.is_default_mode() else preview.selected_action, _last_ally)
	staging.visible = waiting_for_start
	if waiting_for_start:
		hud.get_node("Round").text = tr("전투 준비")
	hud.get_node("Skills").visible = not waiting_for_start
	hud.get_node("EndTurn").visible = not waiting_for_start
	hud.show_move_mode(preview.show_move_mode)
	if not preview.target_note.is_empty():
		hud.show_target_note(preview.target_note)
	if actions.is_over() and not _victory_waiting:
		hud.show_outcome(actions.is_victory())
		if not preparation.visible:
			hud.show_result(actions.is_victory(), progress.graduated, _enemy_turn_running or actions.busy)
	# 이어하기는 장면을 연 뒤에 정비 화면을 다시 열므로, 그 프레임이 끝난 마지막 상태로 곡을 고른다.
	_sync_music.call_deferred()
	queue_redraw()
