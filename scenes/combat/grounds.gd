class_name CombatGrounds
extends RefCounted
## 전투 장판(불·독·독안개·기름)과 속성 반응·나무 불탐·저장/검증을 함께 관리한다.

## 기름 장판의 지속(시전자 턴)과 미끌거림 DC(장판 정의의 고정값).
const TURNS: int = 3
const SLIP_DC: int = 4
## 독 장판 정의의 고정 DC (능력치 기획서 8장). 부여한 독이 이 값을 보존한다.
const POISON_DC: int = 4
## 속성 반응표. 바깥 키는 동작의 속성, 안 키는 닿은 장판 종류, 값은 반응이다. 빈 값은 반응 없음이다.
const REACTIONS: Dictionary = {
	"fire": {"oil": "ignite"},
	"water": {"oil": "remove", "burn": "remove"},
}


class Ground extends RefCounted:
	const POISON_DC: int = 4
	var source: CombatUnit
	var cell: Vector2i
	var kind: String
	var turns_left: int
	var dc: int
	var entered: Array[CombatUnit] = []

	## fog는 시전 때 기록한 save_dc를 쓴다. 시전마다 칸 하나에 기록 하나를 둔다.
	func _init(caster: CombatUnit, position: Vector2i, effect: String, save_dc: int = 0) -> void:
		source = caster
		cell = position
		kind = effect
		turns_left = 2 if kind == "burn" else (CombatGrounds.TURNS if kind == "oil" else 4)
		dc = POISON_DC if kind == "poison" else (save_dc if kind == "fog" else (CombatGrounds.SLIP_DC if kind == "oil" else 0))


var _entries: Array[Ground] = []
## 이번 전투에서 탄 나무 칸. 전투를 다시 열면 비고 저장에 들어간다.
var burned_trees: Array[Vector2i] = []
var _host_ref: WeakRef
var _host: Object:
	get:
		return _host_ref.get_ref() if _host_ref != null else null


static func reaction(attribute: String, ground_kind: String) -> String:
	return REACTIONS.get(attribute, {}).get(ground_kind, "")


## 중심과 상하좌우 4칸(곡사 반경 1의 십자 5칸). 맵과 막힌 칸은 호출자가 거른다.
static func cross_cells(center: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [center]
	for offset: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		cells.append(center + offset)
	return cells


## start에서 상하좌우로 이어진 기름 칸 전체. start가 기름 칸이 아니면 비어 있다.
static func connected(start: Vector2i, oil_cells: Array[Vector2i]) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	if start not in oil_cells:
		return found
	var frontier: Array[Vector2i] = [start]
	found.append(start)
	while not frontier.is_empty():
		var here: Vector2i = frontier.pop_back()
		for offset: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = here + offset
			if next in oil_cells and next not in found:
				found.append(next)
				frontier.append(next)
	return found


func bind(host: Object) -> void:
	_host_ref = weakref(host) if host != null else null


func clear() -> void:
	_entries.clear()
	burned_trees.clear()


func all() -> Array[Ground]:
	return _entries.duplicate()


## 테스트나 통제 fixture에서 장판 항목을 직접 추가한다.
func add(source: CombatUnit, cell: Vector2i, kind: String, save_dc: int = 0) -> Ground:
	var ground: Ground = Ground.new(source, cell, kind, save_dc)
	_entries.append(ground)
	return ground


## 특정 종류의 장판을 모두 지운다.
func remove_kind(kind: String) -> void:
	_entries.assign(_entries.filter(func(ground: Ground) -> bool: return ground.kind != kind))


func save_state(units: Array[CombatUnit]) -> Dictionary:
	var saved_grounds: Array = []
	for ground: Ground in _entries:
		saved_grounds.append([units.find(ground.source), ground.cell, ground.kind, ground.turns_left,
			ground.entered.map(func(unit: CombatUnit) -> int: return units.find(unit)), ground.dc])
	return {"grounds": saved_grounds, "burned_trees": burned_trees.duplicate()}


func load_state(data: Dictionary, units: Array[CombatUnit], grid: CombatGrid) -> void:
	_entries.clear()
	for saved: Array in data.grounds:
		var ground: Ground = Ground.new(units[saved[0]], saved[1], saved[2])
		ground.turns_left = saved[3]
		ground.dc = saved[5]
		for index: int in saved[4]:
			ground.entered.append(units[index])
		_entries.append(ground)
	burned_trees.clear()
	for saved: Vector2i in data.burned_trees:
		if grid.burn_tree(saved):
			burned_trees.append(saved)


static func is_valid_state(data: Variant, count: int, map_size: Vector2i, tree_cells: Array[Vector2i] = []) -> bool:
	var area: Rect2i = Rect2i(Vector2i.ZERO, map_size)
	if not (data is Dictionary and data.get("grounds") is Array and data.grounds.size() <= area.get_area() * 2
			and data.get("burned_trees") is Array and data.burned_trees.size() <= tree_cells.size()):
		return false
	var burned: Array = data.burned_trees
	if not burned.all(func(saved: Variant) -> bool:
			return saved is Vector2i and saved in tree_cells and burned.count(saved) == 1):
		return false
	var unit_index: Callable = func(index: Variant) -> bool: return index is int and index >= 0 and index < count
	return data.grounds.all(func(saved: Variant) -> bool:
		return (saved is Array and saved.size() == 6 and unit_index.call(saved[0])
			and saved[1] is Vector2i and area.has_point(saved[1]) and saved[2] in ["burn", "poison", "fog", "oil"]
			and saved[3] is int and saved[3] >= 1 and saved[3] <= 4
			and saved[4] is Array and saved[4].size() <= count and saved[4].all(unit_index)
			and saved[5] is int and saved[5] >= 0 and saved[5] <= CombatUnit.SAVED_INT_LIMIT
			and (saved[5] == 0 if saved[2] == "burn" else saved[5] > 0)
			and (saved[5] == SLIP_DC and saved[3] <= TURNS if saved[2] == "oil" else true)))


func oil_at(cell: Vector2i) -> Ground:
	for ground: Ground in _entries:
		if ground.kind == "oil" and ground.cell == cell:
			return ground
	return null


func _oil_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for ground: Ground in _entries:
		if ground.kind == "oil" and ground.cell not in cells:
			cells.append(ground.cell)
	return cells


## 기름을 깔 수 있는 칸: 맵 안의 바닥, 벽·박스·바위 아님, 중심과 높이 차 1 이하. 물 칸도 된다.
func oil_site_ok(center: Vector2i, cell: Vector2i) -> bool:
	var grid: CombatGrid = _host.grid
	return (grid.is_floor(cell) and not grid.is_blocked(cell)
		and absi(grid.height_at(center) - grid.height_at(cell)) <= 1)


## 목표 칸 center에 던졌을 때 실제로 기름이 깔리는 칸. 생성과 미리보기가 함께 쓴다.
## 중심이 박스·바위 칸이어도 고를 수 있고, 그 칸만 빠진 나머지가 깔린다. 중심이 고를 수 없는 칸이면 비어 있다.
func oil_sites(center: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var grid: CombatGrid = _host.grid
	if not grid.is_aimable(center):
		return cells
	for cell: Vector2i in cross_cells(center):
		if oil_site_ok(center, cell):
			cells.append(cell)
	return cells


## 중심의 십자 5칸에 기름 장판을 깐다. 같은 칸은 하나이고 다시 깔면 기간만 3으로 갱신한다(원 시전자 유지).
## 시전자가 쓰러져도 남는다. 칸 위의 유닛에게는 즉시 효과가 없다.
func create_oil(source: CombatUnit, center: Vector2i) -> bool:
	var sites: Array[Vector2i] = oil_sites(center)
	var units: Array[CombatUnit] = _host.units
	if not is_instance_valid(source) or source not in units or source.hit_points <= 0 or sites.is_empty():
		return false
	var placed: Array[Vector2i] = []
	for cell: Vector2i in sites:
		var existing: Ground = oil_at(cell)
		if existing != null:
			existing.turns_left = TURNS
		else:
			_entries.append(Ground.new(source, cell, "oil"))
		placed.append(cell)
	_host.logged.emit(tr("%s 기름 장판: %d, %d · %d칸") % [source.get_display_name(), center.x, center.y, placed.size()])
	# 불 장판 칸에 기름이 생겨도 닿은 것으로 본다(전투 설계 6장). create_ground처럼 그 칸에 불 장판을 남기지 않는다.
	for ground: Ground in _entries.duplicate():
		if ground.kind == "burn" and ground.cell in placed and oil_at(ground.cell) != null:
			_entries.erase(ground)
			var alive: bool = is_instance_valid(ground.source) and ground.source in units and ground.source.hit_points > 0
			ignite(ground.cell, ground.source if alive else source)
	_host.changed.emit()
	return true


func create_ground(source: CombatUnit, cell: Vector2i, kind: String) -> bool:
	var grid: CombatGrid = _host.grid
	var units: Array[CombatUnit] = _host.units
	if (not is_instance_valid(source) or source not in units or source.hit_points <= 0
		or kind not in ["burn", "poison"] or not grid.is_floor(cell) or grid.is_blocked(cell)
		or kind == "burn" and cell in grid.water_cells):
		# 물 칸에는 불 장판이 생기지 않는다(환경요소 6장). 범위로 깔면 칸마다 이 검사를 지나 물 칸만 빠진다.
		return false
	# 불이 기름 칸에 닿으면 점화한다. 기름이 불이 된 칸에는 불 장판을 새로 두지 않는다.
	# shortcut: 범위 불은 첫 칸의 점화가 이어진 기름을 다 지워 남은 칸에 불이 생긴다. 범위 불 공급원(#500 2b) 전에 점화 칸 목록으로 거른다.
	if kind == "burn" and oil_at(cell) != null:
		return ignite(cell, source)
	var refreshed: bool = false
	var owner: CombatUnit = source
	for ground: Ground in _entries:
		if ground.cell == cell and ground.kind == kind:
			ground.turns_left = 2 if kind == "burn" else 4
			owner = ground.source
			refreshed = true
			break
	if not refreshed:
		_entries.append(Ground.new(source, cell, kind))
	_host.logged.emit(tr("%s %s 장판 %s: %d, %d") % [owner.get_display_name(),
		tr("불") if kind == "burn" else tr("독"), tr("갱신") if refreshed else tr("생성"), cell.x, cell.y])
	_host.changed.emit()
	return true


## 속성 동작이 칸에 닿았을 때 반응표(REACTIONS)를 적용한다. 화염은 기름을 점화하고, 물은 닿은 칸의 기름과 불 장판을 지운다.
func touch_attribute(cell: Vector2i, attribute: String, source: CombatUnit) -> bool:
	var grid: CombatGrid = _host.grid
	if attribute == "fire" and grid.burn_tree(cell):
		burned_trees.append(cell)
		_host.logged.emit(tr("나무가 불탐: %d, %d") % [cell.x, cell.y])
		_host.changed.emit()
		return true
	var removed: bool = false
	for ground: Ground in _entries.duplicate():
		if ground.cell != cell:
			continue
		match reaction(attribute, ground.kind):
			"ignite":
				return ignite(cell, source)
			"remove":
				_entries.erase(ground)
				removed = true
	if removed:
		_host.logged.emit(tr("속성: 장판 삭제 %d, %d") % [cell.x, cell.y])
		_host.changed.emit()
	return removed


## 화염이 기름 칸에 닿았다: 이어진 기름 칸 전체가 타고, 그 칸 위의 모든 살아 있는 유닛(점화한 유닛 포함)이 화상 2중첩을 받는다.
## 물 칸 위의 유닛은 화상을 받지 않는다(apply_status의 기존 규칙).
func ignite(cell: Vector2i, igniter: CombatUnit) -> bool:
	var units: Array[CombatUnit] = _host.units
	if (not is_instance_valid(igniter) or igniter not in units or igniter.hit_points <= 0 or _host.is_over()
		or oil_at(cell) == null):
		return false
	var burned: Array[Vector2i] = connected(cell, _oil_cells())
	for ground: Ground in _entries.duplicate():
		if ground.kind == "oil" and ground.cell in burned:
			_entries.erase(ground)
	_host.logged.emit(tr("%s 점화: 기름 %d칸") % [igniter.get_display_name(), burned.size()])
	_host.oil_ignited.emit(burned)
	for unit: CombatUnit in units.duplicate():
		if unit.hit_points > 0 and unit.cell in burned and _host.apply_status(igniter, unit, "burn"):
			_host.apply_status(igniter, unit, "burn")
			_host.logged.emit(tr("%s 점화: 화상 2중첩") % unit.get_display_name())
	_host.changed.emit()
	return true


## 기름 칸을 떠나기 직전에 미끌거림을 굴린다. 참이면 제자리를 지켜 계속 이동할 수 있고, 거짓이면 넘어져 멈춘다.
func try_leave_oil(unit: CombatUnit) -> bool:
	if oil_at(unit.cell) == null or unit.oil_slipped:
		return true
	return _slip_roll(unit)


## 기름 칸에 들어가거나 기름 칸에 강제로 착지한 유닛의 미끌거림. 턴마다 기름 장판 전체에 대해 한 번이다.
func enter_oil(unit: CombatUnit) -> void:
	if (not is_instance_valid(unit) or unit.hit_points <= 0 or _host.is_over() or unit.oil_slipped
		or oil_at(unit.cell) == null):
		return
	_slip_roll(unit)


## 솜씨 내성굴림(DC 4). 실패하면 넘어진다. 굴림은 성공과 무관하게 이번 턴의 기름 1회로 쓴다. 참이면 제자리를 지킨 것이다.
func _slip_roll(unit: CombatUnit) -> bool:
	var ability: CombatUnit.Ability = CombatUnit.Ability.FINESSE
	var sides: int = unit.get_ability_sides(ability)
	unit.oil_slipped = true
	var saved: CombatChecks.RollResult = CombatChecks.saving_throw(sides, unit.get_defense_bonus(), SLIP_DC,
		CombatActionRules.save_mode(unit, ability), _host.dice, unit.get_ability_modifier(ability))
	_host._show_roll_in_background(CombatDiceRoll.save(unit, sides, saved, saved.added(), tr("DC"), SLIP_DC))
	var slip_reason: String = _host._save_reason(unit, ability)
	_host.logged.emit(tr("%s 미끌거림(솜씨 내성%s): 솜씨 d%d %s %+d = %d / DC %d · %s") % [unit.get_display_name(),
		"" if slip_reason.is_empty() else " · " + slip_reason, sides, str(saved.rolls), saved.added(), saved.total, SLIP_DC, _host._save_outcome(saved)])
	if saved.success:
		return true
	unit.fallen = true
	_host.status_applied.emit(unit, "fallen")
	_host.logged.emit(tr("%s 넘어짐") % unit.get_display_name())
	_host.feedback.emit(unit, tr("넘어짐"))
	_host.changed.emit()
	return false


func apply_to_unit(unit: CombatUnit, entering: bool) -> void:
	var revision: int = _host._revision
	apply_fog(unit, entering)
	if entering:
		enter_oil(unit)
	if not _host._same_combat(unit, revision):
		return
	for ground: Ground in _entries.duplicate():
		if not is_instance_valid(unit) or unit.hit_points <= 0 or _host.is_over():
			break
		if ground.kind in ["fog", "oil"]:
			continue
		if (ground not in _entries or ground.cell != unit.cell
			or not is_instance_valid(ground.source) or ground.source.hit_points <= 0):
			continue
		if entering:
			if unit in ground.entered:
				continue
			ground.entered.append(unit)
		if _host.apply_status(ground.source, unit, ground.kind, ground.dc):
			_host.logged.emit(tr("%s %s 장판: %s 부여") % [unit.get_display_name(),
				tr("불") if ground.kind == "burn" else tr("독"), tr("화상") if ground.kind == "burn" else tr("독")])


## 독안개 칸의 건강 내성굴림. 칸 단위로 한 번 굴리고 그 칸의 모든 독안개 기록에 진입을 남긴다.
## 시전자가 쓰러졌어도 장판은 남으므로 시전자의 생사를 보지 않는다. DC는 칸에서 가장 먼저 시전한 기록을 쓴다.
func apply_fog(unit: CombatUnit, entering: bool) -> void:
	if not is_instance_valid(unit) or unit.hit_points <= 0 or _host.is_over() or unit.is_poison_immune():
		return
	var fogs: Array[Ground] = []
	for ground: Ground in _entries:
		if ground.kind == "fog" and ground.cell == unit.cell:
			fogs.append(ground)
	if fogs.is_empty() or entering and fogs.all(func(ground: Ground) -> bool: return unit in ground.entered):
		return
	for ground: Ground in fogs:
		if unit not in ground.entered:
			ground.entered.append(unit)
	var revision: int = _host._revision
	var health_sides: int = unit.get_ability_sides(CombatUnit.Ability.HEALTH)
	var saved: CombatChecks.RollResult = CombatChecks.saving_throw(health_sides, unit.get_defense_bonus(),
		fogs[0].dc, CombatActionRules.save_mode(unit, CombatUnit.Ability.HEALTH), _host.dice, unit.get_ability_modifier(CombatUnit.Ability.HEALTH))
	_host._show_roll_in_background(CombatDiceRoll.save(unit, health_sides, saved, saved.added(), tr("DC"), fogs[0].dc))
	var fog_reason: String = _host._save_reason(unit, CombatUnit.Ability.HEALTH)
	_host.logged.emit(tr("%s 독안개(건강 내성%s): 건강 d%d %s %+d = %d / DC %d · %s") % [unit.get_display_name(),
		"" if fog_reason.is_empty() else " · " + fog_reason, health_sides, str(saved.rolls), saved.added(), saved.total, fogs[0].dc, _host._save_outcome(saved)])
	if not _host._same_combat(unit, revision) or saved.success or unit.get_status_count("poison") >= 3:
		return
	# 독안개로 얻은 독 중첩은 기간이 없고(turns_left 0) 시전자가 쓰러져도 남는다. 제거 DC는 고정 4다.
	unit.status_effects.append(CombatUnit.StatusEffect.new("poison", fogs[0].source, 0, POISON_DC))
	_host.status_applied.emit(unit, "poison")
	_host.logged.emit(tr("%s 독안개: 독 부여") % unit.get_display_name())
	_host.feedback.emit(unit, tr("독"))
	_host.changed.emit()


## 독안개를 영역에 깔고 시전 순간 영역 안의 유닛이 바로 내성굴림을 한다(진입 1회로 소비).
func place_fog(caster: CombatUnit, cell: Vector2i, area: Array[Vector2i], dc: int) -> void:
	for area_cell: Vector2i in area:
		_entries.append(Ground.new(caster, area_cell, "fog", dc))
	var revision: int = _host._revision
	_host.logged.emit(tr("%s 독안개 시전: %d, %d · DC %d") % [caster.get_display_name(), cell.x, cell.y, dc])
	for unit: CombatUnit in _host.units.duplicate():
		if revision != _host._revision or _host.is_over():
			break
		if unit.cell in area:
			apply_fog(unit, true)
	if revision == _host._revision:
		_host.changed.emit()


func clear_entered_for(unit: CombatUnit) -> void:
	for ground: Ground in _entries:
		ground.entered.erase(unit)


## 불·독 장판의 기간을 줄이고 만료 로그 메시지를 돌려준다.
func tick_non_persistent(caster: CombatUnit) -> Array[String]:
	var messages: Array[String] = []
	for ground: Ground in _entries.duplicate():
		if ground.source == caster and ground.kind not in ["fog", "oil"]:
			ground.turns_left -= 1
			if ground.turns_left == 0:
				_entries.erase(ground)
				messages.append(tr("%s %s 장판 만료: %d, %d") % [caster.get_display_name(),
					tr("불") if ground.kind == "burn" else tr("독"), ground.cell.x, ground.cell.y])
	return messages


## 독안개·기름 장판은 시전자가 쓰러졌어도 시계 슬롯으로 기간을 줄인다.
func tick_persistent(caster: CombatUnit) -> void:
	for ground: Ground in _entries.duplicate():
		if ground.kind in ["fog", "oil"] and ground.source == caster:
			ground.turns_left -= 1
			if ground.turns_left == 0:
				_entries.erase(ground)
				_host.logged.emit(tr("%s %s 만료: %d, %d") % [caster.get_display_name(),
					tr("독안개") if ground.kind == "fog" else tr("기름 장판"), ground.cell.x, ground.cell.y])


func has_persistent_for(caster: CombatUnit) -> bool:
	return _entries.any(func(ground: Ground) -> bool: return ground.kind in ["fog", "oil"] and ground.source == caster)


## 시전자가 전투 불능이 되면 진입 기록을 지우고 불·독 장판을 즉시 해제한다.
func on_caster_incapacitated(target: CombatUnit) -> Array[String]:
	var messages: Array[String] = []
	for ground: Ground in _entries.duplicate():
		ground.entered.erase(target)
		if ground.source == target and ground.kind in ["burn", "poison"]:
			_entries.erase(ground)
			messages.append(tr("%s %s 장판 해제: %d, %d") % [target.get_display_name(),
				tr("불") if ground.kind == "burn" else tr("독"), ground.cell.x, ground.cell.y])
	return messages


## 이동 경로 탐색 시 actor가 피해야 할 장판 칸 목록. 독 면역은 불·기름만 피한다.
func hazard_cells_for(actor: CombatUnit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for ground: Ground in _entries:
		if actor.is_poison_immune() and ground.kind not in ["burn", "oil"]:
			continue
		if ground.cell not in cells:
			cells.append(ground.cell)
	return cells


## 걷기 경로(출발 칸 제외)에서 미끌거림을 굴리게 되면 그 DC 안내. 굴림은 턴마다 한 번이라 안내도 한 줄이다.
func slip_note(unit: CombatUnit, path: Array[Vector2i]) -> String:
	if not is_instance_valid(unit) or path.is_empty() or unit.oil_slipped:
		return ""
	var leaving: bool = oil_at(unit.cell) != null
	if not leaving and not path.any(func(cell: Vector2i) -> bool: return oil_at(cell) != null):
		return ""
	return tr("미끌거림: 솜씨 내성 DC %d") % SLIP_DC


## 시전자의 독안개 중 남은 기간 값의 종류 수. 한 턴에 한 번만 시전하므로 같은 시전의 칸은 같은 값이라 유효한 시전 수가 된다.
func fog_cast_count(caster: CombatUnit) -> int:
	var durations: Array[int] = []
	for ground: Ground in _entries:
		if ground.kind == "fog" and ground.source == caster and ground.turns_left not in durations:
			durations.append(ground.turns_left)
	return durations.size()


## caster가 시전한 독안개가 덮은 칸. caster가 null이면 모든 독안개 칸이다.
func fog_cells(caster: CombatUnit = null) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for ground: Ground in _entries:
		if ground.kind == "fog" and (caster == null or ground.source == caster) and ground.cell not in cells:
			cells.append(ground.cell)
	return cells
