# 서비스(Service) 기초 — 컨테이너를 선언적으로 관리하기

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [02편: Swarm 클러스터 구축하기](02-environment-setup.md)
> **시리즈**: Docker Swarm 학습 가이드 3/11

---

## 개요

`docker run`은 컨테이너 1개를 직접 실행합니다.
Swarm의 **Service**는 "nginx 3개를 항상 실행 상태로 유지해줘"처럼 **원하는 상태를 선언**합니다.
노드가 죽어도 Swarm이 알아서 다른 노드에서 재시작해줍니다.

---

## Service vs Container 차이

```
docker run (일반 컨테이너):
  ┌────────────┐
  │ Container  │  ← 내가 직접 실행/중지
  └────────────┘    노드 죽으면? 그냥 죽음 💀

docker service create (Swarm Service):
  ┌──────────────────────────────────────┐
  │           Service: nginx             │
  │  목표: replicas=3                    │
  │                                      │
  │  [Task1:nginx] → worker1             │
  │  [Task2:nginx] → worker2     ← Swarm │
  │  [Task3:nginx] → manager1      이    │
  │                                관리  │
  │  worker1 죽으면? → worker2에 재배치! │
  └──────────────────────────────────────┘
```

---

## Service 핵심 명령어

### 서비스 생성

```bash
# 기본 생성
docker service create --name my-nginx nginx

# 복제본(replicas) 수 지정
docker service create \
  --name my-nginx \
  --replicas 3 \
  nginx

# 포트 노출 + 복제본 수 지정
docker service create \
  --name my-web \
  --replicas 3 \
  --publish published=8080,target=80 \
  nginx
```

### 서비스 목록 확인

```bash
docker service ls
```

```
ID             NAME       MODE         REPLICAS   IMAGE          PORTS
xyzabc123def   my-web     replicated   3/3        nginx:latest   *:8080->80/tcp
```

> `3/3` → 목표 3개, 현재 실행 중 3개 ✅
> `2/3` → 목표 3개, 현재 2개 실행 중 (1개 시작 중 또는 장애)

### Task(컨테이너) 상태 확인

```bash
# 서비스의 Task 목록
docker service ps my-web
```

```
ID            NAME        IMAGE          NODE      DESIRED STATE   CURRENT STATE
abc1def2ghi3  my-web.1   nginx:latest   manager1  Running         Running 2 min
jkl4mno5pqr6  my-web.2   nginx:latest   worker1   Running         Running 2 min
stu7vwx8yz90  my-web.3   nginx:latest   worker2   Running         Running 2 min
```

---

## Replicated vs Global 모드

```
Replicated (기본):              Global:
replica=3으로 설정 시           노드마다 1개씩 실행

  manager1: [Task]              manager1: [Task]
  worker1:  [Task]              worker1:  [Task]
  worker2:  [Task]              worker2:  [Task]
  (총 3개 — 지정한 수만큼)       (노드 추가 시 자동 배포)
```

**Global 모드 사용 예시** (모든 노드에 모니터링 에이전트 배포):

```bash
docker service create \
  --name node-exporter \
  --mode global \
  prom/node-exporter
```

---

## 실습: 서비스 장애 복구 확인

Swarm의 핵심 기능인 **자동 복구**를 직접 확인해봅니다.

```bash
# Step 1: 서비스 생성
docker service create \
  --name resilient-nginx \
  --replicas 3 \
  nginx

# Step 2: Task가 어떤 노드에 배치됐는지 확인
docker service ps resilient-nginx

# Step 3: worker1을 강제 중지 (장애 시뮬레이션)
docker stop worker1

# Step 4: 잠시 후 Task 상태 재확인 (다른 노드로 자동 이동!)
watch docker service ps resilient-nginx
```

**예상 결과**:
```
NAME              NODE      DESIRED STATE   CURRENT STATE
resilient-nginx.1 manager1  Running         Running
resilient-nginx.2 worker1   Shutdown        Failed       ← 장애!
resilient-nginx.2 worker2   Running         Running      ← 자동 재배치!
resilient-nginx.3 worker2   Running         Running
```

> 💡 Task는 같은 ID로 이전되지 않고, 새 Task가 다른 노드에 생성됩니다.

---

## 서비스 스케일 조정

```bash
# 방법 1: scale 명령
docker service scale my-web=5

# 방법 2: update 명령
docker service update --replicas 5 my-web

# 확인
docker service ls
# my-web: 5/5 로 변경됨
```

---

## 서비스 제거

```bash
# 서비스 삭제 (모든 Task도 함께 삭제)
docker service rm my-web

# 여러 서비스 동시 삭제
docker service rm my-web my-nginx node-exporter
```

---

## 자주 쓰는 서비스 명령어 정리

```bash
# 생성
docker service create --name <이름> --replicas <수> <이미지>

# 목록
docker service ls

# Task 상태
docker service ps <이름>

# 상세 정보
docker service inspect <이름> --pretty

# 로그 확인
docker service logs <이름>

# 스케일 조정
docker service scale <이름>=<수>

# 삭제
docker service rm <이름>
```

---

## 요약

- **Service** = "이 상태를 항상 유지해줘"라는 선언적 명세
- **Task** = 실제 실행 중인 컨테이너 1개 (Swarm이 자동 관리)
- **Replicated** 모드: 지정한 수만큼 복제본 유지
- **Global** 모드: 모든 노드에 1개씩 배포 (모니터링 에이전트 등에 유용)
- 노드 장애 시 Swarm이 자동으로 다른 노드에 Task 재배치

---

## 다음 편 예고

서비스들이 서로 통신하려면 어떻게 할까요?
Swarm의 Overlay 네트워크와 서비스 디스커버리를 알아봅니다.

→ **[04편: 네트워크 이해하기](04-networking.md)**

---

## 참고 자료

- [Docker Swarm Services 공식 문서](https://docs.docker.com/engine/swarm/services/) — docs.docker.com
- [Docker Swarm Key Concepts](https://docs.docker.com/engine/swarm/key-concepts/) — docs.docker.com
