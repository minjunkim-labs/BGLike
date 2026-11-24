class_name CombatPreparationState
extends RefCounted
## 보상 확인과 정비 화면의 도메인 상태와 아이템 이동·폐기·종료 규칙.

var loot: CombatLoot
var party: Array[CombatUnit] = []
var rewards: Array[Dictionary] = []
## 승리 때 줍지 않아 사라진 상자 아이템 수. 보상 확인 단계에서 알린다.
var lost_floor_items: int = 0
var active: bool = false
var maintaining: bool = false
var final_stage: bool = false
var last_in_act: bool = false


func open(
	model: CombatLoot, allies: Array[CombatUnit], drops: Array[Dictionary],
	is_final: bool, is_last_in_act: bool, is_maintaining: bool = false, lost_drops: int = 0
) -> bool:
	if active:
		return false
	loot = model
	party = allies
	rewards = drops
	final_stage = is_final
	last_in_act = is_last_in_act
	maintaining = is_maintaining
	lost_floor_items = lost_drops
	active = true
	return true


func begin_maintenance() -> bool:
	if not active or maintaining:
		return false
	maintaining = true
	return true


func bag_limit() -> int:
	return int(loot.data["bag_limit"]) if loot != null else 0


func potion_limit() -> int:
	return int(loot.data["potion_limit"]) if loot != null else 0


func bag_shortage() -> int:
	if loot == null:
		return 0
	return maxi(0, loot.bag.size() + rewards.size() - bag_limit())


func needs_finish_confirmation(confirm_finish: bool) -> bool:
	return active and maintaining and not rewards.is_empty() and confirm_finish


func finish() -> bool:
	if not active or not maintaining or loot == null or bag_shortage() > 0:
		return false
	loot.bag.append_array(rewards)
	rewards.clear()
	active = false
	return true


## 이 캐릭터의 `slot`번 물약 칸의 물약류 항목. 빈 칸이면 빈 Dictionary다.
func slot_potion(unit: CombatUnit, slot: int) -> Dictionary:
	if loot == null or unit == null or slot < 0 or slot >= unit.potions.size():
		return {}
	return loot.potion_definition(unit.potions[slot])


## 지정한 칸의 아이템. 범위를 벗어나거나 비어 있으면 빈 Dictionary다.
func item_at(kind: String, index: int, slot: int = -1) -> Dictionary:
	match kind:
		"reward":
			return rewards[index] if index >= 0 and index < rewards.size() else {}
		"bag":
			return loot.bag[index] if loot != null and index >= 0 and index < loot.bag.size() else {}
		"weapon":
			return party[index].weapon if index >= 0 and index < party.size() else {}
		"armor":
			return party[index].armor if index >= 0 and index < party.size() else {}
		"potion":
			return slot_potion(party[index], slot) if index >= 0 and index < party.size() else {}
	return {}


func can_receive(ally: int, item: Dictionary, from_bag: bool) -> bool:
	if loot == null or ally < 0 or ally >= party.size() or item.is_empty():
		return false
	var unit: CombatUnit = party[ally]
	if from_bag:
		return unit.potions.size() < potion_limit() if str(item.get("kind", "")) == "potion" else true
	return loot.can_receive(unit, item)


func receive_reward(index: int, ally: int) -> bool:
	if not active or not maintaining or loot == null or index < 0 or index >= rewards.size() \
		or ally < 0 or ally >= party.size():
		return false
	if not loot.receive(party[ally], rewards[index]):
		return false
	rewards.remove_at(index)
	return true


func store_reward(index: int) -> bool:
	if not active or not maintaining or loot == null or index < 0 or index >= rewards.size() \
		or loot.bag.size() >= bag_limit():
		return false
	loot.bag.append(rewards.pop_at(index))
	return true


func receive_from_bag(index: int, ally: int) -> bool:
	if not active or not maintaining or loot == null or ally < 0 or ally >= party.size():
		return false
	return loot.receive_from_bag(party[ally], index)


func unequip_armor(ally: int) -> bool:
	if not active or not maintaining or loot == null or ally < 0 or ally >= party.size():
		return false
	return loot.unequip_armor(party[ally])


func transfer_potion(source: int, target: int, slot: int = -1) -> bool:
	if not active or not maintaining or loot == null or source < 0 or source >= party.size() \
		or target < 0 or target >= party.size():
		return false
	return loot.transfer_potion(party[source], party[target], slot)


func discard_bag_item(index: int) -> bool:
	if not active or not maintaining or loot == null or index < 0 or index >= loot.bag.size():
		return false
	loot.bag.remove_at(index)
	return true


func can_drop(
	source_kind: String, source_index: int, source_item: Dictionary,
	target_kind: String, target_index: int, source_slot: Variant = -1
) -> bool:
	if not active or not maintaining or loot == null:
		return false
	if source_kind in ["reward", "bag"]:
		var items: Array[Dictionary] = rewards if source_kind == "reward" else loot.bag
		if source_index < 0 or source_index >= items.size() or source_item != items[source_index]:
			return false
		var item: Dictionary = items[source_index]
		if target_kind == "empty_bag":
			return source_kind == "reward" and loot.bag.size() < bag_limit()
		return target_kind in [str(item.get("kind", "")), "ally"] \
			and can_receive(target_index, item, source_kind == "bag")
	if source_index < 0 or source_index >= party.size():
		return false
	if source_kind == "armor":
		return target_kind == "empty_bag" and source_item == party[source_index].armor \
			and loot.armor_unequip_blocker(party[source_index]).is_empty()
	# 끌기 시작 때의 칸이 그대로 그 물약일 때만 넘긴다.
	return (source_kind == "potion" and target_kind in ["potion", "ally"]
		and target_index >= 0 and target_index < party.size()
		and source_slot is int and source_item == slot_potion(party[source_index], source_slot)
		and not source_item.is_empty()
		and source_index != target_index
		and party[target_index].potions.size() < potion_limit())


func apply_drop(
	source_kind: String, source_index: int, source_item: Dictionary,
	target_kind: String, target_index: int, source_slot: Variant = -1
) -> bool:
	if not can_drop(source_kind, source_index, source_item, target_kind, target_index, source_slot):
		return false
	match source_kind:
		"reward":
			return store_reward(source_index) if target_kind == "empty_bag" else receive_reward(source_index, target_index)
		"bag":
			return receive_from_bag(source_index, target_index)
		"armor":
			return unequip_armor(source_index)
		"potion":
			return transfer_potion(source_index, target_index, int(source_slot))
	return false
