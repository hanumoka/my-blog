# 데이터 영속성 관리 — 볼륨과 Swarm

> **난이도**: 중급
> **소요 시간**: 약 2분
> **사전 지식**: [05편: Stack과 Compose 파일](05-stack-and-compose.md)
> **시리즈**: Docker Swarm 학습 가이드 6/11

---

## 개요

컨테이너는 삭제되면 데이터도 사라집니다.
Swarm에서 데이터를 영구 보존하는 방법과, 멀티 노드 환경에서의 볼륨 전략을 배웁니다.

---

## Swarm에서 볼륨의 문제점

```
단일 호스트:                      멀티 노드 Swarm:
  ┌─────────┐                      ┌─────────┐  ┌─────────┐
  │  Host   │                      │ worker1 │  │ worker2 │
  │ ┌─────┐ │                      │ ┌─────┐ │  │ ┌─────┐ │
  │ │Vol  │ │                      │ │Vol A│ │  │ │Vol B│ │
  │ └──┬──┘ │                      │ └──┬──┘ │  │ └──┬──┘ │
  │    │    │                      │    │    │  │    │    │
  │ [Task1] │                      │ [Task1] │  │ [Task2] │
  └─────────┘                      └─────────┘  └─────────┘
  ✅ 간단                             ⚠️ Vol A ≠ Vol B
                                      데이터 불일치 발생!
```

> ⚠️ **핵심 문제**: Swarm은 볼륨을 자동으로 노드 간 동기화하지 않습니다.
> Task가 재배치되면 다른 노드의 빈 볼륨을 사용하게 됩니다.

---

## 볼륨 전략 3가지

### 전략 1: Placement Constraint (단순, 권장)

데이터를 가진 노드에만 배포를 고정합니다.

```yaml
# compose.yml
services:
  db:
    image: mysql:8.0
    volumes:
      - db_data:/var/lib/mysql
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.labels.data == true   # 데이터 노드 고정

volumes:
  db_data:
```

```bash
# 특정 노드에 'data=true' 레이블 부여
docker node update --label-add data=true worker1
```

```
장점: 설정 간단
단점: 해당 노드 장애 시 데이터 접근 불가
적합: DB, 상태형 서비스 (replicas=1)
```

### 전략 2: NFS 볼륨 (멀티 노드 공유)

모든 노드에서 같은 NFS 서버의 데이터를 공유합니다.

```yaml
volumes:
  shared_data:
    driver: local
    driver_opts:
      type: nfs
      o: addr=YOUR_NFS_SERVER_IP,rw,nfsvers=4
      device: ":/exports/mydata"
```

```
장점: 노드 간 데이터 공유
단점: NFS 서버 별도 구성 필요, 성능 제한
적합: 파일 공유, 설정 파일 배포
```

### 전략 3: 분산 스토리지 플러그인 (고급)

Portworx, GlusterFS, Ceph 같은 분산 스토리지를 볼륨 드라이버로 사용합니다.

```bash
# 예시: Portworx 플러그인 사용
docker volume create \
  -d pxd \
  --opt size=10 \
  --opt repl=2 \
  my-px-volume
```

```
장점: 자동 복제, 노드 장애 시 자동 페일오버
단점: 구성 복잡, 비용 발생 가능
적합: 고가용성이 필요한 DB 서비스
```

---

## 실습: MySQL Stack with Placement Constraint

```yaml
# mysql-stack.yml
version: "3.9"

services:
  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: YOUR_ROOT_PASSWORD
      MYSQL_DATABASE: appdb
    volumes:
      - mysql_data:/var/lib/mysql
    networks:
      - db-network
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.labels.db == true
      restart_policy:
        condition: on-failure

volumes:
  mysql_data:
    driver: local

networks:
  db-network:
    driver: overlay
```

```bash
# db 노드 레이블 지정
docker node update --label-add db=true worker1

# Stack 배포
docker stack deploy -c mysql-stack.yml mydb

# 볼륨 확인 (worker1에서)
docker volume ls
docker volume inspect mydb_mysql_data
```

---

## 볼륨 관리 명령어

```bash
# 볼륨 목록
docker volume ls

# 볼륨 상세 정보
docker volume inspect <볼륨명>

# 사용하지 않는 볼륨 삭제
docker volume prune

# 특정 볼륨 삭제
docker volume rm <볼륨명>
```

---

## 실무 선택 가이드

```
서비스 종류별 권장 전략:

  MySQL / PostgreSQL (단일 인스턴스)
    → Placement Constraint + Named Volume ✅

  Redis (캐시 용도)
    → 볼륨 불필요 (재시작 시 캐시 워밍업 허용)

  파일 업로드 서비스 (멀티 인스턴스)
    → NFS 또는 S3 연동 ✅

  고가용성 DB (복제 필요)
    → 분산 스토리지 플러그인 또는
      DB 자체 복제(MySQL Replication) 활용 ✅
```

---

## 요약

- Swarm은 볼륨을 노드 간 자동 동기화하지 않음 — 전략 선택 필수
- **Placement Constraint**: 가장 단순, DB 단일 인스턴스에 적합
- **NFS 볼륨**: 멀티 노드 공유 가능, NFS 서버 필요
- **분산 스토리지**: 고가용성 필요 시, 구성 복잡
- 상태형(Stateful) 서비스는 `replicas: 1` + `placement constraint`가 일반적

---

## 다음 편 예고

비밀번호, API 키 같은 민감한 데이터를 안전하게 관리하는 **Secrets & Configs**를 배웁니다.

→ **[07편: Secrets & Configs](07-secrets-and-configs.md)**

---

## 참고 자료

- [Swarm 볼륨 공식 문서](https://docs.docker.com/engine/swarm/services/#give-a-service-access-to-volumes-or-bind-mounts) — docs.docker.com
- [Docker 볼륨 드라이버](https://docs.docker.com/engine/extend/plugins_volume/) — docs.docker.com
