class_name CombatCover
extends RefCounted
## 3차원 중심 선분 기반 전엄폐 판정(docs/design/combat/cover.md 4장, #358).
## 높이에 4를 곱한 정수 연산으로 스침 통과(z_line >= z_top)와 모서리 점 규칙을 오차 없이 판정한다.

const UNIT_HEIGHT_DEFAULT: int = 2
const UNIT_HEIGHT_SPIDERLING: int = 1
const OBJECT_HEIGHTS: Dictionary[String, int] = {
	"crate": 1,
	"rock": 2,
	"ruin_wall": 3,
	"tree": 3,
	"cottage": 4,
}
const DEFAULT_WALL_HEIGHT: int = 3
const PIT_TOP4: int = -1000000


class Result extends RefCounted:
	## 0.0 = 통과, 1.0 = 전엄폐 막힘. 반엄폐 확장을 위해 정도(ratio)로 돌려준다.
	var blocked: bool = false
	var ratio: float = 0.0
	var blocking_cells: Array[Vector2i] = []
	var reason: String = ""
	## 선분 매개변수 [0.0, 1.0]에서 처음 막히는 위치. 통과면 1.0이다.
	var hit_t: float = 1.0


static func unit_height(unit: CombatUnit) -> int:
	if unit == null:
		return UNIT_HEIGHT_DEFAULT
	return UNIT_HEIGHT_SPIDERLING if unit.kind == CombatUnit.Kind.SPIDERLING else UNIT_HEIGHT_DEFAULT


static func object_height(kind: String) -> int:
	return OBJECT_HEIGHTS.get(kind, DEFAULT_WALL_HEIGHT)


## 직사 기본 공격 대상인지: 아군 궁수·적 풋내기 궁수의 기본 공격("attack")만 직사다.
static func is_direct_fire(actor: CombatUnit, action: String) -> bool:
	return actor != null and action == "attack" and actor.kind == CombatUnit.Kind.ARCHER


static func floor_height(grid: CombatGrid, cell: Vector2i) -> int:
	if grid == null or grid.water_cells.has(cell):
		return 0
	return grid.height_at(cell)


static func check_unit(grid: CombatGrid, attacker: CombatUnit, target: CombatUnit,
		from_cell: Vector2i = Vector2i(-1, -1)) -> Result:
	if grid == null or attacker == null or target == null:
		return Result.new()
	var origin: Vector2i = attacker.cell if from_cell == Vector2i(-1, -1) else from_cell
	return evaluate(grid, origin, unit_height(attacker), target.cell, unit_height(target), attacker.is_ally)


static func check_prop(grid: CombatGrid, attacker: CombatUnit, prop: CombatGrid.Prop,
		from_cell: Vector2i = Vector2i(-1, -1)) -> Result:
	if grid == null or attacker == null or prop == null:
		return Result.new()
	var origin: Vector2i = attacker.cell if from_cell == Vector2i(-1, -1) else from_cell
	return evaluate(grid, origin, unit_height(attacker), prop.cell, object_height(prop.kind), attacker.is_ally)


## 공격자(origin, attacker_height)에서 대상(target_cell, target_height)까지의 3차원 선분 엄폐 판정.
static func evaluate(grid: CombatGrid, origin: Vector2i, attacker_height: int,
		target_cell: Vector2i, target_height: int, attacker_is_ally: bool) -> Result:
	var result: Result = Result.new()
	if grid == null or origin == target_cell:
		return result
	var dx: int = target_cell.x - origin.x
	var dy: int = target_cell.y - origin.y
	var adx: int = absi(dx)
	var ady: int = absi(dy)
	var sx: int = signi(dx)
	var sy: int = signi(dy)
	var z_start4: int = floor_height(grid, origin) * 4 + attacker_height * 3
	var z_end4: int = floor_height(grid, target_cell) * 4 + target_height * 2
	var dz4: int = z_end4 - z_start4
	var q: int = 2 * maxi(1, adx) * maxi(1, ady)
	var step_x: int = q / (2 * adx) if adx > 0 else q
	var step_y: int = q / (2 * ady) if ady > 0 else q
	var k: int = 0
	var m: int = 0
	var cx: int = origin.x
	var cy: int = origin.y
	var p_prev: int = 0
	while true:
		var px: int = (2 * k + 1) * step_x if k < adx else q
		var py: int = (2 * m + 1) * step_y if m < ady else q
		var p_next: int = mini(px, py)
		var cell: Vector2i = Vector2i(cx, cy)
		if cell != origin and cell != target_cell:
			var info: Dictionary = _cell_blocker(grid, cell, attacker_is_ally)
			var top4: int = info["top4"]
			var floor4: int = info["floor4"]
			var z_prev_q: int = z_start4 * q + dz4 * p_prev
			var z_next_q: int = z_start4 * q + dz4 * p_next
			if z_prev_q < top4 * q or z_next_q < top4 * q:
				result.blocked = true
				result.ratio = 1.0
				result.blocking_cells = [cell]
				var min_z_q: int = mini(z_prev_q, z_next_q)
				result.reason = _reason_for(info, min_z_q < floor4 * q)
				if z_prev_q < top4 * q or dz4 == 0:
					result.hit_t = float(p_prev) / float(q)
				else:
					result.hit_t = clampf(float(z_start4 - top4) / float(-dz4), float(p_prev) / float(q), float(p_next) / float(q))
				return result
		if p_next == q:
			break
		if px == py:
			# 정확히 칸 모서리 점을 지남: 닿기만 하는 두 칸이 둘 다 막혀야 막힘.
			var side_a: Vector2i = Vector2i(cx + sx, cy)
			var side_b: Vector2i = Vector2i(cx, cy + sy)
			var info_a: Dictionary = _cell_blocker(grid, side_a, attacker_is_ally)
			var info_b: Dictionary = _cell_blocker(grid, side_b, attacker_is_ally)
			var z_corner_q: int = z_start4 * q + dz4 * p_next
			if z_corner_q < int(info_a["top4"]) * q and z_corner_q < int(info_b["top4"]) * q:
				result.blocked = true
				result.ratio = 1.0
				var cells: Array[Vector2i] = [side_a, side_b]
				cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
					return a.x < b.x if a.x != b.x else a.y < b.y)
				result.blocking_cells = cells
				var first_info: Dictionary = info_a if cells[0] == side_a else info_b
				result.reason = _reason_for(first_info, z_corner_q < int(first_info["floor4"]) * q)
				result.hit_t = float(p_next) / float(q)
				return result
			cx += sx
			cy += sy
			k += 1
			m += 1
		elif px < py:
			cx += sx
			k += 1
		else:
			cy += sy
			m += 1
		p_prev = p_next
	return result


static func _cell_blocker(grid: CombatGrid, cell: Vector2i, attacker_is_ally: bool) -> Dictionary:
	if not grid.is_inside(cell) or grid.pits.has(cell):
		return {"top4": PIT_TOP4, "floor4": PIT_TOP4, "kind": "pit"}
	var base: int = floor_height(grid, cell)
	var extra: int = 0
	var kind: String = "terrain"
	if grid.blocked_cells.has(cell):
		if grid.trees.has(cell):
			extra = OBJECT_HEIGHTS["tree"]
			kind = "tree"
		elif grid.scenery_kinds.has(cell):
			kind = grid.scenery_kinds[cell]
			extra = object_height(kind)
		else:
			extra = DEFAULT_WALL_HEIGHT
			kind = "ruin_wall"
	else:
		var prop: CombatGrid.Prop = grid.prop_at(cell)
		if prop != null:
			kind = prop.kind
			extra = object_height(prop.kind)
		else:
			var unit: CombatUnit = grid.unit_at(cell)
			if unit != null and unit.is_ally != attacker_is_ally:
				kind = "enemy"
				extra = unit_height(unit)
	return {"top4": (base + extra) * 4, "floor4": base * 4, "kind": kind}


static func _reason_for(info: Dictionary, blocked_by_terrain: bool) -> String:
	if blocked_by_terrain:
		return TranslationServer.tr("지형에 가려짐")
	match str(info.get("kind", "terrain")):
		"crate":
			return TranslationServer.tr("나무 상자에 가려짐")
		"rock":
			return TranslationServer.tr("바위에 가려짐")
		"tree":
			return TranslationServer.tr("나무에 가려짐")
		"cottage":
			return TranslationServer.tr("집에 가려짐")
		"ruin_wall":
			return TranslationServer.tr("벽에 가려짐")
		"enemy":
			return TranslationServer.tr("적에게 가려짐")
		_:
			return TranslationServer.tr("지형에 가려짐")
