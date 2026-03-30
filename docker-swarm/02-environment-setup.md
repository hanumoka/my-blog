# 빈 Ubuntu 서버에서 Docker Swarm 클러스터 만들기 — OS 레벨 초기 셋팅 완전 정복

> **난이도**: 중급
> **소요 시간**: 약 15분
> **사전 지식**: Linux 기본 명령어, Docker 컨테이너 기본 개념
> **시리즈**: Docker Swarm 학습 가이드 2/11
> **대상**: Docker를 설치해본 적 있는 주니어 개발자, 온프레미스 서버에 Swarm을 처음 셋팅하는 분
> **핵심 키워드**: Docker Swarm, 커널 모듈, br_netfilter, overlay network, swarm init, daemon.json

---

## 이 글의 목표

이 글을 다 읽고 따라 하면 Ubuntu 서버 3대가 Docker Swarm 클러스터로 동작하게 된다.

```
[Node 1 - Manager] ──── [Node 2 - Manager] ──── [Node 3 - Manager]
  192.168.1.101            192.168.1.102            192.168.1.103

$ docker node ls
ID        HOSTNAME   STATUS    AVAILABILITY   MANAGER STATUS
abc123 *  node-1     Ready     Active         Leader
def456    node-2     Ready     Active         Reachable
ghi789    node-3     Ready     Active         Reachable
```

흔히 Swarm을 "그냥 `docker swarm init`만 하면 되는 거 아니야?"라고 생각한다. 맞다. 단일 노드라면 그걸로 끝이다. 하지만 여러 서버를 묶어서 컨테이너가 노드를 넘나드는 overlay 네트워크를 쓰려면, **OS 레벨 사전 준비가 필요**하다. 이게 빠지면 서비스가 뜨더라도 노드 간 통신이 안 되거나, 재부팅 후 갑자기 네트워크가 깨진다.

**전체 흐름:**

```
Step 1. Docker Engine 설치
Step 2. 커널 모듈 로드 및 영구화
Step 3. sysctl 네트워크 파라미터 적용
Step 4. Docker daemon.json 설정
Step 5. 방화벽 포트 개방
Step 6. Swarm 초기화 (init + join)
Step 7. 검증
```

---

## 환경 정보

이 가이드에서 사용하는 예시 환경이다. 실제 IP와 계정은 자신의 환경에 맞게 바꾼다.

| 역할 | hostname | IP | OS |
|------|----------|----|----|
| Manager (Leader) | node-1 | 192.168.1.101 | Ubuntu 24.04 LTS |
| Manager | node-2 | 192.168.1.102 | Ubuntu 24.04 LTS |
| Manager | node-3 | 192.168.1.103 | Ubuntu 24.04 LTS |

- **계정**: sonix (sudo 권한 있음)
- **네트워크**: 3대 모두 같은 대역, 서로 ping 가능
- **Docker**: 아직 미설치 상태에서 시작

> **왜 Manager 3대인가?**
> Swarm은 내부 상태를 Raft 합의 알고리즘으로 관리한다. Manager가 1대이면 그 서버가 죽는 순간 클러스터 운영이 멈춘다. 3대면 1대가 죽어도 나머지 2대로 계속 운영된다. 홀수로 구성하는 게 핵심이다 (2대는 1대 장애도 못 버팀).
> 자세한 Raft 동작 원리는 [01편: Docker Swarm이란?](01-what-is-docker-swarm.md) 참고.

> 💡 **로컬에서 빠르게 테스트하고 싶다면?**
> Docker-in-Docker(dind)를 사용하면 단일 머신에서 Swarm 클러스터를 시뮬레이션할 수 있다.
> `docker run --privileged docker:dind`로 노드를 흉내 낼 수 있지만, 커널 모듈/방화벽 등 OS 레벨 셋팅은 학습할 수 없다. 실제 운영 환경을 준비하려면 이 글의 방식을 따르자.

---

## Step 1: Docker Engine 설치

**모든 노드**(node-1, node-2, node-3)에서 실행한다.

### 1-1. 기존 패키지 제거

Ubuntu에 기본으로 설치된 구버전 docker 패키지가 있으면 충돌이 생긴다. 먼저 지운다.

```bash
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
```

없으면 에러가 나도 괜찮다(`|| true`로 무시).

### 1-2. APT 저장소 설정

Docker는 Ubuntu 기본 저장소가 아닌 Docker 공식 저장소에서 설치해야 최신 버전을 받을 수 있다.

```bash
# 필수 패키지 설치
sudo apt-get update
sudo apt-get install -y ca-certificates curl

# Docker GPG 키 등록 (패키지 무결성 검증용)
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Docker APT 저장소 추가
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

### 1-3. Docker Engine 설치

```bash
sudo apt-get update
sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
```

각 패키지의 역할:

| 패키지 | 역할 |
|--------|------|
| docker-ce | Docker Engine 본체 |
| docker-ce-cli | `docker` 명령어 도구 |
| containerd.io | 컨테이너 런타임 |
| docker-buildx-plugin | 멀티 플랫폼 이미지 빌드 |
| docker-compose-plugin | `docker compose` 명령 지원 |

### 1-4. 사용자를 docker 그룹에 추가

기본적으로 docker 명령은 sudo가 필요하다. 매번 sudo를 치는 건 불편하고, 특히 스크립트 자동화 시 문제가 된다.

```bash
sudo usermod -aG docker $USER
```

> **주의**: 그룹 변경은 **재로그인 후** 적용된다. 현재 세션에서 바로 쓰려면 `newgrp docker`를 실행한다.

### 1-5. 서비스 시작 및 자동 시작 등록

```bash
sudo systemctl enable docker   # 부팅 시 자동 시작
sudo systemctl start docker    # 지금 당장 시작
```

### 1-6. 설치 확인

```bash
docker --version
docker compose version
```

예상 출력:

```
Docker version 29.3.1, build ...
Docker Compose version v5.1.1
```

---

## Step 2: 커널 모듈 설정

**왜 필요한가?** Docker Swarm의 overlay 네트워크는 VXLAN(Virtual Extensible LAN) 기술을 사용해서 서로 다른 물리 서버의 컨테이너를 하나의 가상 네트워크로 연결한다. 이 기술이 동작하려면 리눅스 커널에서 특정 모듈이 로드되어 있어야 한다.

### overlay 네트워크란?

단일 서버에서 Docker를 쓸 때는 bridge 네트워크만으로 충분하다. 같은 서버 안의 컨테이너끼리 통신하면 되니까. 하지만 Swarm처럼 여러 서버에 걸쳐 컨테이너가 분산 배포되면, 서로 다른 물리 서버의 컨테이너끼리도 통신해야 한다.

```
[문제 상황 — bridge 네트워크의 한계]

  node-1 (192.168.1.101)            node-2 (192.168.1.102)
  ┌─────────────────────┐           ┌─────────────────────────┐
  │  web-app (172.18.0.2)│           │  api-server (172.18.0.2) │
  │        │             │           │        │                │
  │  ── bridge ──        │           │  ── bridge ──           │
  └─────────────────────┘           └─────────────────────────┘

  172.18.0.2 → 172.18.0.2 ?  ← 같은 IP 대역인데 물리적으로 다른 서버. 통신 불가!
```

overlay 네트워크는 이 문제를 해결한다. 물리 네트워크 위에 가상 네트워크를 한 겹 덮어씌워서(overlay = 덮어씌우다), 서로 다른 서버의 컨테이너가 마치 같은 네트워크에 있는 것처럼 통신할 수 있게 만든다.

```
[해결 — overlay 네트워크]

  node-1 (192.168.1.101)            node-2 (192.168.1.102)
  ┌─────────────────────┐           ┌──────────────────────────┐
  │  web-app (10.0.1.3)  │           │  api-server (10.0.1.5)    │
  │        │             │           │        │                 │
  │  ══ overlay (10.0.1.0/24) ═══════════════════              │
  └─────────────────────┘           └──────────────────────────┘

  10.0.1.3 → 10.0.1.5  ← overlay 네트워크가 알아서 물리 서버를 넘어 전달!
```

overlay 네트워크에 속한 컨테이너는 서로 고유한 IP를 갖고, DNS 이름(서비스 이름)으로도 통신 가능하다. Swarm이 `docker service create` 시 자동으로 overlay 네트워크에 컨테이너를 연결해준다.

### VXLAN이란?

overlay 네트워크의 구현 기술이 VXLAN이다. 아이디어는 단순하다 — 컨테이너 패킷을 UDP로 한 번 더 감싸서 물리 네트워크로 보낸다.

```
[VXLAN 패킷 구조]

  컨테이너가 보낸 원본 패킷:
  ┌─────────────────────────────────────┐
  │ src: 10.0.1.3  dst: 10.0.1.5       │
  │ [HTTP 요청 데이터]                   │
  └─────────────────────────────────────┘
                    ↓ VXLAN 캡슐화
  ┌───────────────────────────────────────────────────────┐
  │ 외부 IP헤더                                            │
  │ src: 192.168.1.101  dst: 192.168.1.102                │
  │ ┌─────────────────────────────────────────────────┐   │
  │ │ UDP 헤더 (port 4789)                             │   │
  │ │ ┌─────────────────────────────────────────────┐ │   │
  │ │ │ VXLAN 헤더 (VNI: 네트워크 식별자)              │ │   │
  │ │ │ ┌─────────────────────────────────────────┐ │ │   │
  │ │ │ │ 원본 패킷                                │ │ │   │
  │ │ │ │ src: 10.0.1.3  dst: 10.0.1.5            │ │ │   │
  │ │ │ │ [HTTP 요청 데이터]                        │ │ │   │
  │ │ │ └─────────────────────────────────────────┘ │ │   │
  │ │ └─────────────────────────────────────────────┘ │   │
  │ └─────────────────────────────────────────────────┘   │
  └───────────────────────────────────────────────────────┘
```

흐름을 정리하면:

1. web-app(node-1)이 api-server(node-2)로 HTTP 요청을 보낸다
2. node-1의 VXLAN 모듈이 이 패킷을 UDP 4789 포트로 감싸서 node-2(192.168.1.102)로 전송한다
3. node-2의 VXLAN 모듈이 UDP 껍데기를 벗기고, 원본 패킷을 api-server 컨테이너에 전달한다

이 과정이 리눅스 커널 레벨에서 일어나기 때문에, 아래의 커널 모듈들이 반드시 로드되어 있어야 한다.

### 커널 모듈이란?

리눅스 커널은 모놀리식(monolithic)이지만, 모든 기능을 한꺼번에 메모리에 올리지는 않는다. 네트워크 필터링, 파일 시스템, 가상 네트워크 같은 기능은 **모듈(module)**이라는 단위로 분리되어 있고, 필요할 때만 커널에 로드한다.

```
[리눅스 커널 모듈 구조]

  ┌──────────────────────────────────────────────┐
  │                리눅스 커널                      │
  │                                              │
  │  ┌──────────┐ ┌──────────┐ ┌──────────┐      │
  │  │ 코어     │ │ 네트워크  │ │ 파일시스템│      │
  │  │ (항상    │ │ (항상    │ │ (항상    │      │
  │  │  로드됨) │ │  로드됨) │ │  로드됨) │      │
  │  └──────────┘ └──────────┘ └──────────┘      │
  │                                              │
  │  ┌─ 필요할 때 로드하는 모듈들 ──────────────┐   │
  │  │ br_netfilter │ vxlan │ overlay │ ip_vs │  │
  │  └──────────────────────────────────────┘   │
  └──────────────────────────────────────────────┘
```

Docker Swarm은 overlay 네트워크, 브릿지 방화벽, 로드밸런싱 같은 고급 네트워크 기능을 사용한다. 이 기능들은 커널에 기본 로드되어 있지 않으므로, 직접 로드해줘야 한다.

### 필요한 커널 모듈

#### 1) br_netfilter — 브릿지 방화벽 연동

Docker는 컨테이너를 연결할 때 리눅스 브릿지(bridge)를 사용한다. 브릿지는 가상 스위치처럼 동작해서 컨테이너들을 하나의 네트워크로 묶는다.

문제는, 브릿지를 통과하는 패킷은 기본적으로 iptables(방화벽) 규칙을 **무시**한다는 점이다. 브릿지는 L2(데이터링크 계층)에서 동작하고, iptables는 L3(네트워크 계층)에서 동작하기 때문이다.

```
[br_netfilter 없이]

  컨테이너 A ──→ bridge ──→ 컨테이너 B
                  │
                  ✕ iptables 규칙 무시 (L2 통과)

[br_netfilter 로드 후]

  컨테이너 A ──→ bridge ──→ iptables ──→ 컨테이너 B
                             │
                             ✓ 방화벽 규칙 적용 (포트 제한, NAT 등)
```

br_netfilter가 없으면 Docker의 포트 매핑(`-p 8080:80`), 서비스 디스커버리, 네트워크 격리가 전부 동작하지 않는다. Swarm에서 가장 중요한 모듈이다.

> Docker Engine 27.3.1+부터 `br_netfilter`를 자동 로드하지 않으므로 명시적 로드가 필수다.

#### 2) vxlan — VXLAN 캡슐화

overlay 네트워크의 핵심 모듈이다. 위에서 설명한 VXLAN 패킷 캡슐화/역캡슐화를 커널 레벨에서 처리한다. 이 모듈이 없으면 **서로 다른 노드의 컨테이너 간 통신이 불가능**하다.

```
node-1의 컨테이너 패킷 → vxlan 모듈이 UDP 4789로 캡슐화 → 물리 네트워크 전송
                                                              ↓
node-2의 vxlan 모듈이 역캡슐화 → node-2의 컨테이너에 전달
```

#### 3) overlay — OverlayFS 스토리지 드라이버

이름이 같아서 헷갈리지만, 이 모듈은 네트워크가 아니라 **파일 시스템** 모듈이다. Docker 이미지의 레이어 구조를 구현하는 OverlayFS를 지원한다.

```
[Docker 이미지 레이어 — OverlayFS]

  ┌────────────────────────┐  ← 컨테이너 쓰기 레이어 (upperdir)
  ├────────────────────────┤
  │  내 애플리케이션 코드     │  ← 이미지 레이어 3 (lowerdir)
  ├────────────────────────┤
  │  Node.js 런타임         │  ← 이미지 레이어 2 (lowerdir)
  ├────────────────────────┤
  │  Ubuntu 베이스 이미지    │  ← 이미지 레이어 1 (lowerdir)
  └────────────────────────┘

  OverlayFS가 이 레이어들을 합쳐서 하나의 파일 시스템으로 보여준다.
```

대부분의 Ubuntu 배포판에서 이미 로드되어 있지만, 명시적으로 로드해두면 확실하다.

#### 4) ip_vs 계열 — Swarm 내부 로드밸런싱

IPVS(IP Virtual Server)는 리눅스 커널에 내장된 L4 로드밸런서다. Swarm은 서비스에 요청이 들어오면 IPVS를 사용해서 여러 컨테이너(레플리카)에 트래픽을 분배한다.

```
[Swarm 내부 로드밸런싱 흐름]

  클라이언트 요청 (curl node-1:8080)
        │
        ▼
  ┌─────────────┐
  │  Swarm VIP   │  ← 가상 IP (10.0.0.100)
  │  (IPVS)      │
  └──────┬──────┘
         │ ip_vs가 트래픽 분배
    ┌────┼────┐
    ▼    ▼    ▼
  nginx  nginx  nginx
  .1     .2     .3
  (node-1) (node-2) (node-3)
```

| 모듈 | 분배 알고리즘 | 설명 |
|------|-------------|------|
| ip_vs | — | IPVS 코어 모듈. 나머지 알고리즘 모듈의 기반 |
| ip_vs_rr | 라운드로빈 | 순서대로 돌아가며 분배. Swarm 기본값 |
| ip_vs_wrr | 가중치 라운드로빈 | 노드별 가중치에 따라 분배. 성능 차이가 있는 서버 구성 시 유용 |
| ip_vs_sh | 소스 해시 | 같은 클라이언트 IP는 항상 같은 컨테이너로 보냄. 세션 유지에 사용 |

### modprobe란?

`modprobe`는 리눅스 커널 모듈을 로드하거나 제거하는 명령어다. 이름은 module + probe(탐색하다)의 합성어로, "모듈을 탐색해서 올려라"는 뜻이다.

#### 커널 모듈 관리 명령어 전체 그림

리눅스에는 커널 모듈을 다루는 명령어가 여러 개 있다. 각각의 역할을 먼저 정리하자.

| 명령어 | 역할 | 비유 |
|--------|------|------|
| `lsmod` | 현재 로드된 모듈 목록 조회 | "지금 설치된 프로그램 목록 보기" |
| `modinfo` | 모듈의 상세 정보 조회 (버전, 의존성, 설명) | "프로그램 정보 보기" |
| `insmod` | 모듈 하나를 직접 로드 (의존성 해결 안 함) | "수동 설치 — 필요한 라이브러리는 직접 챙겨야 함" |
| `rmmod` | 모듈 하나를 직접 제거 (의존성 확인 안 함) | "수동 삭제" |
| `modprobe` | 모듈을 **의존성 포함**해서 로드/제거 | "패키지 매니저 — 의존성 자동 해결" |
| `depmod` | 모듈 간 의존성 데이터베이스 갱신 | "패키지 인덱스 업데이트" |

핵심은 `insmod`/`rmmod`가 저수준 도구이고, `modprobe`가 이들을 감싸는 **고수준** 도구라는 점이다.

```
[커널 모듈 관리 계층]

  사용자
    │
    ▼
  modprobe (고수준 — 의존성 자동 해결)
    │
    │  의존성 DB 참조: /lib/modules/$(uname -r)/modules.dep
    │
    ▼
  insmod / rmmod (저수준 — 단일 모듈만 처리)
    │
    ▼
  리눅스 커널 (모듈 로드/언로드)
```

#### insmod vs modprobe — 왜 modprobe를 써야 하는가

`insmod`은 `.ko`(커널 오브젝트) 파일의 전체 경로를 지정해야 하고, 의존성을 해결하지 않는다.

```bash
# insmod — 전체 경로 필요, 의존성 해결 안 됨
sudo insmod /lib/modules/$(uname -r)/kernel/net/netfilter/ipvs/ip_vs_rr.ko
# → 에러: "Unknown symbol ip_vs_register_scheduler" (ip_vs 모듈이 먼저 필요)
```

`modprobe`는 모듈 이름만 주면 된다. 경로도 자동으로 찾고, 의존성도 알아서 해결한다.

```bash
# modprobe — 이름만 주면 의존성까지 자동 처리
sudo modprobe ip_vs_rr
# → ip_vs 모듈을 먼저 로드한 후, ip_vs_rr을 로드한다
```

실제로 어떤 의존성이 있는지 확인해볼 수 있다:

```bash
# 모듈의 의존성 확인
modinfo ip_vs_rr | grep depends
# depends: ip_vs

# 의존성 트리 전체 확인 (실제 로드하지 않고 미리보기)
modprobe --show-depends ip_vs_rr
# insmod /lib/modules/.../ip_vs.ko
# insmod /lib/modules/.../ip_vs_rr.ko
```

`modprobe --show-depends`를 쓰면 실제 로드하지 않고 어떤 순서로 무엇을 로드할지만 확인할 수 있다. 처음 다루는 모듈이라면 이 명령으로 먼저 확인하는 습관을 들이자.

#### modprobe의 내부 동작

`modprobe ip_vs_rr`을 실행하면 내부적으로 이런 과정이 일어난다:

```
[modprobe ip_vs_rr 실행 흐름]

  1) 의존성 DB 읽기
     /lib/modules/$(uname -r)/modules.dep 파일에서
     ip_vs_rr의 의존성 목록을 찾는다
         │
         ▼
  2) 의존성 트리 구성
     ip_vs_rr → ip_vs 필요
     ip_vs    → nf_conntrack 필요 (커널에 이미 내장된 경우 스킵)
         │
         ▼
  3) 바텀업 로드
     nf_conntrack (이미 로드됨 → 스킵)
     ip_vs        → insmod /lib/modules/.../ip_vs.ko
     ip_vs_rr     → insmod /lib/modules/.../ip_vs_rr.ko
         │
         ▼
  4) 설정 적용
     /etc/modprobe.d/*.conf 에서 해당 모듈의
     옵션(options), 별칭(alias), 블랙리스트 확인
         │
         ▼
  5) 완료 — lsmod에서 확인 가능
```

> `/lib/modules/$(uname -r)/`은 뭔가?
> 커널 모듈의 `.ko` 파일이 저장된 디렉토리다. `$(uname -r)`은 현재 커널 버전을 반환한다 (예: `6.8.0-45-generic`). 커널 업데이트 시 새 디렉토리가 생기고, `depmod`가 새 의존성 DB를 생성한다.

#### 자주 쓰는 modprobe 명령 정리

```bash
# 모듈 로드
sudo modprobe br_netfilter

# 모듈 제거 (-r = remove)
sudo modprobe -r br_netfilter

# 실제 로드하지 않고 의존성만 확인 (dry-run)
sudo modprobe --show-depends ip_vs_rr

# 모듈 상세 정보 확인 (modprobe가 아니라 modinfo)
modinfo br_netfilter

# 현재 로드된 모듈 확인
lsmod | grep br_netfilter
```

`lsmod` 출력을 읽는 방법도 알아두자:

```bash
lsmod | grep ip_vs
```

```
[lsmod 출력 해석]

  Module       Size     Used by
  ip_vs_rr     16384    0
  ip_vs_wrr    16384    0
  ip_vs_sh     16384    0
  ip_vs        212992   6    ip_vs_rr,ip_vs_wrr,ip_vs_sh,...
  │            │        │    │
  │            │        │    └─ 이 모듈을 사용 중인 다른 모듈 목록
  │            │        └─ 이 모듈을 참조하는 모듈 수 (0이면 제거 가능)
  │            └─ 메모리 사용량 (bytes)
  └─ 모듈 이름
```

`Used by`가 0이 아닌 모듈은 다른 모듈이 의존하고 있으므로 `modprobe -r`로 제거할 수 없다. 의존하는 모듈을 먼저 제거해야 한다.

**중요한 점**: `modprobe`로 로드한 모듈은 **메모리에만** 존재한다. 서버를 재부팅하면 사라진다. 그래서 2-2 단계에서 영구화 설정이 필요하다.

### 2-1. 즉시 로드

모든 노드에서 아래 명령을 실행한다. `modprobe`가 의존성을 자동으로 처리하므로 순서는 크게 상관없지만, 코어 모듈(`ip_vs`)을 먼저 로드하는 게 관례다.

```bash
sudo modprobe br_netfilter
sudo modprobe overlay
sudo modprobe vxlan
sudo modprobe ip_vs
sudo modprobe ip_vs_rr
sudo modprobe ip_vs_wrr
sudo modprobe ip_vs_sh
```

### 2-2. 재부팅 후에도 자동 로드 (영구화)

`modprobe`로 로드한 모듈은 재부팅 시 사라진다. `/etc/modules-load.d/` 디렉토리에 설정 파일을 만들어두면, 부팅 시 `systemd-modules-load` 서비스가 이 파일을 읽고 자동으로 모듈을 로드한다.

```
[영구화 동작 흐름]

  서버 부팅
    │
    ▼
  systemd-modules-load.service 시작
    │
    ▼
  /etc/modules-load.d/*.conf 파일 읽기
    │
    ▼
  각 줄의 모듈 이름으로 modprobe 실행
    │
    ▼
  br_netfilter, overlay, vxlan, ip_vs, ... 로드 완료
```

아래 명령을 한 줄씩 뜯어보자.

```bash
cat <<EOF | sudo tee /etc/modules-load.d/docker-swarm.conf
br_netfilter
overlay
vxlan
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
EOF
```

이 명령은 셸의 **Heredoc**과 파이프, `tee`를 조합한 패턴이다. 리눅스 설정 파일을 만들 때 가장 많이 쓰는 방식이므로 익혀두면 좋다.

```
[명령어 분해]

  cat <<EOF                     │  "EOF가 나올 때까지의 텍스트를 그대로 출력해라"
  br_netfilter                  │
  overlay                       │
  vxlan                         │  ← 이 7줄이 cat의 입력(stdin)으로 들어간다
  ip_vs                         │
  ip_vs_rr                      │
  ip_vs_wrr                     │
  ip_vs_sh                      │
  EOF                           │  "여기서 끝"
       │
       │ 파이프 (|) — cat의 출력을 tee의 입력으로 전달
       ▼
  sudo tee /etc/modules-load.d/docker-swarm.conf
       │
       │  tee는 두 가지를 동시에 한다:
       │  1) 받은 내용을 지정한 파일에 쓴다
       │  2) 받은 내용을 터미널(stdout)에도 출력한다
       ▼
  /etc/modules-load.d/docker-swarm.conf 파일 생성!
```

> **왜 `sudo echo > 파일`이 아니라 `sudo tee`를 쓰는가?**
> `sudo echo "내용" > /etc/modules-load.d/docker-swarm.conf`를 하면 **권한 에러**가 난다. `sudo`는 `echo`에만 적용되고, `>` 리다이렉션은 현재 사용자 권한으로 실행되기 때문이다. `tee` 명령 자체에 `sudo`를 붙이면 파일 쓰기까지 root 권한으로 처리된다.

생성된 파일의 내용은 단순하다. 한 줄에 모듈 이름 하나씩:

```
# /etc/modules-load.d/docker-swarm.conf
br_netfilter
overlay
vxlan
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
```

#### /etc/modules-load.d/ 디렉토리의 규칙

이 디렉토리는 `systemd-modules-load` 서비스가 관리한다. 알아둘 규칙은 세 가지다:

| 규칙 | 설명 |
|------|------|
| 파일명은 `.conf`로 끝나야 한다 | `.conf`가 아닌 파일은 무시된다 |
| 한 줄에 모듈 이름 하나 | 옵션이나 인자는 쓸 수 없다. 모듈 옵션이 필요하면 `/etc/modprobe.d/`에 별도 설정 |
| `#`으로 시작하는 줄은 주석 | 비활성화할 모듈은 삭제 대신 주석 처리하면 편하다 |

파일명은 자유롭게 지을 수 있다. 여기서는 `docker-swarm.conf`로 지었지만, 용도만 알 수 있으면 된다. 시스템에 이미 다른 `.conf` 파일이 있어도 충돌하지 않는다 — `systemd-modules-load`는 디렉토리 안의 모든 `.conf` 파일을 읽고 합쳐서 처리한다.

```bash
# 기존 파일 확인 — 다른 서비스가 만든 .conf 파일이 있을 수 있다
ls /etc/modules-load.d/
```

#### 영구화가 제대로 됐는지 확인하는 방법

파일을 만들었다고 끝이 아니다. 재부팅 없이도 제대로 작성됐는지 검증할 수 있다.

```bash
# 1. 파일 내용 확인
cat /etc/modules-load.d/docker-swarm.conf

# 2. systemd 서비스로 직접 테스트 (재부팅 없이 영구화 설정 검증)
sudo systemctl restart systemd-modules-load

# 3. 에러가 있으면 여기서 확인
sudo systemctl status systemd-modules-load
```

정상이면 `Active: active (exited)` 상태가 보인다. 모듈 이름에 오타가 있으면 이 단계에서 에러 로그가 남는다.

### 2-3. 확인

```bash
lsmod | grep -E "br_netfilter|overlay|vxlan|ip_vs"
```

예상 출력:

```
br_netfilter           32768  0
overlay               212992  0
vxlan                  98304  0
ip_vs_sh               16384  0
ip_vs_wrr              16384  0
ip_vs_rr               16384  0
ip_vs                 176128  6 ip_vs_sh,ip_vs_wrr,ip_vs_rr
```

---

## Step 3: sysctl 네트워크 파라미터 설정

**왜 필요한가?** 리눅스는 보안상 기본적으로 브릿지 네트워크의 패킷이 iptables를 거치지 않는다. 이 설정을 켜야 컨테이너 간 방화벽 규칙이 제대로 동작하고, IP 포워딩이 활성화되어 컨테이너가 외부 네트워크와 통신할 수 있다.

> **주의**: `br_netfilter` 모듈이 로드된 상태에서만 `net.bridge.*` 키가 존재한다. **Step 2를 먼저 완료**해야 한다.

### 3-1. 설정 파일 생성

```bash
cat <<EOF | sudo tee /etc/sysctl.d/99-docker-swarm.conf
# 컨테이너 라우팅에 필요한 IP 포워딩
net.ipv4.ip_forward = 1

# 브릿지 패킷이 iptables를 통과하도록 설정
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
```

### 3-2. 즉시 적용

```bash
sudo sysctl --system
```

### 3-3. 확인

```bash
sysctl net.ipv4.ip_forward
sysctl net.bridge.bridge-nf-call-iptables
```

예상 출력:

```
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
```

---

## Step 4: Docker daemon.json 설정

`daemon.json`은 Docker 데몬(백그라운드 서비스) 전체 동작 방식을 설정하는 파일이다. 기본값만으로도 Swarm은 동작하지만, 운영 환경에서는 아래 설정이 없으면 **로그 파일이 디스크를 꽉 채우는** 문제가 생긴다.

**모든 노드**에서 실행한다.

```bash
sudo tee /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "metrics-addr": "127.0.0.1:9323"
}
EOF
```

각 설정의 역할:

| 설정 | 기본값 | 역할 |
|------|--------|------|
| log-driver: json-file | json-file | 로그를 JSON 파일로 저장 |
| max-size: 10m | **무제한** | 로그 파일 1개당 최대 10MB. 이게 없으면 로그가 디스크를 꽉 채운다 |
| max-file: 3 | 1 | 로그 파일을 최대 3개까지 보관 (총 30MB 한도) |
| metrics-addr | 비활성 | Prometheus 메트릭 노출 엔드포인트. 모니터링 연동 시 사용 |

적용:

```bash
sudo systemctl restart docker
```

> **`live-restore`와 Swarm — 주의!**
> `"live-restore": true` 옵션은 Docker 데몬 재시작 시 컨테이너를 살려두는 기능이다. 단독 컨테이너에서는 유용하지만, **Swarm 모드에서는 호환되지 않는다**. Docker 공식 문서에 명시: "live restore only pertains to standalone containers, not Swarm services." **Swarm 클러스터의 daemon.json에는 `live-restore`를 설정하지 않는다.**

> **`storage-driver` 참고**
> Docker Engine 29.0+부터 신규 설치 시 containerd image store가 기본값이다. 기존의 `"storage-driver": "overlay2"` 설정은 레거시이므로, 신규 설치에서는 별도 지정하지 않는 것이 권장된다.

---

## Step 5: 방화벽 포트 설정

Docker Swarm은 노드 간 통신에 아래 3개 포트를 사용한다.

| 포트 | 프로토콜 | 방향 | 역할 | 필요한 노드 |
|------|----------|------|------|-------------|
| 2377 | TCP | Inbound | 클러스터 관리 (Swarm init/join, Raft 합의) | Manager 노드 |
| 7946 | TCP + UDP | Inbound | 노드 간 gossip (상태 공유, 서비스 디스커버리) | 모든 노드 |
| 4789 | UDP | Inbound | VXLAN overlay 네트워크 데이터 전송 | 모든 노드 |

비유: 2377은 "사령부 통신선", 7946은 "노드끼리 수다 채널", 4789는 "컨테이너 데이터 고속도로"다.

> **encrypted overlay 사용 시**: `--opt encrypted` 옵션으로 overlay 네트워크를 암호화하면 **IP protocol 50 (ESP)**도 추가로 허용해야 한다. UFW에서는 `sudo ufw allow proto esp from <노드대역>`으로 설정한다.

### UFW를 사용하는 경우

```bash
# 모든 노드에서 실행
sudo ufw allow 7946/tcp comment 'Docker Swarm gossip'
sudo ufw allow 7946/udp comment 'Docker Swarm gossip'
sudo ufw allow 4789/udp comment 'Docker Swarm overlay VXLAN'

# Manager 노드에서만 실행
sudo ufw allow 2377/tcp comment 'Docker Swarm management'

sudo ufw reload
sudo ufw status
```

### UFW가 비활성화된 경우 (개발/내부망)

```bash
sudo ufw status
# Status: inactive
```

내부 개발망에서 UFW가 꺼져 있다면 별도 포트 개방 없이 진행해도 된다. 단, **운영 환경에서는 반드시 방화벽을 설정**해야 한다.

---

## Step 6: Swarm 초기화

이제 실제 Swarm 클러스터를 구성한다.

### 6-1. Manager 초기화 (node-1에서만 실행)

```bash
docker swarm init --advertise-addr 192.168.1.101
```

`--advertise-addr`는 다른 노드들이 이 Manager에 접속할 IP를 지정한다. 서버에 네트워크 인터페이스가 여러 개라면 **반드시** 명시해야 한다. 단일 IP 서버에서는 생략해도 Docker가 자동 감지하지만, **명시하는 것이 안전**하다.

예상 출력:

```
Swarm initialized: current node (abc123xyz) is now a manager.

To add a worker to this swarm, run the following command:

    docker swarm join --token SWMTKN-1-xxxxxx-worker-token 192.168.1.101:2377

To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.
```

### 6-2. Manager join 토큰 확인

이 예제에서는 3대 모두 Manager로 구성한다. Manager join 토큰을 확인한다.

```bash
# node-1에서 실행
docker swarm join-token manager
```

예상 출력:

```
To add a manager to this swarm, run the following command:

    docker swarm join --token SWMTKN-1-xxxxxx-manager-token 192.168.1.101:2377
```

> **토큰 보안**: join 토큰은 비밀번호와 같다. 이 토큰을 가진 사람은 누구든 클러스터에 노드를 추가할 수 있다. 외부에 노출되지 않도록 주의하고, **주기적으로 교체**한다.
>
> ```bash
> docker swarm join-token --rotate manager  # Manager 토큰 교체
> docker swarm join-token --rotate worker   # Worker 토큰 교체
> ```

### 6-3. node-2, node-3을 Manager로 합류

**node-2**에서 실행:

```bash
docker swarm join \
  --token SWMTKN-1-xxxxxx-manager-token \
  192.168.1.101:2377
```

**node-3**에서 실행:

```bash
docker swarm join \
  --token SWMTKN-1-xxxxxx-manager-token \
  192.168.1.101:2377
```

> 네트워크 인터페이스가 여러 개인 서버에서는 `--advertise-addr <해당노드IP>`를 추가한다.

예상 출력:

```
This node joined a swarm as a manager.
```

### Worker 노드를 추가하는 경우

Manager가 아닌 Worker 노드를 추가할 때는 Worker 토큰을 사용한다.

```bash
# node-1에서 Worker 토큰 확인
docker swarm join-token worker

# Worker 노드에서 실행
docker swarm join \
  --token SWMTKN-1-xxxxxx-worker-token \
  192.168.1.101:2377
```

---

## Step 7: 검증

### 7-1. 노드 상태 확인

node-1(또는 아무 Manager 노드)에서 실행:

```bash
docker node ls
```

예상 출력:

```
ID                            HOSTNAME   STATUS    AVAILABILITY   MANAGER STATUS   ENGINE VERSION
abc123xyz *                   node-1     Ready     Active         Leader           29.3.1
def456uvw                     node-2     Ready     Active         Reachable        29.3.1
ghi789rst                     node-3     Ready     Active         Reachable        29.3.1
```

모든 노드가 `STATUS: Ready`, `MANAGER STATUS: Leader/Reachable`이면 정상이다.

### 7-2. overlay 네트워크 생성 테스트

```bash
docker network create --driver overlay test-overlay
docker network ls | grep overlay
```

예상 출력:

```
abc123def456   test-overlay    overlay   swarm
ingress         ingress         overlay   swarm
```

### 7-3. 테스트 서비스 배포

```bash
docker service create \
  --name test-nginx \
  --replicas 3 \
  --network test-overlay \
  -p 8080:80 \
  nginx:latest
```

```bash
docker service ls
```

예상 출력:

```
ID             NAME         MODE         REPLICAS   IMAGE          PORTS
aaaabbbbcccc   test-nginx   replicated   3/3        nginx:latest   *:8080->80/tcp
```

`REPLICAS`가 `3/3`이면 3개 컨테이너가 모두 정상 실행 중이다.

```bash
docker service ps test-nginx
```

예상 출력:

```
ID             NAME             IMAGE          NODE     DESIRED STATE   CURRENT STATE
xxx111yyy222   test-nginx.1     nginx:latest   node-1   Running         Running 30 seconds ago
zzz333www444   test-nginx.2     nginx:latest   node-2   Running         Running 28 seconds ago
aaa555bbb666   test-nginx.3     nginx:latest   node-3   Running         Running 26 seconds ago
```

각 노드에 1개씩 분산 배포된 것을 확인할 수 있다. 아무 노드에서나 `curl localhost:8080`을 실행하면 nginx 응답이 온다 — 어느 노드에서 요청해도 Swarm의 내부 로드밸런서가 알아서 처리한다.

**테스트 후 정리:**

```bash
docker service rm test-nginx
docker network rm test-overlay
```

---

## 자주 하는 실수 & 트러블슈팅

### 실수 1: --advertise-addr 누락

**증상**: 노드가 join은 됐는데 overlay 네트워크로 컨테이너 간 통신이 안 됨.

**원인**: Docker가 잘못된 IP를 advertise-addr로 선택 (예: loopback 127.0.0.1).

**해결**: `docker node inspect self | grep Addr`으로 현재 advertise-addr 확인 후, 클러스터를 다시 만들거나 노드를 제거 후 재join.

```bash
docker swarm leave --force   # 해당 노드에서
docker swarm join --advertise-addr <올바른 IP> --token <TOKEN> <MANAGER_IP>:2377
```

### 실수 2: br_netfilter 미로드 상태에서 sysctl 적용

**증상**: `sysctl net.bridge.bridge-nf-call-iptables` 설정이 안 먹히거나, 재부팅 후 컨테이너 네트워크가 깨짐.

**원인**: `br_netfilter`가 로드되지 않으면 `net.bridge.*` sysctl 키 자체가 존재하지 않아 설정이 무시됨.

**해결**: Step 2(커널 모듈 로드)를 먼저 완료한 후 Step 3(sysctl)을 적용한다. `/etc/modules-load.d/`에 모듈이 등록되어 있는지 확인.

```bash
cat /etc/modules-load.d/docker-swarm.conf
lsmod | grep br_netfilter
```

### 실수 3: MTU 불일치로 인한 패킷 손실

**증상**: 같은 서버의 컨테이너 간 통신은 되는데, 서로 다른 서버의 컨테이너 간 통신이 간헐적으로 끊김.

**원인**: VXLAN은 패킷에 50바이트 오버헤드를 추가한다. 호스트 MTU가 1500이면 overlay 네트워크의 MTU는 1450이어야 하는데, 기본값이 1500으로 잡히면 큰 패킷이 잘림.

**해결**: overlay 네트워크 생성 시 MTU를 명시하거나, daemon.json에 기본 MTU를 설정.

```bash
# 네트워크 생성 시
docker network create \
  --driver overlay \
  --opt com.docker.network.driver.mtu=1450 \
  my-network
```

### 실수 4: Manager가 짝수 대 (quorum 상실)

**증상**: Manager 1대가 죽자 클러스터 전체가 먹통이 됨.

**원인**: Manager 2대 구성에서는 1대가 죽으면 과반수(2/2)를 유지 못해 Raft 합의 불가.

**해결**: Manager는 항상 **홀수**로 구성한다. 최소 3대.

| Manager 수 | 허용 장애 수 |
|-----------|-------------|
| 1 | 0 |
| 3 | 1 |
| 5 | 2 |
| 7 | 3 |

### 실수 5: Docker 버전 불일치

**증상**: 노드 join은 됐는데 서비스가 이상하게 동작하거나, 알 수 없는 에러 발생.

**원인**: 노드마다 Docker 버전이 달라 기능 호환성 문제 발생.

**해결**: 모든 노드를 **동일한 Docker 버전**으로 맞춘다.

```bash
# 모든 노드에서 버전 확인
docker version --format '{{.Server.Version}}'
```

### 실수 6: live-restore를 Swarm에서 사용

**증상**: 서비스 업데이트/롤백이 비정상 동작하거나, Task가 예상대로 스케줄링되지 않음.

**원인**: `daemon.json`에 `"live-restore": true`를 설정한 경우. 이 옵션은 standalone 컨테이너 전용이며 **Swarm 모드와 호환되지 않는다**.

**해결**: `daemon.json`에서 `live-restore` 항목을 제거하고 Docker를 재시작한다.

```bash
# daemon.json에서 live-restore 제거 후
sudo systemctl restart docker
```

---

## 긴급 복구: Quorum 상실 후 클러스터 재건

Manager 과반수가 동시에 죽어서 클러스터 운영이 불가한 경우, 남은 Manager 1대에서 **강제로** 새 클러스터를 만들 수 있다.

```bash
# 데이터 백업 먼저!
sudo tar -czf swarm-backup-$(date +%Y%m%d).tar.gz /var/lib/docker/swarm/

# 강제 재초기화 (단일 Manager로 새 클러스터 시작)
docker swarm init --force-new-cluster --advertise-addr <이 노드의 IP>

# 이후 나머지 노드들을 다시 join
```

> **주의**: 이 명령은 기존 Raft 상태를 버리고 새로 시작하는 것이다. 진행 중이던 서비스 상태는 초기화될 수 있다.

---

## 전체 체크리스트

셋팅 완료 후 아래 항목을 순서대로 확인한다.

```
[ ] 모든 노드에 Docker 29+ 설치 확인 (docker --version)
[ ] 모든 노드에서 docker compose 동작 확인 (docker compose version)
[ ] 모든 노드에서 br_netfilter, vxlan, ip_vs 모듈 로드 확인 (lsmod)
[ ] /etc/modules-load.d/docker-swarm.conf 파일 존재 확인
[ ] sysctl net.ipv4.ip_forward = 1 확인
[ ] sysctl net.bridge.bridge-nf-call-iptables = 1 확인
[ ] /etc/docker/daemon.json 설정 및 docker restart 완료
[ ] daemon.json에 live-restore가 없는지 확인
[ ] docker swarm init 완료 (node-1)
[ ] node-2, node-3 join 완료
[ ] docker node ls — 3대 모두 Ready / Reachable 확인
[ ] overlay 네트워크 생성 및 테스트 서비스 배포 확인
```

---

## 요약

- Ubuntu 서버에서 Swarm 셋업은 `docker swarm init`만으로 끝나지 않는다
- **커널 모듈**(br_netfilter, vxlan, overlay, ip_vs 계열)과 **sysctl 파라미터**가 사전 준비되어야 overlay 네트워크가 정상 동작한다
- `daemon.json`에서 로그 로테이션 필수, **`live-restore`는 Swarm에서 사용 금지**
- 방화벽 포트 3종(2377, 7946, 4789) 개방 필수
- Manager는 **홀수**(최소 3대)로 구성, `--advertise-addr`는 명시 권장

---

## 다음 편 예고

클러스터가 준비되었으니, 다음 편에서는 실제로 서비스를 배포하고 관리하는 방법을 배운다.
`docker service create`로 첫 서비스를 띄우고, 복제본(replicas), 스케일링, 로그 확인까지 진행한다.

→ **[03편: 서비스(Service) 기초](03-service-basics.md)**

---

## 참고 자료

- [Docker Engine 설치 — Ubuntu](https://docs.docker.com/engine/install/ubuntu/) — 공식 설치 가이드 (Ubuntu 24.04 LTS)
- [Overlay 네트워크 드라이버](https://docs.docker.com/engine/network/drivers/overlay/) — docs.docker.com
- [docker swarm init 레퍼런스](https://docs.docker.com/reference/cli/docker/swarm/init/) — docs.docker.com
- [daemon.json 설정 레퍼런스](https://docs.docker.com/reference/cli/dockerd/#daemon-configuration-file) — docs.docker.com
- [Swarm 운영 가이드](https://docs.docker.com/engine/swarm/admin_guide/) — docs.docker.com
