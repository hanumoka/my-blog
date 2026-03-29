# 스케일링과 배치 전략 — 올바른 노드에 올바른 서비스를

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [08편: 롤링 업데이트와 롤백](08-rolling-update.md)
> **시리즈**: Docker Swarm 학습 가이드 9/11

---

## 개요

트래픽이 급증할 때 빠르게 서비스를 확장하고, GPU 노드에는 AI 서비스만, SSD 노드에는 DB만 배포하는 방법을 배웁니다.
**스케일링**과 **배치 전략(Placement)**은 리소스를 효율적으로 사용하는 핵심 기술입니다.

---

## 스케일링

### 수동 스케일링

```bash
# 방법 1: scale 명령 (빠르고 직관적)
docker service scale my-web=10

# 방법 2: update 명령
docker service update --replicas 10 my-web

# 여러 서비스 동시 스케일
docker service scale my-web=10 my-api=5

# 확인
docker service ls
# my-web: 10/10
```

### 리소스 제한 설정

스케일 전 반드시 리소스 제한을 설정하세요. 그렇지 않으면 한 노드에서 모든 리소스를 소진합니다.

```bash
docker service update \
  --limit-cpu 0.5 \
  --limit-memory 512M \
  --reserve-cpu 0.25 \
  --reserve-memory 256M \
  my-web
```

```
limit (최대):      리소스 상한선 — 이 이상 사용 불가
reservation (예약): 이 노드에 이만큼 여유가 있어야 Task 배치
```

---

## 배치 전략 (Placement)

### Constraints — 특정 노드에만 배포

노드 레이블이나 속성으로 배포 위치를 제한합니다.

```bash
# 노드에 레이블 추가
docker node update --label-add region=us-east worker1
docker node update --label-add region=us-west worker2
docker node update --label-add gpu=true worker3
docker node update --label-add ssd=true worker1

# Constraint 사용
docker service create \
  --name ai-service \
  --constraint node.labels.gpu==true \
  my-ai-app

docker service create \
  --name db-service \
  --constraint node.labels.ssd==true \
  --constraint node.role==worker \
  postgres
```

**사용 가능한 기본 속성**:

```
node.id            == abc123
node.hostname      == worker1
node.ip            == 10.0.0.5
node.role          == manager | worker
node.platform.os   == linux | windows
node.platform.arch == x86_64 | aarch64
node.labels.xxx    == 직접 정의한 레이블
engine.labels.xxx  == Docker Engine 레이블
```

---

## 배치 시각화

```
클러스터 구성:
┌────────────┐  ┌────────────┐  ┌────────────┐
│  manager1  │  │  worker1   │  │  worker2   │
│            │  │ ssd=true   │  │ gpu=true   │
│            │  │ region=east│  │ region=west│
└────────────┘  └────────────┘  └────────────┘

배치 결과:
  web-service (constraint: region==east)
    → worker1에만 배포

  ai-service (constraint: gpu==true)
    → worker2에만 배포

  db-service (constraint: ssd==true, role==worker)
    → worker1에만 배포

  monitor-service (mode: global)
    → 모든 노드에 1개씩
```

---

## Preferences — 분산 배포 선호

Constraint는 강제 조건이지만, Preferences는 **최대한** 분산하려는 선호도입니다.

```bash
# 데이터센터별로 균등 분산 (가능한 한)
docker service create \
  --replicas 6 \
  --placement-pref spread=node.labels.datacenter \
  my-service
```

```
datacenter=A 노드: 3개, datacenter=B 노드: 3개
→ 균등 분산! (B에 문제가 생겨도 A에서 3개 유지)
```

---

## 실습: 실무형 멀티 티어 Stack

```yaml
# production-stack.yml
version: "3.9"

services:
  # 프론트엔드 — 어느 노드에나
  frontend:
    image: my-frontend:latest
    ports:
      - "80:3000"
    networks:
      - app-network
    deploy:
      replicas: 3
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
      placement:
        preferences:
          - spread: node.labels.zone   # zone별 균등 분산

  # 백엔드 API — Worker 노드에만
  backend:
    image: my-backend:latest
    networks:
      - app-network
    deploy:
      replicas: 4
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
        reservations:
          cpus: "0.5"
          memory: 256M
      placement:
        constraints:
          - node.role == worker

  # DB — SSD 레이블 노드에만
  db:
    image: postgres:16
    networks:
      - app-network
    deploy:
      replicas: 1
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 512M
      placement:
        constraints:
          - node.labels.ssd == true
          - node.role == worker

  # 모니터링 — 모든 노드
  node-exporter:
    image: prom/node-exporter:latest
    networks:
      - monitoring-network
    deploy:
      mode: global     # 모든 노드에 1개씩

networks:
  app-network:
    driver: overlay
  monitoring-network:
    driver: overlay
```

---

## 스케일 시 주의사항

```
자주 하는 실수:

  ❌ replicas를 노드 수보다 훨씬 크게 설정
     → 한 노드에 Task가 몰려 리소스 고갈

  ❌ 리소스 제한 없이 스케일
     → OOM(메모리 부족) 발생

  ❌ DB 서비스를 constraint 없이 replicas>1
     → 데이터 불일치 위험

  ✅ 올바른 방법:
     resources.limits + reservations 설정 후 스케일
     DB는 replicas=1 + placement constraint 고정
```

---

## 요약

- `docker service scale <이름>=<수>` — 빠른 스케일 조정
- **Constraint**: 특정 노드에만 배포 강제 (gpu, ssd, region 등)
- **Preferences**: 특정 속성 기준으로 분산 배포 권장
- 리소스 `limits` + `reservations` 설정 필수 (안정적 스케일링)
- DB는 `replicas: 1` + `placement constraint` 고정이 원칙

---

## 다음 편 예고

운영 중인 Swarm 클러스터를 모니터링하고 로그를 중앙에서 수집하는 방법을 배웁니다.

→ **[10편: 모니터링과 로깅](10-monitoring-and-logging.md)**

---

## 참고 자료

- [Swarm 서비스 배치 공식 문서](https://docs.docker.com/engine/swarm/services/#control-service-placement) — docs.docker.com
- [Docker Service Scale](https://docs.docker.com/reference/cli/docker/service/scale/) — docs.docker.com
