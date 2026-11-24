class_name CombatPresentation
extends Node2D
## 전투 연출 어댑터. 속도 계수, 단일 리플레이 음소거 게이트, 시그널→SFX/VFX 라우팅,
## 이동·공격·주사위 애니메이션 훅, 유닛 위 피드백 팝업 배치를 한 곳에서 맡는다.

## 유닛 이동·연출 시간의 전체 속도(#516 5절). 1보다 작으면 느려진다. 플레이로 조정하는 곳은 이 상수 하나다.
## 피해 팝업·주사위·HUD 시간과 Engine.time_scale에는 적용하지 않는다.
const PRESENTATION_SPEED: float = 0.7
const MOVE_STEP_TIME: float = 0.09
const ARROW_FLIGHT_TIME: float = 0.16
## 근접 공격 뒤 기다리는 시간(기본값). 전체 속도 계수로 늘어난다.
const MELEE_ATTACK_TIME: float = 1.0 / 6.0
const FEEDBACK_RISE: float = 12.0
const FEEDBACK_NEAR: float = 40.0

var _actions: CombatActions
var _map: CombatMap
var _hud: CombatTurnHud
var _dice_view: CombatDiceRollView
var _sounds: CombatSounds
var _hit_effects: CombatHitEffects
var _is_replaying: Callable
var _is_waiting_for_start: Callable
var _get_units: Callable
var _get_stage: Callable
var _show_enemy_action: Callable
var _follow_turn_tile: Callable
var _on_victory_downed: Callable


## 기본 시간(초)을 전체 속도로 늘린 값.
static func duration(base: float) -> float:
	return base / PRESENTATION_SPEED


## 기본 fps를 전체 속도로 늦춘 값.
static func fps(base: float) -> float:
	return base * PRESENTATION_SPEED


func bind(actions: CombatActions, turns: CombatTurns, map: CombatMap, hud: CombatTurnHud,
		dice_view: CombatDiceRollView, sounds: CombatSounds, hit_effects: CombatHitEffects,
		callbacks: Dictionary) -> void:
	_actions = actions
	_map = map
	_hud = hud
	_dice_view = dice_view
	_sounds = sounds
	_hit_effects = hit_effects
	_is_replaying = callbacks.get("is_replaying", Callable())
	_is_waiting_for_start = callbacks.get("is_waiting_for_start", Callable())
	_get_units = callbacks.get("get_units", Callable())
	_get_stage = callbacks.get("get_stage", Callable())
	_show_enemy_action = callbacks.get("show_enemy_action", Callable())
	_follow_turn_tile = callbacks.get("follow_turn_tile", Callable())
	_on_victory_downed = callbacks.get("on_victory_downed", Callable())

	actions.feedback.connect(_on_feedback)
	actions.healed.connect(_on_healed)
	actions.damaged.connect(_on_damaged)
	actions.critical_hit.connect(_on_critical_hit)
	actions.downed.connect(_on_downed)
	actions.self_used.connect(_on_self_used)
	actions.swept.connect(_on_swept)
	actions.status_applied.connect(_on_status_applied)
	actions.status_ticked.connect(_on_status_ticked)
	actions.oil_ignited.connect(_on_oil_ignited)
	actions.struck.connect(_on_struck)
	actions.movement_animation = animate_movement
	actions.jump_animation = animate_jump
	actions.attack_animation = animate_attack
	actions.cell_attack_animation = animate_cell_attack
	actions.roll_animation = animate_roll
	turns.turn_started.connect(on_turn_started)


func _is_muted() -> bool:
	return _is_replaying.is_valid() and bool(_is_replaying.call())


func _units() -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	if _get_units.is_valid():
		result.assign(_get_units.call())
	return result


## 진영이 바뀌는 턴 시작 신호음. 전투 준비 중과 이어하기 재실행에서는 내지 않는다.
func on_turn_started(unit: CombatUnit) -> void:
	if _is_muted():
		return
	if _is_waiting_for_start.is_valid() and bool(_is_waiting_for_start.call()):
		return
	_sounds.turn_started(unit)


func _on_feedback(unit: CombatUnit, text: String) -> void:
	if _is_muted():
		return
	show_feedback(unit, text, _hud.feedback_obstacles())


func _on_healed(unit: CombatUnit, amount: int) -> void:
	if _is_muted():
		return
	show_feedback(unit, str(amount), _hud.feedback_obstacles(), CombatUnit.HEAL_COLOR)
	_sounds.play(&"heal")
	_hit_effects.play_heal(unit)


func _on_damaged(target: Object) -> void:
	if _is_muted():
		return
	_sounds.play_hit(target)


func _on_critical_hit(_target: CombatUnit) -> void:
	if _is_muted():
		return
	_sounds.play_critical()


func _on_downed(unit: CombatUnit) -> void:
	if _is_muted():
		return
	_sounds.play(&"downed")
	_hit_effects.play_down(unit, _map.map_to_surface(unit.cell))
	if _on_victory_downed.is_valid():
		_on_victory_downed.call(unit)


func _on_self_used(actor: CombatUnit, action: String) -> void:
	if _is_muted():
		return
	if action == "holy_veil":
		_sounds.play(&"shield")
		_hit_effects.play_shield(actor)
	elif action == "battle_cry":
		_sounds.play(&"shout")
		for unit: CombatUnit in _units():
			if unit.hit_points > 0 and unit.battle_cry_source == actor:
				_hit_effects.play_buff(unit)


func _on_swept(actor: CombatUnit, facing: Vector2i) -> void:
	if _is_muted():
		return
	_hit_effects.play_sweep(actor, _map.map_to_local(facing) - _map.map_to_local(actor.cell))


func _on_status_applied(target: CombatUnit, kind: String) -> void:
	if _is_muted():
		return
	_hit_effects.play_status(_map.map_to_surface(target.cell), kind)


func _on_status_ticked(unit: CombatUnit, kind: String, _amount: int) -> void:
	if _is_muted():
		return
	_hit_effects.play_status(_map.map_to_surface(unit.cell), kind)


func _on_oil_ignited(cells: Array[Vector2i]) -> void:
	if _is_muted():
		return
	for cell: Vector2i in cells:
		_hit_effects.play_ignite(_map.map_to_surface(cell))


## 타격 섬광·히트스톱·빗나감 잔상(#559). 이어하기 재실행에서는 피해 팝업·피격음처럼 생략한다.
func _on_struck(attacker: CombatUnit, target: CombatUnit, cell: Vector2i, hit: bool) -> void:
	if _is_muted():
		return
	if not hit:
		_sounds.play(&"miss")
		_hit_effects.play_miss(attacker, target)
	elif target == null:
		_hit_effects.play_hit(attacker, null, _map.map_to_surface(cell) + Vector2(0, -8))
	else:
		_hit_effects.play_hit(attacker, target, target.position + Vector2(0, target.floor_offset_y - 14))


func animate_movement(unit: CombatUnit, cell: Vector2i) -> void:
	var destination: Vector2 = _map.map_to_local(cell)
	# 다시 실행할 때도 방향은 저장하는 상태라 그대로 바꾼다.
	if _is_muted():
		unit.face_toward(destination)
		return
	if _show_enemy_action.is_valid():
		await _show_enemy_action.call()
	unit.face_toward(destination)
	_sounds.play(CombatSounds.step_cue(_actions.grid, _get_stage.call(), cell))
	unit.is_moving = true
	var tween: Tween = create_tween().set_parallel()
	var step_time: float = duration(MOVE_STEP_TIME)
	tween.tween_property(unit, "position", destination, step_time)
	tween.tween_property(unit, "floor_offset_y", _map.map_to_surface(cell).y - destination.y, step_time)
	tween.tween_property(unit, "body_offset_y", -3.0, step_time / 2.0)
	tween.tween_property(unit, "body_offset_y", 0.0, step_time / 2.0).from(-3.0).set_delay(step_time / 2.0)
	await tween.finished
	unit.position = destination
	unit.body_offset_y = 0.0
	unit.is_moving = false
	if _follow_turn_tile.is_valid():
		_follow_turn_tile.call(unit, cell)


func animate_jump(unit: CombatUnit, cell: Vector2i) -> void:
	var destination: Vector2 = _map.map_to_local(cell)
	if _is_muted():
		unit.face_toward(destination)
		return
	if _show_enemy_action.is_valid():
		await _show_enemy_action.call()
	var step_duration: float = duration(MOVE_STEP_TIME * 2.0)
	var apex: float = -float(_map.tile_set.tile_size.y)
	unit.face_toward(destination)
	_sounds.play(&"jump")
	unit.is_moving = true
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(unit, "position", destination, step_duration)
	tween.tween_property(unit, "floor_offset_y", _map.map_to_surface(cell).y - destination.y, step_duration)
	tween.tween_property(unit, "body_offset_y", apex, step_duration / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(unit, "body_offset_y", 0.0, step_duration / 2.0).from(apex).set_delay(step_duration / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished
	unit.position = destination
	unit.body_offset_y = 0.0
	unit.is_moving = false
	if _follow_turn_tile.is_valid():
		_follow_turn_tile.call(unit, cell)
	_sounds.play(&"land")


func animate_attack(actor: CombatUnit, target: CombatUnit) -> void:
	var destination: Vector2 = target.position + Vector2(0, target.floor_offset_y - 14)
	if _is_muted():
		actor.face_toward(destination)
		return
	if _show_enemy_action.is_valid():
		await _show_enemy_action.call()
	await animate_attack_at(actor, destination)


## 아군이 굴릴 때만 보인다. 몬스터의 굴림과 이어하기로 다시 실행하는 굴림은 보이지 않는다.
func animate_roll(roll: CombatDiceRoll) -> void:
	if _is_muted() or not roll.roller.is_ally:
		return
	await _dice_view.play(roll)


## 빈 칸을 겨눈 화살 연출.
func animate_cell_attack(actor: CombatUnit, cell: Vector2i) -> void:
	await animate_attack_at(actor, _map.map_to_surface(cell) + Vector2(0, -8))


func animate_attack_at(actor: CombatUnit, destination: Vector2) -> void:
	actor.face_toward(destination)
	actor.play_attack()
	if actor.kind != CombatUnit.Kind.ARCHER:
		await get_tree().create_timer(duration(MELEE_ATTACK_TIME), false).timeout
		return
	var arrow: Polygon2D = Polygon2D.new()
	arrow.name = "Arrow"
	arrow.polygon = PackedVector2Array([
		Vector2(-4, -1), Vector2(4, -1), Vector2(4, 1), Vector2(-4, 1)
	])
	arrow.color = Color("efe4c8")
	arrow.z_index = 1
	arrow.position = actor.position + Vector2(-8 if actor.facing_left else 8, actor.floor_offset_y - 16)
	arrow.rotation = (destination - arrow.position).angle()
	var arrow_host: Node = get_parent() if get_parent() != null else self
	arrow_host.add_child(arrow)
	var tween: Tween = create_tween()
	tween.tween_property(arrow, "position", destination, duration(ARROW_FLIGHT_TIME))
	await tween.finished
	arrow.queue_free()


## 현재 화면에 떠 있는 피드백 팝업 목록.
func feedback_popups() -> Array[Label]:
	var popups: Array[Label] = []
	for child: Node in get_children():
		if child is Label and child.has_meta("feedback_unit"):
			popups.append(child as Label)
	return popups


## 스테이지 전환 시 남아 있는 피드백 팝업을 모두 정리한다.
func clear_feedback() -> void:
	for popup: Label in feedback_popups():
		popup.free()


## 유닛 위 피드백 팝업을 만들고 다른 팝업·상태 줄·HUD를 피해 배치한다.
func show_feedback(unit: CombatUnit, text: String, obstacles: Array[Rect2] = [],
		color: Color = CombatUnit.WEAPON_COLOR) -> Label:
	var popup: Label = Label.new()
	popup.z_index = 10
	popup.text = text
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_theme_font_size_override("font_size", 10)
	popup.add_theme_color_override("font_color", color)
	popup.add_theme_color_override("font_outline_color", CombatUnit.OUTLINE_COLOR)
	popup.add_theme_constant_override("outline_size", 2)
	popup.set_meta("feedback_unit", unit.get_instance_id())
	# 전투 불능 유닛도 마지막 피해를 표시한다.
	add_child(popup)
	popup.size = popup.get_combined_minimum_size()
	popup.position = _feedback_position(unit, popup, obstacles)
	var tween: Tween = popup.create_tween()
	tween.tween_property(popup, "position:y", popup.position.y - FEEDBACK_RISE, 0.8)
	tween.parallel().tween_property(popup, "modulate:a", 0.0, 0.8)
	tween.tween_callback(popup.queue_free)
	return popup


func _feedback_position(unit: CombatUnit, popup: Label, obstacles: Array[Rect2]) -> Vector2:
	var canvas: Transform2D = get_global_transform_with_canvas()
	var popup_size: Vector2 = (canvas * Rect2(Vector2.ZERO, popup.size)).size
	var rise: float = absf(canvas.basis_xform(Vector2(0, -FEEDBACK_RISE)).y)
	var canvas_scale: float = maxf(absf(canvas.get_scale().x), absf(canvas.get_scale().y))
	var padding: float = 2.0 * canvas_scale
	var viewport: Rect2 = get_viewport().get_visible_rect()
	var origin: Vector2 = canvas * (unit.position + Vector2(-16, unit.floor_offset_y + unit.get_status_label_y() - 5))
	var first: Vector2 = viewport.position + Vector2(padding, rise + padding)
	var center: Vector2 = origin.clamp(first, viewport.end - popup_size - Vector2.ONE * padding)
	# 화면 패널, 다른 대상 팝업의 상승 경로, 지금 보이는 상태 글자와 대상 자신의 상태 자리는 언제나 피한다.
	var blocked: Array[Rect2] = obstacles.duplicate()
	# 다른 유닛의 새 기절과 현재 화상·독을 읽을 자리는 근처에 빈 자리가 있을 때만 비워 둔다.
	var reserved: Array[Rect2] = []
	# 같은 대상의 팝업은 이전 팝업 위에 순서대로 쌓는다(#260).
	var ceiling: float = INF
	for other: CombatUnit in _units():
		var periodic: String = other.get_periodic_status_text()
		var area: Rect2 = other.get_status_area(
			tr("기절") + (" " + periodic if not periodic.is_empty() else ""), padding)
		if other == unit:
			blocked.append(area)
		else:
			reserved.append(area)
		var shown: String = other.get_status_text()
		if not shown.is_empty():
			blocked.append(other.get_status_area(shown, padding))
	for existing: Label in feedback_popups():
		if existing == popup:
			continue
		var area: Rect2 = canvas * existing.get_rect()
		if existing.get_meta("feedback_unit") == unit.get_instance_id():
			# 같은 대상의 팝업은 같은 속도로 떠오르므로 상승 경로를 비우지 않고 바로 위에 쌓는다.
			ceiling = minf(ceiling, area.position.y - 2.0 * padding)
			blocked.append(area.grow(padding))
			continue
		area.position.y -= rise
		area.size.y += rise
		blocked.append(area.grow(padding))
	var anchor: Vector2 = Vector2(center.x, minf(center.y, ceiling - popup_size.y - padding))
	var near: float = FEEDBACK_NEAR * canvas_scale
	var quantum: float = 2.0 * padding
	var steps: int = floori(near / quantum)
	var nearby: Array[Vector2] = _spot_grid(anchor, quantum, steps, steps, steps, near)
	var screen: Array[Vector2] = []
	var step: Vector2 = popup_size + Vector2(padding * 2, rise + padding * 2)
	for row: int in range(ceili(viewport.size.y / step.y)):
		for column: int in range(ceili(viewport.size.x / step.x)):
			screen.append(first + Vector2(column, row) * step)
	var all_blocked: Array[Rect2] = blocked + reserved
	# 1~2: 기준 자리 40px 안. 근처가 차면 다른 유닛의 상태 자리 예약을 풀고 다시 찾는다.
	# 3: 기준 자리 위쪽 띠(가로 ±40px)로 쌓는다. 4: 위가 막히면 순서를 포기하고 대상 기준점 40px 안에서 찾는다.
	# 5~6: 그래도 없으면 전처럼 화면 전체에서 대상에 가장 가까운 빈 자리를 쓴다.
	for search: Array in [[nearby, all_blocked, ceiling, anchor], [nearby, blocked, ceiling, anchor],
			[_spot_grid(anchor, quantum, steps, 0, ceili((anchor.y - first.y) / quantum)), blocked, ceiling, anchor],
			[_spot_grid(center, quantum, steps, steps, steps, near), blocked, INF, center],
			[screen, all_blocked, INF, center], [screen, blocked, INF, center]]:
		var found: Variant = _closest_free_spot(search[0], search[3], popup_size, rise, padding, search[1], search[2])
		if found != null:
			return canvas.affine_inverse() * (found as Vector2)
	return canvas.affine_inverse() * center


## base에서 quantum 간격의 후보 격자. 가로 ±columns칸, 아래 down칸에서 위 up칸까지. radius 밖은 뺀다.
func _spot_grid(base: Vector2, quantum: float, columns: int, down: int, up: int, radius: float = INF) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	for row: int in range(-down, up + 1):
		for column: int in range(-columns, columns + 1):
			var offset: Vector2 = Vector2(column, -row) * quantum
			if offset.length() <= radius:
				spots.append(base + offset)
	return spots


## 후보 중 기준점에 가장 가까운 빈 자리. 없으면 null. 팝업 아래쪽은 ceiling을 넘지 않는다.
func _closest_free_spot(candidates: Array[Vector2], target: Vector2, popup_size: Vector2, rise: float,
		padding: float, blocked: Array[Rect2], ceiling: float) -> Variant:
	var viewport: Rect2 = get_viewport().get_visible_rect()
	var best: Variant = null
	var distance: float = INF
	for candidate: Vector2 in candidates:
		var candidate_distance: float = candidate.distance_squared_to(target)
		if candidate_distance >= distance:
			continue
		# 위로 뜨는 전체 경로를 예약해 연출 중에도 팝업과 HUD를 피한다.
		var area: Rect2 = Rect2(candidate - Vector2(0, rise), popup_size + Vector2(0, rise)).grow(padding)
		if not viewport.encloses(area) or area.end.y > ceiling:
			continue
		var available: bool = true
		for rect: Rect2 in blocked:
			if area.intersects(rect):
				available = false
				break
		if available:
			best = candidate
			distance = candidate_distance
	return best
