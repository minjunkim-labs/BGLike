class_name CombatSnapshot
extends RefCounted
## 전투·정비 자동 저장 섹션의 조립, 신뢰 불가 데이터 검증, 복원 적용을 맡는다 (docs/adr/0003).


## 스테이지별 저장 검증에 필요한 최소 메타데이터. 장면 인스턴스화 없이 검증할 수 있다.
class StageMeta extends RefCounted:
	var map_size: Vector2i = Vector2i.ZERO
	var identities: Array = []
	var tree_cells: Array[Vector2i] = []
	var crate_count: int = 0

	static func from_stage(stage: CombatStage, party: Array[CombatUnit]) -> StageMeta:
		var meta: StageMeta = StageMeta.new()
		meta.map_size = stage.map_size
		meta.identities = party.map(func(unit: CombatUnit) -> Array: return [unit.kind, true])
		var enemies: Node = stage.enemies.instantiate()
		for child: Node in enemies.get_children():
			meta.identities.append([(child as CombatUnit).kind, false])
		enemies.free()
		meta.tree_cells = stage.tree_cells()
		meta.crate_count = stage.crate_cells.size()
		return meta


## restore_save 검증 결과. 유효하면 전투 복원 뒤 정비 화면을 열지 여부를 함께 담는다.
class SavePlan extends RefCounted:
	var valid: bool = false
	var error_message: String = ""
	var combat: Dictionary = {}
	var open_preparation: bool = false
	var maintaining: bool = false


## 이어하기에 필요한 전투 상태 전체. Object 없이 GameSave에 그대로 쓸 수 있는 값이다.
static func capture_combat(progress: CombatActProgress, waiting_for_start: bool, actions: CombatActions,
		loot: CombatLoot, units: Array[CombatUnit], turns: CombatTurns, last_ally: CombatUnit) -> Dictionary:
	var state: Dictionary = progress.save_state()
	state["waiting_for_start"] = waiting_for_start
	state.merge(actions.save_state())
	state["bag"] = loot.bag
	state["units"] = units.map(func(unit: CombatUnit) -> Dictionary: return unit.save_state(units))
	state["turns"] = turns.save_state(units)
	state["last_ally"] = units.find(last_ally)
	return state.duplicate(true)


## GameSave.write()에 넘길 sections 딕셔너리를 조립한다.
static func capture_sections(combat_state: Dictionary, preparation_visible: bool, maintaining: bool) -> Dictionary:
	var sections: Dictionary = {"combat": combat_state}
	# 선택한 칸과 열린 확인 창은 저장하지 않는다. 이어하기는 같은 화면 단계에서 아무것도 고르지 않은 채 시작한다.
	if preparation_visible:
		sections["preparation"] = {"maintaining": maintaining}
	return sections


## 저장 파일의 전투 섹션을 신뢰하지 않고 모든 하위 모듈·교차 불변식을 검증한다.
static func is_valid_combat(state: Variant, stage_count: int, stage_meta_lookup: Callable,
		loot: CombatLoot, unit_template: CombatUnit = null) -> bool:
	if not (state is Dictionary and state.get("waiting_for_start", false) is bool
			and CombatActProgress.is_valid_state(state, stage_count, loot)
			and state.get("units") is Array and state.get("last_ally") is int
			and _valid_items(state.get("bag"), loot) and state.bag.size() <= int(loot.data["bag_limit"])):
		return false
	if state.get("waiting_for_start", false) and state.rewarded:
		return false
	var meta: StageMeta = stage_meta_lookup.call(state.stage) as StageMeta
	if meta == null:
		return false
	var owned_template: CombatUnit = null
	var validator: CombatUnit = unit_template
	if validator == null:
		owned_template = CombatUnit.new()
		validator = owned_template
	var ok: bool = _validate_combat_with_meta(state, meta, loot, validator)
	if owned_template != null:
		owned_template.free()
	return ok


static func _validate_combat_with_meta(state: Dictionary, meta: StageMeta,
		loot: CombatLoot, validator: CombatUnit) -> bool:
	var identities: Array = meta.identities
	var saved_units: Array = state.units
	var count: int = saved_units.size()
	# 늘어나는 유닛은 새끼 거미뿐이고 한 칸에 하나다.
	if count < identities.size() or count > identities.size() + meta.map_size.x * meta.map_size.y:
		return false
	for index: int in range(count):
		var saved: Variant = saved_units[index]
		var identity: Array = identities[index] if index < identities.size() else [CombatUnit.Kind.SPIDERLING, false]
		if (not validator.is_valid_state(saved, count, meta.map_size) or [saved.kind, saved.ally] != identity
				or not (saved.weapon.is_empty() or loot.is_valid_item(saved.weapon) and saved.weapon.kind == "weapon")
				or not (saved.armor.is_empty() or loot.is_valid_item(saved.armor) and saved.armor.kind == "armor")
				or not loot.is_valid_potions(saved.potions) or not (saved.ally or saved.potions.is_empty())):
			return false
		var agility_sides: int = (CombatUnit.ALLY_ABILITY_SIDES[saved.kind][CombatUnit.Ability.AGILITY]
			if saved.ally else CombatEnemyDefinitions.for_kind(saved.kind)["abilities"][CombatUnit.Ability.AGILITY])
		# 생성한 새끼는 굴리지 않고 엄마 앞에 삽입되므로 원본 값 0을 보존한다.
		if saved.initiative_roll < (1 if index < identities.size() else 0) or saved.initiative_roll > agility_sides:
			return false
	if not (state.last_ally >= 0 and state.last_ally < count and saved_units[state.last_ally].ally
			and CombatTurns.is_valid_state(state.get("turns"), count)
			and CombatActions.is_valid_state(state, count, meta.map_size, meta.tree_cells)):
		return false
	# 떨어진·주운 아이템은 이 스테이지의 상자 수를 넘지 않고, 남은 상자 칸에 떨어져 있지 않다.
	var crates: Array = state.props.filter(func(saved: Array) -> bool: return saved[0] == "crate")
	if not (CombatFloorLoot.is_valid_state(state.get("floor_loot"), meta.map_size,
			maxi(0, meta.crate_count - crates.size()), loot.is_valid_item)
			and crates.all(func(saved: Array) -> bool: return state.floor_loot.drops.all(
				func(drop: Array) -> bool: return drop[0] != saved[1]))):
		return false
	# 턴 순서는 살아 있는 유닛 전부다. 쓰러진 유닛이나 빠진 유닛이 있으면 턴이 끝없이 넘어가거나 멈춘다.
	var order: Array = state.turns.order
	var living: Array = range(count).filter(func(index: int) -> bool: return saved_units[index].hit_points > 0)
	if (order.size() != living.size() or not living.all(func(index: int) -> bool: return index in order)
			or not order.is_empty() and state.turns.current < 0):
		return false
	# 시계 슬롯은 쓰러진 시전자의 자리다. 시전자가 살아 있으면 두 번 줄고, 기준 유닛이 쓰러졌으면 줄지 않는다.
	for slot: Array in state.clock_slots:
		if slot[0] in order or slot[1] not in order:
			return false
	# 기절은 시전자의 턴이 와야 풀린다. 시전자가 살아서 순서에 있어야 턴이 끝없이 넘어가지 않는다.
	for saved: Dictionary in saved_units:
		if saved.stunned and saved.hit_points > 0 and (saved_units[saved.stun_source].hit_points <= 0
				or saved.stun_source not in state.turns.order):
			return false
	var replay: Variant = state.get("replay", {})
	if not (replay is Dictionary and replay.get("actions", 0) is int
			and replay.get("actions", 0) <= CombatUnit.SAVED_INT_LIMIT and replay.get("reactions", []) is Array
			and replay.get("reactions", []).size() <= CombatUnit.SAVED_INT_LIMIT
			# 반응 답은 bool이거나, 반사신경이 고른 지도 안의 칸이다.
			and replay.get("reactions", []).all(func(answer: Variant) -> bool:
				return answer is bool or answer is Vector2i and Rect2i(Vector2i.ZERO, meta.map_size).has_point(answer))
			and (replay.get("actions", 0) > 0 or replay.get("reactions", []).is_empty())):
		return false
	if state.get("waiting_for_start", false) and (state.turns.round != 1 or replay.get("actions", 0) != 0):
		return false
	if replay.get("actions", 0) == 0:
		return true
	# 적 턴 중간 저장은 살아 있는 적의 차례이고 양편이 남아 있을 때만 있다.
	var current: int = state.turns.current
	return (replay.actions > 0 and current >= 0 and not saved_units[current].ally
		and saved_units[current].hit_points > 0
		and saved_units.any(func(unit: Dictionary) -> bool: return unit.ally and unit.hit_points > 0))


## GameSave.read()의 sections(combat + 선택적 preparation)를 검증하고 복원 계획을 돌려준다.
static func parse_save(sections: Variant, stage_count: int, stage_meta_lookup: Callable,
		loot: CombatLoot, unit_template: CombatUnit = null) -> SavePlan:
	var plan: SavePlan = SavePlan.new()
	var combat: Variant = sections.get("combat") if sections is Dictionary else null
	var screen: Variant = sections.get("preparation", {}) if sections is Dictionary else null
	if not (screen is Dictionary and combat is Dictionary
			and is_valid_combat(combat, stage_count, stage_meta_lookup, loot, unit_template)):
		plan.error_message = "저장을 읽을 수 없음"  # NO_TRANSLATE: push_warning 디버그 문구
		return plan
	# #345의 지도 준비 정비 화면 저장(`before_battle`)은 #395 뒤에 만들지 않는다. 그 화면의 변경은 이미 combat에 있어
	# 같은 지도 준비로 이어한다.
	var before_battle: bool = screen.get("before_battle") is bool and screen.before_battle
	if not screen.is_empty():
		var valid: bool = screen.get("maintaining") is bool
		if before_battle:
			valid = valid and screen.size() == 2 and screen.maintaining and combat.get("waiting_for_start", false)
		else:
			valid = valid and screen.keys() == ["maintaining"] and combat.rewarded
			valid = valid and combat.units.all(func(unit: Dictionary) -> bool: return unit.ally or unit.hit_points <= 0)
		if not valid:
			plan.error_message = "저장한 정비 단계가 전투 상태와 맞지 않음"  # NO_TRANSLATE: push_warning 디버그 문구
			return plan
	plan.valid = true
	plan.combat = combat
	plan.open_preparation = not screen.is_empty() and not before_battle
	plan.maintaining = bool(screen.get("maintaining", false)) if plan.open_preparation else false
	return plan


## 검증된 전투 상태를 progress·loot·units·actions·turns에 순서대로 복원한다.
static func apply_combat(state: Dictionary, progress: CombatActProgress, loot: CombatLoot,
		units: Array[CombatUnit], actions: CombatActions, turns: CombatTurns,
		spawn_enemy: Callable, sync_party_level: Callable) -> Dictionary:
	progress.load_state(state)
	# 유닛 load_state 전에 맞춘다. 레벨 setter가 보정한 HP를 저장한 HP로 덮는다.
	sync_party_level.call()
	loot.bag.assign(state.bag)
	for saved: Dictionary in state.units.slice(units.size()):
		units.append(spawn_enemy.call(saved) as CombatUnit)
	for index: int in range(units.size()):
		units[index].load_state(state.units[index], units)
	actions.load_state(state)
	turns.load_state(state.turns, units)
	var replay: Dictionary = state.get("replay", {})
	actions.replay_answers.assign(replay.get("reactions", []))
	return {
		"waiting_for_start": state.get("waiting_for_start", false),
		"last_ally": units[state.last_ally],
		"replay_actions": replay.get("actions", 0),
	}


static func _valid_items(items: Variant, loot: CombatLoot) -> bool:
	return items is Array and (items as Array).all(loot.is_valid_item)
