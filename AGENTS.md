# BGLike 작업 지침

Godot 4 싱글 플레이 PC 게임입니다. 여러 사람이 함께 개발합니다. GitHub 품질 운영(필수 승인 0명 등)은 아직 1인 프로필 기준입니다. 미확정 제품 결정은 관련 Issue에서 확인합니다.

프로필: 1인
이 파일은 사람, Claude Code, Codex의 공통 길잡이입니다. 도구별 프로젝트 지침 파일을 만들지 않습니다. `CLAUDE.md`는 `@AGENTS.md` 한 줄이라 Claude Code도 이 파일을 읽습니다. `.claude/CLAUDE.md`·`CLAUDE.local.md`는 두지 않습니다.

## 명령

`python3 -I .baseline/baseline.py run test`처럼 부릅니다. 이 칸은 `.baseline/commands.json`과 같아야 합니다. 엔진 경로는 `GODOT=<Godot 4.7.2 실행 파일>`로 지정합니다.

- setup: `make godot-install`
- check: `make repository-check`
- test: `make godot-check`
- build: `N/A: 출시 빌드 없음. 검증용 PCK는 [Draft 절차](docs/process/ci/draft-release.md)`

setup은 고정한 Godot을 받아 해시를 확인합니다. Git LFS와 `git config core.hooksPath .githooks`는 [README](README.md#시작)대로 한 번 합니다. check는 공백 검사와 Python 테스트입니다. test는 Godot import·메인 장면·회귀 검사입니다. 둘 다 돌리려면 `make check`이고, 회귀 스크립트 일부만 돌리려면 `bash scripts/check_godot.sh <테스트 경로>`입니다.

## 길잡이

| 경로 | 무엇 |
| --- | --- |
| `scenes/`, `project.godot` | 게임 장면·GDScript·자산. [코드·테스트 지도](docs/agents/code-map.md) |
| `tests/` | Godot 회귀 검사·QA 시나리오. [코드·테스트 지도](docs/agents/code-map.md) |
| `scripts/` | 검사·CI·Draft 도구와 Python 테스트 |
| `docs/` | 기획·ADR·작업 규칙. [전체 문서 색인](docs/README.md), [문서 길잡이](docs/agents/domain.md) |
| `docs/agents/ops.md` | ops 규칙. 배포·SDK·비밀값을 다룰 때 읽는다 |
| `.mise.toml` | 툴체인 판(Python). `run`이 이 판으로 돈다 |
| `scripts/godot.env` | mise가 다루지 못하는 Godot의 판(4.7.2 Standard)과 공식 archive 해시. `make godot-install`이 받아 확인한다. 이미 설치한 Godot은 `GODOT`로 가리킨다 |
| `REVIEW.md` | 리뷰 기준. 리뷰할 때만 읽는다 |

- 작업 시작: [협업 규칙](docs/process/workflow.md)과 [브랜치·커밋 규칙](docs/process/git-conventions.md)을 읽습니다. 다른 작업자의 변경을 보존합니다.
- 브랜치를 만들기 전에 [브랜치·커밋 규칙](docs/process/git-conventions.md)을 먼저 읽습니다. 도구가 `claude/…`처럼 자동 이름을 지정해도 이름 검사가 면제될 뿐이므로, 새 작업은 최신 `main`에서 `<type>/<issue번호>-<짧은-설명>` 형식의 브랜치로 시작합니다.
- 제품 사양: 관련 Issue의 목표·완료 조건과 연결한 기획 문서를 읽습니다. 용어·ADR은 [문서 길잡이](docs/agents/domain.md)를 따릅니다.
- 검증: [CI 구성](docs/process/ci/ci.md)의 범위 규칙을 확인합니다. 플레이 변경의 직접 확인 기준은 [협업 규칙](docs/process/workflow.md#검증과-보고)을 따릅니다.
- 작업 진입·초기 설정 확인·명세와 티켓의 통합: [개발 절차](docs/agents/development.md). 작은 수정에는 전체 명세 절차를 강제하지 않습니다.
- 리뷰 절차: [리뷰 절차](docs/agents/review.md). PR 본문은 [PR 양식](.github/pull_request_template.md)을 따르며, 순수 문서 PR(지침·에이전트·설정·의존성 제외) 외에는 머지 큐가 Review 칸의 「리뷰한 head:」 SHA를 검사합니다.
- GitHub 설정: [설정 기준선](docs/process/ci/repository-setup.md). 권리·외부 자산: [COPYRIGHT](COPYRIGHT.md)와 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md).

## 병합

- 상시 지시: 문서·쉬움 PR은 리뷰가 끝나면 `python3 -I .baseline/baseline.py enqueue <PR> <리뷰한 head>`로 머지 큐에 넣는다. 소유자가 끄려면 이 줄을 지운다.

## 이 저장소의 규칙

- 끝나지 않은 기능은 꺼진 진입점 뒤에 둔다.
- 작업 추적은 GitHub Issue 하나만 쓴다. 내부 트래커(예: Linear)는 쓰지 않는다. 일정·우선순위·기획 판단도 공개 Issue와 `docs/`에 적는다. 아래 관리 블록 「하지 않는 것」의 "우선순위·일정·내부 판단"을 공개 Issue·PR·커밋에 쓰지 않는다는 부분은 이 저장소에 적용하지 않는다. 취약점 설명은 그대로 쓰지 않는다.
- 취약점은 [SECURITY.md](SECURITY.md)의 비공개 취약점 보고로 받는다.
- `.env.example`은 비밀값 파일이 아니다. [ops 규칙](docs/agents/ops.md)대로 빈 칸만 두고 커밋한다.
- 같은 실수가 두 번 나오면 린트·검사로 막고, 그다음 `REVIEW.md` 한 줄, 그다음 이 파일의 길잡이 순서로 고친다.

## Agent skills

- Issue tracker: GitHub `minjunkim-labs/BGLike`. `docs/agents/issue-tracker.md`를 읽습니다.
- Triage labels: `docs/agents/triage-labels.md`에서 다섯 역할과 라벨을 확인합니다.
- Domain docs: [문서 길잡이](docs/agents/domain.md)를 따릅니다.

## pstack

pstack 스킬은 사람이 요청할 때만 쓴다. 이 저장소의 규칙이 pstack 기본 동작보다 먼저다.

- `poteto-mode`의 Shipping playbook과 병합·auto-merge 단계는 쓰지 않는다. 병합은 POLICY §5대로 한다.
- `correct`는 제안까지만 한다. 사람이 고른 것만 반영한다.
- 판단 규칙은 `AGENTS.md`가 아니라 `REVIEW.md` 「배운 규칙」에 둔다.
- `create-verification-skill`의 결과는 에이전트 도구가 읽는 저장소 스킬 경로(Claude `.claude/skills/`, Codex·Cursor `.agents/skills/`)에 두고, 실행 명령을 `AGENTS.md`의 check·test에 잇는다. 그 경로는 에이전트 설정 폴더라서 그 PR은 되돌리기 어려움이고 소유자가 병합한다(POLICY §4).
- `interrogate`·`blast-radius`는 리뷰에 관점을 더할 뿐이다. 리뷰는 그대로 새 세션에서 `prompts/review.md`로 받는다.
- 서로 다른 모델로 검토하지 않았으면 그 사실을 보고에 적는다.

<!-- baseline:start -->
## 작업 방식

- 규칙은 repo-baseline의 [POLICY.md](https://github.com/minjunkim-labs/repo-baseline/blob/main/POLICY.md)다. 이 블록은 그 요약이다.
- 시작 전에 열린 PR과 Issue에서 같은 일을 찾는다. 있으면 그 PR을 잇거나 소유자에게 묻는다.
- 시작 전에 완료 기준을 정해 PR 본문 Summary에 쓴다. 완료 주장은 명령의 실제 출력이다.
- 리뷰 등급은 셋이다. 문서는 필수 CI만, 쉬움은 구현 대화를 물려받지 않는 하위 에이전트 리뷰 한 번, 어려움은 구현 대화를 물려받지 않는 새 세션 하나가 Spec·Standards와 보안 관점을 본 뒤 소유자 병합이다(POLICY §3).
- 등급은 `review-preflight`가 정하고 리뷰어는 올릴 수만 있다. `enqueue`는 어려움 PR을 넣지 않는다.
- 하위 에이전트·새 세션·headless 실행을 띄울 때는 POLICY §3의 모델 층과 effort를 사용자 전역 지시가 가리키는 층 표로 실제 모델로 바꾼다. 층은 내리지 않는다.
- 무엇을 만들고 무엇이라 부를지 정할 일이 크면 사람만 부르는 스킬(`grill-with-docs`, `wayfinder`, `to-spec`, `to-tickets`)의 이름을 대고 실행을 권한다.
- 이 블록은 repo-baseline이 관리한다. 고치지 않는다. 블록 밖은 프로젝트가 쓴다.

## 하지 않는 것

- 비밀값(`.env*`, 키, 토큰)을 읽거나 커밋하지 않는다. 커밋됐으면 먼저 키를 폐기한다.
- `main`에 직접 push하지 않는다. `enqueue`를 거치지 않고 병합하지 않는다.
- 어려움 PR(예: 돈, 인증·권한, 복구가 어려운 migration, workflow 권한, 에이전트 설정 폴더, `.baseline/`)을 병합하지 않는다.
- 우선순위·일정·내부 판단과 취약점 설명을 공개 Issue·PR·커밋에 쓰지 않는다.
- 브랜치 보호·저장소 설정·CI workflow를 사람 승인 없이 바꾸지 않는다.
<!-- baseline:end -->
