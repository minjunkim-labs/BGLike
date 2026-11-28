# 코드·테스트 지도

`scenes/`의 주요 스크립트와 `tests/`의 회귀·QA 스크립트를 기능별로 묶은 빠른 길잡이입니다. 전체 문서 색인은 [docs/README.md](../README.md)에 있습니다.

## `scenes/` 모듈 구조

| 경로 | 클래스 | 맡은 일 |
| --- | --- | --- |
| `scenes/title.gd` | `TitleScreen` | 타이틀 화면, 새 게임·이어하기·테스트 진입 |
| `scenes/title_backdrop.gd` | `TitleBackdrop` | 타이틀 1-1 정지 배경 조합 |
| `scenes/pause_menu.gd` | `PauseMenu` | 전투·정비 중 Esc·Start 일시정지 메뉴 |
| `scenes/settings.gd` | `SettingsScreen` | 음량·창 모드·화면 맞춤 설정 UI |
| `scenes/help.gd` | `HelpScreen` | 주제별 8탭 도움말 화면 |
| `scenes/audio/game_music.gd` | `GameMusic` | 화면별 배경음 재생·전환 유지 |
| `scenes/audio/sound_variants.gd` | `SoundVariants` | 효과음 갈래 묶음·피치 흔들기 |
| `scenes/ui/ui_sounds.gd` | (Autoload `UiSounds`) | 버튼 호버·클릭·취소·사용 불가 UI 소리 |
| `scenes/save/game_save.gd` | `GameSave` | 단일 슬롯 자동 저장(`BGLS`, `FORMAT_VERSION`) |
| `scenes/save/game_settings.gd` | `GameSettings` | `user://settings.cfg` 설정 저장·복원 |
| `scenes/combat/battle.gd` | (장면 루트) | 전투 화면·3막 루프·연출/입력 연결 |
| `scenes/combat/actions.gd` | `CombatActions` | 동작 실행·자원 소비·반응 대기 |
| `scenes/combat/action_rules.gd` | `CombatActionRules` | 스킬·공용 동작 비용·제한·설명 정의 |
| `scenes/combat/turns.gd` | `CombatTurns` | 라운드 이니셔티브·턴 묶음·시계 슬롯 |
| `scenes/combat/grid.gd` | `CombatGrid` | 사각 높이 격자·경로 탐색·사거리·이동 비용 |
| `scenes/combat/map.gd` | `CombatMap` | 바닥 높이 타일·마름모 좌표 변환 |
| `scenes/combat/cover.gd` | `CombatCover` | 3차원 중심 선분 전엄폐 판정 |
| `scenes/combat/checks.gd` | `CombatChecks` | 명중·내성·유리/불리·절대면 판정 |
| `scenes/combat/dice.gd` | `CombatDice` | 주사위 RNG seam |
| `scenes/combat/dice_roll.gd` | `CombatDiceRoll` | 머리 위 굴림 연출 데이터 |
| `scenes/combat/dice_roll_view.gd` | `CombatDiceRollView` | 머리 위 주사위 굴림 UI·연출 |
| `scenes/combat/grounds.gd` | `CombatGrounds` | 불·독안개·기름 장판, 점화·나무 불탐·저장 검증 |
| `scenes/combat/props.gd` | `CombatProps` | 나무 상자·바위 생성·공격·바위 굴리기 |
| `scenes/combat/floor_loot.gd` | `CombatFloorLoot` | 상자 드랍 바닥 아이템·줍기 |
| `scenes/combat/loot.gd` | `CombatLoot` | `item_data.json` 드랍·장착·물약·공용 12칸 가방 |
| `scenes/combat/preparation.gd` | `CombatPreparation` | 승리 뒤 보상·정비 화면 UI |
| `scenes/combat/preparation_state.gd` | `CombatPreparationState` | 보상·정비 도메인 상태·아이템 이동/폐기 |
| `scenes/combat/selection.gd` | `CombatSelection` | 2클릭 선택·취소·확정·미리보기 스냅샷 |
| `scenes/combat/presentation.gd` | `CombatPresentation` | `PRESENTATION_SPEED`·SFX/VFX 라우팅·팝업 배치 |
| `scenes/combat/hit_effects.gd` | `CombatHitEffects` | 타격 섬광·히트스톱·빗나감 잔상·상태 효과 |
| `scenes/combat/combat_sounds.gd` | `CombatSounds` | 전투 사건별 SFX 재생·4배속 간격 억제 |
| `scenes/combat/turn_hud.gd` | `CombatTurnHud` | 전투 HUD·스킬 바·초상·상태 호버 |
| `scenes/combat/turn_order_scroll.gd` | (컨테이너) | 턴 순서 스크롤 영역 입력 필터 |
| `scenes/combat/hover_tooltip.gd` | `HoverTooltip` | 0.5초 지연 마우스·포커스 호버 설명 |
| `scenes/combat/camera.gd` | `CombatCamera` | 확대/축소·이동·C 복귀 카메라 |
| `scenes/combat/unit.gd` | `CombatUnit` | 유닛 종류·능력치·자원·상태·도트 애니메이션 |
| `scenes/combat/enemy_definitions.gd` | `CombatEnemyDefinitions` | 몬스터 8종 고정 수치·동작 |
| `scenes/combat/enemy_ai.gd` | `CombatEnemyAi` | 적 행동 우선순위·전술 선택 |
| `scenes/combat/act_progress.gd` | `CombatActProgress` | 3막 스테이지 진행·회복·졸업 |
| `scenes/combat/stage.gd` | `CombatStage` | 스테이지 지형·장식·시작 배치 리소스 |
| `scenes/combat/snapshot.gd` | `CombatSnapshot` | 전투·정비 자동 저장 직렬화·복원 검증 |

## `tests/` 검사 스크립트

`*_test.gd` 27개는 [scripts/check_godot.sh](../../scripts/check_godot.sh)에 등록되어 `make godot-check`와 CI `smoke`에서 실행됩니다. 단일 실행은 `bash scripts/check_godot.sh tests/<파일>.gd`를 씁니다.

| 영역 | 스크립트 |
| --- | --- |
| 전투 동작·스킬·장판 | `combat_actions_test.gd`, `combat_checks_test.gd`, `combat_warrior_test.gd`, `combat_archer_test.gd`, `combat_oil_test.gd` |
| AI·몬스터·엄폐·턴 | `combat_ai_test.gd`, `combat_monster_stats_test.gd`, `combat_cover_test.gd`, `combat_turns_test.gd`, `combat_selection_test.gd` |
| 연출·HUD·사운드·캡처 | `combat_feedback_test.gd`, `combat_hud_test.gd`, `combat_dice_roll_test.gd`, `combat_sound_test.gd`, `combat_capture_test.gd` |
| 진행·정비·저장·타이틀 | `combat_progression_test.gd`, `combat_loot_test.gd`, `combat_staging_test.gd`, `combat_save_test.gd`, `combat_preparation_save_test.gd`, `combat_snapshot_test.gd`, `save_test.gd`, `continue_test.gd` |
| 화면·메뉴·테마·배경음 | `title_test.gd`, `pause_test.gd`, `ui_theme_test.gd`, `music_test.gd` |

## `tests/` 수동 QA·보조 스크립트

`*_qa.gd` 9개는 [manual_qa.py](../../scripts/manual_qa.py)(또는 `qa_movement.py`)로 실행하는 Forward+ 확인 사례이며, `make godot-check` 전체 실행에서는 `--check-only` 문법 검사 대상에 포함됩니다.

| 파일 | 역할 |
| --- | --- |
| `layout_qa.gd` | 14×14 1-1 초기·호버 배치 픽셀 측정 |
| `terrain_qa.gd` | 9개 스테이지 지형·상자·바위 캡처 |
| `preparation_qa.gd` | 보상·정비·가방 부족·버리기 캡처 |
| `presentation_qa.gd`, `soak_qa.gd` | macOS 입력 전환·장기 AI 관찰 |
| `combat_ui_qa.gd`, `fog_spider_qa.gd`, `overload_burn_qa.gd` | UI·독안개 거미·과부하 화상 수동 사례 |
| `movement_qa.gd` | PCK 이동 후조건 검증(`qa_movement.py`) |
| `scripted_dice.gd`, `monster_baseline.gd`, `capture_observer.gd`, `large_map_battle.gd` | 테스트용 주사위·튜닝 전 기준 수치·뷰포트 캡처·28×20 큰 맵 진입점 |
