# Docker Swarm이란? — 컨테이너 오케스트레이션 입문

> **난이도**: 입문
> **소요 시간**: 약 12분
> **사전 지식**: Docker 컨테이너 기본 개념 (docker run, docker pull)
> **시리즈**: Docker Swarm 학습 가이드 1/11

---

## 개요

여러 서버에서 컨테이너를 동시에 관리해야 한다면 어떻게 할까요?
이 편에서는 Docker Swarm이 무엇인지, 어떤 구조로 동작하는지, 그리고 언제 사용하면 좋은지 배웁니다.

---

## 왜 오케스트레이션이 필요할까?

개발할 때는 `docker run` 하나로 컨테이너를 띄우면 됩니다.
하지만 실제 서비스가 커지면 이런 상황이 생깁니다.

- 서버 1대에 장애가 생겼다 → 서비스 전체 중단 😱
- 트래픽이 몰렸다 → 컨테이너를 10개로 늘려야 하는데 수동으로?
- 새 버전 배포 → 기존 서비스 중단 없이 교체할 수 있을까?

이 문제를 해결해 주는 것이 **컨테이너 오케스트레이션**입니다.
Docker Swarm은 Docker Engine에 내장된 오케스트레이션 도구입니다.

---

## Docker Swarm 아키텍처

```
┌──────────────────────────────────────────────────────────────┐
│                        Docker Swarm                          │
│                                                              │
│   ┌─────────────────┐     ┌─────────────────┐               │
│   │  Manager Node   │────▶│  Manager Node   │  ← 리더 선출  │
│   │   (Leader)      │     │   (Follower)    │    (Raft)      │
│   └────────┬────────┘     └────────┬────────┘               │
│            │ 작업 분배              │                         │
│   ┌────────▼──────────────────────▼────────┐                │
│   │              Worker Nodes              │                │
│   │  ┌──────────┐  ┌──────────┐  ┌──────┐ │                │
│   │  │ Worker 1 │  │ Worker 2 │  │  W3  │ │                │
│   │  │[Task][T] │  │[Task][T] │  │ [T]  │ │                │
│   │  └──────────┘  └──────────┘  └──────┘ │                │
│   └────────────────────────────────────────┘                │
└──────────────────────────────────────────────────────────────┘
```

### 핵심 구성 요소 한눈에 보기

| 구성 요소        | 역할                                                  | 비유                  |
| ---------------- | ----------------------------------------------------- | --------------------- |
| **Node**         | 클러스터에 참여하는 Docker Engine 인스턴스 (서버 1대) | 공장                  |
| **Manager Node** | 클러스터 관리, 작업 분배, API 제공                    | 공장 관리자           |
| **Worker Node**  | 실제 컨테이너 실행, 상태 보고                         | 공장 직원             |
| **Service**      | "nginx 3개 실행"처럼 원하는 상태 선언                 | 작업 지시서           |
| **Task**         | 실제로 실행 중인 컨테이너 1개 (스케줄링 최소 단위)    | 직원이 하는 개별 작업 |
| **Stack**        | 여러 Service를 묶은 애플리케이션 단위                 | 작업 지시서 묶음      |

아래에서 각 요소를 자세히 살펴봅니다.

---

## Node — Manager와 Worker

**Node**는 Swarm 클러스터에 참여하는 Docker Engine 인스턴스입니다.
물리 서버 1대 또는 VM 1개가 Node 1개에 해당합니다.

### Manager Node의 세 가지 핵심 역할

```
┌─────────────────────────────────────────────────────┐
│                  Manager Node                        │
│                                                      │
│  ① 클러스터 상태 관리          ② 서비스 스케줄링      │
│     Raft 합의로 모든              어떤 Worker에       │
│     Manager가 동일한              어떤 Task를          │
│     상태 유지                     배치할지 결정        │
│                                                      │
│  ③ API 제공                    + Worker 역할도 겸함   │
│     docker service,               (기본 설정)         │
│     docker node 등                                   │
│     모든 관리 명령 처리                                │
└─────────────────────────────────────────────────────┘
```

1. **클러스터 상태 관리** — Raft 합의 알고리즘으로 모든 Manager가 동일한 상태를 유지합니다. 서비스 정의, 네트워크, Secret 등의 정보가 여기에 포함됩니다.
2. **서비스 스케줄링** — 어떤 Worker에 어떤 Task를 배치할지 결정합니다. 리소스 제한, 배치 제약 조건 등을 고려합니다.
3. **API 제공** — `docker service`, `docker node`, `docker stack` 등 모든 Swarm 관리 명령을 처리합니다. **Manager에서만** 이 명령들을 실행할 수 있습니다.

### Worker Node

Worker는 Manager로부터 할당받은 컨테이너를 실행합니다.
내부 **에이전트(Agent)**가 Task 상태를 Manager에게 지속적으로 보고합니다.

```
Worker가 하는 일:
┌────────────────────────────────────────────┐
│  • Manager로부터 Task 할당받기              │
│  • 컨테이너 실행                            │
│  • Agent가 Task 상태를 Manager에게 보고     │
│  • 이것만 함! (스케줄링, API 처리 안 함)     │
└────────────────────────────────────────────┘
```

> 💡 **실무 팁**: Manager 노드는 홀수(1, 3, 5, 최대 7)로 구성하세요.
> Raft 합의 알고리즘 특성상 과반수가 살아있어야 클러스터가 정상 동작합니다.
> 노드 1개 → 고가용성 없음 / 노드 3개 → 1개 장애 허용 / 노드 5개 → 2개 장애 허용
> 7개 초과는 Raft 오버헤드만 증가하므로 권장하지 않습니다.

### 노드 상태 (Availability)

```
active  ─── 정상 운영. 새 Task 할당 받음 (기본값)
pause   ─── 새 Task 할당 중단, 기존 Task는 계속 실행
drain   ─── 기존 Task를 다른 노드로 이전 + 새 Task도 받지 않음 (유지보수용)
```

역할 변경도 가능합니다:

- `docker node promote worker1` — Worker → Manager 승격
- `docker node demote manager2` — Manager → Worker 강등

---

## Service와 Task의 관계

핵심을 먼저 짚겠습니다.

- **Service** = "무엇을, 몇 개, 어떤 조건으로 실행할지" 적어둔 **선언서(Desired State)**
- **Task** = 그 선언을 기반으로 **실제 생성된 Docker 컨테이너 1개**

```
Service (선언서):                    Task (실체):
┌────────────────────────┐          ┌─────────────────────────────────┐
│  이미지: nginx:1.27    │          │  Task my-web.1 → 컨테이너 on W1│
│  개수: 3개             │  ──────▶ │  Task my-web.2 → 컨테이너 on W2│
│  포트: 8080→80         │          │  Task my-web.3 → 컨테이너 on W1│
│  CPU: 0.5, 메모리: 256M│          └─────────────────────────────────┘
└────────────────────────┘
  "피자 3판 주문서"                    "실제로 만들어진 피자 1판씩"
```

Swarm Manager는 **주방장** 역할입니다.
주문서(Service)를 보고 피자(Task)가 항상 3판 유지되도록 관리합니다.
Task 1개가 죽으면 "3개여야 하는데 2개네?" → 새 Task를 자동 생성합니다.

---

## Service — 원하는 상태 선언

**Service**는 "어떤 이미지를, 몇 개, 어떤 조건으로 실행할지" 선언하는 단위입니다.
Swarm은 이 선언을 **원하는 상태(Desired State)**로 보고, 실제 상태가 항상 일치하도록 유지합니다.

```
사용자가 선언:                      Swarm이 유지:
"nginx를 3개 실행해줘"              항상 nginx 3개가 실행 중이도록 관리

  docker service create \              컨테이너 1개 장애 발생!
    --name my-web \                    → Swarm이 자동으로 새 컨테이너 생성
    --replicas 3 \                     → 다시 3개 유지 ✅
    nginx
```

### 두 가지 서비스 모드

```
Replicated 모드 (기본):                 Global 모드:
  "총 3개 실행해줘"                       "모든 노드에 1개씩 실행해줘"

  ┌────────┐ ┌────────┐ ┌────────┐      ┌────────┐ ┌────────┐ ┌────────┐
  │ Node A │ │ Node B │ │ Node C │      │ Node A │ │ Node B │ │ Node C │
  │ [T][T] │ │  [T]   │ │        │      │  [T]   │ │  [T]   │ │  [T]   │
  └────────┘ └────────┘ └────────┘      └────────┘ └────────┘ └────────┘
  스케줄러가 분배 결정                    노드 추가 시 자동으로 Task 생성
```

- **Replicated 모드** (기본): 지정한 개수만큼 Task를 생성합니다. 스케줄러가 어떤 노드에 배치할지 결정합니다. 웹 서버, API 서버 등 대부분의 서비스에 사용합니다.
- **Global 모드**: 모든 노드에 **정확히 1개씩** Task를 실행합니다. 새 노드가 추가되면 자동으로 해당 노드에도 Task가 생성됩니다. 모니터링 에이전트, 로그 수집기 등에 적합합니다.

### Desired State Reconciliation (원하는 상태 유지)

Swarm의 핵심 동작 원리입니다. Manager는 **실제 상태**를 지속적으로 모니터링하고, **원하는 상태**와 차이가 생기면 자동으로 조치합니다.

```
원하는 상태: replicas=3

  실제 상태          Swarm의 조치
  ──────────────     ─────────────────────
  3개 실행 중    →   아무것도 안 함 ✅
  2개 실행 중    →   1개 새로 생성 (자동 복구)
  4개 실행 중    →   1개 종료 (초과분 제거)
  노드 장애      →   다른 노드에 재배치
```

---

## Task — 스케줄링의 최소 단위

**Task**는 Swarm에서 스케줄링의 최소 단위이며, 실행 중인 컨테이너 1개에 해당합니다.
Service가 "무엇을 몇 개 실행할지" 정의라면, Task는 "실제로 실행 중인 개별 인스턴스"입니다.

```
Service: my-web (replicas=3)
  │
  ├── Task 1 (my-web.1)  →  컨테이너 [nginx]  on Worker1
  ├── Task 2 (my-web.2)  →  컨테이너 [nginx]  on Worker2
  └── Task 3 (my-web.3)  →  컨테이너 [nginx]  on Worker1
```

### Task의 핵심 특성

- **불변(Immutable)**: 한 번 노드에 할당되면 다른 노드로 이동하지 않습니다. 장애 시 기존 Task를 종료하고 **새 Task를 생성**합니다.
- **단방향 생명주기**: Task의 상태는 앞으로만 진행합니다. 절대 이전 ���태로 돌아가지 않습니다.

### Task 생명주기

```
NEW → PENDING → ASSIGNED → ACCEPTED → PREPARING → READY → STARTING → RUNNING
                                                                          │
                                                           ┌──────────────┤
                                                           ▼              ▼
                                                       COMPLETE       FAILED
                                                      (정상 종료)     (오류 종료)

기타 상태:
  SHUTDOWN  ── Docker가 Task 종료를 요청함
  REJECTED  ── Worker가 Task를 거부함 (리소스 부족 등)
  ORPHANED  ── 노드가 오래 동안 연결 불가
```

| 상태      | 설명                                        |
| --------- | ------------------------------------------- |
| NEW       | 오케스트레이터가 Task 초기화                |
| PENDING   | 네트워크 등 리소스 할당 중                  |
| ASSIGNED  | 스케줄러가 특정 노드에 배정 완료            |
| ACCEPTED  | Worker 노드가 Task를 수락                   |
| PREPARING | 이미지 pull 등 준비 작업 진행               |
| READY     | 실행 준비 완료                              |
| STARTING  | 컨테이너 시작 중                            |
| RUNNING   | 컨테이너 실행 중                            |
| COMPLETE  | 정상 종료 (exit code 0)                     |
| FAILED    | 오류 종료 (exit code ≠ 0)                   |
| SHUTDOWN  | 종료 요청됨 (스케일 다운, 롤링 업데이트 등) |

### Slot 모델 (Replicated 서비스)

Replicated 서비스에서 각 replica는 **슬롯 번호**(1, 2, 3...)를 갖습니다.
Task가 실패하면 같은 슬롯 번호로 새 Task가 생성되어 이력을 추적할 수 있습니다.

```bash
$ docker service ps my-web

ID        NAME         NODE      CURRENT STATE
abc123    my-web.1     worker1   Running        ← 슬롯 1 (현재)
def456    my-web.2     worker2   Running        ← 슬롯 2 (현재)
ghi789    my-web.3     worker1   Running        ← 슬롯 3 (현재)
old111    my-web.1     worker2   Failed         ← 슬롯 1 (이전 — 실패 이력)
```

---

## Stack — 서비스 묶음

**Stack**은 여러 Service를 하나의 Compose 파일로 묶어서 한 번에 배포하는 단위입니다.
예를 들어, 웹 서버 + DB + 캐시를 하나의 Stack으로 관리합니다.

```
Stack "my-app":
  ┌─────────────────────────────────────────────────┐
  │  Service: frontend (replicas: 3)                │
  │  Service: backend  (replicas: 2)                │
  │  Service: redis    (replicas: 1)                │
  │  Network: my-app_default (overlay)              │
  │  Volume:  my-app_redis_data                     │
  └─────────────────────────────────────────────────┘

  배포: docker stack deploy -c compose.yml my-app
  → 모든 리소스 이름에 "my-app_" 접두사 자동 부여
```

> Stack은 5편에서 자세히 다룹니다 → [05편: Stack과 Compose 파일](05-stack-and-compose.md)

---

## 로드 밸런싱 — Ingress와 VIP

Swarm은 별도 설정 없이 로드 밸런싱을 제공합니다.
**별도의 Task/컨테이너로 올라가지 않습니다** — Docker Engine 자체에 내장된 기능입니다.

> Kubernetes는 `kube-proxy` Pod가 별도로 실행되지만,
> Docker Swarm은 Engine에 내장되어 있어 더 단순합니다.

### Ingress (외부 → 서비스)

`docker swarm init`을 하면 **ingress**라는 overlay 네트워크가 자동 생성됩니다.
이 네트워크에 연결된 모든 노드는 Linux 커널의 **IPVS(IP Virtual Server)** 모듈을 통해 라우팅을 처리합니다.

```
서비스: nginx (replicas=2, port 8080:80)
Task는 Worker1, Worker2에만 있음

  ┌──────────────────────────────────────────────────────────────┐
  │                      Swarm 클러스터                          │
  │                                                              │
  │   Manager1            Worker1             Worker2            │
  │  ┌──────────┐       ┌──────────┐        ┌──────────┐        │
  │  │  :8080   │       │  :8080   │        │  :8080   │        │
  │  │ [IPVS]   │       │ [IPVS]  │        │ [IPVS]  │        │
  │  │ Task 없음 │       │ [Task]  │        │ [Task]  │        │
  │  └──────────┘       └──────────┘        └──────────┘        │
  │       │                                                      │
  │       └───── IPVS가 Worker1 또는 Worker2로 전달 ─────────▶  │
  └──────────────────────────────────────────────────────────────┘

  핵심: 모든 노드가 published 포트(8080)를 리스닝!
```

- **Manager1:8080** 으로 요청 → Task가 없지만 IPVS가 Worker1 또는 Worker2로 전달 ✅
- **Worker1:8080** 으로 요청 → 자신의 Task로 처리하거나 Worker2로 전달 ✅
- **Worker2:8080** 으로 요청 → 자신의 Task로 처리하거나 Worker1로 전달 ✅

> 💡 **실무 팁**: 외부 로드밸런서(AWS ALB 등)는 아무 노드나 가리키면 됩니다.
> Swarm Ingress가 알아서 Task가 있는 노드로 전달합니다.

### VIP (서비스 간 내부 통신)

서비스 간 통신도 별도의 Task 없이 **Swarm 내장 DNS + IPVS**가 처리합니다.

```
backend 서비스에서 db 서비스를 호출하는 경우:

  backend 컨테이너 내부:
    curl http://db:5432
         │
         ▼
  ① Swarm 내장 DNS가 "db" → VIP 10.0.0.5 로 변환
         │
         ▼
  ② IPVS가 VIP 10.0.0.5 → 실제 db 컨테이너 IP로 라우팅
         │
         ├──▶ db Task1 (10.0.0.11) on Worker1
         └──▶ db Task2 (10.0.0.12) on Worker2  (라운드 로빈)
```

- **Manager**가 서비스 생성 시 VIP를 할당합니다
- 각 노드의 **Docker Engine**이 DNS 조회와 IPVS 라우팅을 수행합니다
- 서비스 이름으로 DNS 조회하면 VIP가 반환됩니다
- 별도의 로드 밸런서 설치 없이 서비스 간 통신이 가능합니다

### 누가 이 기능을 제공하는가?

```
┌─────────────┬──────────────────────────────────────────────┐
│ 구성 요소    │ 제공 주체                                     │
├─────────────┼──────────────────────────────────────────────┤
│ Ingress     │ Docker Engine + Linux IPVS (커널 모듈)        │
│             │ → 모든 노드에서 동작, 별도 Task 없음           │
├─────────────┼──────────────────────────────────────────────┤
│ VIP + DNS   │ Manager가 VIP 할당                            │
│             │ + 각 노드의 Docker Engine이 DNS/IPVS 처리     │
│             │ → 별도 Task 없음                              │
└─────────────┴──────────────────────────────────────────────┘
```

---

## Raft 합의란?

Manager가 여러 개일 때, 누가 "진짜 리더"인지 결정하는 알고리즘입니다.
**Worker Node는 Raft에 참여하지 않습니다** — 오직 Manager Node만 투표합니다.

```
투표 참여 ✅                      투표 참여 ❌
┌─────────────────────┐          ┌───────────────────────────┐
│  Manager1 (Leader)  │          │  Worker1  Worker2  ...    │
│  Manager2 (Follower)│          │  컨테이너 실행만 담당      │
│  Manager3 (Follower)│          │  Raft 로그 저장 안 함      │
└─────────────────────┘          └───────────────────────────┘
```

### 노드의 세 가지 역할

Raft에서 각 Manager Node는 항상 세 가지 상태 중 하나입니다:

```
Leader     ─── 클러스터의 모든 결정을 내리는 리더 (1명만 존재)
Follower   ─── 리더의 명령을 따르는 추종자 (나머지 전부)
Candidate  ─── 리더가 되고 싶어서 선거를 시작한 후보자 (선거 중에만)
```

### 정상 상태: Heartbeat

Leader는 주기적으로(150~300ms 간격) heartbeat를 Follower에게 보냅니다.
Follower는 heartbeat를 받을 때마다 자신의 타이머를 리셋합니다.

```
  Manager1 (Leader)
      │
      ├──── 💓 heartbeat ────▶ Manager2 (Follower)  "나 살아있어"
      └──── 💓 heartbeat ────▶ Manager3 (Follower)  "나 살아있어"
```

### 장애 발생 → 리더 선출 과정

Manager1(Leader)에 장애가 발생하면 heartbeat가 중단됩니다.
각 Follower는 자신의 **election timeout**(랜덤 값)이 만료되면 선거를 시작합니다.

```
[1단계] Leader 장애 — heartbeat 중단
─────────────────────────────────────────
  Manager1 (Leader) ── 💀 장애!
  Manager2 (Follower)  "heartbeat가 안 온다..." (타이머: 250ms)
  Manager3 (Follower)  "heartbeat가 안 온다..." (타이머: 320ms)


[2단계] 타이머 먼저 만료된 노드가 후보(Candidate)로 전환
─────────────────────────────────────────
  Manager2의 타이머가 먼저 만료! (250ms < 320ms)

  Manager2가 하는 일:
    ① 자신의 임기(Term) 번호를 1 증가 (Term 1 → Term 2)
    ② 자기 자신에게 투표 (1표 확보)
    ③ Candidate 상태로 전환
    ④ 다른 모든 Manager에게 "나를 투표해달라(RequestVote)" 전송


[3단계] 투표
─────────────────────────────────────────
  Manager2 (Candidate, Term 2)
      │
      ├── RequestVote(Term=2) ──▶ Manager1 (장애) → 응답 없음
      └── RequestVote(Term=2) ──▶ Manager3 (Follower)
                                       │
                                       ▼
                                  "Term 2가 내 Term보다 높고,
                                   이번 Term에 아직 투표 안 했으니
                                   → 찬성!" ✅

  투표 규칙:
    • 각 노드는 하나의 Term에 1번만 투표 가능 (선착순)
    • 요청자의 Term이 자신보다 높거나 같아야 투표
    • 요청자의 로그가 자신보다 최신이어야 투표


[4단계] 과반수 확보 → 리더 확정
─────────────────────────────────────────
  Manager2 득표: 자기 자신(1) + Manager3(1) = 2표
  전체 Manager 3대 중 과반수(2) 충족 ✅

  → Manager2가 새 Leader로 확정!


[5단계] 새 Leader가 즉시 heartbeat 전송
─────────────────────────────────────────
  Manager2 (새 Leader, Term 2)
      │
      └──── 💓 heartbeat ────▶ Manager3 "새 Leader 확인, 타이머 리셋"

  → Manager3은 Candidate가 될 필요 없어짐
  → 클러스터 정상 운영 재개! (수백 밀리초 내 완료)
```

### 왜 타이머가 랜덤인가? (Split Vote 방지)

```
타이머가 모두 같다면:                 타이머가 랜덤이면:
  M2 ── 250ms ── Candidate!          M2 ── 250ms ── Candidate!
  M3 ── 250ms ── Candidate!          M3 ── 320ms ── 아직 Follower
  → 둘 다 자기에게 투표               → M3이 M2에게 투표
  → 1표 vs 1표 → 과반수 실패 ❌      → M2가 과반수 확보 ✅
```

Split Vote가 발생하면 새로운 랜덤 타이머로 재선거를 진행합니다.
랜덤 값 덕분에 보통 1~2회 내에 리더가 결정됩니다.

### 장애 노드 복구 시

```
Manager1 복구:

  Manager2 (Leader, Term 2) ── 💓 heartbeat(Term=2) ──▶ Manager1
                                                            │
                                                            ▼
                                                      "내 Term(1)보다
                                                       높은 Term(2)이네?
                                                       → Follower로 합류"

  → Manager1은 자동으로 Follower가 됨 (기존 Leader 지위 상실)
```

### Quorum (정족수)과 장애 허용

과반수의 기준은 **현재 살아있는 노드가 아니라, 클러스터에 등록된 전체 Manager 수**입니다.
과반수를 요구하면 어떤 식으로 네트워크가 분할되어도 **리더를 가진 그룹은 최대 1개만** 존재합니다 (Split Brain 방지).

```
Manager 수 │ Quorum(과반수) │ 장애 허용 │ 이유
───────────┼────────────────┼──────────┼──────────────────────────
    1      │      1         │    0개   │ 1개 죽으면 0/1 — 과반수 불가
    2      │      2         │    0개   │ 1개 죽으면 1/2 — 과반수 미달
    3      │      2         │    1개   │ 1개 죽어도 2/3 ≥ 2 ✅
    5      │      3         │    2개   │ 2개 죽어도 3/5 ≥ 3 ✅
    7      │      4         │    3개   │ 3개 죽어도 4/7 ≥ 4 ✅
```

> **짝수가 비효율적인 이유**: 4대의 과반수는 3대, 3대의 과반수는 2대.
> 4대에서 2개 죽으면 남은 2대 < 과반수 3 → 실패. 3대와 장애 허용 수가 같으므로 **홀수가 효율적**입니다.

---

## Docker Swarm vs Kubernetes

| 항목                | Docker Swarm | Kubernetes        |
| ------------------- | ------------ | ----------------- |
| 학습 난이도         | 쉬움 ⭐⭐    | 어려움 ⭐⭐⭐⭐⭐ |
| 설정 복잡도         | 낮음         | 높음              |
| 기능 범위           | 기본~중급    | 매우 풍부         |
| 적합한 규모         | 수십 노드    | 수백~수천 노드    |
| Docker Compose 호환 | 높음 ✅      | 변환 필요         |

> **언제 Swarm을 선택할까?**
>
> - 소~중규모 서비스 (노드 수십 개 이하)
> - Docker Compose를 이미 사용 중인 팀
> - 빠르게 오케스트레이션을 도입해야 할 때
> - 운영 복잡도를 낮추고 싶을 때

---

## 현재 상태 (2026년 기준)

- Docker Engine v29에 Swarm 모드 내장 (별도 설치 불필요)
- **Swarm 모드**는 현재도 지원 중 — Mirantis가 **2030년까지 장기 지원** 약속 (MKE 3)
- ⚠️ 과거의 "Docker Classic Swarm" (별도 바이너리)과는 다름 — v23.0에서 완전 제거됨
- 신기능 개발보다는 안정성/보안 패치 중심으로 유지보수됨
- Docker v23.0에서 Kubernetes 스택/컨텍스트 지원이 제거되어, `docker stack`의 **유일한 오케스트레이터**가 됨

---

## 요약

- Docker Swarm은 Docker Engine에 내장된 컨테이너 오케스트레이션 도구
- **Manager Node**: 상태 관리 + 스케줄링 + API 제공 / **Worker Node**: 컨테이너 실행 + 상태 보고
- **Service**: 원하는 상태 선언 (Replicated / Global 모드) → Swarm이 자동으로 유지
- **Task**: 스케줄링 최소 단위. 불변이며 단방향 생명주기 (NEW → RUNNING → COMPLETE/FAILED)
- **Stack**: 여러 Service를 Compose 파일로 묶어 한 번에 배포
- **로드 밸런싱**: Ingress (외부 트래픽) + VIP (내부 통신) 자동 제공
- Manager는 홀수 구성(최대 7) + Raft 합의로 고가용성 확보
- 소~중규모, Docker Compose 친화적 환경에서 Kubernetes 대비 빠른 도입 가능

---

## 다음 편 예고

다음 편에서는 실제로 Docker Swarm 클러스터를 구축해봅니다.
`docker swarm init` 한 줄로 클러스터를 시작하고, Worker 노드를 추가하는 실습을 진행합니다.

→ **[02편: Swarm 클러스터 구축하기](02-environment-setup.md)**

---

## 참고 자료

- [Docker Swarm 공식 문서](https://docs.docker.com/engine/swarm/) — docs.docker.com
- [Docker Swarm Key Concepts](https://docs.docker.com/engine/swarm/key-concepts/) — 핵심 개념 정리
- [How Nodes Work](https://docs.docker.com/engine/swarm/how-swarm-mode-works/nodes/) — Manager/Worker 동작 원리
- [How Services Work](https://docs.docker.com/engine/swarm/how-swarm-mode-works/services/) — Service/Task 동작 원리
- [Swarm Task States](https://docs.docker.com/engine/swarm/how-swarm-mode-works/swarm-task-states/) — Task 생명주기 상태
- [Swarm Mode Routing Mesh](https://docs.docker.com/engine/swarm/ingress/) — Ingress 로드 밸런싱
- [Raft Consensus Algorithm](https://www.baeldung.com/cs/raft-consensus-algorithm) — Raft 알고리즘 상세 설명
- [Raft (algorithm) - Wikipedia](https://en.wikipedia.org/wiki/Raft_(algorithm)) — Raft 개요 및 선출 과정
- [Docker Engine v29 릴리즈 노트](https://docs.docker.com/engine/release-notes/29/) — docs.docker.com
