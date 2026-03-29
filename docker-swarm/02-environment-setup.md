# Swarm 클러스터 구축하기 — init부터 join까지

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [01편: Docker Swarm이란?](01-what-is-docker-swarm.md)
> **시리즈**: Docker Swarm 학습 가이드 2/11

---

## 개요

이 편에서는 실제로 Docker Swarm 클러스터를 만들어봅니다.
Manager 1개 + Worker 2개, 총 3노드 구성을 목표로 합니다.
실습 환경은 **Docker-in-Docker(dind)** 방식으로 단일 머신에서도 따라할 수 있습니다.

---

## 실습 환경 선택

| 방법 | 장점 | 단점 | 추천 대상 |
|------|------|------|----------|
| **Docker-in-Docker** | 로컬 1대로 가능 | 프로덕션과 차이 있음 | 학습용 ✅ |
| **Multipass VM** | 실제 VM 환경 | VM 설치 필요 | 실무 연습 |
| **클라우드 서버** | 실제 환경과 동일 | 비용 발생 | 프로덕션 전 테스트 |

이 가이드는 **Docker-in-Docker** 방식으로 진행합니다.

---

## 필요한 포트 (방화벽 설정 시 참고)

```
┌─────────────────────────────────────────────────────┐
│             Swarm 통신에 필요한 포트                  │
│                                                     │
│  2377/TCP  ← Manager 노드 간 통신 (클러스터 관리)    │
│  7946/TCP  ← 노드 헬스 체크 및 노드 디스커버리       │
│  7946/UDP  ← 노드 헬스 체크 및 노드 디스커버리       │
│  4789/UDP  ← Overlay 네트워크 트래픽 (VXLAN)        │
└─────────────────────────────────────────────────────┘
```

---

## 실습: 3노드 클러스터 구축

### Step 1 — 네트워크 준비

```bash
# Swarm 노드들이 통신할 전용 네트워크 생성
docker network create --driver bridge swarm-net
```

### Step 2 — Manager 노드 실행

```bash
docker run -d \
  --name manager1 \
  --hostname manager1 \
  --network swarm-net \
  --privileged \
  -p 8080:80 \
  docker:dind

# Manager 노드 IP 확인
docker inspect manager1 \
  --format '{{ .NetworkSettings.Networks.swarm-net.IPAddress }}'
```

### Step 3 — Worker 노드 실행

```bash
docker run -d \
  --name worker1 \
  --hostname worker1 \
  --network swarm-net \
  --privileged \
  docker:dind

docker run -d \
  --name worker2 \
  --hostname worker2 \
  --network swarm-net \
  --privileged \
  docker:dind
```

### Step 4 — Swarm 초기화 (Manager에서)

```bash
# manager1 컨테이너 안으로 들어가기
docker exec -it manager1 sh

# Swarm 초기화
docker swarm init --advertise-addr $(hostname -i)
```

**출력 결과 예시**:
```
Swarm initialized: current node (abc123...) is now a manager.

To add a worker to this swarm, run the following command:

    docker swarm join --token SWMTKN-1-49nj1cmql0jk...8vxv8rssmk743ojnwacrr2e7c 172.20.0.2:2377

To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.
```

> 💡 이 join 토큰을 복사해두세요! Worker 노드 추가에 필요합니다.

### Step 5 — Worker 노드 참가

```bash
# worker1 컨테이너 안으로 들어가기 (새 터미널)
docker exec -it worker1 sh

# Swarm에 참가 (앞서 복사한 토큰 사용)
docker swarm join \
  --token SWMTKN-1-49nj1cmql0jk...8vxv8rssmk743ojnwacrr2e7c \
  172.20.0.2:2377
```

```bash
# worker2도 동일하게 (새 터미널)
docker exec -it worker2 sh
docker swarm join \
  --token SWMTKN-1-49nj1cmql0jk...8vxv8rssmk743ojnwacrr2e7c \
  172.20.0.2:2377
```

### Step 6 — 클러스터 상태 확인

```bash
# manager1 컨테이너에서 실행
docker node ls
```

**예상 출력**:
```
ID                            HOSTNAME   STATUS    AVAILABILITY   MANAGER STATUS
abc123def456 *                manager1   Ready     Active         Leader
xyz789ghi012                  worker1    Ready     Active
mno345pqr678                  worker2    Ready     Active
```

```
✅ STATUS: Ready   → 노드 정상
✅ AVAILABILITY: Active → 작업 배분 가능
⭐ MANAGER STATUS: Leader → 현재 리더 Manager
```

---

## 유용한 관리 명령어

```bash
# join 토큰 재확인 (토큰을 잊었을 때)
docker swarm join-token worker    # Worker 토큰
docker swarm join-token manager   # Manager 토큰

# 노드 상세 정보
docker node inspect manager1 --pretty

# 노드를 드레인 모드로 (유지보수 시 — 기존 Task 다른 노드로 이전)
docker node update --availability drain worker1

# 일시 정지 모드 (새 Task 배분 안 함, 기존 Task는 유지)
docker node update --availability pause worker1

# 다시 활성화
docker node update --availability active worker1

# Swarm에서 노드 제거 (Worker에서 먼저 실행)
docker swarm leave
# Manager에서 노드 삭제
docker node rm worker1
```

---

## 클러스터 구성도 확인

```
현재 구축된 클러스터:
┌─────────────────────────────────────────────┐
│              swarm-net (bridge)             │
│                                             │
│  ┌─────────────────┐                        │
│  │    manager1     │ ← Leader Manager       │
│  │  172.20.0.2     │   docker swarm init    │
│  └────────┬────────┘                        │
│           │ join                            │
│  ┌────────┴──────────────────────┐          │
│  │  ┌──────────┐  ┌──────────┐  │          │
│  │  │ worker1  │  │ worker2  │  │          │
│  │  │172.20.0.3│  │172.20.0.4│  │          │
│  │  └──────────┘  └──────────┘  │          │
│  └───────────────────────────────┘          │
└─────────────────────────────────────────────┘
```

---

## 요약

- `docker swarm init --advertise-addr <IP>` — 클러스터 초기화 (Manager)
- `docker swarm join --token <TOKEN> <IP>:2377` — 클러스터 참가 (Worker)
- `docker node ls` — 클러스터 노드 상태 확인
- 방화벽에서 2377, 7946, 4789 포트 허용 필요
- 노드 availability: `active`(정상), `pause`(신규 Task 중단), `drain`(기존 Task 이전)

---

## 다음 편 예고

클러스터가 준비됐으니, 이제 실제 서비스를 배포해봅니다.
`docker service create` 명령으로 컨테이너를 여러 노드에 분산 배포합니다.

→ **[03편: 서비스(Service) 기초](03-service-basics.md)**

---

## 참고 자료

- [Swarm Tutorial 공식 문서](https://docs.docker.com/engine/swarm/swarm-tutorial/) — docs.docker.com
- [Swarm 클러스터 생성](https://docs.docker.com/engine/swarm/swarm-tutorial/create-swarm/) — docs.docker.com
