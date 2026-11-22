class_name CombatSelection
extends RefCounted
## 전투 조작의 선택·미리보기·실행 연결.
## 좌표 해석과 화면 그리기는 battle이 맡고, 조준 규칙·미리보기 모델·동작 실행은 이 모듈이 맡는다.

class Preview:
	extends RefCounted
	var movement_cells: Array[Vector2i] = []
	var attack_cells: Array[Vector2i] = []
	var path: Array[Vector2i] = []
	var origin: Vector2i = Vector2i.ZERO
	var previewed_units: Array[CombatUnit] = []
	var preview_prop: CombatGrid.Prop
	var attack_preview_target: CombatUnit
	var attack_preview: CombatChecks.AttackPreview
	var rock_roll: CombatActions.RockRoll
	var inspected_unit: CombatUnit
	var target_note: String = ""
	var show_move_mode: bool = false

var selected_action: String = "attack"
var preview_target: CombatUnit
var preview_prop: CombatGrid.Prop
var preview_cell: Vector2i = Vector2i(-1, -1)
var preview_path: Array[Vector2i] = []
var inspected_unit: CombatUnit

var _actions: CombatActions
var _prop_executor: Callable


func bind(actions: CombatActions, prop_executor: Callable = Callable()) -> void:
	_actions = actions
	_prop_executor = prop_executor


func reset() -> void:
	selected_action = "attack"
	inspected_unit = null
	clear_preview()


func clear_preview() -> void:
	preview_target = null
	preview_prop = null
	preview_cell = Vector2i(-1, -1)
	preview_path.clear()


func inspect(unit: CombatUnit) -> void:
	if CombatActionRules.is_move_action(selected_action):
		selected_action = "attack"
	clear_preview()
	inspected_unit = unit


## 같은 자기 대상 동작을 다시 선택하면 호출자가 실행한다.
func select_action(action: String) -> bool:
	inspected_unit = null
	clear_preview()
	if action == selected_action and CombatActionRules.is_self_target(action):
		return true
	selected_action = action
	return false


## 스킬 바 선택. 일어나기와 자기 대상 2회 클릭 실행까지 처리한다.
func choose_action(actor: CombatUnit, action: String) -> bool:
	if _actions == null or actor == null or not actor.is_ally:
		return false
	if action == "stand_up":
		_actions.stand_up(actor)
		return true
	if not _actions.can_use(actor, action):
		return false
	if select_action(action):
		_actions.use_self(actor, action)
		finish_execution()
	return true


func begin_field_input(left_click: bool) -> void:
	inspected_unit = null
	if left_click and CombatActionRules.is_move_action(selected_action):
		selected_action = "attack"
		clear_preview()


## 유효한 같은 목적지를 다시 선택하면 호출자가 이동을 실행한다. 점프·무빙샷 도약도 같은 두 번 우클릭이다.
func select_move(cell: Vector2i, path: Array[Vector2i]) -> bool:
	if selected_action not in ["jump", "moving_shot"]:
		selected_action = "move"
	var confirmed: bool = not path.is_empty() and cell == preview_cell
	clear_preview()
	if not confirmed and not path.is_empty():
		preview_cell = cell
		preview_path = path.duplicate()
	return confirmed


## 우클릭 이동·점프·무빙샷 도약의 미리보기와 확정 실행.
func right_click_cell(actor: CombatUnit, cell: Vector2i) -> bool:
	if _actions == null or actor == null or not actor.is_ally:
		return false
	begin_field_input(false)
	var path: Array[Vector2i] = []
	var jumping: bool = selected_action == "jump"
	# 무빙샷 도약도 점프처럼 착지 칸을 먼저 보고 같은 칸을 다시 우클릭하면 뛴다(#528).
	var leaping: bool = selected_action == "moving_shot"
	if leaping:
		if cell in _actions.moving_shot_cells(actor):
			path = [cell]
	elif jumping and _actions.jump_cells(actor).has(cell):
		path = _actions.grid.jump_path(actor, cell)
	elif not jumping and _actions.can_move(actor, cell):
		path = _actions.grid.path_to(actor, cell)
	if select_move(cell, path):
		var executed: bool
		if leaping:
			executed = await _actions.moving_shot(actor, cell)
		elif jumping:
			executed = await _actions.jump_to(actor, cell)
		else:
			executed = await _actions.move_to(actor, cell)
		if executed:
			finish_execution()
	return true


## 좌클릭 필드 입력의 조준·미리보기·확정 실행. 빈 칸 정리만 했으면 false다.
func left_click_field(actor: CombatUnit, cell: Vector2i, target: CombatUnit = null, prop: CombatGrid.Prop = null,
		facing_cell: Vector2i = Vector2i(-1, -1), prop_in_front: bool = true) -> bool:
	if _actions == null or actor == null or not actor.is_ally:
		return false
	begin_field_input(true)
	if CombatActionRules.is_aim_action(selected_action):
		var aimed_cell: Vector2i = cell
		if CombatActionRules.aim_snaps_entity(selected_action):
			# 유닛 몸통이나 사물을 눌러도 그 칸을 고른다.
			if target != null:
				aimed_cell = target.cell
			elif prop != null:
				aimed_cell = prop.cell
		await _select_aim_cell(actor, aimed_cell)
		return true
	if CombatActionRules.is_facing_action(selected_action):
		var facing: Vector2i = facing_cell if facing_cell != Vector2i(-1, -1) else cell
		await _select_facing_cell(actor, facing)
		return true
	# 윤곽이 보이는 가린 유닛은 몸통 클릭이 동작할 때만 앞 사물보다 우선한다.
	var unit_first: bool = target != null and target.is_occluded and (
		not target.is_ally or CombatActionRules.allows_ally_target(selected_action))
	if prop != null and not unit_first and prop_in_front:
		if select_prop(prop, CombatActionRules.allows_prop_target(selected_action) and _actions.can_attack_prop(actor, prop)):
			begin_execution()
			var completed: bool = true
			if _prop_executor.is_valid():
				completed = await _prop_executor.call(actor, prop)
			else:
				_actions.attack_prop(actor, prop)
			if not completed:
				return true
			finish_execution()
			_offer_moving_shot(actor)
		return true
	if target != null:
		if target.is_ally and not CombatActionRules.allows_ally_target(selected_action):
			clear_preview()
		elif select_target(target, _actions.can_target(actor, target, selected_action)):
			await _execute_target(actor, target)
		return true
	clear_preview()
	return false


func preview_unit(target: CombatUnit) -> void:
	clear_preview()
	preview_target = target


func preview_enemy(actor: CombatUnit, target: CombatUnit, units: Array[CombatUnit]) -> bool:
	if actor == null or not actor.is_ally or target not in units or target.is_ally or target.hit_points <= 0:
		return false
	preview_unit(target)
	return true


func select_target(target: CombatUnit, can_execute: bool) -> bool:
	if target == preview_target and can_execute:
		return true
	preview_unit(target)
	return false


## 칸을 조준하는 동작(휩쓸기·효시·화살·기름). 실행할 수 있는 같은 칸을 다시 선택하면 호출자가 실행한다.
func select_cell(cell: Vector2i, can_execute: bool) -> bool:
	if cell == preview_cell and preview_path.is_empty() and can_execute:
		return true
	clear_preview()
	preview_cell = cell
	return false


func select_prop(prop: CombatGrid.Prop, can_execute: bool) -> bool:
	if prop == preview_prop and can_execute:
		return true
	clear_preview()
	preview_prop = prop
	return false


func begin_execution() -> String:
	var action: String = selected_action
	clear_preview()
	return action


func finish_execution() -> void:
	selected_action = "attack"


func discard_incapacitated_inspection() -> void:
	if inspected_unit != null and inspected_unit.hit_points <= 0:
		inspected_unit = null


## 현재 선택 상태의 화면 표시 모델(강조 칸, 대상 윤곽, 공격/바위 미리보기, 안내 문구)을 계산한다.
func build_preview(actor: CombatUnit, units: Array[CombatUnit], hover_cell: Vector2i = Vector2i(-1, -1)) -> Preview:
	var preview: Preview = Preview.new()
	discard_incapacitated_inspection()
	if _actions == null:
		return preview
	if preview_prop != null and preview_prop not in _actions.get_props():
		clear_preview()
	var is_facing: bool = CombatActionRules.is_facing_action(selected_action)
	var facing_preview: bool = is_facing and actor != null and actor.is_ally and preview_cell != Vector2i(-1, -1)
	var facing_targets: Array[CombatUnit] = []
	if facing_preview:
		facing_targets = (_actions.sweep_targets(actor, preview_cell) if selected_action == "sweep"
			else _actions.whistle_targets(actor, preview_cell))
	for unit: CombatUnit in units:
		if (unit == preview_target
			or (not preview_path.is_empty() and _actions.can_target(actor, unit, "attack", preview_cell))
			or unit in facing_targets):
			preview.previewed_units.append(unit)
	if actor != null and actor.is_ally:
		if selected_action == "move":
			preview.movement_cells.assign(_actions.reachable_cells(actor).keys())
		elif selected_action == "jump":
			preview.movement_cells.assign(_actions.jump_cells(actor).keys())
		elif selected_action == "moving_shot":
			preview.movement_cells.assign(_actions.moving_shot_cells(actor))
		elif facing_preview:
			preview.movement_cells.assign(_actions.grid.sweep_cells(actor.cell, preview_cell)
				if selected_action == "sweep" else _actions.grid.band_cells(actor.cell, preview_cell))
		elif CombatActionRules.is_aim_action(selected_action):
			var aimed: bool = _actions.can_aim(actor, selected_action, preview_cell)
			if aimed and CombatActionRules.aim_radius(selected_action) < 0:
				preview.movement_cells.assign([preview_cell])
			elif aimed:
				preview.movement_cells.assign(_actions.aim_area(actor, selected_action, preview_cell))
			else:
				preview.movement_cells.assign(_actions.aim_cells(actor, selected_action))
		elif is_facing:
			# 방향을 고르기 전에는 고를 수 있는 인접 칸을 보인다.
			for cell: Vector2i in CombatGrid.neighbors(actor.cell):
				if _can_face(actor, selected_action, cell):
					preview.movement_cells.append(cell)
	preview.origin = actor.cell if actor != null else Vector2i.ZERO
	preview.path = preview_path.duplicate()
	if _actions.pending_kind == "reflex" and _actions.pending_reactor != null:
		# 반사신경 확인 창이 열린 동안에는 회피할 후보 칸만 이동 칸처럼 보인다.
		preview.movement_cells.assign(_actions.pending_cells)
		preview.origin = _actions.pending_reactor.cell
		preview.path.clear()
	else:
		for cell: Vector2i in preview.movement_cells:
			if is_facing or not _attack_targets_from(actor, units, cell).is_empty():
				preview.attack_cells.append(cell)
	preview.preview_prop = preview_prop
	preview.show_move_mode = selected_action == "move" or not preview_path.is_empty()
	_fill_preview_details(preview, actor, units, hover_cell, facing_preview, facing_targets)
	return preview


func _select_aim_cell(actor: CombatUnit, cell: Vector2i) -> void:
	var action: String = selected_action
	if select_cell(cell, _actions.can_aim(actor, action, cell)):
		begin_execution()
		match action:
			"oil_throw", "oil_bottle":
				_actions.throw_oil(actor, cell, action)
			"trick_arrow":
				await _actions.trick_arrow(actor, cell)
			"firework_arrow":
				await _actions.firework_arrow(actor, cell)
		finish_execution()
		_offer_moving_shot(actor)


func _select_facing_cell(actor: CombatUnit, facing: Vector2i) -> void:
	var action: String = selected_action
	if CombatGrid.distance(actor.cell, facing) != 1 or not _actions.grid.is_inside(facing):
		clear_preview()
	elif select_cell(facing, _can_face(actor, action, facing)):
		begin_execution()
		if action == "sweep":
			await _actions.sweep(actor, facing)
		else:
			await _actions.whistle(actor, facing)
		finish_execution()


func _execute_target(actor: CombatUnit, target: CombatUnit) -> void:
	var action: String = begin_execution()
	match action:
		"attack":
			await _actions.attack(actor, target)
		"cross_slash":
			await _actions.cross_slash(actor, target)
		"steel_charge":
			await _actions.steel_charge(actor, target)
		"bow_bash":
			await _actions.bow_bash(actor, target)
		"shove":
			_actions.shove(actor, target)
	finish_execution()
	_offer_moving_shot(actor)


## 무빙샷을 쓸 수 있게 되면 선택을 도약으로 바꿔 도착 칸을 보인다(#528).
func _offer_moving_shot(actor: CombatUnit) -> void:
	if (actor != null and actor.moving_shot_ready
			and (_actions.turns == null or actor == _actions.turns.current_unit)):
		selected_action = "moving_shot"


func _can_face(actor: CombatUnit, action: String, facing: Vector2i) -> bool:
	return _actions.can_sweep(actor, facing) if action == "sweep" else _actions.can_whistle(actor, facing)


func _attack_targets_from(actor: CombatUnit, units: Array[CombatUnit], cell: Vector2i) -> Array[CombatUnit]:
	var targets: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if _actions.can_target(actor, unit, "attack", cell):
			targets.append(unit)
	return targets


func _fill_preview_details(preview: Preview, actor: CombatUnit, units: Array[CombatUnit], hover_cell: Vector2i,
		facing_preview: bool, facing_targets: Array[CombatUnit]) -> void:
	if preview_target != null:
		# 고른 동작의 명중 능력치·근접 여부를 따른다(활 후려치기는 힘 d6, 원거리 불리 없음).
		preview.attack_preview_target = preview_target
		preview.attack_preview = _actions.grid.attack_preview(actor, preview_target, selected_action)
		preview.target_note = _target_action_note(actor, preview_target)
	elif preview_prop != null:
		preview.target_note = _prop_note(preview, actor, preview_prop)
	elif inspected_unit != null:
		preview.inspected_unit = inspected_unit
	# 걷기·무빙샷 도약 미리보기는 안내를 숨기지만, 도착 칸이 물이면 서기 전에 물 칸 화상 규칙을, 기름 칸이면 미끌거림 안내를 보인다(#503, #600).
	if selected_action != "jump" and not preview_path.is_empty():
		var notes: Array[String] = []
		for note: String in [_actions.water_note(preview_cell),
				_actions.slip_note(actor, preview_path),
				_actions.pickup_note(actor, preview_path)]:
			if not note.is_empty():
				notes.append(note)
		if not notes.is_empty():
			preview.show_move_mode = false
			preview.target_note = "\n".join(notes)
	if selected_action == "jump":
		preview.show_move_mode = false
		preview.target_note = _jump_note(actor)
	elif actor != null and actor.is_ally and not _actions.busy:
		if selected_action == "sweep":
			preview.target_note = _sweep_note(actor, facing_preview, facing_targets)
		elif selected_action == "whistle":
			preview.target_note = _whistle_note(actor, facing_preview, facing_targets)
		elif CombatActionRules.is_oil_action(selected_action):
			var oil_name: String = CombatActionRules.NAMES[selected_action]
			preview.target_note = (tr("%s · 보조 행동1 · 기름을 깔 칸을 좌클릭합니다.\n같은 칸을 다시 좌클릭하면 던집니다.") % oil_name
				if not _actions.can_aim(actor, selected_action, preview_cell)
				else tr("%s · 보조 행동1 · 십자 5칸 기름 3턴\n같은 칸을 다시 좌클릭하면 던집니다.") % oil_name)
		elif CombatActionRules.is_aim_action(selected_action):
			preview.target_note = _arrow_note(actor, units, selected_action, preview_cell)
	var hovered: Dictionary = _actions.floor_loot.item_at(hover_cell)
	if (not hovered.is_empty() and preview_target == null and preview_prop == null and preview_path.is_empty()
			and selected_action not in ["jump", "moving_shot"]
			and not CombatActionRules.is_aim_action(selected_action)
			and not CombatActionRules.is_facing_action(selected_action)):
		preview.show_move_mode = false
		preview.target_note = tr("바닥 아이템 · %s") % CombatLoot.describe(hovered)


func _target_action_note(actor: CombatUnit, target: CombatUnit) -> String:
	if selected_action == "shove":
		if _actions.can_target(actor, target, "shove"):
			var cell: Vector2i = _actions.grid.push_destination(actor.cell, target.cell)
			var landing: String = _actions.shove_landing(target, cell)
			var chance: float = 1.0
			if CombatActionRules.shove_saves(actor, target):
				chance -= CombatActionRules.save_chance(actor, target, "shove")
			return (tr("밀려날 칸: %d, %d") % [cell.x, cell.y]
				+ ("" if landing.is_empty() else " · " + landing) + " · " + tr("밀칠 확률 %.1f%%") % (chance * 100.0))
		return tr("밀치기를 사용할 수 없음")
	if selected_action == "steel_charge":
		if not _actions.can_target(actor, target, "steel_charge"):
			return tr("강철 돌진을 사용할 수 없음")
		# 전진하는 아군은 대상이 있던 칸에 도착해 그 칸의 아이템을 줍는다 (환경요소 3-5).
		var advance: String = _actions.pickup_note(actor, [target.cell])
		if _actions.grid.can_shove(actor, target):
			var cell: Vector2i = _actions.grid.push_destination(actor.cell, target.cell)
			var landing: String = _actions.shove_landing(target, cell)
			return (tr("명중하면 밀려날 칸: %d, %d") % [cell.x, cell.y]
				+ ("" if landing.is_empty() else " · " + landing) + ("" if advance.is_empty() else " · " + advance))
		return (tr("밀려날 칸이 막힘 · 명중하면 피해만, 쓰러뜨리면 그 칸으로 전진")
			+ ("" if advance.is_empty() else " · " + advance))
	return ""


func _prop_note(preview: Preview, actor: CombatUnit, prop: CombatGrid.Prop) -> String:
	var note: String = tr("기본 공격만 가능")
	var title: String = tr("바위") if prop.kind == "rock" else tr("나무 상자 · 내구도 %d/6") % prop.hit_points
	if CombatActionRules.allows_prop_target(selected_action) and actor != null:
		if prop.kind == "rock":
			var roll: CombatActions.RockRoll = _actions.preview_rock(actor, prop)
			preview.rock_roll = roll
			var direction: String = {
				Vector2i.RIGHT: tr("오른쪽 아래"), Vector2i.DOWN: tr("왼쪽 아래"),
				Vector2i.LEFT: tr("왼쪽 위"), Vector2i.UP: tr("오른쪽 위")
			}.get(roll.direction, tr("방향 없음"))
			var collisions: Array[String] = []
			for unit: CombatUnit in roll.collisions:
				var landing: String = _actions.rock_collision_note(roll, unit)
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
		if not _actions.can_attack_prop(actor, prop):
			if actor.action_left <= 0:
				note = tr("행동 없음")
			elif actor.is_stunned:
				note = tr("기절하여 공격 불가")
			else:
				note = _actions.unavailable_reason(actor, "attack")
				if note.is_empty():
					note = tr("사거리 또는 높이 조건을 확인")
	return title + "\n" + note


func _jump_note(actor: CombatUnit) -> String:
	var note: String = tr("점프 · 착지할 칸을 우클릭합니다.\n같은 칸을 다시 우클릭하면 확정합니다.")
	if not preview_path.is_empty():
		var cell: Vector2i = preview_cell
		var reactors: int = _actions.jump_reactors(actor, cell).size()
		var fall: int = _actions.fall_damage(actor, cell)
		note = tr("점프 · 이동 %d · 보조 행동1\n%s · %s") % [_actions.jump_cells(actor).get(cell, 0),
			tr_n("기회 공격 %d명", "기회 공격 %d명", reactors) % reactors if reactors > 0 else tr("기회 공격 없음"),
			tr("낙하 피해 %d") % fall if fall > 0 else tr("낙하 없음")]
		var water: String = _actions.water_note(cell)
		if not water.is_empty():
			note += "\n" + water
		# 점프는 넘어가는 중간 칸에 서지 않으므로 미끌거림은 착지 칸 기준이다(#600).
		var slip: String = _actions.slip_note(actor, [cell])
		if not slip.is_empty():
			note += "\n" + slip
		var pickup: String = _actions.pickup_note(actor, [cell])
		if not pickup.is_empty():
			note += "\n" + pickup
	return note


func _sweep_note(actor: CombatUnit, facing_preview: bool, facing_targets: Array[CombatUnit]) -> String:
	if not facing_preview:
		return tr("휩쓸기 · 정면으로 삼을 인접한 칸을 좌클릭합니다.\n같은 칸을 다시 좌클릭하면 실행합니다.")
	if facing_targets.is_empty():
		return tr("휩쓸기 · 행동1 · 영향 칸에 적이 없음\n같은 칸을 다시 좌클릭하면 실행합니다.")
	var chances: Array[String] = []
	for target: CombatUnit in facing_targets:
		chances.append("%s %.1f%%" % [target.get_display_name(), _actions.sweep_chance(actor, target) * 100.0])
	return tr("휩쓸기 · 행동1 · 시계방향 명중률\n%s\n같은 칸을 다시 좌클릭하면 실행합니다.") % " → ".join(chances)


func _whistle_note(actor: CombatUnit, facing_preview: bool, facing_targets: Array[CombatUnit]) -> String:
	if not facing_preview:
		return tr("효시 · 방향으로 삼을 인접한 칸을 좌클릭합니다.\n같은 칸을 다시 좌클릭하면 실행합니다.")
	if facing_targets.is_empty():
		return tr("효시 · 행동1 · 영향 칸에 적이 없음\n같은 칸을 다시 좌클릭하면 실행합니다.")
	var chances: Array[String] = []
	for target: CombatUnit in facing_targets:
		chances.append(CombatActionRules.save_chance_text(actor, target, "whistle"))
	return tr("효시 · 행동1 · 전투마다 1 · 의지 내성 성공률\n%s\n같은 칸을 다시 좌클릭하면 실행합니다.") % " · ".join(chances)


## 두 화살의 안내 문구. 칸을 고르기 전에는 사용법을, 고른 뒤에는 확률과 맞는 유닛을 보인다.
func _arrow_note(actor: CombatUnit, units: Array[CombatUnit], action: String, cell: Vector2i) -> String:
	var name: String = CombatActionRules.NAMES[action]
	if not _actions.can_aim(actor, action, cell):
		return tr("%s · 행동1 · 겨눌 칸을 좌클릭합니다.\n같은 칸을 다시 좌클릭하면 쏩니다.") % name
	if action == "trick_arrow":
		var note: String = tr("장난스러운 화살 · 행동1 · 삐끗 16.7% · 물 33.3% · 화염 50%")
		var target: CombatUnit = _actions.grid.unit_at(cell)
		if target != null and target.hit_points > 0:
			var attack_preview: CombatChecks.AttackPreview = _actions.grid.attack_preview(actor, target, action)
			note += "\n" + tr("%s 명중률 %.1f%%") % [target.get_display_name(), attack_preview.chance * 100.0]
			if target.is_ally:
				note += " · " + tr("아군")
		if _actions.grid.is_tree(cell):
			note += "\n" + tr("화염이 나오면 나무가 타서 길이 열림")
		return note + "\n" + tr("같은 칸을 다시 좌클릭하면 쏩니다.")
	var chances: Array[String] = []
	for unit: CombatUnit in units:
		if unit.hit_points > 0 and unit.cell in _actions.aim_area(actor, action, cell):
			chances.append("%s %.1f%%" % [unit.get_display_name(), CombatActionRules.save_chance(actor, unit, action) * 100.0])
	var firework: String = tr("폭죽 화살 · 행동1 · 막당 1 · 아군과 자신도 맞음\n민첩 내성 성공률: %s\n같은 칸을 다시 좌클릭하면 쏩니다.") % (
		" · ".join(chances) if not chances.is_empty() else tr("대상 없음"))
	if _actions.aim_area(actor, action, cell).any(func(area_cell: Vector2i) -> bool: return _actions.grid.is_tree(area_cell)):
		firework += "\n" + tr("나무가 타서 길이 열림")
	return firework
