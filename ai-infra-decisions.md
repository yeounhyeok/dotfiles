# AI 인프라 의사결정 기록 (ADR)
> 작성: 2026-07-21 · 대상: 운혁(yeounhyeok) · 용도: ROLEX 봇 + 연구 코딩 에이전트 백엔드 선택
> 이 문서는 opencode의 AGENTS.md 컨텍스트로 물리거나, ROLEX가 참조하도록 설계됨.

---

## TL;DR — 최종 아키텍처
```
🤖 ROLEX 봇(hermes) = DeepSeek direct (deepseek-chat=v4-flash) · 캐싱 · ~$2~4/월 · 선불 · 격리
💻 연구 코딩        = opencode + OpenRouter (8월~) · DeepSeek 기본 + 최강 온탭 · 선불 $20~50
🌉 7월 브릿지       = Claude Code Max (공짜) — 하드/아이디어빌딩 몰아서
🔑 원칙            = 싼거 기본+승급 · 선불캡 · 봇/코딩 계정 분리(격리)
```

## 내 프로파일 (판단 전제)
- **헤비 에이전트 유저** — 과거 Codex Plus/Pro 맥스아웃. 플랜 벽에 잘 부딪힘.
- **프런티어만 써옴** (Opus, GPT-5.6) — 티어 나눠쓰는 습관 없었음.
- **연구**: 3DGS drag + vision intelligence, 2·3저자급(재현·실험·선행연구 중심, 현재 프런티어급 난제는 없음).
- **CLI 선호**, **중국 무관**(오직 env 키 유출만 신경), **비용 의식적**이나 소액은 OK.
- 하드웨어: 게임용 RTX 5060(8GB, 코딩모델엔 부족), 랩 GPU(RTX PRO 6000×4)는 공용이라 임시만.
- 미래: 산학협력 무료 계정 **불확실**(안 할 수도) → 아키텍처는 여기 의존 안 함.

---

## 결정 로그 (결정 · 근거 · 기각안)

### 1. ROLEX 봇 백엔드 = **DeepSeek direct**
- **근거**: DeepSeek 자체 캐싱($0.0028 cache-read)으로 재전송 헤비 패턴이 월 $2. 단일모델 봇이라 멀티모델 불필요. 코딩과 예산 격리(봇이 코딩 잔액에 안 휘둘림).
- **기각**: OpenRouter(캐싱 손실→비싸짐 + 예산 커플링) / Claude Code OAuth(Anthropic이 서드파티앱 차단, HTTP 400 "extra usage") / GitHub Copilot(학생플랜 API 죽음, 403) / 로컬 gemma(공용GPU·게임 충돌·8GB 부족) / 무료 Gemini(쿼터 과소).
- **상태**: LIVE. 실측 = 헤비세션 1개 31req/1.18M토큰/$0.02.

### 2. 연구 코딩 = **opencode + OpenRouter** (8월~)
- **근거**: CLI 선호=opencode(터미널 에이전트, Claude Code와 UX 동일, BYO 모델). OpenRouter=키 하나로 모든 모델, 빠르게 뒤집히는 판(예: Kimi K3가 Fable/Sol 능가)에 락인 회피. 선불캡=폭탄 방지. 종량제=플랜 벽 없음(헤비유저 핵심).
- **기각**: Codex Plus(정액이지만 또 맥스아웃=벽) / OpenCode Go $10(한도 부족, 헤비면 며칠 소진) / GLM 정액(벽 or $72급 비쌈) / DeepSeek direct only(vision·승급 탈출구 없음 — 근데 봇엔 이게 맞음) / Gemini 유료(Flash 멍청 + 구글 악감정) / Fireworks(오픈모델만, 닫힌모델 못 씀).

### 3. 모델 전략 = 싼거 기본 + 승급 + vision
- **워크호스(80~90%)** = DeepSeek V4(flash/pro). 재현·실험·표준구현엔 지능 충분.
- **승급(어려운 순수코딩)** = GLM-5.2(오픈 SWE-Pro 1위) 또는 Kimi K3(Terminal-Bench 88.3).
- **vision(렌더·figure)** = Qwen3-VL/GLM-4.6V(싸게) 또는 Claude(정밀). ※DeepSeek·GLM-5.2는 텍스트 전용.
- **하드 10%** = Claude Opus/GPT (진짜 난제 — 지능 갭 실존).

### 4. 서브에이전트 오케스트레이션 = Pro헤드 + Flash워커
- opencode `opencode.json`에 orchestrator(reasoner/Pro, 계획·위임) + coder(flash, 대량구현) + hardmode(Claude/Kimi, 승급) 에이전트 정의.
- 루프 1회 ~$1~1.5 (헤드 비용이 좌우 — Opus 헤드는 금물).

---

## 재사용 가능한 원칙 (이 대화의 핵심 지혜)
1. **루프 비용 = 헤드(오케스트레이터) 모델빨.** 워커(flash)는 껌값. 자율루프 헤드에 Opus 넣으면 $700 사고. 싼-스마트 헤드(reasoner/GLM) 써라.
2. **사고 = 똑똑한 모델(저볼륨·고가치, 비싸도 쌈) / 노가다 = Flash(고볼륨).** 아이디어빌딩·설계·난제디버깅엔 아끼지 마라(세션당 몇 백 원). 변수명 바꾸는 데 Opus 쓰지 마라.
3. **선불(prepaid)캡 = 폭탄 구조적 차단.** 후불무제한이 $700의 원인. 넣은 만큼만 나감.
4. **캐싱이 에이전트 재전송 패턴엔 결정적.** DeepSeek direct $0.0028 캐시 = 봇이 월 $2인 이유. 서드파티 경유하면 손실 가능.
5. **빠른 판 = 유연성(OpenRouter) 가치 있음.** 이달 최강이 다음달 2등. 락인 회피가 +5.5% 수수료 값.
6. **저-stakes 반복비용은 타임박스.** "일주일 실측"이 "종이 위 20라운드"보다 낫다. (이 대화가 그 반례 ㅋㅋ)
7. **역할별 분리 > 통합.** 항상 켜진 저-stakes 봇과 변동 큰 고품질 코딩은 도구·계정 분리해야 서로 안 죽임.
8. **DeepSeek ≈ GPT-5.5급, Opus 4.8보단 확실히 아래.** 연구 난제엔 프런티어 승급 규율 필요 — 게으르면 연구품질 조용히 하락.

## 모델 지능 팩트 (2026-07 기준, 시간 지나면 갱신)
- **SWE-bench Verified**: Opus 4.8 88.6 > DeepSeek V4-Pro 80.6 > Kimi K3 76.8
- **SWE-bench Pro**: Opus 4.8 69.2 > GLM-5.2 62.1(오픈1위) > GPT-5.4 59.1 > GPT-5.5 58.6
- **Terminal-Bench 2.1**: Kimi K3 88.3 ≈ Opus 85 > GPT-5.5 84 > GLM-5.2 81 ≫ DeepSeek V4 62
- 요약: Opus 최상, 그 아래 GPT-5.x/DeepSeek/GLM/Kimi가 근접 클러스터. Kimi K3가 일부(프론트엔드/터미널) 최강 넘봄.

## 비용 데이터 (실측)
- ROLEX 헤비세션 1개 = 31 req / 1.18M 토큰 / **$0.02** → 월 ~$2~4
- DeepSeek v4-flash: 입력 $0.14 / 출력 $0.28 / **캐시 $0.0028** per 1M
- DeepSeek 피크(2배): 한국시간 10~13시, 15~19시. 심야가 쌈.
- 예산: 코딩 OpenRouter 선불 $20~50, 봇 DeepSeek 톱업 $5~10(몇 달치)

---

## 8월 액션 플랜 (체크리스트)
- [ ] OpenRouter 가입 → **$20 선불** 충전 (하드캡)
- [ ] `opencode auth login` → OpenRouter 키
- [ ] `opencode.json` 작성: orchestrator(reasoner/Kimi) + coder(flash) + **hardmode(Claude/Kimi K3) 미리 등록** ← 승급 게으름 방지
- [ ] `.env`를 opencode ignore 등록 + 승인모드 (키 유출 방지)
- [ ] 기본 모델 = DeepSeek, `/models`로 승급/vision 전환
- [ ] 봇: DeepSeek 잔액 낮으면 톱업만 (provider 변경 X)
- [ ] **일주일 실측** → 소진속도·품질 보고 기본모델/예산 조정

## 미래의 나에게 (경고)
- **하드할 때 프런티어 승급하는 규율을 지켜라.** 게을러서 싼 DeepSeek로만 버티면 연구품질이 조용히 떨어진다. hardmode 에이전트 미리 등록해두는 이유가 이거.
- **flip-flop 그만.** 유연성 원하면 OpenRouter 확정, 매주 재고민 금지. 되돌릴 수 있으니(모든 선택 2초 변경) 완벽 안 서도 커밋해라.
- **판이 바뀌면 모델만 갈아끼워라.** 아키텍처(opencode+OpenRouter+선불캡+티어링)는 모델 불가지론이라 그대로 유효하다.
