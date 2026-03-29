# Stack과 Compose 파일 — 멀티 서비스를 한 번에 배포하기

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [04편: 네트워크 이해하기](04-networking.md)
> **시리즈**: Docker Swarm 학습 가이드 5/11

---

## 개요

서비스가 여러 개면 `docker service create`를 여러 번 실행해야 합니다.
**Stack**은 Compose 파일 하나로 여러 서비스를 한 번에 정의하고 배포합니다.
이 편에서는 Compose v3 문법의 `deploy` 섹션과 Stack 배포 방법을 배웁니다.

---

## Stack이란?

```
docker service create (서비스 1개씩):     docker stack deploy (한 번에):
  $ docker service create nginx           compose.yml 파일 작성 후
  $ docker service create redis             $ docker stack deploy -c compose.yml myapp
  $ docker service create backend
  $ docker service create frontend        → 4개 서비스가 한 번에 배포!
  (4번 실행, 실수 가능)                     (파일로 관리, 버전 관리 가능)
```

---

## Compose 파일 구조 (Swarm용)

일반 `docker compose up`과 `docker stack deploy`의 차이는 `deploy` 섹션입니다.

```yaml
# compose.yml (Swarm 배포용)
version: "3.9"

services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
    networks:
      - app-network
    deploy:                       # ← Swarm 전용 섹션
      replicas: 3                 # 복제본 수
      update_config:
        parallelism: 1            # 한 번에 업데이트할 Task 수
        delay: 10s                # Task 간 대기 시간
      restart_policy:
        condition: on-failure     # 실패 시 재시작

  redis:
    image: redis:7-alpine
    networks:
      - app-network
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager  # Manager 노드에만 배포

networks:
  app-network:
    driver: overlay
```

---

## 실습: WordPress + MySQL Stack 배포

실제 서비스를 Stack으로 배포해봅니다.

**파일 생성**: `wordpress-stack.yml`

```yaml
version: "3.9"

services:
  db:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: YOUR_ROOT_PASSWORD
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wpuser
      MYSQL_PASSWORD: YOUR_WP_PASSWORD
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - wp-network
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager

  wordpress:
    image: wordpress:latest
    ports:
      - "8080:80"
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_NAME: wordpress
      WORDPRESS_DB_USER: wpuser
      WORDPRESS_DB_PASSWORD: YOUR_WP_PASSWORD
    networks:
      - wp-network
    deploy:
      replicas: 2
      update_config:
        parallelism: 1
        delay: 30s
      restart_policy:
        condition: on-failure
        max_attempts: 3
    # ⚠️ depends_on은 docker stack deploy에서 무시됩니다!
    # Swarm은 서비스 시작 순서를 보장하지 않으므로
    # 앱에서 DB 연결 재시도 로직을 구현해야 합니다.

volumes:
  db_data:

networks:
  wp-network:
    driver: overlay
```

**배포 및 확인**:

```bash
# Stack 배포
docker stack deploy -c wordpress-stack.yml wp

# Stack 목록 확인
docker stack ls

# Stack 내 서비스 확인
docker stack services wp

# Stack 내 Task 확인
docker stack ps wp

# 실시간 상태 모니터링
watch docker stack ps wp
```

**예상 출력**:
```
NAME           SERVICES
wp             2

ID             NAME           MODE         REPLICAS   IMAGE
xyzabc123def   wp_db          replicated   1/1        mysql:8.0
defghi456jkl   wp_wordpress   replicated   2/2        wordpress:latest
```

---

## deploy 섹션 주요 옵션

```yaml
deploy:
  replicas: 3                    # 복제본 수

  resources:                     # 리소스 제한 (실무 필수!)
    limits:
      cpus: "0.5"                # 최대 0.5 CPU
      memory: 512M               # 최대 512MB
    reservations:
      cpus: "0.25"               # 최소 예약 CPU
      memory: 256M               # 최소 예약 메모리

  update_config:                 # 롤링 업데이트 설정
    parallelism: 2               # 동시 업데이트 수
    delay: 10s                   # 업데이트 간격
    failure_action: rollback     # 실패 시 자동 롤백
    order: start-first           # 새 Task 먼저 시작 후 이전 종료

  rollback_config:               # 롤백 설정
    parallelism: 1
    delay: 5s

  restart_policy:                # 재시작 정책
    condition: on-failure        # on-failure | any | none
    delay: 5s
    max_attempts: 3
    window: 120s

  placement:                     # 배치 제약
    constraints:
      - node.role == worker
      - node.labels.region == us-east
    preferences:
      - spread: node.labels.zone # 여러 zone에 분산
```

---

## Stack 업데이트 및 삭제

```bash
# Stack 업데이트 (compose 파일 수정 후 재배포)
docker stack deploy -c wordpress-stack.yml wp

# 특정 서비스만 스케일 조정
docker service scale wp_wordpress=5

# Stack 전체 삭제
docker stack rm wp
# ⚠️ 볼륨은 삭제되지 않음 — 별도로 docker volume rm 필요
```

---

## 주의사항: `docker compose` vs `docker stack deploy`

```
docker compose up          docker stack deploy
(로컬 개발용)               (Swarm 배포용)
    │                           │
    ├─ build 지원 ✅             ├─ build 미지원 ❌ (이미지 사용)
    ├─ deploy 무시 ✅            ├─ deploy 적용 ✅
    ├─ swarm 기능 없음           ├─ swarm 기능 모두 사용
    └─ 단일 호스트               └─ 멀티 노드 클러스터
```

> 💡 **실무 팁**: 로컬에서는 `docker compose up`으로 개발하고,
> 운영 배포 시 동일 파일로 `docker stack deploy`를 사용합니다.
> `build:` 섹션은 Swarm에서 무시되므로, 배포 전 이미지를 레지스트리에 올려야 합니다.

> ⚠️ **Compose V1 (`docker-compose`, 하이픈) 지원 종료**
> - Docker Compose V1은 2023년 7월 **완전 EOL** — Docker Desktop에서도 제거됨
> - 현재는 **Compose V2** (`docker compose`, 스페이스)가 표준 (Go 기반 CLI 플러그인)
> - Compose V2에서 `version` 필드는 deprecated (생략해도 무방)
> - 단, `docker stack deploy`는 여전히 **version 3.0+ 형식**이 필요

---

## 요약

- **Stack** = Compose 파일로 여러 서비스를 한 번에 배포하는 단위
- `docker stack deploy -c <파일> <스택명>` — Stack 배포
- `docker stack services <스택명>` — 서비스 목록 확인
- `deploy:` 섹션에서 replicas, 리소스 제한, 업데이트/롤백 전략 설정
- `docker compose up`과 달리 `build:` 무시 → 배포 전 이미지 빌드 필요

---

## 다음 편 예고

데이터베이스처럼 데이터를 영구적으로 보관해야 하는 서비스의 볼륨 관리를 알아봅니다.

→ **[06편: 데이터 영속성 관리](06-volumes-and-data.md)**

---

## 참고 자료

- [Docker Stack 공식 문서](https://docs.docker.com/engine/swarm/stack-deploy/) — docs.docker.com
- [Compose file deploy 레퍼런스](https://docs.docker.com/compose/compose-file/deploy/) — docs.docker.com
