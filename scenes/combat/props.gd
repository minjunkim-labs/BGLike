class_name CombatProps
extends RefCounted
## 환경 오브젝트(나무 상자·바위) 생성, 공격 판정, 바위 굴리기 시뮬레이션과 미리보기를 맡는다.

## 바위 충돌 뒤 살아남은 대상의 민첩 내성 DC (환경요소 4장).
const ROCK_STUN_DC: int = 10


class RockStep extends RefCounted:
	var cell: Vector2i
	var target: CombatUnit
	var damage: int = 0
	var push: bool = false
	var push_cell: Vector2i
	var advance: bool = true
	var destroyed: bool = false
	var reason: String = ""


class RockRoll extends RefCounted:
	var direction: Vector2i = Vector2i.ZERO
	var cells: Array[Vector2i] = []
	var steps: Array[RockStep] = []
	var collisions: Array[CombatUnit] = []
	var stop_cell: Vector2i
	var destroyed: bool = false
	var reason: String = TranslationServer.tr("최대3칸")


var _host_ref: WeakRef


func bind(host: Object) -> void:
	_host_ref = weakref(host) if host != null else null


func _host() -> Object:
	return _host_ref.get_ref() if _host_ref != null else null


func create(cell: Vector2i, kind: String) -> CombatGrid.Prop:
	var host: Object = _host()
	var grid: CombatGrid = host.grid
	if (kind not in ["crate", "rock"] or not grid.is_floor(cell) or grid.is_blocked(cell)
		or grid.unit_at(cell) != null or grid.prop_at(cell) != null):
		return null
	var prop: CombatGrid.Prop = CombatGrid.Prop.new(cell, kind)
	grid.props.append(prop)
	host.changed.emit()
	return prop


func all() -> Array[CombatGrid.Prop]:
	var grid: CombatGrid = _host().grid
	return grid.props.duplicate()


func can_attack(actor: CombatUnit, prop: CombatGrid.Prop) -> bool:
	var host: Object = _host()
	var grid: CombatGrid = host.grid
	if (not is_instance_valid(actor) or host.turns == null or actor not in host.units
		or not host._can_act(actor) or host.turns.is_turn_finished(actor) or actor.action_left <= 0
		or not CombatActionRules.belongs_to(actor, "attack")
		or prop == null or prop not in grid.props or prop.hit_points <= 0):
		return false
	return (grid.in_range(actor.cell, prop.cell, actor.get_attack_range())
		and (actor.get_attack_range() > 1 or grid.are_adjacent(actor.cell, prop.cell))
		and not host.cover_for_prop(actor, prop, "attack").blocked)


func attack(actor: CombatUnit, prop: CombatGrid.Prop, animation: Callable = Callable()) -> bool:
	if not can_attack(actor, prop):
		return false
	var host: Object = _host()
	var grid: CombatGrid = host.grid
	var revision: int = host._revision
	host.busy = true
	if animation.is_valid():
		var roll: RockRoll = preview_rock(actor, prop) if prop.kind == "rock" else null
		var outcome: Variant = await animation.call(actor, prop, roll)
		if outcome is bool and not outcome:
			return false
	if revision != host._revision:
		host.busy = false
		return false
	if (prop not in grid.props or prop.hit_points <= 0 or not is_instance_valid(actor)
		or actor not in host.units or actor.hit_points <= 0 or host.is_over()):
		host.busy = false
		host.changed.emit()
		return false
	actor.moving_shot_ready = false
	host._break_stealth(actor)
	actor.spend_resource(CombatUnit.TurnResource.ACTION)
	host.last_damage_rolls.clear()
	# 나무 상자·바위 공격도 기본 공격이라 애기살 1발을 쓴다. 바위는 피해 굴림이 없다.
	var aegisal: bool = host._spend_aegisal(actor, "attack")
	if prop.kind == "rock":
		host.last_damage = 0
		host.damaged.emit(prop)
		_roll_rock(actor, prop)
		host._arm_moving_shot(actor)
		host.busy = false
		host.changed.emit()
		return true
	var prop_ability: CombatUnit.Ability = CombatActionRules.damage_ability(actor, "attack")
	for roll: int in range(2 if aegisal else 1):
		host.last_damage_rolls.append(CombatChecks.damage_roll(
			actor.get_ability_sides(prop_ability), host.dice, actor.get_ability_modifier(prop_ability)))
	if (prop not in grid.props or not is_instance_valid(actor) or actor not in host.units
		or actor.hit_points <= 0 or host.is_over()):
		host.busy = false
		host.changed.emit()
		return false
	host.last_damage = actor.get_damage_bonus()
	if aegisal:
		host.last_damage += int(host.last_damage_rolls.max())
	else:
		for rolled: int in host.last_damage_rolls:
			host.last_damage += rolled
	host.last_damage = maxi(1, host.last_damage)
	host._arm_moving_shot(actor)
	prop.hit_points = maxi(0, prop.hit_points - host.last_damage)
	if prop.hit_points == 0:
		grid.props.erase(prop)
	var message: String = tr("%s 나무 상자 공격: %d, %d · 피해 %d · 내구도 %d/6%s") % [
		actor.get_display_name(), prop.cell.x, prop.cell.y, host.last_damage, prop.hit_points,
		tr(" · 파괴") if prop.hit_points == 0 else ""]
	host.hit_landed.emit()
	host.damaged.emit(prop)
	host.struck.emit(actor, null, prop.cell, true)
	host.logged.emit(message)
	# 명중 callback이 전투를 다시 시작했으면 지난 전투의 상자는 아이템을 떨어뜨리지 않는다.
	if prop.hit_points == 0 and revision == host._revision:
		host._drop_crate_item(prop.cell)
	host.busy = false
	host.changed.emit()
	return true


func preview_rock(actor: CombatUnit, prop: CombatGrid.Prop) -> RockRoll:
	var host: Object = _host()
	var roll: RockRoll = RockRoll.new()
	if (not is_instance_valid(actor) or prop == null or prop not in host.grid.props
		or prop.kind != "rock" or prop.hit_points <= 0):
		roll.reason = tr("대상 없음")
		return roll
	var offset: Vector2i = prop.cell - actor.cell
	roll.direction = (Vector2i(signi(offset.x), 0) if absi(offset.x) >= absi(offset.y)
		else Vector2i(0, signi(offset.y)))
	if roll.direction == Vector2i.ZERO:
		roll.reason = tr("방향 없음")
		return roll
	return _trace_rock(prop, roll.direction, 3, [])


func _trace_rock(prop: CombatGrid.Prop, direction: Vector2i, limit: int,
		damaged: Array[CombatUnit]) -> RockRoll:
	var host: Object = _host()
	var grid: CombatGrid = host.grid
	var roll: RockRoll = RockRoll.new()
	roll.direction = direction
	var struck: Array[CombatUnit] = damaged.duplicate()
	var positions: Dictionary[CombatUnit, Vector2i] = {}
	var health: Dictionary[CombatUnit, int] = {}
	for unit: CombatUnit in host.units:
		if unit.hit_points > 0:
			positions[unit] = unit.cell
			# 방어막이 먼저 받으므로 HP + 방어막이 남아 있으면 버틴다. 낙사는 아래에서 0으로 둔다.
			health[unit] = unit.hit_points + unit.shield_points
	var cell: Vector2i = prop.cell
	for index: int in range(limit):
		var step: RockStep = RockStep.new()
		var next: Vector2i = cell + direction
		step.cell = next
		roll.stop_cell = next
		if not grid.is_inside(next):
			step.advance = false
			step.reason = tr("맵 경계")
		elif grid.is_blocked(next):
			step.advance = false
			step.reason = tr("물체") if grid.prop_at(next) != null else tr("장벽")
		elif grid.height_at(next) > grid.height_at(cell):
			step.advance = false
			step.reason = tr("오르막")
		elif grid.pits.has(next) or grid.height_at(cell) - grid.height_at(next) >= 2:
			step.destroyed = true
			step.reason = tr("낭떠러지 소멸") if grid.pits.has(next) else tr("높이 차2 파괴")
		else:
			for target: CombatUnit in positions:
				if positions[target] == next and health[target] > 0:
					step.target = target
					break
			if step.target != null:
				var target: CombatUnit = step.target
				if target not in struck:
					struck.append(target)
					step.damage = 4
					health[target] = maxi(0, health[target] - 4)
				if target not in roll.collisions:
					roll.collisions.append(target)
				if health[target] > 0:
					var destination: Vector2i = next + direction
					var blocked: bool = (not grid.is_inside(destination) or grid.is_blocked(destination)
						or grid.height_at(destination) > grid.height_at(next))
					for other: CombatUnit in positions:
						if other != target and health[other] > 0 and positions[other] == destination:
							blocked = true
					if blocked:
						step.advance = false
						step.reason = tr("밀기 막힘")
					else:
						step.push = true
						step.push_cell = destination
						positions[target] = destination
						var fall: int = host._fall_damage_from(target, next, destination)
						health[target] = 0 if grid.pits.has(destination) else maxi(0, health[target] - fall)
				if health[target] == 0:
					var side_alive: bool = false
					for other: CombatUnit in health:
						if other.is_ally == target.is_ally and health[other] > 0:
							side_alive = true
					if not side_alive:
						step.advance = false
						step.reason = tr("전투 종료")
		roll.steps.append(step)
		if step.advance:
			roll.cells.append(next)
			cell = next
		if step.destroyed or not step.advance:
			roll.destroyed = step.destroyed
			roll.reason = step.reason
			break
	return roll


func _roll_rock(actor: CombatUnit, prop: CombatGrid.Prop) -> void:
	var host: Object = _host()
	var direction: Vector2i = preview_rock(actor, prop).direction
	var struck: Array[CombatUnit] = []
	var impact_summary: String = ""
	## 충돌 피해를 받은 대상. 밀기 전에 기절 내성을 굴린다.
	var stun_target: CombatUnit = null
	for index: int in range(3):
		var origin: Vector2i = prop.cell
		if not _can_continue_rock(actor, prop, origin) or host.is_over():
			return
		var step: RockStep = _trace_rock(prop, direction, 1, struck).steps[0]
		if step.target != null and step.damage > 0:
			var target: CombatUnit = step.target
			struck.append(target)
			host._damage(target, step.damage)
			stun_target = target
			if not _can_continue_rock(actor, prop, origin) or not is_instance_valid(target) or target not in host.units:
				return
			impact_summary += (tr(" · 충돌: %s 피해4") if impact_summary.is_empty() else tr(", %s 피해4")) % target.get_display_name()
			host.logged.emit(tr("%s 바위 충돌: 피해4 · HP %d") % [target.get_display_name(), target.hit_points])
			if not _can_continue_rock(actor, prop, origin) or not is_instance_valid(target) or target not in host.units:
				return
			if host.is_over():
				host.logged.emit(tr("바위 정지: 전투 종료") + impact_summary)
				return
			step = _trace_rock(prop, direction, 1, struck).steps[0]
			if step.damage > 0:
				return
		if stun_target != null:
			var stunned: CombatUnit = stun_target
			stun_target = null
			if stunned.hit_points > 0:
				_roll_rock_stun(actor, stunned)
				if not _can_continue_rock(actor, prop, origin) or not is_instance_valid(stunned) or stunned not in host.units or host.is_over():
					return
		if step.push:
			var target: CombatUnit = step.target
			host._land(target, step.push_cell)
			if not _can_continue_rock(actor, prop, origin) or not is_instance_valid(target) or target not in host.units:
				return
			if host.is_over():
				host.logged.emit(tr("바위 정지: 전투 종료") + impact_summary)
				return
			step = _trace_rock(prop, direction, 1, struck).steps[0]
			if step.damage > 0:
				return
		if step.advance:
			prop.cell = step.cell
		if step.destroyed:
			prop.hit_points = 0
			host.grid.props.erase(prop)
		host.logged.emit(tr("바위 %s: %d, %d") % [step.reason if not step.reason.is_empty() else tr("이동"),
			prop.cell.x, prop.cell.y] + (impact_summary if not step.reason.is_empty() else ""))
		if step.destroyed or not step.advance:
			return
		if not _can_continue_rock(actor, prop, step.cell) or host.is_over():
			return
	host.logged.emit(tr("바위 정지: 최대3칸") + impact_summary)


func _can_continue_rock(actor: CombatUnit, prop: CombatGrid.Prop, cell: Vector2i) -> bool:
	var host: Object = _host()
	return (prop in host.grid.props and prop.hit_points > 0 and prop.cell == cell and is_instance_valid(actor)
		and actor in host.units and actor.hit_points > 0 and host.turns.current_unit == actor)


## 바위에 부딪혀 살아남은 대상의 민첩 내성굴림(DC ROCK_STUN_DC). 실패하면 굴린 유닛을 시전자로 기절시킨다. 보스는 면역이라 굴리지 않는다 (환경요소 4장).
func _roll_rock_stun(actor: CombatUnit, target: CombatUnit) -> void:
	if target.is_boss():
		return
	var host: Object = _host()
	var ability: CombatUnit.Ability = CombatUnit.Ability.AGILITY
	var sides: int = target.get_ability_sides(ability)
	var saved: CombatChecks.RollResult = CombatChecks.saving_throw(sides,
		target.get_defense_bonus(), ROCK_STUN_DC, CombatActionRules.save_mode(target, ability), host.dice,
		target.get_ability_modifier(ability))
	host._show_roll_in_background(CombatDiceRoll.save(target, sides, saved, saved.added(), tr("DC"), ROCK_STUN_DC))
	var stunned: bool = not saved.success and host.apply_status(actor, target, "stun")
	var rock_reason: String = host._save_reason(target, ability)
	host.logged.emit(tr("%s %s 내성%s %d 대 DC %d") % [target.get_display_name(), CombatUnit.ability_name(ability),
		"" if rock_reason.is_empty() else "(%s)" % rock_reason, saved.total, ROCK_STUN_DC])
	host.logged.emit((tr("%s: 기절") if stunned else tr("%s: 버팀")) % target.get_display_name())
	if stunned:
		host.feedback.emit(target, tr("기절"))


## 미리보기용: 충돌 피해 뒤에도 살아 있는 비보스 대상인지. 방어막이 먼저 흡수한다 (_damage와 같은 순서).
func rock_stun_risk(target: CombatUnit) -> bool:
	return not target.is_boss() and target.hit_points + target.shield_points > 4


## 바위 미리보기의 충돌 대상 뒤 문구: 밀려서 받는 낙하·낙사와 기절 위험.
func rock_collision_note(roll: RockRoll, target: CombatUnit) -> String:
	var note: String = rock_landing(roll, target)
	if rock_stun_risk(target):
		note += (" · " if not note.is_empty() else "") + tr("기절 위험")
	return note


# _trace_rock이 예측한 밀기마다 같은 낙하 계산을 더한다.
func rock_landing(roll: RockRoll, target: CombatUnit) -> String:
	var host: Object = _host()
	var grid: CombatGrid = host.grid
	var fall: int = 0
	var landing: Array[Vector2i] = []
	for step: RockStep in roll.steps:
		if step.push and step.target == target:
			if grid.pits.has(step.push_cell):
				return tr("낙사")
			fall += host._fall_damage_from(target, step.cell, step.push_cell)
			landing.append(step.push_cell)
	var notes: Array[String] = []
	if fall > 0:
		notes.append(tr("낙하 피해 %d") % fall)
	var pickup: String = host.pickup_note(target, landing)
	if not pickup.is_empty():
		notes.append(pickup)
	return " · ".join(notes)
