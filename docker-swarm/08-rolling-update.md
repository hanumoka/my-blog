# 롤링 업데이트와 롤백 — 무중단 배포 구현하기

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [07편: Secrets & Configs](07-secrets-and-configs.md)
> **시리즈**: Docker Swarm 학습 가이드 8/11

---

## 개요

새 버전 배포 시 서비스를 중단하지 않는 것이 운영의 핵심입니다.
Swarm의 **롤링 업데이트**는 Task를 순서대로 교체해 무중단 배포를 구현합니다.
문제가 생기면 **롤백**으로 이전 버전으로 즉시 되돌립니다.

---

## 롤링 업데이트란?

```
replicas=4, 업데이트 parallelism=1:

  Before:  [v1] [v1] [v1] [v1]

  Step 1:  [v2] [v1] [v1] [v1]   ← Task 1 교체 (10초 대기)
  Step 2:  [v2] [v2] [v1] [v1]   ← Task 2 교체 (10초 대기)
  Step 3:  [v2] [v2] [v2] [v1]   ← Task 3 교체 (10초 대기)
  Step 4:  [v2] [v2] [v2] [v2]   ← 완료!

  → 항상 최소 3개의 서비스가 실행 중!
```

---

## update_config 옵션 설명

```yaml
deploy:
  update_config:
    parallelism: 2        # 동시에 교체할 Task 수
    delay: 10s            # 배치 간 대기 시간
    failure_action: rollback  # pause | continue | rollback
    monitor: 30s          # 업데이트 후 실패 모니터링 시간
    max_failure_ratio: 0.1    # 허용 실패율 (0.1 = 10%)
    order: start-first    # start-first | stop-first
```

```
order: stop-first (기본):     order: start-first (권장):
  기존 종료 → 신규 시작          신규 시작 → 기존 종료
  ┌────────────────────┐        ┌────────────────────┐
  │ [v1] stop          │        │ [v2] start         │
  │   ↓                │        │   ↓                │
  │ [v2] start         │        │ [v1] stop          │
  └────────────────────┘        └────────────────────┘
  ⚠️ 잠깐 replica 감소          ✅ 항상 충분한 replica 유지
```

---

## 실습: 롤링 업데이트

```bash
# Step 1: v1 서비스 생성 (업데이트 설정 포함)
docker service create \
  --name my-web \
  --replicas 4 \
  --update-delay 10s \
  --update-parallelism 1 \
  --update-failure-action rollback \
  --update-order start-first \
  nginx:1.25

# Step 2: 현재 상태 확인
docker service ps my-web

# Step 3: v2로 업데이트
docker service update \
  --image nginx:1.27 \
  my-web

# Step 4: 업데이트 진행 중 실시간 확인
watch docker service ps my-web
```

**업데이트 진행 중 출력**:
```
NAME        IMAGE         NODE      CURRENT STATE
my-web.1    nginx:1.27    worker1   Running  (새 버전)
my-web.2    nginx:1.25    worker2   Running  (이전 버전)
my-web.3    nginx:1.25    manager1  Running  (이전 버전)
my-web.4    nginx:1.25    worker1   Running  (이전 버전)
 \_ my-web.1 nginx:1.25   worker1   Shutdown (교체됨)
```

---

## 롤백

업데이트 중 문제가 생기면 즉시 이전 버전으로 되돌립니다.

```bash
# 수동 롤백
docker service rollback my-web

# 롤백 상태 확인
docker service ps my-web
# Shutdown 상태의 이전 Task들이 다시 Running으로 변경됨
```

**Compose 파일에서 rollback_config 설정**:

```yaml
deploy:
  rollback_config:
    parallelism: 2
    delay: 5s
    failure_action: pause
    monitor: 20s
    max_failure_ratio: 0.2
    order: stop-first
```

---

## 자동 롤백 설정

업데이트 실패 시 자동으로 롤백합니다.

```bash
docker service create \
  --name my-web \
  --replicas 4 \
  --update-failure-action rollback \
  --update-monitor 30s \
  --update-max-failure-ratio 0.2 \
  --rollback-parallelism 2 \
  --rollback-monitor 20s \
  nginx:1.25
```

```
자동 롤백 동작 흐름:

  업데이트 시작
      ↓
  Task 교체 중 ... (30초 모니터링)
      ↓ 실패율 > 20%?
      ├─ NO  → 다음 배치 진행
      └─ YES → 자동 롤백 시작!
                   ↓
              이전 버전으로 복구
```

---

## Health Check와 업데이트 연동

업데이트 시 헬스 체크가 통과된 Task만 정상으로 인정합니다.

```yaml
# compose.yml
services:
  my-web:
    image: nginx:latest
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s    # 시작 후 헬스 체크 시작까지 대기
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 10s
        failure_action: rollback
        monitor: 30s       # 헬스 체크 통과 후 30초 모니터링
```

---

## 업데이트 강제 재시작

```bash
# 배포가 멈췄을 때 강제로 업데이트 재트리거
docker service update --force my-web

# 특정 이미지로 다시 업데이트
docker service update --image nginx:1.27 my-web
```

> 💡 **참고**: `failure_action: pause`로 설정하면 실패 시 업데이트가 자동 일시 중지됩니다.
> `docker service update --force`로 재시작하거나, `docker service rollback`으로 되돌릴 수 있습니다.

---

## 요약

- **롤링 업데이트**: parallelism 개수씩 순서대로 Task 교체 → 무중단 배포
- `order: start-first` — 신규 Task 먼저 시작해 가용성 최대화
- `failure_action: rollback` — 실패 시 자동 롤백
- `docker service rollback` — 수동 롤백 명령
- Health Check 연동으로 실제 동작 확인 후 다음 배치 진행

---

## 다음 편 예고

트래픽 증가 시 서비스를 빠르게 확장하고, 특정 노드에만 배포하는 **스케일링과 배치 전략**을 배웁니다.

→ **[09편: 스케일링과 배치 전략](09-scaling-and-placement.md)**

---

## 참고 자료

- [Swarm 롤링 업데이트 공식 문서](https://docs.docker.com/engine/swarm/swarm-tutorial/rolling-update/) — docs.docker.com
- [Docker Service Update 레퍼런스](https://docs.docker.com/reference/cli/docker/service/update/) — docs.docker.com
