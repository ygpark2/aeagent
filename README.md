# 자율 진화형 에이전트 (Autonomous Evolutionary Agent) 🧬

엘릭서(Elixir/OTP) 기반의 **Outcome-Driven Agent Graph** 아키텍처를 채택하여, 고정된 명령을 수행하는 것을 넘어 스스로 사고하고, 결과를 검증하며, 경험을 통해 진화하는 차세대 인공지능 에이전트 시스템입니다.

## 현재 구현 상태

- LiveView 대시보드에서 에이전트 실행 상태와 툴 실행 흐름을 볼 수 있습니다.
- 위험 툴(`execute_command`, `write_file`, `replace`)은 사용자 승인 후에만 실행됩니다.
- 우측 Inspection Pane에서 파일 읽기/수정 결과와 웹 검색 결과를 확인할 수 있습니다.
- 내부 `web_search` 툴로 실시간 웹 검색을 수행할 수 있습니다.
- 실행 이력은 DB에 저장되고, Architect는 최근 성공 이력 중 유사한 작업을 우선 참고합니다.
- 예산 정책은 누적 비용과 루프 횟수를 기준으로 실행을 제한합니다.
- 안전 정책은 PII와 파괴적 의도를 차단하고, 내부 파일/명령 툴은 workspace 범위와 allowlist를 강제합니다.
- 스킬 선택 결과는 worker/executor 프롬프트에 실제 지침으로 주입됩니다.
- 위임 노드는 delegation depth 제한과 동일 작업 재귀 위임 방지를 적용합니다.

## 🌟 핵심 아키텍처 (Key Pillars)

### 1. 자율 설계자 (Strategic Architect)
- 사용자의 미션을 분석하여 실시간으로 최적의 **에이전트 그래프(Agent Graph)**를 설계합니다.
- 고정된 프로필 없이, 상황에 맞는 전문가 노드(Node)들을 유기적으로 배치합니다.

### 2. 결과 중심 엔진 (Outcome-Driven Engine)
- 단순히 단계를 밟는 것이 아니라, **성공 기준(Outcome)**을 달성할 때까지 스스로 경로를 수정합니다.
- 실패 시 비판적 검토(Evaluator)를 통해 피드백을 수용하고 자가 수정을 반복합니다.

### 3. 장기 기억 및 진화 (Long-term Memory & Evolution)
- 모든 실행 이력을 데이터베이스에 영구 저장합니다.
- 과거의 성공 사례를 분석하여 시간이 흐를수록 더 정교하고 효율적인 전략을 수립합니다.

### 4. 에이전트 군집 위임 (Multi-Agent Delegation)
- 복잡한 작업은 전문 서브 에이전트에게 위임(MCT)합니다.
- 에이전트들이 서로 협력하여 거대한 목표를 달성하는 '벌집(Hive)' 구조를 지향합니다.

### 5. 지능형 정책 가드레일 (Multi-policy Gatekeeper)
- 안전(Safety), 예산(Budget), 도메인(Domain) 정책을 통해 에이전트의 자율성을 통제합니다.
- 개인정보, 파괴적 명령, 과도한 루프, 예산 초과를 차단합니다.

## 🛠️ 기술 스택 (Tech Stack)
- **Language**: Elixir / OTP (고도의 병렬성 및 내결함성)
- **Intelligence**: Anthropic Claude / OpenAI / Google Gemini (통합 LLM 레이어)
- **Database**: PostgreSQL (Long-term Memory 저장소)
- **Framework**: Phoenix LiveView (실시간 모니터링 및 인터랙션)

## 🚀 시작하기
```bash
# 의존성 설치
mix deps.get

# 데이터베이스 준비
mix ecto.setup

# 에이전트 가동
mix phx.server
```

## 💻 CLI 사용법
웹 UI 없이도 실행을 만들고 추적할 수 있습니다.

```bash
# 대화형 CLI 시작
mix agent.chat

# 기존 session_id로 이어서 대화
mix agent.chat --session-id <session_id>

# 실행 생성
mix agent.run "README에 CLI 설명 추가"

# 실제 실행 없이 queued 상태로만 생성
mix agent.run --no-start "queued only task"

# 특정 실행 상태 조회
mix agent.status <execution_id>

# 최근 실행 목록 조회
mix agent.history
mix agent.history --limit 10

# 특정 실행의 audit/artifact 로그 조회
mix agent.logs <execution_id>

# 실패/중단 실행 재개
mix agent.resume <execution_id>

# 특정 checkpoint 기준으로 재개
mix agent.resume --checkpoint-id <artifact_id> <execution_id>

# checkpoint 노드부터 다시 실행
mix agent.resume --checkpoint-id <artifact_id> --resume-mode checkpoint_node <execution_id>

# 동일 세션으로 재시도
mix agent.retry <execution_id>

# 실행 replay bundle 조회
mix agent.replay <execution_id>

# 런타임 진단/메트릭
mix agent.doctor
mix agent.metrics
```

CLI 명령은 모두 애플리케이션을 부팅한 뒤 현재 DB를 기준으로 동작합니다. 먼저 `mix ecto.migrate`를 적용해 두는 편이 안전합니다.
`mix agent.chat`은 같은 세션에 execution을 계속 추가하는 대화형 루프이고, `mix agent.run --session-id <id>`는 기존 세션 문맥을 이어받아 단발 실행을 추가하는 방식입니다.
`mix agent.chat` 안에서는 slash command를 쓸 수 있습니다. 예: `/help`, `/logs`, `/logs on`, `/logs off`, `/session`, `/exit`, `/quit`

이제 **자율 진화형 에이전트**는 당신의 가장 똑똑하고 신뢰할 수 있는 파트너가 될 것입니다.
