class_name CombatTurnHud
extends Control
## 전투 화면. 비용 기호와 막당 횟수를 서로 다른 위치에 표시한다.

signal unit_selected(unit: CombatUnit)
## 턴 순서 초상에 마우스가 올라가면 그 유닛, 떠나면 null(#556).
signal unit_hovered(unit: CombatUnit)
signal end_turn_requested
signal action_selected(action: String)
signal reaction_selected(use_reaction: bool)
signal restart_requested

# Space는 적 턴 가속 키다. 반응 확인 창의 포커스된 버튼을 누르지 않는다.
class SpaceBlocker extends Node:
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()


## 유닛 패널 능력치 1칸. 12 논리px 아이콘과 주사위를 보이고 호버·포커스로 능력치 이름을 띄운다(#795).
class AbilitySlot extends HBoxContainer:
	var ability: CombatUnit.Ability
	var icon_rect: TextureRect = TextureRect.new()
	var die_label: RichTextLabel = RichTextLabel.new()

	func _init(slot_ability: CombatUnit.Ability) -> void:
		ability = slot_ability
		name = "Ability_" + CombatUnit.ABILITY_IDS[ability]
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_theme_constant_override("separation", 2)
		icon_rect.name = "Icon"
		icon_rect.texture = CombatUnit.ability_icon(ability)
		icon_rect.material = preload("res://scenes/combat/art/pixel_art.tres")
		icon_rect.custom_minimum_size = Vector2(CombatUnit.ABILITY_ICON_SIZE, CombatUnit.ABILITY_ICON_SIZE)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon_rect)
		die_label.name = "Die"
		die_label.bbcode_enabled = true
		die_label.fit_content = true
		die_label.scroll_active = false
		die_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		die_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		die_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		die_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(die_label)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _get_tooltip(_at_position: Vector2) -> String:
		return ""

	func _draw() -> void:
		if has_focus():
			draw_rect(Rect2(Vector2.ZERO, size), FOCUS_COLOR, false, 1.0)

## 확인 창 모양은 프로젝트 공용 테마에서 가져온다(#262).
const UI_THEME: Theme = preload("res://scenes/ui_theme.tres")
const DEFAULT_BUTTON_COLOR: Color = Color("223940")
const END_BUTTON_COLOR: Color = Color("926725")
## 포커스 테두리 색(docs/design/pixel-art.md UI 절).
const FOCUS_COLOR: Color = Color("ebba84")
const RESOURCE_COLORS: Array[Color] = [Color("70c76d"), Color("edaa54"), Color("ac90e5")]
## 행동·보조 행동·반응의 칸 안 비용 기호(RESOURCE_COLORS와 같은 순서).
const COST_SYMBOLS: Array[String] = ["●", "▲", "◆"]
const COST_OUTLINE_COLOR: Color = Color("120d16")
## 스킬 칸 면. 쓸 수 있으면 공용 테마의 버튼 호버색, 쓸 수 없으면 어두운 회색이다(#517).
const SLOT_FACE_ACTIVE: Color = Color("365d61")
const SLOT_FACE_IDLE: Color = Color("242a30")
## 스킬 칸 폭. 한 줄이 넘치면 SLOT_MIN까지 줄인다. 아이콘(24)과 좌우 여백 2씩이 들어가는 최소다(#554).
const SLOT_FULL: int = 52
const SLOT_MIN: int = 28
const SLOT_GAP: int = 3
const SLOT_HEIGHT: int = 34
## 한 줄에 들어가는 최대 칸 수. 넘으면 SLOT_MIN에서 더 줄지 않아 패널이 넓어지므로 배치를 다시 정한다(#554).
const SLOT_ROW_MAX: int = 8
## 스킬 줄 왼쪽의 패시브 열 폭(버튼 22)과 간격.
const PASSIVE_COLUMN: int = 25
const TITLE_GAP: int = 1
## 호버 설명의 왼쪽 여백·최대 폭·대상과의 간격. 640×360 기준 고정값이다(#555).
const TOOLTIP_LEFT: int = 8
const TOOLTIP_MAX_WIDTH: int = 240
const TOOLTIP_GAP: int = 4
const NARROW_MARGIN: int = 2

var _shown_order: Array[CombatUnit] = []
var _portraits: Dictionary[CombatUnit, Button] = {}
var _order_moves: Dictionary[CombatUnit, Vector2] = {}
var _order_tween: Tween
var _order_revision: int = 0
var _actions: Dictionary[String, Button] = {}
# 지금 보이는 스킬 버튼. 숫자 키와 방향키가 왼쪽부터 이 순서를 쓴다.
var _action_slots: Array[Button] = []
var _badges: Dictionary[String, Label] = {}
var _costs: Dictionary[String, HBoxContainer] = {}
var _containers: Array[PanelContainer] = []
# 스킬 컨테이너 맨 왼쪽의 패시브 칸(#457). 켜짐·적용 중에만 강조한다.
var _passives: Dictionary[String, Button] = {}
var _passive_dots: Dictionary[String, Label] = {}
var _ability_slots: Array[AbilitySlot] = []
var _titles: Array[Label] = []
var _log_lines: Array[String] = []
var _status_buttons: Array[Button] = []
var _status_signature: Array[PackedStringArray] = []
var _status_display_text: String = ""
# 기본 툴팁 창 대신 같은 HUD의 최상단에 설명을 그린다.
var _tooltip: HoverTooltip = HoverTooltip.new()
var _cover_tooltip: PanelContainer
var _cover_tooltip_label: Label
var reaction_dialog: ConfirmationDialog = ConfirmationDialog.new()
## 반사신경 비모달 안내 배너(#824). 맵 클릭을 막지 않고 후보 칸 선택과 넘기기를 안내한다.
var reflex_banner: PanelContainer = PanelContainer.new()
var _reflex_prompt_label: Label = Label.new()
var reflex_skip_button: Button = Button.new()
## 기름에서 넘어진 아군이 자기 턴에 이동력을 내고 일어나는 버튼(#500 2a). 턴 종료 버튼 바로 위에 둔다.
var stand_button: Button = Button.new()
## 유닛 패널의 AC와 팔랑크스 상태를 위치로 계산한다. 없으면 유닛 AC만 보인다.
var grid: CombatGrid

@onready var round_label: Label = $Round
@onready var progress_label: Label = $Progress
@onready var order_bar: HBoxContainer = $OrderScroll/OrderBar
@onready var unit_label: Label = $UnitDetails/UnitPanel/Info/CurrentUnit
@onready var actor_label: Label = $UnitDetails/UnitPanel/Info/Actor
@onready var vitals_label: RichTextLabel = $UnitDetails/UnitPanel/Info/Vitals
@onready var ability_grid: GridContainer = $UnitDetails/UnitPanel/Info/Abilities
@onready var resource_label: RichTextLabel = $UnitDetails/UnitPanel/Info/Resources
@onready var status_row: HFlowContainer = $UnitDetails/UnitPanel/Info/StatusRow
@onready var health_bar: ProgressBar = $UnitDetails/UnitPanel/Info/Health
@onready var end_button: Button = $EndTurn
@onready var preview_label: Label = $UnitDetails/AttackPreview
@onready var action_bar: VBoxContainer = $Skills/Groups
@onready var message_label: RichTextLabel = $CombatLog/Message
@onready var result_label: Label = $Result/Panel/Contents/Outcome
@onready var restart_button: Button = $Result/Panel/Contents/Restart


## 한 줄에 count개 버튼이 들어가도록 줄이는 칸 폭. 들어가면 SLOT_FULL이고 아무리 좁아도 SLOT_MIN이다(#554).
static func slot_width(available: float, count: int) -> int:
	if count <= 0:
		return SLOT_FULL
	return clampi(floori((available - SLOT_GAP * (count - 1)) / count), SLOT_MIN, SLOT_FULL)


func is_reaction_open() -> bool:
	return reaction_dialog.visible or reflex_banner.visible


func feedback_obstacles() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for panel: Control in [$Round, $Progress, $OrderScroll, $UnitDetails, $Skills, $CombatLog, $EndTurn, stand_button, reflex_banner]:
		if panel.is_visible_in_tree():
			result.append(panel.get_global_rect())
	return result


func _ready() -> void:
	# 유닛 정보 패널의 HP 바는 맵 위 HP 바와 같은 색이다.
	var health_fill: StyleBoxFlat = StyleBoxFlat.new()
	health_fill.bg_color = CombatUnit.HEAL_COLOR
	var health_back: StyleBoxFlat = StyleBoxFlat.new()
	health_back.bg_color = CombatUnit.OUTLINE_COLOR
	health_bar.add_theme_stylebox_override("fill", health_fill)
	health_bar.add_theme_stylebox_override("background", health_back)
	# 호버 설명은 왼쪽 열(x 8, 최대 폭 240)에 둔다. 스킬·패시브는 스킬 패널 위, 초상·유닛 상태는 턴 순서 바 아래다(#555, #619, #796).
	# 전투 로그와 유닛 정보는 오른쪽 열이라 자리만으로 가리지 않는다.
	_tooltip.max_width = TOOLTIP_MAX_WIDTH
	_tooltip.place = func(target: Control, tooltip_size: Vector2) -> Vector2:
		var left: float = get_global_rect().position.x + TOOLTIP_LEFT
		if order_bar.is_ancestor_of(target) or status_row.is_ancestor_of(target):
			return Vector2(left, ($OrderScroll as Control).get_global_rect().end.y + TOOLTIP_GAP)
		if ability_grid.is_ancestor_of(target):
			var rect: Rect2 = target.get_global_rect()
			return Vector2(rect.position.x, rect.end.y + TOOLTIP_GAP)
		return Vector2(left, ($Skills as Control).get_global_rect().position.y - TOOLTIP_GAP - tooltip_size.y)
	_tooltip.hidden_when = func() -> bool: return is_reaction_open() or $Result.visible
	_tooltip.format = func(target: Control) -> String:
		return target.get_meta(&"tooltip_bbcode") as String if target.has_meta(&"tooltip_bbcode") \
			else HoverTooltip.headed(target.tooltip_text)
	add_child(_tooltip)
	_cover_tooltip = PanelContainer.new()
	_cover_tooltip.name = "CoverTooltip"
	_cover_tooltip.theme_type_variation = &"HudPanel"
	_cover_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover_tooltip.visible = false
	_cover_tooltip.z_index = 20
	_cover_tooltip_label = Label.new()
	_cover_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover_tooltip_label.add_theme_color_override("font_color", Color("ff8a80"))
	_cover_tooltip.add_child(_cover_tooltip_label)
	add_child(_cover_tooltip)
	end_button.pressed.connect(func() -> void: end_turn_requested.emit())
	stand_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	stand_button.offset_left = end_button.offset_left
	stand_button.offset_right = end_button.offset_right
	stand_button.offset_bottom = end_button.offset_top - 4
	stand_button.offset_top = stand_button.offset_bottom - 22
	stand_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	stand_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stand_button.visible = false
	stand_button.pressed.connect(func() -> void: action_selected.emit("stand_up"))
	add_child(stand_button)
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	_build_ability_slots()
	_build_passives()
	for index: int in range(CombatActionRules.GROUPS.size()):
		var panel: PanelContainer = PanelContainer.new()
		panel.theme_type_variation = &"HudPanel"
		action_bar.add_child(panel)
		_containers.append(panel)
		# 컨테이너마다 한 줄이다. 버튼이 줄을 넘치면 줄바꿈하지 않고 칸 폭을 줄인다(#554, 옛 줄바꿈은 #438).
		var row: HBoxContainer = HBoxContainer.new()
		# Galmuri11 제목이 대체 글꼴보다 넓어, 제목과 버튼 사이를 1로 줄여 한 줄에 8칸(최소 폭 28)이 들어가게 한다.
		row.add_theme_constant_override("separation", TITLE_GAP)
		panel.add_child(row)
		var title: Label = Label.new()
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.add_theme_color_override("font_color", RESOURCE_COLORS[index])
		# 제목 폭을 맞춰 세 줄의 첫 버튼을 같은 세로선에 둔다.
		title.custom_minimum_size.x = 65
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(title)
		_titles.append(title)
		var buttons: HBoxContainer = HBoxContainer.new()
		buttons.add_theme_constant_override("separation", SLOT_GAP)
		buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 버튼이 없는 줄(궁수의 반응 칸)도 다른 줄과 같은 높이를 둔다.
		buttons.custom_minimum_size.y = SLOT_HEIGHT
		row.add_child(buttons)
		for action: String in CombatActionRules.GROUPS[index]:
			var button: Button = HoverTooltip.HoverButton.new()
			# 아이콘 오른쪽에 비용 마크 자리를 남긴다. 높이는 그림을 줄이기 전(#362)의 입력 영역이다.
			button.custom_minimum_size = Vector2(SLOT_FULL, SLOT_HEIGHT)
			button.icon = CombatActionRules.icon_of(action)
			button.material = preload("res://scenes/combat/art/pixel_art.tres")
			button.add_theme_constant_override("icon_max_width", CombatActionRules.ICON_SIZE)
			# 곱셈 색은 채도를 빼지 못해 어둡게 눌러 회색 배경에 묻는다. 반투명으로 하면 윤곽이 배경에 묻혀 불투명으로 둔다(#517).
			button.add_theme_color_override("icon_disabled_color", Color("8a939b"))
			button.accessibility_name = CombatActionRules.NAMES[action]
			# 반응은 표시용이다. 자기 턴의 입력에는 연결하지 않는다.
			if index != 2:
				button.pressed.connect(func() -> void: action_selected.emit(action))
			buttons.add_child(button)
			_tooltip.attach(button)
			_actions[action] = button
			button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			# 비용 기호는 칸 오른쪽 아래에 기호마다 제 자원 색의 글자로 선다. 오른쪽 위는 횟수 배지 자리다(#517).
			var cost: HBoxContainer = HBoxContainer.new()
			cost.add_theme_constant_override("separation", 1)
			cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cost.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			cost.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			cost.grow_vertical = Control.GROW_DIRECTION_BEGIN
			cost.offset_left = -3
			cost.offset_right = -3
			cost.offset_top = -2
			cost.offset_bottom = -2
			for mark: int in CombatActionRules.cost_marks(action):
				var symbol: Label = Label.new()
				symbol.text = COST_SYMBOLS[mark]
				symbol.add_theme_font_size_override("font_size", 10)
				symbol.add_theme_color_override("font_color", RESOURCE_COLORS[mark])
				# 청록 면에서 보라 ◆의 명암비가 낮아 어두운 외곽선으로 가장자리를 세운다.
				symbol.add_theme_color_override("font_outline_color", COST_OUTLINE_COLOR)
				symbol.add_theme_constant_override("outline_size", 2)
				symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cost.add_child(symbol)
			button.add_child(cost)
			_costs[action] = cost
			var badge: Label = Label.new()
			badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			badge.position = Vector2(-12, -8)
			badge.custom_minimum_size.x = 12
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge.add_theme_font_size_override("font_size", 8)
			badge.add_theme_color_override("font_color", Color("ffffff"))
			var badge_style: StyleBoxFlat = _button_style(Color("485568"))
			badge_style.content_margin_left = 1
			badge_style.content_margin_right = 1
			badge_style.content_margin_top = 0
			badge_style.content_margin_bottom = 0
			badge.add_theme_stylebox_override("normal", badge_style)
			badge.reset_size()
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(badge)
			_badges[action] = badge
	add_child(reaction_dialog)
	reaction_dialog.theme = UI_THEME
	reaction_dialog.add_child(SpaceBlocker.new())
	reaction_dialog.title = tr("반응")
	reaction_dialog.dialog_autowrap = true
	reaction_dialog.dialog_hide_on_ok = false
	reaction_dialog.confirmed.connect(_finish_reaction.bind(true))
	reaction_dialog.canceled.connect(_finish_reaction.bind(false))
	_build_reflex_banner()


## 반사신경 발동 시 맵 클릭을 막지 않는 비모달 안내 배너(#824).
func _build_reflex_banner() -> void:
	reflex_banner.name = "ReflexBanner"
	reflex_banner.theme_type_variation = &"HudPanel"
	reflex_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	reflex_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	reflex_banner.offset_top = 26.0
	reflex_banner.visible = false
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	reflex_banner.add_child(row)
	var text_box: VBoxContainer = VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 1)
	row.add_child(text_box)
	_reflex_prompt_label.name = "Prompt"
	_reflex_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(_reflex_prompt_label)
	var hint: Label = Label.new()
	hint.name = "Hint"
	hint.text = tr("이동할 칸을 클릭하거나 Esc로 넘깁니다.")
	hint.add_theme_color_override("font_color", Color("c5b29f"))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(hint)
	reflex_skip_button.name = "SkipReflex"
	reflex_skip_button.text = tr("넘기기")
	reflex_skip_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reflex_skip_button.pressed.connect(_finish_reaction.bind(false))
	row.add_child(reflex_skip_button)
	add_child(reflex_banner)


## 유닛 패널의 2열 3줄 능력치 칸 6개를 만든다(#795, #824).
func _build_ability_slots() -> void:
	for index: int in range(CombatUnit.ABILITY_IDS.size()):
		var slot: AbilitySlot = AbilitySlot.new(index as CombatUnit.Ability)
		ability_grid.add_child(slot)
		_tooltip.attach(slot)
		_ability_slots.append(slot)


## 컨테이너 묶음(Groups)을 가로 줄로 감싸고 그 왼쪽 끝에 패시브 칸을 둔다. 버튼에는 비용 기호와 횟수 배지가 없다.
func _build_passives() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	$Skills.add_child(row)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	row.add_child(column)
	action_bar.reparent(row)
	action_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for passive: String in CombatActionRules.PASSIVES:
		var button: Button = HoverTooltip.HoverButton.new()
		button.custom_minimum_size = Vector2(22, 34)
		# 아이콘이 없으면 이름 첫 글자를 보인다.
		button.icon = CombatActionRules.passive_icon_of(passive)
		if button.icon == null:
			button.text = CombatActionRules.PASSIVE_NAMES[passive].left(1)
			button.add_theme_font_size_override("font_size", 12)
		else:
			button.material = preload("res://scenes/combat/art/pixel_art.tres")
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.add_theme_constant_override("icon_max_width", CombatActionRules.PASSIVE_ICON_SIZE)
			# 조건 미충족(무빙샷)도 어둡게 하지 않는다. 기본 비활성 아이콘 색은 반투명이다.
			button.add_theme_color_override("icon_disabled_color", Color.WHITE)
		button.focus_mode = Control.FOCUS_NONE
		button.accessibility_name = CombatActionRules.PASSIVE_NAMES[passive]
		button.tooltip_text = CombatActionRules.PASSIVE_NAMES[passive] + "\n" + CombatActionRules.PASSIVE_EFFECTS[passive]
		# 무빙샷은 도약할 수 있는 동안 눌러 도약 선택으로 돌아간다(#528). 다른 패시브는 표시용이다.
		if passive == "moving_shot":
			button.pressed.connect(func() -> void: action_selected.emit("moving_shot"))
		column.add_child(button)
		_tooltip.attach(button)
		_passives[passive] = button
		# 켜짐 표시는 버튼 아래쪽 작은 점이다. 오른쪽 위는 횟수 배지 자리라 비운다.
		var dot: Label = Label.new()
		dot.text = "●"
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_font_size_override("font_size", 6)
		dot.add_theme_color_override("font_color", Color("f4ead1"))
		button.add_child(dot)
		dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		dot.position.y -= 2
		_passive_dots[passive] = dot


## 패시브 칸을 갱신한다. 팔랑크스는 아군이 인접해 실제로 적용되는 동안만 강조한다. 괴력의 사내는 상태가 없어 평범한 모습이다.
func _refresh_passives(shown: CombatUnit) -> void:
	for passive: String in CombatActionRules.PASSIVES:
		var button: Button = _passives[passive]
		button.visible = shown != null and CombatActionRules.belongs_to(shown, passive)
		if not button.visible:
			continue
		var on: bool = (passive == "phalanx" and grid != null and grid.phalanx_bonus(shown) > 0
			or passive == "moving_shot" and shown.moving_shot_ready)
		button.disabled = passive == "moving_shot" and not on
		var style: StyleBoxFlat = _button_style(Color("3b4f63") if on else Color("293541"), Color("f4ead1") if on else Color("61717e"))
		# 칸 폭 22 안에 16 논리px 아이콘이 들어가도록 좌우 여백을 3으로 줄인다(#517).
		style.content_margin_left = 3
		style.content_margin_right = 3
		if on:
			style.set_border_width_all(2)
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(state, style)
		# 꺼짐·조건 미충족은 어둡게 하지 않는다. 회색은 사용 불가의 뜻이라 글자색은 켜짐과 같다.
		button.add_theme_color_override("font_color", Color.WHITE)
		_passive_dots[passive].visible = on


## index번째 스킬 줄의 버튼들이 쓸 수 있는 폭. 넘친 내용이 키운 크기를 읽지 않고 장면이 정한 패널 폭에서 센다.
func _slot_room(index: int) -> float:
	var skills: Control = $Skills
	var inner: float = skills.offset_right - skills.offset_left - skills.get_theme_stylebox("panel").get_minimum_size().x
	var row: float = _containers[index].get_theme_stylebox("panel").get_minimum_size().x
	return inner - PASSIVE_COLUMN - row - _titles[index].get_combined_minimum_size().x - TITLE_GAP


func refresh_actions(actions: CombatActions, selected: String, last_ally: CombatUnit) -> void:
	var actor: CombatUnit = actions.turns.current_unit
	var shown: CombatUnit = actor if actor != null and actor.is_ally else last_ally
	var ally_turn: bool = actor != null and actor.is_ally
	var locked: bool = actions.busy or actions.is_over()
	var symbols: Array[String] = ["●", "▲", "◆"]
	var empty_symbols: Array[String] = ["○", "△", "◇"]
	var names: Array[String] = [tr("행동"), tr("보조 행동"), tr("반응")]
	_action_slots.clear()
	_refresh_passives(shown)
	stand_button.visible = ally_turn and actor.fallen and not locked
	if stand_button.visible:
		var cost: int = CombatActionRules.standing_cost(actor.get_movement())
		stand_button.text = tr("일어나기 · 이동력 %d") % cost
		stand_button.disabled = actor.movement_left < cost
	for index: int in range(_containers.size()):
		# 궁수의 반응 칸은 반사신경 자리라 비어 있어도 보인다(#528).
		_containers[index].visible = shown != null
		if shown == null:
			continue
		var amounts: Array[int] = [shown.action_left, shown.bonus_action_left, shown.reaction_left]
		var capacities: Array[int] = [shown.action_capacity, shown.bonus_action_capacity, shown.reaction_capacity]
		var remaining: int = clampi(amounts[index], 0, capacities[index])
		_titles[index].text = "%s %s" % [names[index],
			symbols[index].repeat(remaining) + empty_symbols[index].repeat(capacities[index] - remaining)]
		_titles[index].modulate = Color.WHITE if ally_turn else Color("888888")
		var visible_count: int = 0
		for action: String in CombatActionRules.GROUPS[index]:
			# 물약류는 가진 종류만 보인다. 없는 종류는 꺼진 버튼이 아니라 숨긴다(#576).
			_actions[action].visible = (CombatActionRules.belongs_to(shown, action)
				and not (action in CombatActionRules.POTION_ITEM and CombatActionRules.uses_left(shown, action) == 0))
			visible_count += int(_actions[action].visible)
		# 줄은 늘 한 줄이다. 넘치면 칸 폭을 줄이고 아이콘 크기는 그대로 둔다(#554).
		var width: int = slot_width(_slot_room(index), visible_count)
		var narrowed: bool = width < SLOT_FULL
		for action: String in CombatActionRules.GROUPS[index]:
			var button: Button = _actions[action]
			button.custom_minimum_size.x = width
			if button.visible and _containers[index].visible:
				_action_slots.append(button)
			button.tooltip_text = CombatActionRules.NAMES[action] + "\n" + action_details(actions, shown, action)
			button.set_meta(&"tooltip_bbcode", action_tooltip(actions, shown, action))
			var active: bool = ally_turn and not locked and actions.can_use(actor, action)
			# 반응은 횟수나 자원을 다 써도 자기 턴에는 켜진 표시로 남는다.
			button.disabled = (not ally_turn or locked) if index == 2 else not active
			var color: Color = SLOT_FACE_ACTIVE if not button.disabled else SLOT_FACE_IDLE
			var border: Color = Color("f4cf69") if selected == action and active else Color("61717e")
			# 줄인 칸은 좌우 여백도 줄여 아이콘 24가 칸 폭 28에 들어간다.
			var margin: int = NARROW_MARGIN if narrowed else 4
			for state: String in ["normal", "hover", "pressed", "disabled"]:
				button.add_theme_stylebox_override(state, _button_style(color, border, margin))
			# 키보드·컨트롤러 포커스는 배경 위에 흰 테두리만 겹친다.
			var focus: StyleBoxFlat = _button_style(color, FOCUS_COLOR, margin)
			focus.draw_center = false
			button.add_theme_stylebox_override("focus", focus)
			var uses: int = CombatActionRules.uses_left(shown, action)
			_badges[action].visible = uses >= 0
			_badges[action].text = str(uses)
			_badges[action].reset_size()
			_costs[action].reset_size()
			_badges[action].modulate = Color.WHITE if ally_turn else Color("888888")
			_costs[action].modulate = Color.WHITE if not button.disabled else Color("666666")
			# 줄인 칸에서는 줄 제목에 이미 있는 하나뿐인 비용 기호를 숨긴다. 복합 비용은 그대로다.
			_costs[action].visible = not (narrowed and _costs[action].get_child_count() == 1)
	# 좌우 방향키·D-pad는 스킬 바 안에서만 옮긴다. 스틱을 누르고 있어도 끝에서 멈춘다.
	for index: int in range(_action_slots.size()):
		var button: Button = _action_slots[index]
		button.focus_neighbor_left = button.get_path_to(_action_slots[maxi(index - 1, 0)])
		button.focus_neighbor_right = button.get_path_to(_action_slots[mini(index + 1, _action_slots.size() - 1)])
	end_button.disabled = not ally_turn or locked
	for button: Button in _portraits.values():
		button.disabled = button.disabled or locked


## 스킬 바의 slot번째 버튼에 포커스를 준다. 비활성 버튼은 설명만 보이고 누르지 않는다.
func focus_action_slot(slot: int, press: bool) -> void:
	if slot >= _action_slots.size():
		return
	var button: Button = _action_slots[slot]
	button.grab_focus()
	if press and not button.disabled:
		button.pressed.emit()


## 호버 설명의 이름 뒤 세 부분. 효과, 쓸 수 없을 때만 그 이유, 사거리~횟수 세부 순서다(#620).
func _detail_parts(actions: CombatActions, actor: CombatUnit, action: String) -> Array[String]:
	var reason: String = actions.unavailable_reason(actor, action)
	return [CombatActionRules.effect(actor, action),
		"" if reason.is_empty() else tr("지금 사용 불가: %s") % reason,
		CombatActionRules.details(actor, action, actions.units)]


func action_details(actions: CombatActions, actor: CombatUnit, action: String) -> String:
	if actor == null:
		return ""
	var lines: Array[String] = []
	for part: String in _detail_parts(actions, actor, action):
		if not part.is_empty():
			lines.append(part)
	return "\n".join(lines)


## action_details에 이름을 붙이고 줄 역할별로 칠한 BBCode. 태그를 뺀 글은 이름 + action_details와 같다.
func action_tooltip(actions: CombatActions, actor: CombatUnit, action: String) -> String:
	if actor == null:
		return ""
	var parts: Array[String] = _detail_parts(actions, actor, action)
	var colors: Array[Color] = [HoverTooltip.BODY_COLOR, CombatActionRules.BAD_COLOR, HoverTooltip.DETAIL_COLOR]
	var lines: Array[String] = [HoverTooltip.paint(CombatActionRules.NAMES[action], HoverTooltip.TITLE_COLOR)]
	for index: int in range(parts.size()):
		if not parts[index].is_empty():
			lines.append(HoverTooltip.paint(parts[index], colors[index]))
	return "\n".join(lines)


func add_log(message: String) -> void:
	_log_lines.append(CombatUnit.decorate_abilities(message.replace("\n", " ").replace("[", "[lb]")))
	while _log_lines.size() > 3:
		_log_lines.pop_front()
	message_label.text = "\n".join(_log_lines)


func show_reaction(kind: String, prompt: String, _cells: Array[Vector2i] = []) -> void:
	if kind == "reflex":
		hide_reaction()
		_reflex_prompt_label.text = prompt
		reflex_banner.visible = true
		return
	reflex_banner.visible = false
	reaction_dialog.dialog_text = prompt
	reaction_dialog.get_ok_button().text = tr("반격") if kind == "counter" else tr("공격")
	reaction_dialog.get_ok_button().visible = true
	reaction_dialog.get_cancel_button().text = tr("넘기기")
	reaction_dialog.exclusive = true
	reaction_dialog.popup_centered(Vector2i(360, 110))


func hide_reaction() -> void:
	# Godot 4.7.2 접근성은 창 제거 중에도 exclusive child에 포커스를 전달한다.
	reaction_dialog.exclusive = false
	reaction_dialog.hide()
	reflex_banner.visible = false


func _hide_reaction() -> void:
	hide_reaction()


func _finish_reaction(use_reaction: bool) -> void:
	hide_reaction()
	reaction_selected.emit(use_reaction)


func begin_stage(act: int, stage: int) -> void:
	_order_revision += 1
	if _order_tween != null:
		_order_tween.kill()
	_order_moves.clear()
	_shown_order.clear()
	progress_label.text = tr("%d막 · %d스테이지") % [act, stage]
	$Result.hide()
	hide_reaction()
	_log_lines.clear()
	message_label.text = ""
	restart_button.show()


func show_result(victory: bool, graduated: bool = false, locked: bool = false) -> void:
	hide_reaction()
	var complete: bool = victory and graduated
	result_label.text = tr("3막 졸업") if complete else tr("승리") if victory else tr("패배")
	restart_button.text = tr("타이틀로") if complete else tr("보상 확인") if victory else tr("이 막 다시 시작")
	$Result.show()
	restart_button.grab_focus()
	restart_button.disabled = locked


func hide_result() -> void:
	$Result.hide()


func show_outcome(victory: bool) -> void:
	round_label.text = tr("승리") if victory else tr("패배")


## 표식·밀치기처럼 명중률 대신 보일 대상 안내.
func show_target_note(text: String) -> void:
	preview_label.text = text


func show_move_mode(showing_move: bool) -> void:
	preview_label.visible = not showing_move


func show_cover_reason(reason: String, screen_position: Vector2 = Vector2.INF) -> void:
	if _cover_tooltip == null or reason.is_empty():
		hide_cover_reason()
		return
	_cover_tooltip_label.text = reason
	_cover_tooltip.reset_size()
	var tip_size: Vector2 = _cover_tooltip.get_combined_minimum_size()
	var view_size: Vector2 = get_viewport_rect().size
	var pos: Vector2 = screen_position + Vector2(10, -tip_size.y - 6) if screen_position != Vector2.INF else Vector2(8, 8)
	pos.x = clampf(pos.x, 4.0, maxf(4.0, view_size.x - tip_size.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, view_size.y - tip_size.y - 4.0))
	_cover_tooltip.position = pos
	_cover_tooltip.visible = true


func hide_cover_reason() -> void:
	if _cover_tooltip != null:
		_cover_tooltip.visible = false


func refresh(turns: CombatTurns, has_available_action: bool) -> void:
	preview_label.text = ""
	if _shown_order != turns.ordered_units:
		for unit: CombatUnit in _shown_order:
			if unit not in turns.ordered_units or (_order_tween != null and _order_tween.is_running()):
				prepare_order_rotation(_shown_order)
				break
		_build_portraits(turns)
	var current: CombatUnit = turns.current_unit
	end_button.disabled = current == null
	if current == null:
		round_label.text = tr("턴 종료")
		unit_label.text = tr("유닛 없음")
		vitals_label.text = ""
		ability_grid.visible = false
		resource_label.text = ""
		_clear_status_row()
		actor_label.text = ""
		return
	round_label.text = tr("라운드 %d · %s") % [turns.round_number, tr("아군 턴 묶음") if current.is_ally else tr("적 턴 묶음 · Space: 빠르게")]
	actor_label.text = (tr("조작: %s") if current.is_ally else tr("진행: %s")) % current.get_display_name()
	show_unit(current)
	for unit: CombatUnit in _portraits:
		var button: Button = _portraits[unit]
		button.text = _portrait_text(unit)
		if unit.initiative_roll == 0:
			button.tooltip_text = tr("%s: 엄마 거미 바로 앞 순서\n생성한 라운드에는 행동하지 않습니다.") % unit.get_display_name()
		else:
			button.tooltip_text = tr("%s: %s = %d") % [
				unit.get_display_name(), CombatUnit.ability_text(unit, CombatUnit.Ability.AGILITY), unit.get_initiative()]
		# 고철로봇은 켜지기 전부터 과부하 조건·효과와 물 칸 규칙을 읽는다(#503).
		var overload: String = CombatActionRules.overload_text(unit)
		if not overload.is_empty():
			button.tooltip_text += "\n" + overload
		var in_group: bool = unit in turns.get_current_group()
		(button.get_node("PendingTurn") as Control).visible = (
			in_group and not turns.is_turn_started(unit) and not turns.is_turn_finished(unit))
		button.disabled = false
		var color: Color = CombatUnit.ALLY_COLOR if unit.is_ally else CombatUnit.ENEMY_COLOR
		if turns.is_turn_finished(unit):
			color = Color("777777")
		var border: Color = Color.WHITE if in_group else Color("61717e")
		if unit == current:
			border = Color("f4cf69")
		for state: String in ["normal", "disabled", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, _button_style(color.darkened(0.3), border))
	var end_color: Color = DEFAULT_BUTTON_COLOR if has_available_action else END_BUTTON_COLOR
	# 남은 동작이 없으면 테마 버튼 프레임에 강조 색만 입힌다. 있으면 테마 색 그대로다.
	for state: String in ["normal", "hover", "pressed"]:
		var end_style: StyleBoxTexture = UI_THEME.get_stylebox(state, "Button").duplicate() as StyleBoxTexture
		if not has_available_action:
			end_style.modulate_color = end_color.lightened(0.12) if state == "hover" \
				else end_color.darkened(0.12) if state == "pressed" else end_color
		end_button.add_theme_stylebox_override(state, end_style)


## 유닛 패널 상태 줄의 현재 표시 문자열("상태: 없음" 또는 "상태: ...").
func status_text() -> String:
	return _status_display_text


## 유닛 패널 상태 줄에 표시 중인 개별 상태 호버 버튼 목록. 상태가 없으면 비어 있다(#796).
func status_buttons() -> Array[Button]:
	return _status_buttons.duplicate()


func _clear_status_row() -> void:
	for child: Node in status_row.get_children():
		child.free()
	_status_buttons.clear()
	_status_signature.clear()
	_status_display_text = ""


func _periodic_status_entry(unit: CombatUnit, kind_name: String) -> Dictionary:
	var count: int = unit.get_status_count(kind_name)
	if count <= 0:
		return {}
	var indefinite: bool = false
	var max_turns: int = 0
	var save_dc: int = CombatGrounds.POISON_DC
	var dc_found: bool = false
	for effect: CombatUnit.StatusEffect in unit.status_effects:
		if effect.kind != kind_name:
			continue
		if effect.turns_left == 0:
			indefinite = true
		else:
			max_turns = maxi(max_turns, effect.turns_left)
		if kind_name == "poison" and not dc_found and effect.dc > 0:
			save_dc = effect.dc
			dc_found = true
	if kind_name == "burn":
		var label: String = "%s%d" % [tr("화상"), count]
		var heading: String = tr("화상 %d중첩 (최대 %d턴)") % [count, max_turns] if max_turns > 0 else tr("화상 %d중첩") % count
		return {"label": label, "tooltip": heading + "\n" + tr("내 턴 시작마다 중첩당 1d4 피해.\n물 칸에 들어가거나 물 속성에 닿으면 모두 풀립니다.")}
	var label: String = "%s%d" % [tr("독"), count]
	var heading: String
	if indefinite:
		label += "(%s)" % tr("기간 없음")
		heading = tr("독 %d중첩 (기간 없음)") % count
	else:
		heading = tr("독 %d중첩 (최대 %d턴)") % [count, max_turns]
	return {"label": label, "tooltip": heading + "\n" + tr("내 턴 시작마다 중첩당 피해 %d.\n턴 시작 건강 내성(DC %d)에 성공하면 첫 독 중첩 1개가 풀립니다.") % [CombatActionRules.poison_tick_damage, save_dc]}


func _status_entries(unit: CombatUnit, phalanx: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if unit.is_stunned:
		entries.append({
			"label": tr("기절"),
			"tooltip": tr("기절\n행동·이동·반응을 쓸 수 없고 나를 겨눈 공격이 유리합니다.\n시전자의 다음 턴 시작에 풀립니다.")
		})
	if unit.fallen:
		var cost: int = CombatActionRules.standing_cost(unit.get_movement())
		entries.append({
			"label": tr("넘어짐"),
			"tooltip": tr("넘어짐\n행동·보조 행동·반응을 쓸 수 없고 민첩 내성굴림이 불리합니다.\n이동력 %d로 일어서거나 다음 내 턴 시작에 풀립니다.") % cost
		})
	if unit.stealthed:
		entries.append({
			"label": tr("은신"),
			"tooltip": tr("은신\n적이 공격·스킬 대상으로 지정할 수 없습니다. 범위·장판은 맞습니다.\n피해를 주는 공격을 쓰거나 다음 내 턴 시작에 풀립니다.")
		})
	for kind_name: String in ["burn", "poison"]:
		var periodic: Dictionary = _periodic_status_entry(unit, kind_name)
		if not periodic.is_empty():
			entries.append(periodic)
	# 켜지기 전에는 과부하 조건을 보인다(#503). 호버 설명은 기존 overload_text()를 재사용한다(#796).
	var overload: String = CombatActionRules.overload_status(unit)
	if not overload.is_empty():
		var overload_tip: String = CombatActionRules.overload_text(unit)
		if overload_tip.is_empty():
			overload_tip = tr("과부하\n턴마다 행동 2.\n턴 시작에 자기 피해 %d.") % CombatActionRules.OVERLOAD_SELF_DAMAGE
		entries.append({"label": overload, "tooltip": overload_tip})
	if unit.is_boss():
		entries.append({
			"label": tr("기절 면역"),
			"tooltip": tr("기절 면역\n기절 상태에 걸리지 않습니다.")
		})
	if unit.pull_cooldown > 0:
		entries.append({
			"label": tr("만능팔 대기"),
			"tooltip": tr("만능팔 대기\n대기 중이라 만능팔을 쓸 수 없습니다.\n다음 내 턴 시작마다 대기가 줄어듭니다.")
		})
	if unit.aegisal_left > 0:
		entries.append({
			"label": tr("애기살 %d발") % unit.aegisal_left,
			"tooltip": tr("애기살 %d발\n기본 공격마다 1발을 쓰고 피해 주사위를 2번 굴려 높은 값을 씁니다.\n전투가 끝나면 사라집니다.") % unit.aegisal_left
		})
	if unit.disengaged:
		entries.append({
			"label": tr("기회 공격 면제"),
			"tooltip": tr("기회 공격 면제\n이번 턴의 남은 이동에서 기회 공격을 받지 않습니다.\n이번 턴 묶음이 끝나면 풀립니다.")
		})
	if unit.shield_points > 0:
		entries.append({
			"label": tr("방어막 %d (%d턴)") % [unit.shield_points, unit.shield_turns],
			"tooltip": tr("방어막 %d (%d턴)\nHP보다 먼저 모든 피해를 최대 %d까지 대신 받습니다.\n피해를 모두 흡수하거나 %d턴이 지나면 사라집니다.") % [
				unit.shield_points, unit.shield_turns, unit.shield_points, unit.shield_turns]
		})
	if unit.battle_cry_turns > 0:
		entries.append({
			"label": tr("전투의 함성 명중 +%d (%d턴)") % [unit.battle_cry_bonus, unit.battle_cry_turns],
			"tooltip": tr("전투의 함성 명중 +%d (%d턴)\n모든 명중굴림에 +%d를 더합니다.\n%d턴이 지나면 사라집니다.") % [
				unit.battle_cry_bonus, unit.battle_cry_turns, unit.battle_cry_bonus, unit.battle_cry_turns]
		})
	if unit.distracted_turns > 0:
		entries.append({
			"label": tr("산만함 %d턴") % unit.distracted_turns,
			"tooltip": tr("산만함 %d턴\n내성굴림·명중굴림 불리.\n시전자 턴 시작마다 1턴 줄어듭니다.") % unit.distracted_turns
		})
	if phalanx > 0:
		var phalanx_detail: String = tr("인접한 아군이 있어 AC +%d. 중첩 없음.") % phalanx \
			if (CombatActionRules.belongs_to(unit, "phalanx") and not unit.is_stunned) \
			else tr("인접한 전사 효과로 AC +%d. 중첩 없음.") % phalanx
		entries.append({
			"label": tr("팔랑크스 AC +%d") % phalanx,
			"tooltip": tr("팔랑크스 AC +%d\n%s\n인접에서 벗어나면 바로 사라집니다.") % [phalanx, phalanx_detail]
		})
	return entries


func _status_button_style(color: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = _button_style(color, border, 3)
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style


func _make_status_button(label: String, tooltip: String) -> Button:
	var button: Button = HoverTooltip.HoverButton.new()
	button.text = label
	button.tooltip_text = tooltip
	button.accessibility_name = label
	button.focus_mode = Control.FOCUS_ALL
	var normal: StyleBoxFlat = _status_button_style(Color("293541"), Color("61717e"))
	var hover: StyleBoxFlat = _status_button_style(SLOT_FACE_ACTIVE, FOCUS_COLOR)
	var focus: StyleBoxFlat = _status_button_style(Color("293541"), FOCUS_COLOR)
	focus.draw_center = false
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", focus)
	var colored: String = CombatActionRules.colorize(label)
	if colored != label.replace("[", "[lb]"):
		# 수치 가감(+/-)이 있는 상태 항목은 초록·빨강 색(#457)을 유지하면서 버튼 크기는 text로 맞춘다.
		var transparent: Color = Color(0.0, 0.0, 0.0, 0.0)
		for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(color_name, transparent)
		var rich: RichTextLabel = RichTextLabel.new()
		rich.name = "ColoredLabel"
		rich.bbcode_enabled = true
		rich.scroll_active = false
		rich.autowrap_mode = TextServer.AUTOWRAP_OFF
		rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rich.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rich.set_anchors_preset(Control.PRESET_FULL_RECT)
		rich.offset_left = 3
		rich.offset_right = -3
		rich.text = colored
		button.add_child(rich)
	_tooltip.attach(button)
	return button


func _rebuild_status_row(entries: Array[Dictionary]) -> void:
	var labels: Array[String] = []
	var signature: Array[PackedStringArray] = []
	for entry: Dictionary in entries:
		var label: String = entry["label"] as String
		var tooltip: String = entry["tooltip"] as String
		labels.append(label)
		signature.append(PackedStringArray([label, tooltip]))
	_status_display_text = tr("상태: %s") % (tr("없음") if labels.is_empty() else ", ".join(labels))
	if status_row.get_child_count() > 0 and signature == _status_signature:
		return
	for child: Node in status_row.get_children():
		child.free()
	_status_buttons.clear()
	_status_signature = signature
	var prefix: Label = Label.new()
	prefix.text = tr("상태:")
	prefix.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.add_child(prefix)
	if entries.is_empty():
		var none_label: Label = Label.new()
		none_label.text = tr("없음")
		none_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		none_label.focus_mode = Control.FOCUS_NONE
		status_row.add_child(none_label)
		return
	for entry: Dictionary in entries:
		var button: Button = _make_status_button(entry["label"] as String, entry["tooltip"] as String)
		status_row.add_child(button)
		_status_buttons.append(button)


func show_unit(unit: CombatUnit) -> void:
	unit_label.text = unit.get_display_name()
	health_bar.max_value = unit.get_max_hit_points()
	health_bar.value = unit.hit_points
	var phalanx: int = grid.phalanx_bonus(unit) if grid != null else 0
	vitals_label.text = "[img=12x12]%s[/img] %s   [img=12x12]%s[/img] %s" % [
		CombatUnit.stat_icon_path("hp"),
		tr("HP %d / %d") % [unit.hit_points, unit.get_max_hit_points()],
		CombatUnit.stat_icon_path("ac"),
		tr("AC %d") % (unit.get_armor_class() + phalanx),
	]
	ability_grid.visible = true
	for index: int in range(_ability_slots.size()):
		var ability: CombatUnit.Ability = index as CombatUnit.Ability
		var slot: AbilitySlot = _ability_slots[index]
		var die: String = CombatUnit.ability_die_text(unit, ability)
		slot.die_label.text = "[color=#%s]%s[/color] %s" % [
			CombatUnit.ability_text_color(ability).to_html(false),
			CombatUnit.ability_name(ability),
			CombatActionRules.colorize(die),
		]
		slot.tooltip_text = "%s · %s" % [CombatUnit.ability_name(ability), die]
		slot.accessibility_name = CombatUnit.ability_text(unit, ability)
	resource_label.text = "[img=12x12]%s[/img] %s · [img=12x12]%s[/img] %s · [img=12x12]%s[/img] %s" % [
		CombatUnit.stat_icon_path("attack"),
		CombatActionRules.colorize(tr("공격 %+d") % unit.get_attack_bonus()),
		CombatUnit.stat_icon_path("range"),
		tr("사거리 %d칸") % unit.get_attack_range(),
		CombatUnit.stat_icon_path("movement"),
		tr("이동 %d/%d") % [unit.movement_left, unit.get_movement()],
	]
	_rebuild_status_row(_status_entries(unit, phalanx))


func show_attack_preview(target: CombatUnit, preview: CombatChecks.AttackPreview) -> void:
	show_unit(target)
	var mode_text: String = tr("일반")
	if preview.mode == CombatChecks.RollMode.ADVANTAGE:
		mode_text = tr("유리")
	elif preview.mode == CombatChecks.RollMode.DISADVANTAGE:
		mode_text = tr("불리")
	elif preview.reasons.size() >= 2:
		mode_text = tr("유리/불리 상쇄")
	preview_label.text = tr("명중률 %.1f%% · %s") % [preview.chance * 100.0, mode_text]
	if not preview.valid_target:
		preview_label.text += "\n" + tr("공격할 수 없는 대상")
	elif not preview.blocked_reason.is_empty():
		preview_label.text += "\n" + preview.blocked_reason
	elif not preview.in_range:
		preview_label.text += "\n" + tr("사거리 밖")
	elif not preview.reasons.is_empty():
		preview_label.text += "\n" + ", ".join(preview.reasons)


func prepare_order_rotation(units: Array[CombatUnit]) -> void:
	for unit: CombatUnit in units:
		if unit in _portraits and unit not in _order_moves:
			_order_moves[unit] = _portraits[unit].global_position


func _build_portraits(turns: CombatTurns) -> void:
	_order_revision += 1
	if _order_tween != null:
		_order_tween.kill()
	for child: Node in order_bar.get_children():
		child.free()
	# 커서 밑 초상 버튼을 free하면 mouse_exited가 오지 않는다. 낡은 호버를 풀어 위협 범위가 남지 않게 한다(#556).
	unit_hovered.emit(null)
	_portraits.clear()
	_shown_order = turns.ordered_units.duplicate()
	for group: Array in turns.get_turn_groups():
		var panel: PanelContainer = PanelContainer.new()
		# 묶음 배경만 낮춰 결과·정비 화면의 기존 표시 순서를 유지한다.
		panel.z_index = -1
		# 이동 중 초상을 덮는 다른 묶음의 빈 배경은 클릭을 받지 않는다.
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.theme_type_variation = &"HudPanel"
		var box: HBoxContainer = HBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 3)
		panel.add_child(box)
		order_bar.add_child(panel)
		for unit: CombatUnit in group:
			var button: Button = HoverTooltip.HoverButton.new()
			# 이동 중에도 초상이 다른 묶음의 배경 위에 보이게 한다.
			button.z_index = 1
			button.custom_minimum_size = Vector2(40, 43)
			button.icon = load("res://scenes/combat/art/units/%s/idle/%s/000.png" % [
				unit.get_art_id(), "right" if unit.is_ally else "left"]) as Texture2D
			button.material = preload("res://scenes/combat/art/pixel_art.tres")
			button.add_theme_constant_override("icon_max_width", 32)
			button.add_theme_color_override("font_disabled_color", Color("b5bdc4"))
			button.pressed.connect(func() -> void: unit_selected.emit(unit))
			button.mouse_entered.connect(func() -> void: unit_hovered.emit(unit))
			button.mouse_exited.connect(func() -> void: unit_hovered.emit(null))
			box.add_child(button)
			var pending: Label = Label.new()
			pending.name = "PendingTurn"
			pending.text = "⌛"
			pending.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(pending)
			pending.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			pending.offset_left = -15
			pending.offset_top = -16
			pending.offset_right = -1
			pending.offset_bottom = -1
			_tooltip.attach(button)
			_portraits[unit] = button
	if not _order_moves.is_empty():
		var positions: Dictionary[CombatUnit, Vector2] = _order_moves.duplicate()
		_animate_order_rotation(positions, _order_revision)


func _animate_order_rotation(positions: Dictionary[CombatUnit, Vector2], revision: int) -> void:
	await get_tree().process_frame
	if not is_inside_tree() or revision != _order_revision:
		return
	_order_moves.clear()
	_order_tween = create_tween().set_parallel(true)
	for unit: CombatUnit in positions:
		if unit not in _portraits:
			continue
		var button: Button = _portraits[unit]
		var destination: Vector2 = button.position
		button.position += positions[unit] - button.global_position
		_order_tween.tween_property(button, "position", destination, 0.25).set_trans(
			Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 턴 순서 초상 카드의 두 줄 이름. 적은 보스('고철로봇\n3000')처럼 구분자에서 두 줄로 나눈다(#743).
func _portrait_text(unit: CombatUnit) -> String:
	if unit.is_ally:
		return "%s\n%s" % [tr("아군"), tr("전사") if unit.kind == CombatUnit.Kind.WARRIOR else tr("궁수")]
	var display_name: String = unit.get_display_name()
	for separator: String in ["-", " "]:
		var split: int = display_name.find(separator)
		if split > 0 and split < display_name.length() - 1:
			return display_name.left(split) + "\n" + display_name.substr(split + 1)
	return "%s\n%s" % [tr("적"), display_name]


func _button_style(color: Color, border: Color = Color("61717e"), margin: int = 4) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = margin
	style.content_margin_right = margin
	return style
