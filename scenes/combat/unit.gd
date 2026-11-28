class_name CombatUnit
extends Node2D
## 팀과 직업, 격자 위치와 유닛별 턴 자원·도트 애니메이션.

enum Kind { WARRIOR = 0, ARCHER = 1, SPIDERLING = 2, MOTHER_SPIDER = 3, SCRAP_ROBOT_1000 = 4, SCRAP_ROBOT_2000 = 5, SCRAP_ROBOT_3000 = 6, FOG_SPIDER = 7 }
enum TurnResource { ACTION, BONUS_ACTION, REACTION }
enum Ability { STRENGTH, AGILITY, FINESSE, INTELLIGENCE, WILL, HEALTH }

## 능력치 기획서(docs/design/combat/ability.md) 6-1의 전사·궁수 주사위 (#386).
## 전사의 의지는 재디자인(#423)에서 d8이다.
const ALLY_ABILITY_SIDES: Array[Array] = [[20, 8, 6, 4, 8, 12], [6, 12, 20, 6, 4, 8]]
## 아이템 `stats`의 능력치 가감 키. 순서는 Ability와 같다.
const ABILITY_MODIFIER_KEYS: Array[String] = ["strength_modifier", "agility_modifier", "finesse_modifier",
	"intelligence_modifier", "will_modifier", "health_modifier"]
## 능력치 6종의 영문 파일 식별자와 대표 색(docs/design/combat/ability.md 3-4, #795). 순서는 Ability와 같다.
const ABILITY_IDS: Array[String] = ["strength", "agility", "finesse", "intelligence", "will", "health"]
const ABILITY_COLORS: Array[Color] = [Color("ef4444"), Color("10b981"), Color("fbbf24"),
	Color("06b6d4"), Color("8b5cf6"), Color("ea0cc1")]
## 어두운 패널(#121A22) 작은 글씨용 고대비 능력치 색(대비비 7+, #824).
const ABILITY_TEXT_COLORS: Array[Color] = [Color("ff8a80"), Color("6ee7b7"), Color("fde047"),
	Color("67e8f9"), Color("c4b5fd"), Color("f472b6")]
const ABILITY_ICON_DIR: String = "res://scenes/combat/art/icons/abilities/"
const STAT_ICON_DIR: String = "res://scenes/combat/art/icons/stats/"
const STAT_IDS: Array[String] = ["hp", "ac", "attack", "range", "movement"]
## 능력치 아이콘 표시 크기(48×48 원본의 0.25배 = 12 논리px, #795).
const ABILITY_ICON_SIZE: int = 12
static var ABILITY_NAMES: Array[String] = [TranslationServer.tr("힘"), TranslationServer.tr("민첩"),
	TranslationServer.tr("솜씨"), TranslationServer.tr("지능"), TranslationServer.tr("의지"), TranslationServer.tr("건강")]
static var _ability_icons: Dictionary[int, Texture2D] = {}
static var _stat_icons: Dictionary[String, Texture2D] = {}
static var _ability_mention_regex: RegEx

const MOVEMENT_PER_TURN: int = 8
## 전사의 이동력. 궁수와 이동력을 정하지 않은 몬스터는 MOVEMENT_PER_TURN이다.
const WARRIOR_MOVEMENT: int = 4

const ALLY_COLOR: Color = Color("509be0")
const ENEMY_COLOR: Color = Color("df6256")
const OUTLINE_COLOR: Color = Color("202b35")
const WEAPON_COLOR: Color = Color("f4ead1")
const HEAL_COLOR: Color = Color("70c76d")
const SHIELD_COLOR: Color = Color("6fb7ff")
## 이어하기가 그대로 되돌리는 값. 저장 파일의 값은 이 변수와 같은 타입이어야 한다.
const SAVED_FIELDS: Array[String] = ["cell", "start_cell", "facing_left", "initiative_roll", "movement_left",
	"action_capacity", "bonus_action_capacity", "reaction_capacity", "action_left", "bonus_action_left",
	"reaction_left", "overloaded", "pull_cooldown", "disengaged", "second_wind_left",
	"disengage_left", "cross_slash_left", "steel_charge_left", "battle_cry_left",
	"shield_points", "shield_turns", "battle_cry_bonus", "battle_cry_turns",
	"fallen", "oil_slipped", "oil_throw_left"]
## SAVED_FIELDS 밖의 선택 필드와 기본값(#528). 형식 5를 그대로 두려고, 이 필드가 없는 옛 저장은 기본값으로 읽는다.
const OPTIONAL_FIELDS: Dictionary[String, Variant] = {"aegisal_left": 0, "moving_shot_ready": false, "moving_shot_spent": false,
	"firework_arrow_left": 1, "whistle_left": 1, "distracted_turns": 0,
	"stealthed": false, "stealth_left": 1}
## 저장 파일의 정수 상한. 고친 저장이 끝나지 않는 턴이나 큰 목록을 만들지 않게 한다.
const SAVED_INT_LIMIT: int = 99
const SAVED_HIT_POINT_LIMIT: int = 999

class StatusEffect extends RefCounted:
	var kind: String
	var source: CombatUnit
	var turns_left: int
	## 독 중첩 제거의 건강 내성 DC. 부여한 장판 정의의 고정값을 보존하고, 화상은 0이다.
	var dc: int

	func _init(effect_kind: String, caster: CombatUnit, duration: int, save_dc: int = 0) -> void:
		kind = effect_kind
		source = caster
		turns_left = duration
		dc = save_dc if kind == "poison" else 0


@export var kind: Kind = Kind.WARRIOR
@export var is_ally: bool = true
@export var start_cell: Vector2i = Vector2i.ZERO

var cell: Vector2i = Vector2i.ZERO
var is_moving: bool = false:
	set(value):
		is_moving = value
		_update_animation()
var facing_left: bool = false:
	set(value):
		facing_left = value
		_update_animation()
# 깊이 정렬의 기준점은 높이를 빼기 전 바닥에 두고 그림만 올린다.
var floor_offset_y: float = 0.0:
	set(value):
		floor_offset_y = value
		queue_redraw()
var body_offset_y: float = 0.0:
	set(value):
		body_offset_y = value
		queue_redraw()
## 맞았을 때 그림만 잠깐 미는 거리(#559). position·칸은 바꾸지 않는다.
var recoil_offset: Vector2 = Vector2.ZERO:
	set(value):
		recoil_offset = value
		queue_redraw()
var initiative_roll: int = 0
var movement_left: int = MOVEMENT_PER_TURN
var action_capacity: int = 1
var bonus_action_capacity: int = 1
var reaction_capacity: int = 1
var action_left: int = 1
var bonus_action_left: int = 1
var reaction_left: int = 1
var overloaded: bool = false
var pull_cooldown: int = 0
var _lost_hit_points: int = 0
var hit_points: int = 12:
	set(value):
		if value != hit_points:
			_lost_hit_points = maxi(0, get_max_hit_points() - value)
		hit_points = value
		# 추가 행동은 begin_turn()이 다음 자기 턴부터 준다 (#410).
		if is_boss() and hit_points <= overload_threshold():
			overloaded = true
var stun_source: CombatUnit
var status_effects: Array[StatusEffect] = []
var is_stunned: bool = false:
	set(value):
		is_stunned = value
		if not value:
			stun_source = null
## 풋내기 궁수의 물러서며 쏘기. 아군 궁수는 쓰지 않는다 (#528).
var disengaged: bool = false
var second_wind_left: int = 1
var disengage_left: int = 2
## 애기살 남은 발수. 애기살 급조마다 +2, 아군 궁수의 기본 공격마다 -1. 새 전투에서 0이다 (궁수 문서).
var aegisal_left: int = 0
## 무빙샷: 지금 1칸 도약할 수 있는지, 이번 턴의 첫 행동 원거리 공격을 이미 했는지. 자기 턴 시작에 모두 false다.
var moving_shot_ready: bool = false
var moving_shot_spent: bool = false
## 물약류 칸마다 아이템 id(`item_data.json`). 빈 칸은 없는 압축 목록이고 길이가 쓴 칸 수다(#575). 한도는 CombatLoot가 안다.
var potions: Array[String] = []
var cross_slash_left: int = 1
var steel_charge_left: int = 1
var battle_cry_left: int = 1
## 넘어짐(기름 미끌거림 실패). 행동·보조 행동·반응을 막고, 자기 턴 시작이나 일어서기로 풀린다 (궁수 문서).
var fallen: bool = false
## 이번 턴에 기름 장판의 미끌거림을 이미 굴렸는지. 기름 장판 전체에 대해 자기 턴마다 1회다.
var oil_slipped: bool = false
var oil_throw_left: int = 1
## 폭죽 화살의 막당 남은 횟수. 새 막에서 1로 회복한다(궁수 문서).
var firework_arrow_left: int = 1
## 효시의 전투마다 남은 횟수(궁수 문서).
var whistle_left: int = 1
## 직사 기본 공격에서 엄폐에 막혀 선택할 수 없는 대상인지(#358). 참이면 스프라이트를 회색조로 표시한다.
var is_cover_blocked: bool = false:
	set(value):
		is_cover_blocked = value
		queue_redraw()
## 산만함(효시): 이 유닛의 명중굴림·내성굴림이 불리다. 시전자(궁수) 턴 시작마다 1씩 줄고 0이면 사라진다. 시전자는 쓰러져도 유지한다.
var distracted_turns: int = 0
var distracted_source: CombatUnit
## 은신: 적이 공격·스킬의 대상으로 지정할 수 없다. 다음 자기 턴 시작, 피해를 주는 공격 동작, 전투 불능, 새 전투에서 풀린다 (궁수 문서).
var stealthed: bool = false:
	set(value):
		stealthed = value
		queue_redraw()
## 은신의 전투마다 남은 횟수.
var stealth_left: int = 1
## 성스러운 장막의 방어막. 피해를 HP보다 먼저 받고, 자기 턴 시작마다 shield_turns가 준다.
var shield_points: int = 0:
	set(value):
		shield_points = value
		queue_redraw()
var shield_turns: int = 0
## 전투의 함성의 명중 보너스. 시전자의 턴 시작(쓰러졌으면 시계 슬롯)마다 battle_cry_turns가 준다.
var battle_cry_bonus: int = 0
var battle_cry_turns: int = 0
var battle_cry_source: CombatUnit
var weapon: Dictionary = {}
var armor: Dictionary = {}:
	set(value):
		var lost: int = maxi(_lost_hit_points, get_max_hit_points() - hit_points)
		armor = value
		if hit_points > 0:
			hit_points = maxi(1, get_max_hit_points() - lost)
			# 최소1 보정 전의 손실을 다음 장비 교체에도 보존한다.
			_lost_hit_points = lost
		queue_redraw()
## 파티 주사위 레벨(#477). 파티의 값을 battle이 아군에 맞추며 저장하지 않는다. 몬스터는 늘 0이다.
## 최대 HP가 늘면 잃은 HP는 그대로라 현재 HP도 같은 만큼 오른다. 쓰러진 유닛은 0 그대로다.
var dice_level: int = 0:
	set(value):
		var lost: int = maxi(_lost_hit_points, get_max_hit_points() - hit_points)
		dice_level = value
		if hit_points > 0:
			hit_points = maxi(1, get_max_hit_points() - lost)
			_lost_hit_points = lost
		queue_redraw()
var is_previewed: bool = false:
	set(value):
		is_previewed = value
		queue_redraw()
var is_selected: bool = false:
	set(value):
		is_selected = value
		queue_redraw()
var is_occluded: bool = false
var _silhouette: Sprite2D
var _sprite: AnimatedSprite2D
var _attacking: bool = false
var _art_top_y: float = -28.0


## 능력치의 면은 1~n이다. 값은 능력치 점수나 d20 보정값이 아닌 면 수다 (#321).
func get_ability_sides(ability: Ability) -> int:
	if is_ally and kind in [Kind.WARRIOR, Kind.ARCHER]:
		return ALLY_ABILITY_SIDES[kind][ability]
	return int(CombatEnemyDefinitions.for_kind(kind)["abilities"][ability])


static func ability_name(ability: Ability) -> String:
	return ABILITY_NAMES[ability]


static func ability_color(ability: Ability) -> Color:
	return ABILITY_COLORS[ability]


static func ability_text_color(ability: Ability) -> Color:
	return ABILITY_TEXT_COLORS[ability]


## 툴팁·전투 로그 본문의 능력치 판정 표기(예: "힘 d20", "민첩 내성")에 12px 아이콘과 고대비 색을 인라인으로 붙인다(#824).
static func decorate_abilities(text: String) -> String:
	if text.is_empty():
		return text
	if _ability_mention_regex == null:
		_ability_mention_regex = RegEx.new()
		var names: String = "|".join(ABILITY_NAMES)
		var suffixes: String = "|".join([
			"d\\d+",
			TranslationServer.tr("내성"),
			TranslationServer.tr("굴림"),
			TranslationServer.tr("가감"),
		])
		_ability_mention_regex.compile("(^|[\\s(:·\\]])(%s)(?=\\s+(?:%s))" % [names, suffixes])
	var matches: Array[RegExMatch] = _ability_mention_regex.search_all(text)
	if matches.is_empty():
		return text
	var result: String = ""
	var cursor: int = 0
	for found: RegExMatch in matches:
		var name_start: int = found.get_start(2)
		var name_end: int = found.get_end(2)
		var label: String = found.get_string(2)
		var index: int = ABILITY_NAMES.find(label)
		if index < 0:
			continue
		var ability: Ability = index as Ability
		result += text.substr(cursor, name_start - cursor)
		result += "[img=12x12]%s[/img][color=#%s]%s[/color]" % [
			ability_icon_path(ability),
			ability_text_color(ability).to_html(false),
			label,
		]
		cursor = name_end
	result += text.substr(cursor)
	return result


static func ability_icon_path(ability: Ability) -> String:
	return "%s%s.png" % [ABILITY_ICON_DIR, ABILITY_IDS[ability]]


static func ability_icon(ability: Ability) -> Texture2D:
	var key: int = int(ability)
	if not _ability_icons.has(key):
		_ability_icons[key] = load(ability_icon_path(ability)) as Texture2D
	return _ability_icons[key]


static func stat_icon_path(stat_id: String) -> String:
	return "%s%s.png" % [STAT_ICON_DIR, stat_id]


static func stat_icon(stat_id: String) -> Texture2D:
	if not _stat_icons.has(stat_id):
		_stat_icons[stat_id] = load(stat_icon_path(stat_id)) as Texture2D
	return _stat_icons[stat_id]


## 굴림값과 표준값에 더하는 값. 주사위 레벨(파티 공통)과 장비의 능력치 가감 합이다 (주사위 육성 4장, 아이템 기획 폼 3장).
func get_ability_modifier(ability: Ability) -> int:
	return dice_level + get_equipment_modifier(ability)


## 장비의 능력치 가감 합. 레벨은 포함하지 않는다.
func get_equipment_modifier(ability: Ability) -> int:
	return _equipment_stat(ABILITY_MODIFIER_KEYS[ability])


## 능력치 이름 없는 주사위 표기(`d20`, `d20+2`, `d20 +1`, #795).
static func ability_die_text(unit: CombatUnit, ability: Ability) -> String:
	var modifier: int = unit.get_equipment_modifier(ability)
	return "d%d%s%s" % [unit.get_ability_sides(ability), "" if modifier == 0 else "%+d" % modifier,
		"" if unit.dice_level == 0 else " %+d" % unit.dice_level]


## 패널·호버의 능력치 표기. 장비 가감이 있으면 `힘 d20+2`처럼, 레벨이 있으면 `힘 d20 +1`처럼 덧붙인다 (#456, #477).
static func ability_text(unit: CombatUnit, ability: Ability) -> String:
	return "%s %s" % [ABILITY_NAMES[ability], ability_die_text(unit, ability)]


## 이름 뒤에 주격 조사 이/가를 붙인다. 숫자로 끝나면 읽은 소리를 따른다(1000 → 천 → 이, #415).
static func with_subject_particle(display_name: String) -> String:
	if display_name.is_empty():
		return display_name
	var last: int = display_name.unicode_at(display_name.length() - 1)
	var has_final: bool
	if last >= 0xAC00 and last <= 0xD7A3:
		has_final = (last - 0xAC00) % 28 != 0
	elif last >= 0x30 and last <= 0x39:
		# 0(영·십·백·천·만)과 1·3·6·7·8은 받침이 있다.
		has_final = char(last) in "013678"
	else:
		return display_name + "(이)가"  # NO_TRANSLATE: 한국어 조사 규칙
	return display_name + ("이" if has_final else "가")  # NO_TRANSLATE: 한국어 조사 규칙


## 현재 일반 무기는 직업의 기본 대검·활을 강화하는 장비다. 실제 대상 거리로 유형을 바꾸지 않는다.
## 아군 궁수는 임시로 솜씨, 풋내기 궁수는 민첩이다 (능력치 기획서 4-2·7장, #386).
func get_attack_ability() -> Ability:
	if kind != Kind.ARCHER:
		return Ability.STRENGTH
	return Ability.FINESSE if is_ally else Ability.AGILITY


func is_ranged_attack() -> bool:
	return kind == Kind.ARCHER


func get_defense_bonus() -> int:
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["defense_bonus"])
	return _equipment_stat("defense_bonus")


## AC = 민첩 표준값 + 방어 가산. 몬스터 정의의 armor_class가 있으면 그 값으로 덮어쓴다 (4-3, 7장).
func get_armor_class() -> int:
	var armor_class: int = maxi(1, maxi(1, CombatChecks.standard_value(get_ability_sides(Ability.AGILITY))
		+ get_ability_modifier(Ability.AGILITY)) + get_defense_bonus())
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind).get("armor_class", armor_class))
	return armor_class


## 아군은 (건강 면 수 ÷ 2) × (레벨 + 1) + 5에 장비 최대 HP를 더하며 하한은 1이다 (능력치 기획서 4-6·4-9).
func get_max_hit_points() -> int:
	if not is_ally:
		return maxi(1, int(CombatEnemyDefinitions.for_kind(kind)["max_hit_points"]))
	return maxi(1, get_ability_sides(Ability.HEALTH) / 2 * (dice_level + 1) + 5 + _equipment_stat("max_hit_points"))


func get_attack_bonus() -> int:
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["attack_bonus"])
	return _equipment_stat("attack_bonus")


## 명중굴림의 가산. 공격 가산에 전투의 함성을 더한다. DC는 공격 가산만 쓴다.
func get_hit_bonus() -> int:
	return get_attack_bonus() + battle_cry_bonus


func get_damage_bonus() -> int:
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["damage_bonus"])
	# 아군은 기본 피해 보정이 없고 장비로만 더한다. 피해식은 능력치 주사위 + 레벨 + 기타 가산치다 (#407 답 3번, 궁수 문서).
	return _equipment_stat("damage_bonus")


func _equipment_stat(stat: String) -> int:
	return int(weapon.get("stats", {}).get(stat, 0)) + int(armor.get("stats", {}).get(stat, 0))


func get_attack_range() -> int:
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["attack_range"])
	return 1 if kind == Kind.WARRIOR else 6


## 민첩 굴림값. 눈(initiative_roll)에 민첩 가감을 더한다. 0은 아직 굴리지 않은 소환 유닛이라 그대로 둔다.
func get_initiative() -> int:
	return initiative_roll if initiative_roll == 0 else maxi(1, initiative_roll + get_ability_modifier(Ability.AGILITY))


func get_display_name() -> String:
	if not is_ally:
		return CombatEnemyDefinitions.for_kind(kind)["name"]
	return tr("아군 전사") if kind == Kind.WARRIOR else tr("아군 궁수")


func get_art_id() -> String:
	if not is_ally and kind <= Kind.ARCHER:
		return "novice_barbarian" if kind == Kind.WARRIOR else "novice_archer"
	return ["warrior", "archer", "spiderling", "mother_spider",
		"scrap_robot_1000", "scrap_robot_2000", "scrap_robot_3000", "fog_spider"][kind]


func get_status_label_y() -> float:
	return _art_top_y + body_offset_y - 9.0


## HP 바에서 HP와 방어막이 차지하는 비율(x=HP, y=방어막, #457). 방어막은 HP 뒤에 이어 그린다.
## HP와 방어막 합이 최대 HP를 넘으면 바 전체를 합에 맞춘다. 그래서 만피에 방어막을 받으면 초록이 줄어 보인다.
func get_bar_fractions() -> Vector2:
	var total: float = float(maxi(get_max_hit_points(), hit_points + shield_points))
	return Vector2(hit_points / total, shield_points / total)


## 유닛 위에 지금 보이는 상태 글자. 기절·화상·독.
func get_status_text() -> String:
	var status: String = get_periodic_status_text()
	if is_stunned:
		status = tr("기절") + (" " + status if not status.is_empty() else "")
	if fallen:
		status = tr("넘어짐") + (" " + status if not status.is_empty() else "")
	if stealthed:
		status = tr("은신") + (" " + status if not status.is_empty() else "")
	return status


## 상태 글자 text가 차지할 화면 영역을 padding만큼 넓힌다. 팝업 배치가 피한다.
func get_status_area(text: String, padding: float) -> Rect2:
	var font: Font = ThemeDB.fallback_font
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var area: Rect2 = Rect2(Vector2(-width / 2.0, floor_offset_y + get_status_label_y() - font.get_ascent(10)),
		Vector2(width, font.get_height(10)))
	return (get_global_transform_with_canvas() * area).grow(padding)


func get_status_count(kind_name: String) -> int:
	var count: int = 0
	for effect: StatusEffect in status_effects:
		if effect.kind == kind_name:
			count += 1
	return count


func get_periodic_status_text() -> String:
	var states: Array[String] = []
	for kind_name: String in ["burn", "poison"]:
		var count: int = get_status_count(kind_name)
		if count > 0:
			var text: String = "%s%d" % [tr("화상") if kind_name == "burn" else tr("독"), count]
			# 독안개로 얻은 중첩은 기간이 없다(turns_left 0).
			if status_effects.any(func(effect: StatusEffect) -> bool: return effect.kind == kind_name and effect.turns_left == 0):
				text += "(%s)" % tr("기간 없음")
			states.append(text)
	return " ".join(states)


func is_boss() -> bool:
	return not is_ally and bool(CombatEnemyDefinitions.for_kind(kind).get("boss", false))


## 과부하가 켜지는 HP(최대 HP의 절반). HP setter와 과부하 표시(#503)가 같이 쓴다.
func overload_threshold() -> int:
	return get_max_hit_points() / 2


func is_poison_immune() -> bool:
	return not is_ally and bool(CombatEnemyDefinitions.for_kind(kind).get("poison_immune", false))


func can_drop_extra_reward() -> bool:
	return not is_ally and kind != Kind.SPIDERLING


func get_movement() -> int:
	if is_ally:
		return maxi(1, (WARRIOR_MOVEMENT if kind == Kind.WARRIOR else MOVEMENT_PER_TURN) + _equipment_stat("max_movement"))
	return int(CombatEnemyDefinitions.for_kind(kind).get("movement", MOVEMENT_PER_TURN))


## 자기 턴 시작에 처리하는 상태. 자원은 채우지 않는다(3-3). 과부하의 추가 행동(+1, #410)만 여기서 더한다.
func begin_turn() -> void:
	disengaged = false
	moving_shot_ready = false
	moving_shot_spent = false
	pull_cooldown = maxi(0, pull_cooldown - 1)
	if overloaded:
		action_left += 1


## 턴 자원 4종을 채운다. 자기 턴 묶음이 확정될 때와 전투·스테이지 시작에 부른다(3-3).
func refill_turn_resources() -> void:
	movement_left = get_movement()
	action_left = action_capacity
	bonus_action_left = bonus_action_capacity
	reaction_left = reaction_capacity


func begin_stage(restore_act: bool) -> void:
	overloaded = false
	pull_cooldown = 0
	if restore_act:
		hit_points = get_max_hit_points()
		CombatActionRules.restore_uses(self)
	CombatActionRules.restore_combat_uses(self)
	# 물약은 막 시작과 재시작에서도 현재 개수를 유지한다.
	is_stunned = false
	status_effects.clear()
	clear_unit_effects()
	aegisal_left = 0
	stealthed = false
	fallen = false
	oil_slipped = false
	is_selected = false
	is_previewed = false
	begin_turn()
	refill_turn_resources()


## 방어막과 전투의 함성. 전투 전환과 전투 불능에서 지운다.
func clear_unit_effects() -> void:
	shield_points = 0
	shield_turns = 0
	battle_cry_bonus = 0
	battle_cry_turns = 0
	battle_cry_source = null
	distracted_turns = 0
	distracted_source = null


## 그 종류(아이템 id)의 물약 칸 수.
func potion_count(id: String) -> int:
	return potions.count(id)


## 그 종류의 마지막 칸 하나를 뺀다. 남은 칸은 순서를 지키고 앞으로 당긴다. 없으면 false.
func take_potion(id: String) -> bool:
	var slot: int = potions.rfind(id)
	if slot < 0:
		return false
	potions.remove_at(slot)
	return true


## 이어하기용 상태. 다른 유닛은 전투 유닛 목록의 번호로 적고, 없으면 -1이다.
func save_state(units: Array[CombatUnit]) -> Dictionary:
	var statuses: Array = []
	for effect: StatusEffect in status_effects:
		statuses.append([effect.kind, units.find(effect.source), effect.turns_left, effect.dc])
	var data: Dictionary = {"kind": kind, "ally": is_ally, "weapon": weapon, "armor": armor,
		"hit_points": hit_points, "lost_hit_points": _lost_hit_points, "stunned": is_stunned,
		"stun_source": units.find(stun_source), "statuses": statuses,
		"battle_cry_source": units.find(battle_cry_source), "distracted_source": units.find(distracted_source),
		"potions": potions.duplicate()}
	for field: String in SAVED_FIELDS:
		data[field] = get(field)
	for field: String in OPTIONAL_FIELDS:
		data[field] = get(field)
	return data


## save_state()의 값으로 되돌린다. 장비·HP setter가 바꾸는 HP·과부하는 뒤에서 덮는다.
func load_state(data: Dictionary, units: Array[CombatUnit]) -> void:
	armor = data.armor
	weapon = data.weapon
	hit_points = data.hit_points
	potions.assign(data.potions)
	for field: String in SAVED_FIELDS:
		set(field, data[field])
	for field: String in OPTIONAL_FIELDS:
		set(field, data.get(field, OPTIONAL_FIELDS[field]))
	_lost_hit_points = data.lost_hit_points
	is_stunned = data.stunned
	stun_source = units[data.stun_source] if data.stun_source >= 0 else null
	battle_cry_source = units[data.battle_cry_source] if data.battle_cry_source >= 0 else null
	var distracted: int = data.get("distracted_source", -1)
	distracted_source = units[distracted] if distracted >= 0 else null
	status_effects.clear()
	for saved: Array in data.statuses:
		var effect: StatusEffect = StatusEffect.new(saved[0], units[saved[1]], saved[2], saved[3])
		status_effects.append(effect)


## 저장 파일의 값을 load_state()에 넘겨도 되는지. 장비의 내용은 CombatLoot가 확인한다.
## 타입은 이 유닛의 변수와 비교하므로 어느 유닛에서 불러도 같다. count는 전투 유닛 수다.
func is_valid_state(data: Variant, count: int, map_size: Vector2i) -> bool:
	if not (data is Dictionary and data.get("kind") is int and data.kind in Kind.values() and data.get("ally") is bool
			and data.get("weapon") is Dictionary and data.get("armor") is Dictionary
			and data.get("hit_points") is int and data.hit_points >= 0 and data.hit_points <= SAVED_HIT_POINT_LIMIT
			and data.get("lost_hit_points") is int and data.lost_hit_points >= 0
			and data.lost_hit_points <= SAVED_HIT_POINT_LIMIT and data.get("stunned") is bool
			and _valid_index(data.get("stun_source"), count, true) and (not data.stunned or data.stun_source >= 0)
			and _valid_index(data.get("battle_cry_source"), count, true)
			and data.get("statuses") is Array and data.statuses.size() <= 6
			and data.get("potions") is Array and data.potions.size() <= SAVED_INT_LIMIT
			and data.potions.all(func(id: Variant) -> bool: return id is String)):
		return false
	for field: String in SAVED_FIELDS:
		var value: Variant = data.get(field)
		if typeof(value) != typeof(get(field)) or value is int and (value < 0 or value > SAVED_INT_LIMIT):
			return false
	for field: String in OPTIONAL_FIELDS:
		if not data.has(field):
			continue
		var optional: Variant = data[field]
		if typeof(optional) != typeof(OPTIONAL_FIELDS[field]) or optional is int and (optional < 0 or optional > SAVED_INT_LIMIT):
			return false
	var area: Rect2i = Rect2i(Vector2i.ZERO, map_size)
	if not area.has_point(data.cell) or not area.has_point(data.start_cell):
		return false
	# 방어막은 3턴, 전투의 함성은 2턴이다. 기간이 남은 효과만 값과 시전자를 가진다.
	if (data.shield_turns > CombatActionRules.SHIELD_TURNS or (data.shield_turns == 0) != (data.shield_points == 0)
			or data.battle_cry_turns > CombatActionRules.BATTLE_CRY_TURNS or (data.battle_cry_turns == 0) != (data.battle_cry_source == -1)
			or (data.battle_cry_turns == 0) != (data.battle_cry_bonus == 0)):
		return false
	# 산만함(효시)은 2턴이고, 기간이 남은 효과만 시전자를 가진다. 키가 없는 옛 저장은 산만함 없음이다.
	var distracted_from: Variant = data.get("distracted_source", -1)
	if (not _valid_index(distracted_from, count, true) or data.get("distracted_turns", 0) > CombatActionRules.DISTRACTION_TURNS
			or (data.get("distracted_turns", 0) == 0) != (distracted_from == -1)):
		return false
	return (data.statuses as Array).all(func(saved: Variant) -> bool:
		return (saved is Array and saved.size() == 4 and saved[0] in ["burn", "poison"]
			and _valid_index(saved[1], count, false) and saved[2] is int and saved[2] >= (0 if saved[0] == "poison" else 1) and saved[2] <= 4
			and saved[3] is int and saved[3] >= 0 and saved[3] <= SAVED_INT_LIMIT
			and (saved[3] == 0 if saved[0] == "burn" else saved[3] > 0)))


static func _valid_index(value: Variant, count: int, optional: bool) -> bool:
	return value is int and value >= (-1 if optional else 0) and value < count


func spend_movement(cost: int) -> bool:
	if cost <= 0 or cost > movement_left:
		return false
	movement_left -= cost
	return true


func spend_resource(resource: TurnResource) -> bool:
	match resource:
		TurnResource.ACTION:
			if action_left == 0:
				return false
			action_left -= 1
		TurnResource.BONUS_ACTION:
			if bonus_action_left == 0:
				return false
			bonus_action_left -= 1
		TurnResource.REACTION:
			if reaction_left == 0:
				return false
			reaction_left -= 1
		_:
			return false
	return true


func has_available_turn_action(
	has_move_destination: bool, has_action_target: bool, has_bonus_action_target: bool
) -> bool:
	# 반응은 자기 턴의 종료 가능 여부에 영향을 주지 않는다.
	return (movement_left > 0 and has_move_destination
		or action_left > 0 and has_action_target
		or bonus_action_left > 0 and has_bonus_action_target)


func _ready() -> void:
	facing_left = not is_ally
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.centered = false
	_sprite.offset = Vector2(-32, -56)
	_sprite.scale = Vector2.ONE * 0.5
	_sprite.material = preload("res://scenes/combat/art/pixel_art.tres")
	_sprite.sprite_frames = SpriteFrames.new()
	_sprite.sprite_frames.remove_animation("default")
	var unit_id: String = get_art_id()
	_art_top_y = 0.0
	for state: String in ["idle", "move", "attack"]:
		for direction: String in ["left", "right"]:
			var animation: StringName = state + "_" + direction
			_sprite.sprite_frames.add_animation(animation)
			var speed: float = 3.0 if state == "idle" else CombatPresentation.fps(24.0 if state == "move" else 12.0)
			_sprite.sprite_frames.set_animation_speed(animation, speed)
			_sprite.sprite_frames.set_animation_loop(animation, state != "attack")
			for frame: int in range(2):
				var texture: Texture2D = load("res://scenes/combat/art/units/%s/%s/%s/%03d.png" % [
					unit_id, state, direction, frame]) as Texture2D
				_sprite.sprite_frames.add_frame(animation, texture)
				_art_top_y = minf(_art_top_y, (texture.get_image().get_used_rect().position.y - 56.0) * 0.5)
	add_child(_sprite)
	_silhouette = Sprite2D.new()
	_silhouette.centered = false
	_silhouette.offset = _sprite.offset
	_silhouette.scale = _sprite.scale
	_silhouette.z_index = 1
	_silhouette.visible = false
	var outline: ShaderMaterial = ShaderMaterial.new()
	outline.shader = preload("res://scenes/combat/art/unit_outline.gdshader")
	_silhouette.material = outline
	add_child(_silhouette)
	_sprite.frame_changed.connect(_sync_sprite)
	_sprite.animation_changed.connect(_sync_sprite)
	_sprite.animation_finished.connect(func() -> void:
		_attacking = false
		_update_animation())
	_update_animation()
	cell = start_cell
	hit_points = get_max_hit_points()
	begin_turn()
	refill_turn_resources()
	queue_redraw()


func _update_animation() -> void:
	if _sprite == null:
		return
	var state: String = "attack" if _attacking else ("move" if is_moving else "idle")
	_sprite.play(state + ("_left" if facing_left else "_right"))
	_sync_sprite()


func _sync_sprite() -> void:
	if _silhouette != null and _sprite.sprite_frames.has_animation(_sprite.animation):
		_silhouette.texture = _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)


## 히트스톱(#559): 그림 애니메이션을 멈추거나 다시 재생한다.
func set_hit_pause(paused: bool) -> void:
	if _sprite != null:
		_sprite.speed_scale = 0.0 if paused else 1.0


## 지금 그려진 프레임. 잔상이 복제한다.
func current_frame_texture() -> Texture2D:
	return _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)


func play_attack() -> void:
	_attacking = true
	_sprite.stop()
	_update_animation()


func face_toward(destination: Vector2) -> void:
	if absf(destination.x - position.x) > 0.5:
		facing_left = destination.x < position.x
		queue_redraw()


func _draw() -> void:
	_silhouette.visible = is_occluded or is_selected or is_previewed
	var edge: Color = Color("f4cf69") if is_selected else (
		Color("f4ead1") if is_previewed else (ALLY_COLOR if is_ally else ENEMY_COLOR))
	(_silhouette.material as ShaderMaterial).set_shader_parameter("outline_color", edge)
	(_silhouette.material as ShaderMaterial).set_shader_parameter("fill_alpha", 0.22 if is_occluded else 0.0)
	_silhouette.position = Vector2(0, floor_offset_y + body_offset_y) + recoil_offset
	_sprite.position = _silhouette.position
	var tint: Color = Color(0.55, 0.55, 0.58, 1.0) if is_cover_blocked else Color.WHITE
	tint.a = 0.5 if stealthed else 1.0
	_sprite.modulate = tint
	draw_set_transform(Vector2(0, floor_offset_y))
	var status_y: float = get_status_label_y()
	draw_rect(Rect2(-9, status_y + 4, 18, 4), OUTLINE_COLOR)
	var fractions: Vector2 = get_bar_fractions()
	draw_rect(Rect2(-8, status_y + 5, 16.0 * fractions.x, 2), HEAL_COLOR)
	if shield_points > 0:
		draw_rect(Rect2(-8 + 16.0 * fractions.x, status_y + 5, 16.0 * fractions.y, 2), SHIELD_COLOR)
	var status: String = get_status_text()
	if not status.is_empty():
		var font: Font = ThemeDB.fallback_font
		var width: float = font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, Vector2(-width / 2.0, status_y), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, WEAPON_COLOR)
	draw_polyline(PackedVector2Array([Vector2(-9, 0), Vector2(0, 4), Vector2(9, 0)]),
		ALLY_COLOR if is_ally else ENEMY_COLOR)
	draw_set_transform(Vector2.ZERO)
