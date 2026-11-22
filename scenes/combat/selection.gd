class_name CombatSelection
extends RefCounted
## 전투 조작의 선택·취소·확정과 미리보기 스냅샷·호버 엄폐 계산.
## 화면 좌표 변환과 비동기 실행·표시는 battle이 맡는다.

## 2클릭 또는 재선택으로 확정된 실행 명령. 비동기 실행·연출은 battle이 맡는다.
class Command extends RefCounted:
	enum Kind { NONE, SELF, MOVE, JUMP, MOVING_SHOT, AIM, FACING, TARGET, PROP }

	var kind: Kind = Kind.NONE
	var action: String = ""
	var cell: Vector2i = Vector2i(-1, -1)
	var target: CombatUnit
	var prop: CombatGrid.Prop

	func is_empty() -> bool:
		return kind == Kind.NONE


## 직사 기본 공격의 마우스 호버 엄폐 판정 결과.
class CoverHover extends RefCounted:
	var active: bool = false
	var origin: Vector2i = Vector2i(-1, -1)
	var target_cell: Vector2i = Vector2i(-1, -1)
	var result: CombatCover.Result


## 현재 선택 상태와 전투 상태를 바탕으로 계산한 UI·맵 표시용 스냅샷.
class Preview extends RefCounted:
	var selected_action: String = "attack"
	var movement_cells: Array[Vector2i] = []
	var attack_cells: Array[Vector2i] = []
	var path: Array[Vector2i] = []
	var origin: Vector2i = Vector2i.ZERO
	var previewed_units: Array[CombatUnit] = []
	var direct_fire: bool = false
	var blocked_props: Array[CombatGrid.Prop] = []
	var blocked_units: Array[CombatUnit] = []
	var preview_target: CombatUnit
	var attack_preview: CombatChecks.AttackPreview
	var preview_prop: CombatGrid.Prop
	var rock_roll: CombatActions.RockRoll
	var inspected_unit: CombatUnit
	var show_move_mode: bool = false
	var target_note: String = ""


var _selected_action: String = "attack"
var _preview_target: CombatUnit
var _preview_prop: CombatGrid.Prop
var _preview_cell: Vector2i = Vector2i(-1, -1)
var _preview_path: Array[Vector2i] = []
var _inspected_unit: CombatUnit
var _hover_cell: Vector2i = Vector2i(-1, -1)

var selected_action: String:
	get:
		return _selected_action
var preview_target: CombatUnit:
	get:
		return _preview_target
var preview_prop: CombatGrid.Prop:
	get:
		return _preview_prop
var preview_cell: Vector2i:
	get:
		return _preview_cell
var preview_path: Array[Vector2i]:
	get:
		return _preview_path.duplicate()
var inspected_unit: CombatUnit:
	get:
		return _inspected_unit


func reset() -> void:
	_selected_action = "attack"
	_inspected_unit = null
	clear_preview()


func clear_preview() -> void:
	_preview_target = null
	_preview_prop = null
	_preview_cell = Vector2i(-1, -1)
	_preview_path.clear()


func inspect(unit: CombatUnit) -> void:
	if CombatActionRules.target_mode(_selected_action) == CombatActionRules.TargetMode.MOVE:
		_selected_action = "attack"
	clear_preview()
	_inspected_unit = unit


## 바닥 아이템 호버 칸을 갱신한다. 바닥 아이템 표시가 바뀔 때만 true를 돌려준다.
func set_hover_cell(cell: Vector2i, actions: CombatActions) -> bool:
	if cell == _hover_cell:
		return false
	var affected: bool = (not actions.floor_loot.item_at(_hover_cell).is_empty()
		or not actions.floor_loot.item_at(cell).is_empty())
	_hover_cell = cell
	return affected


## 무빙샷을 쓸 수 있게 되면 선택을 도약으로 바꿔 도착 칸을 보인다(#528).
func offer_moving_shot(actor: CombatUnit, current_unit: CombatUnit) -> void:
	if actor != null and actor.moving_shot_ready and actor == current_unit:
		_selected_action = "moving_shot"


func begin_field_input(left_click: bool) -> void:
	_inspected_unit = null
	if left_click and CombatActionRules.target_mode(_selected_action) == CombatActionRules.TargetMode.MOVE:
		_selected_action = "attack"
		clear_preview()


func preview_unit(target: CombatUnit) -> void:
	clear_preview()
	_preview_target = target


func finish_execution() -> void:
	_selected_action = "attack"


## 동작 바에서 동작을 고른다. 같은 자기 대상 동작을 다시 누르면 실행 명령을 돌려준다.
func choose_action(actor: CombatUnit, actions: CombatActions, action: String) -> Command:
	if actor == null or not actor.is_ally or not actions.can_use(actor, action):
		return Command.new()
	_inspected_unit = null
	clear_preview()
	if action == _selected_action and CombatActionRules.target_mode(action) == CombatActionRules.TargetMode.SELF:
		var command: Command = Command.new()
		command.kind = Command.Kind.SELF
		command.action = action
		return command
	_selected_action = action
	return Command.new()


## 우클릭으로 이동·점프·무빙샷 목적지를 고른다. 유효한 같은 칸을 다시 누르면 실행 명령을 돌려준다.
func choose_move(actor: CombatUnit, actions: CombatActions, cell: Vector2i) -> Command:
	var path: Array[Vector2i] = []
	var jumping: bool = _selected_action == "jump"
	# 무빙샷 도약도 점프처럼 착지 칸을 먼저 보고 같은 칸을 다시 우클릭하면 뛴다(#528).
	var leaping: bool = _selected_action == "moving_shot"
	if actor != null and actor.is_ally:
		if leaping:
			if cell in actions.moving_shot_cells(actor):
				path = [cell]
		elif jumping and actions.jump_cells(actor).has(cell):
			path = actions.grid.jump_path(actor, cell)
		elif not jumping and actions.can_move(actor, cell):
			path = actions.grid.path_to(actor, cell)
	if _selected_action not in ["jump", "moving_shot"]:
		_selected_action = "move"
	var confirmed: bool = not path.is_empty() and not _preview_path.is_empty() and cell == _preview_cell
	clear_preview()
	if confirmed:
		var command: Command = Command.new()
		command.kind = Command.Kind.MOVING_SHOT if leaping else (Command.Kind.JUMP if jumping else Command.Kind.MOVE)
		command.action = _selected_action
		command.cell = cell
		return command
	if not path.is_empty():
		_preview_cell = cell
		_preview_path = path.duplicate()
	return Command.new()


## 칸 조준 동작(기름병 던지기, 장난스러운 화살, 폭죽 화살). 같은 유효 칸을 다시 누르면 실행 명령을 돌려준다.
func choose_aim(actor: CombatUnit, actions: CombatActions, cell: Vector2i) -> Command:
	var action: String = _selected_action
	if _select_cell(cell, actions.can_aim(actor, action, cell)):
		clear_preview()
		var command: Command = Command.new()
		command.kind = Command.Kind.AIM
		command.action = action
		command.cell = cell
		return command
	return Command.new()


## 방향 동작(휩쓸기·효시). 인접한 유효 칸을 다시 누르면 실행 명령을 돌려준다.
func choose_facing(actor: CombatUnit, actions: CombatActions, facing: Vector2i) -> Command:
	var action: String = _selected_action
	if actor == null or CombatGrid.distance(actor.cell, facing) != 1 or not actions.grid.is_inside(facing):
		clear_preview()
		return Command.new()
	if _select_cell(facing, _can_face(actor, actions, action, facing)):
		clear_preview()
		var command: Command = Command.new()
		command.kind = Command.Kind.FACING
		command.action = action
		command.cell = facing
		return command
	return Command.new()


## 환경 오브젝트 좌클릭. 직사 기본 공격이 엄폐에 막히면 미리보기 없이 해제한다(#358).
func choose_prop(actor: CombatUnit, actions: CombatActions, prop: CombatGrid.Prop) -> Command:
	if _selected_action == "attack" and actions.cover_for_prop(actor, prop, "attack").blocked:
		clear_preview()
		return Command.new()
	var can_execute: bool = _selected_action == "attack" and actions.can_attack_prop(actor, prop)
	if prop == _preview_prop and can_execute:
		var action: String = _selected_action
		clear_preview()
		var command: Command = Command.new()
		command.kind = Command.Kind.PROP
		command.action = action
		command.prop = prop
		return command
	clear_preview()
	_preview_prop = prop
	return Command.new()


## 유닛 좌클릭. 아군(밀치기 제외)이나 직사 엄폐 대상은 미리보기 없이 해제한다(#358).
func choose_unit(actor: CombatUnit, actions: CombatActions, unit: CombatUnit) -> Command:
	if unit.is_ally and _selected_action != "shove":
		clear_preview()
		return Command.new()
	if _selected_action == "attack" and actions.cover_for_unit(actor, unit, "attack").blocked:
		clear_preview()
		return Command.new()
	var can_execute: bool = actions.can_target(actor, unit, _selected_action)
	if unit == _preview_target and can_execute:
		var action: String = _selected_action
		clear_preview()
		var command: Command = Command.new()
		command.kind = Command.Kind.TARGET
		command.action = action
		command.target = unit
		return command
	preview_unit(unit)
	return Command.new()


## 현재 선택이 아군의 직사 기본 공격 상태인지 돌려준다.
func is_direct_fire_active(actor: CombatUnit) -> bool:
	return (actor != null and actor.is_ally and _selected_action == "attack"
		and CombatCover.is_direct_fire(actor, "attack"))


## 직사 기본 공격 중 마우스가 올라간 적 유닛이나 환경 오브젝트의 엄폐 판정을 돌려준다.
func evaluate_cover_hover(actor: CombatUnit, actions: CombatActions, units: Array[CombatUnit],
		hovered_unit: CombatUnit, hovered_prop: CombatGrid.Prop) -> CoverHover:
	var hover: CoverHover = CoverHover.new()
	if not is_direct_fire_active(actor):
		return hover
	if (hovered_unit != null and hovered_unit in units and hovered_unit.hit_points > 0
			and not hovered_unit.is_ally and not hovered_unit.stealthed
			and actions.grid.in_range(actor.cell, hovered_unit.cell, actor.get_attack_range())):
		hover.active = true
		hover.origin = actor.cell
		hover.target_cell = hovered_unit.cell
		hover.result = actions.cover_for_unit(actor, hovered_unit, "attack")
		return hover
	if (hovered_prop != null and hovered_prop in actions.grid.props and hovered_prop.hit_points > 0
			and actions.grid.in_range(actor.cell, hovered_prop.cell, actor.get_attack_range())):
		hover.active = true
		hover.origin = actor.cell
		hover.target_cell = hovered_prop.cell
		hover.result = actions.cover_for_prop(actor, hovered_prop, "attack")
		return hover
	return hover


## 현재 선택과 전투 상태로 맵 강조·엄폐 차단·미리보기 안내 스냅샷을 계산한다.
func build_preview(actor: CombatUnit, actions: CombatActions, units: Array[CombatUnit],
		direct_fire_open: bool = true) -> Preview:
	_discard_stale_references(actions)
	var snapshot: Preview = Preview.new()
	snapshot.selected_action = _selected_action
	var mode: CombatActionRules.TargetMode = CombatActionRules.target_mode(_selected_action)
	var facing_preview: bool = (mode == CombatActionRules.TargetMode.FACING
		and actor != null and actor.is_ally and _preview_cell != Vector2i(-1, -1))
	var sweep_targets: Array[CombatUnit] = []
	if facing_preview:
		sweep_targets = (actions.sweep_targets(actor, _preview_cell) if _selected_action == "sweep"
			else actions.whistle_targets(actor, _preview_cell))
	for unit: CombatUnit in units:
		if (unit == _preview_target
				or (not _preview_path.is_empty() and actions.can_target(actor, unit, "attack", _preview_cell))
				or unit in sweep_targets):
			snapshot.previewed_units.append(unit)
	_fill_highlights(snapshot, actor, actions, units, mode, facing_preview)
	_fill_cover_blocks(snapshot, actor, actions, units, direct_fire_open)
	_fill_notes(snapshot, actor, actions, units, mode, facing_preview, sweep_targets)
	return snapshot


func _select_cell(cell: Vector2i, can_execute: bool) -> bool:
	if cell == _preview_cell and _preview_path.is_empty() and can_execute:
		return true
	clear_preview()
	_preview_cell = cell
	return false


func _discard_stale_references(actions: CombatActions) -> void:
	if _inspected_unit != null and _inspected_unit.hit_points <= 0:
		_inspected_unit = null
	if _preview_prop != null and _preview_prop not in actions.get_props():
		clear_preview()


func _can_face(actor: CombatUnit, actions: CombatActions, action: String, facing: Vector2i) -> bool:
	return actions.can_sweep(actor, facing) if action == "sweep" else actions.can_whistle(actor, facing)


func _fill_highlights(snapshot: Preview, actor: CombatUnit, actions: CombatActions, units: Array[CombatUnit],
		mode: CombatActionRules.TargetMode, facing_preview: bool) -> void:
	if actor != null and actor.is_ally:
		if _selected_action == "move":
			snapshot.movement_cells.assign(actions.reachable_cells(actor).keys())
		elif _selected_action == "jump":
			snapshot.movement_cells.assign(actions.jump_cells(actor).keys())
		elif _selected_action == "moving_shot":
			snapshot.movement_cells.assign(actions.moving_shot_cells(actor))
		elif facing_preview:
			snapshot.movement_cells.assign(actions.grid.sweep_cells(actor.cell, _preview_cell)
				if _selected_action == "sweep" else actions.grid.band_cells(actor.cell, _preview_cell))
		elif mode == CombatActionRules.TargetMode.AIM_CELL:
			var aimed: bool = actions.can_aim(actor, _selected_action, _preview_cell)
			if aimed and _selected_action == "trick_arrow":
				snapshot.movement_cells.assign([_preview_cell])
			elif aimed:
				snapshot.movement_cells.assign(actions.aim_area(actor, _selected_action, _preview_cell))
			else:
				snapshot.movement_cells.assign(actions.aim_cells(actor, _selected_action))
		elif mode == CombatActionRules.TargetMode.FACING:
			# 방향을 고르기 전에는 고를 수 있는 인접 칸을 보인다.
			for cell: Vector2i in CombatGrid.neighbors(actor.cell):
				if _can_face(actor, actions, _selected_action, cell):
					snapshot.movement_cells.append(cell)
	snapshot.origin = actor.cell if actor != null else Vector2i.ZERO
	snapshot.path = _preview_path.duplicate()
	if actions.pending_kind == "reflex" and actions.pending_reactor != null:
		# 반사신경 확인 창이 열린 동안에는 회피할 후보 칸만 이동 칸처럼 보인다.
		snapshot.movement_cells.assign(actions.pending_cells)
		snapshot.origin = actions.pending_reactor.cell
		snapshot.path = []
	else:
		for cell: Vector2i in snapshot.movement_cells:
			if mode == CombatActionRules.TargetMode.FACING or _has_attack_target_from(actor, actions, units, cell):
				snapshot.attack_cells.append(cell)


func _has_attack_target_from(actor: CombatUnit, actions: CombatActions, units: Array[CombatUnit],
		cell: Vector2i) -> bool:
	for unit: CombatUnit in units:
		# 이동 후 공격 가능 칸(초록)은 이번 범위에서 엄폐를 반영하지 않는다(#358).
		if actions.can_target(actor, unit, "attack", cell, false):
			return true
	return false


func _fill_cover_blocks(snapshot: Preview, actor: CombatUnit, actions: CombatActions, units: Array[CombatUnit],
		direct_fire_open: bool) -> void:
	snapshot.direct_fire = direct_fire_open and is_direct_fire_active(actor)
	if not snapshot.direct_fire:
		return
	for prop_item: CombatGrid.Prop in actions.get_props():
		if (actions.grid.in_range(actor.cell, prop_item.cell, actor.get_attack_range())
				and actions.cover_for_prop(actor, prop_item, "attack").blocked):
			snapshot.blocked_props.append(prop_item)
	for unit: CombatUnit in units:
		if (not unit.is_ally and unit.hit_points > 0 and not unit.stealthed
				and actions.grid.in_range(actor.cell, unit.cell, actor.get_attack_range())
				and actions.cover_for_unit(actor, unit, "attack").blocked):
			snapshot.blocked_units.append(unit)


func _fill_notes(snapshot: Preview, actor: CombatUnit, actions: CombatActions, units: Array[CombatUnit],
		mode: CombatActionRules.TargetMode, facing_preview: bool, sweep_targets: Array[CombatUnit]) -> void:
	if _preview_target != null:
		snapshot.preview_target = _preview_target
		# 고른 동작의 명중 능력치·근접 여부를 따른다(활 후려치기는 힘 d6, 원거리 불리 없음).
		snapshot.attack_preview = actions.grid.attack_preview(actor, _preview_target, _selected_action)
		if _selected_action == "shove":
			snapshot.target_note = _shove_note(actor, actions, _preview_target)
		elif _selected_action == "steel_charge":
			snapshot.target_note = _steel_charge_note(actor, actions, _preview_target)
	elif _preview_prop != null:
		snapshot.preview_prop = _preview_prop
		if _selected_action == "attack" and actor != null and _preview_prop.kind == "rock":
			snapshot.rock_roll = actions.preview_rock(actor, _preview_prop)
		snapshot.target_note = _prop_note(actor, actions, _preview_prop, snapshot.rock_roll)
	elif _inspected_unit != null:
		snapshot.inspected_unit = _inspected_unit
	snapshot.show_move_mode = _selected_action == "move" or not _preview_path.is_empty()
	# 걷기·무빙샷 도약 미리보기는 안내를 숨기지만, 도착 칸이 물이면 서기 전에 물 칸 화상 규칙을, 기름 칸이면 미끌거림 안내를 보인다(#503, #600).
	if _selected_action != "jump" and not _preview_path.is_empty():
		var notes: Array[String] = []
		for note: String in [actions.water_note(_preview_cell),
				actions.slip_note(actor, _preview_path),
				actions.pickup_note(actor, _preview_path)]:
			if not note.is_empty():
				notes.append(note)
		if not notes.is_empty():
			snapshot.show_move_mode = false
			snapshot.target_note = "\n".join(notes)
	if _selected_action == "jump":
		snapshot.show_move_mode = false
		snapshot.target_note = _jump_note(actor, actions)
	elif _selected_action == "sweep" and actor != null and actor.is_ally and not actions.busy:
		snapshot.target_note = _sweep_note(actor, actions, facing_preview, sweep_targets)
	elif _selected_action == "whistle" and actor != null and actor.is_ally and not actions.busy:
		snapshot.target_note = _whistle_note(actor, facing_preview, sweep_targets)
	elif _selected_action in CombatActionRules.OIL_ACTIONS and actor != null and actor.is_ally and not actions.busy:
		var oil_name: String = CombatActionRules.NAMES[_selected_action]
		snapshot.target_note = (tr("%s · 보조 행동1 · 기름을 깔 칸을 좌클릭합니다.\n같은 칸을 다시 좌클릭하면 던집니다.") % oil_name
			if not actions.can_aim(actor, _selected_action, _preview_cell)
			else tr("%s · 보조 행동1 · 십자 5칸 기름 3턴\n같은 칸을 다시 좌클릭하면 던집니다.") % oil_name)
	elif _selected_action in ["trick_arrow", "firework_arrow"] and actor != null and actor.is_ally and not actions.busy:
		snapshot.target_note = _arrow_note(actor, actions, units, _selected_action, _preview_cell)
	var hovered: Dictionary = actions.floor_loot.item_at(_hover_cell)
	if (not hovered.is_empty() and _preview_target == null and _preview_prop == null
			and _preview_path.is_empty()
			and mode not in [CombatActionRules.TargetMode.AIM_CELL, CombatActionRules.TargetMode.FACING]
			and _selected_action not in ["jump", "moving_shot"]):
		snapshot.show_move_mode = false
		snapshot.target_note = tr("바닥 아이템 · %s") % CombatLoot.describe(hovered)


func _shove_note(actor: CombatUnit, actions: CombatActions, target: CombatUnit) -> String:
	if not actions.can_target(actor, target, "shove"):
		return tr("밀치기를 사용할 수 없음")
	var cell: Vector2i = actions.grid.push_destination(actor.cell, target.cell)
	var landing: String = actions.shove_landing(target, cell)
	var chance: float = 1.0
	if CombatActionRules.shove_saves(actor, target):
		chance -= CombatActionRules.save_chance(actor, target, "shove")
	return (tr("밀려날 칸: %d, %d") % [cell.x, cell.y]
		+ ("" if landing.is_empty() else " · " + landing) + " · " + tr("밀칠 확률 %.1f%%") % (chance * 100.0))


func _steel_charge_note(actor: CombatUnit, actions: CombatActions, target: CombatUnit) -> String:
	if not actions.can_target(actor, target, "steel_charge"):
		return tr("강철 돌진을 사용할 수 없음")
	# 전진하는 아군은 대상이 있던 칸에 도착해 그 칸의 아이템을 줍는다 (환경요소 3-5).
	var advance: String = actions.pickup_note(actor, [target.cell])
	if actions.grid.can_shove(actor, target):
		var cell: Vector2i = actions.grid.push_destination(actor.cell, target.cell)
		var landing: String = actions.shove_landing(target, cell)
		return (tr("명중하면 밀려날 칸: %d, %d") % [cell.x, cell.y] + ("" if landing.is_empty() else " · " + landing)
			+ ("" if advance.is_empty() else " · " + advance))
	return (tr("밀려날 칸이 막힘 · 명중하면 피해만, 쓰러뜨리면 그 칸으로 전진")
		+ ("" if advance.is_empty() else " · " + advance))


func _prop_note(actor: CombatUnit, actions: CombatActions, prop: CombatGrid.Prop,
		roll: CombatActions.RockRoll) -> String:
	var note: String = tr("기본 공격만 가능")
	var title: String = tr("바위") if prop.kind == "rock" else tr("나무 상자 · 내구도 %d/6") % prop.hit_points
	if _selected_action == "attack" and actor != null:
		if prop.kind == "rock":
			var direction: String = {
				Vector2i.RIGHT: tr("오른쪽 아래"), Vector2i.DOWN: tr("왼쪽 아래"),
				Vector2i.LEFT: tr("왼쪽 위"), Vector2i.UP: tr("오른쪽 위")
			}.get(roll.direction, tr("방향 없음"))
			var collisions: Array[String] = []
			for unit: CombatUnit in roll.collisions:
				var landing: String = actions.rock_collision_note(roll, unit)
				collisions.append((tr("아군 피해4: %s") if unit.is_ally else tr("적 피해4: %s")) % unit.get_display_name()
					+ ("" if landing.is_empty() else " · " + landing))
			note = tr("행동1 · 피해 굴림 없음\n%s · %d칸 · %s\n%s\n같은 바위를 다시 좌클릭하면 굴립니다.") % [
				direction, roll.cells.size(), roll.reason,
				", ".join(collisions) if not collisions.is_empty() else tr("충돌 없음")]
		else:
			var ability: CombatUnit.Ability = CombatActionRules.damage_ability(actor, "attack")
			var modifier: int = actor.get_ability_modifier(ability)
			var minimum: int = maxi(1, actor.get_damage_bonus() + maxi(1, 1 + modifier))
			var maximum: int = maxi(1, actor.get_damage_bonus() + maxi(1, actor.get_ability_sides(ability) + modifier))
			note = tr("피해 %d~%d · 행동1 · 자동 명중\n같은 상자를 다시 좌클릭하면 공격합니다.") % [minimum, maximum]
		if not actions.can_attack_prop(actor, prop):
			if actor.action_left <= 0:
				note = tr("행동 없음")
			elif actor.is_stunned:
				note = tr("기절하여 공격 불가")
			else:
				note = actions.unavailable_reason(actor, "attack")
				if note.is_empty():
					note = tr("사거리 또는 높이 조건을 확인")
	return title + "\n" + note


func _jump_note(actor: CombatUnit, actions: CombatActions) -> String:
	var note: String = tr("점프 · 착지할 칸을 우클릭합니다.\n같은 칸을 다시 우클릭하면 확정합니다.")
	if _preview_path.is_empty():
		return note
	var cell: Vector2i = _preview_cell
	var reactors: int = actions.jump_reactors(actor, cell).size()
	var fall: int = actions.fall_damage(actor, cell)
	note = tr("점프 · 이동 %d · 보조 행동1\n%s · %s") % [actions.jump_cells(actor).get(cell, 0),
		tr_n("기회 공격 %d명", "기회 공격 %d명", reactors) % reactors if reactors > 0 else tr("기회 공격 없음"),
		tr("낙하 피해 %d") % fall if fall > 0 else tr("낙하 없음")]
	var water: String = actions.water_note(cell)
	if not water.is_empty():
		note += "\n" + water
	# 점프는 넘어가는 중간 칸에 서지 않으므로 미끌거림은 착지 칸 기준이다(#600).
	var slip: String = actions.slip_note(actor, [cell])
	if not slip.is_empty():
		note += "\n" + slip
	var pickup: String = actions.pickup_note(actor, [cell])
	if not pickup.is_empty():
		note += "\n" + pickup
	return note


func _sweep_note(actor: CombatUnit, actions: CombatActions, facing_preview: bool,
		sweep_targets: Array[CombatUnit]) -> String:
	if not facing_preview:
		return tr("휩쓸기 · 정면으로 삼을 인접한 칸을 좌클릭합니다.\n같은 칸을 다시 좌클릭하면 실행합니다.")
	if sweep_targets.is_empty():
		return tr("휩쓸기 · 행동1 · 영향 칸에 적이 없음\n같은 칸을 다시 좌클릭하면 실행합니다.")
	var chances: Array[String] = []
	for target: CombatUnit in sweep_targets:
		chances.append("%s %.1f%%" % [target.get_display_name(), actions.sweep_chance(actor, target) * 100.0])
	return tr("휩쓸기 · 행동1 · 시계방향 명중률\n%s\n같은 칸을 다시 좌클릭하면 실행합니다.") % " → ".join(chances)


func _whistle_note(actor: CombatUnit, facing_preview: bool, sweep_targets: Array[CombatUnit]) -> String:
	if not facing_preview:
		return tr("효시 · 방향으로 삼을 인접한 칸을 좌클릭합니다.\n같은 칸을 다시 좌클릭하면 실행합니다.")
	if sweep_targets.is_empty():
		return tr("효시 · 행동1 · 영향 칸에 적이 없음\n같은 칸을 다시 좌클릭하면 실행합니다.")
	var chances: Array[String] = []
	for target: CombatUnit in sweep_targets:
		chances.append(CombatActionRules.save_chance_text(actor, target, "whistle"))
	return tr("효시 · 행동1 · 전투마다 1 · 의지 내성 성공률\n%s\n같은 칸을 다시 좌클릭하면 실행합니다.") % " · ".join(chances)


## 두 화살의 안내 문구. 칸을 고르기 전에는 사용법을, 고른 뒤에는 확률과 맞는 유닛을 보인다.
func _arrow_note(actor: CombatUnit, actions: CombatActions, units: Array[CombatUnit],
		action: String, cell: Vector2i) -> String:
	var action_name: String = CombatActionRules.NAMES[action]
	if not actions.can_aim(actor, action, cell):
		return tr("%s · 행동1 · 겨눌 칸을 좌클릭합니다.\n같은 칸을 다시 좌클릭하면 쏩니다.") % action_name
	if action == "trick_arrow":
		var note: String = tr("장난스러운 화살 · 행동1 · 삐끗 16.7% · 물 33.3% · 화염 50%")
		var target: CombatUnit = actions.grid.unit_at(cell)
		if target != null and target.hit_points > 0:
			var preview: CombatChecks.AttackPreview = actions.grid.attack_preview(actor, target, action)
			note += "\n" + tr("%s 명중률 %.1f%%") % [target.get_display_name(), preview.chance * 100.0]
			if target.is_ally:
				note += " · " + tr("아군")
		if actions.grid.is_tree(cell):
			note += "\n" + tr("화염이 나오면 나무가 타서 길이 열림")
		return note + "\n" + tr("같은 칸을 다시 좌클릭하면 쏩니다.")
	var chances: Array[String] = []
	for unit: CombatUnit in units:
		if unit.hit_points > 0 and unit.cell in actions.aim_area(actor, action, cell):
			chances.append("%s %.1f%%" % [unit.get_display_name(), CombatActionRules.save_chance(actor, unit, action) * 100.0])
	var firework: String = tr("폭죽 화살 · 행동1 · 막당 1 · 아군과 자신도 맞음\n민첩 내성 성공률: %s\n같은 칸을 다시 좌클릭하면 쏩니다.") % (
		" · ".join(chances) if not chances.is_empty() else tr("대상 없음"))
	if actions.aim_area(actor, action, cell).any(func(area_cell: Vector2i) -> bool: return actions.grid.is_tree(area_cell)):
		firework += "\n" + tr("나무가 타서 길이 열림")
	return firework
