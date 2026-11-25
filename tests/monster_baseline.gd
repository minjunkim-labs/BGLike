extends RefCounted
## 몬스터 수치 튜닝(2026-11, #702) 이전의 몬스터 수치와 독 틱 피해.
## 기존 회귀 검사는 판정·AI·장판 규칙을 검증하려고 이 값을 가정한다. `apply()`로 실제 정의를 이 값으로 되돌린 뒤 검사한다.
## 지금 쓰는 실제 값은 tests/combat_monster_stats_test.gd가 따로 검사한다.

static func _novice_barbarian() -> Dictionary:
	return {
	"abilities": [10, 6, 4, 4, 4, 4], "defense_bonus": 0,
	"name": TranslationServer.tr("풋내기 야만인"), "max_hit_points": 12,
	"attack_bonus": 3, "damage_bonus": 1, "attack_range": 1,
	"actions": ["attack", "second_wind"]
}


static func _novice_archer() -> Dictionary:
	return {
	"abilities": [4, 10, 4, 4, 4, 4], "defense_bonus": 0,
	"name": TranslationServer.tr("풋내기 궁수"), "max_hit_points": 14,
	"attack_bonus": 0, "damage_bonus": 1, "attack_range": 8,
	"actions": ["attack", "disengage"]
}


static func _scrap_robot_1000() -> Dictionary:
	return {
	"abilities": [12, 4, 8, 4, 12, 4], "defense_bonus": 2,
	"name": TranslationServer.tr("고철로봇-1000"), "boss": true, "max_hit_points": 40,
	"movement": 6,
	"attack_bonus": 3, "damage_bonus": 2, "attack_range": 1,
	"actions": ["attack"]
}


static func _scrap_robot_2000() -> Dictionary:
	return {
	"abilities": [12, 4, 8, 4, 12, 4], "defense_bonus": 3,
	"name": TranslationServer.tr("고철로봇-2000"), "boss": true, "max_hit_points": 45,
	"movement": 6,
	"attack_bonus": 3, "damage_bonus": 2, "attack_range": 1,
	"actions": ["attack", "pull"]
}


static func _scrap_robot_3000() -> Dictionary:
	return {
	"abilities": [12, 4, 8, 4, 12, 4], "defense_bonus": 4,
	"name": TranslationServer.tr("고철로봇-3000"), "boss": true, "max_hit_points": 50,
	"movement": 6,
	"attack_bonus": 3, "damage_bonus": 2, "attack_range": 1,
	"actions": ["attack", "pull", "spin"]
}


static func _spiderling() -> Dictionary:
	return {
	"abilities": [4, 8, 4, 4, 4, 4], "defense_bonus": 0,
	"name": TranslationServer.tr("새끼 거미"), "max_hit_points": 1, "poison_immune": true,
	"attack_bonus": 3, "damage_bonus": 1, "attack_range": 1,
	"actions": ["attack"]
}


static func _mother_spider() -> Dictionary:
	return {
	"abilities": [8, 6, 4, 4, 6, 8], "defense_bonus": 1,
	"name": TranslationServer.tr("엄마 거미"), "max_hit_points": 20, "poison_immune": true,
	"movement": 6,
	"attack_bonus": 3, "damage_bonus": 2, "attack_range": 1,
	"actions": ["attack", "spawn"]
}


static func _fog_spider() -> Dictionary:
	return {
	"abilities": [6, 6, 4, 4, 4, 8], "defense_bonus": 0,
	"name": TranslationServer.tr("독안개 거미"), "max_hit_points": 12, "poison_immune": true,
	"movement": 6,
	"attack_bonus": 3, "damage_bonus": 1, "attack_range": 1,
	"actions": ["attack", "fog"]
}


static func apply() -> void:
	CombatEnemyDefinitions.NOVICE_BARBARIAN.clear()
	CombatEnemyDefinitions.NOVICE_BARBARIAN.merge(_novice_barbarian())
	CombatEnemyDefinitions.NOVICE_ARCHER.clear()
	CombatEnemyDefinitions.NOVICE_ARCHER.merge(_novice_archer())
	CombatEnemyDefinitions.SCRAP_ROBOT_1000.clear()
	CombatEnemyDefinitions.SCRAP_ROBOT_1000.merge(_scrap_robot_1000())
	CombatEnemyDefinitions.SCRAP_ROBOT_2000.clear()
	CombatEnemyDefinitions.SCRAP_ROBOT_2000.merge(_scrap_robot_2000())
	CombatEnemyDefinitions.SCRAP_ROBOT_3000.clear()
	CombatEnemyDefinitions.SCRAP_ROBOT_3000.merge(_scrap_robot_3000())
	CombatEnemyDefinitions.SPIDERLING.clear()
	CombatEnemyDefinitions.SPIDERLING.merge(_spiderling())
	CombatEnemyDefinitions.MOTHER_SPIDER.clear()
	CombatEnemyDefinitions.MOTHER_SPIDER.merge(_mother_spider())
	CombatEnemyDefinitions.FOG_SPIDER.clear()
	CombatEnemyDefinitions.FOG_SPIDER.merge(_fog_spider())
	CombatActionRules.poison_tick_damage = 1
