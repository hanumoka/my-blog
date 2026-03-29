# 프로덕션 운영 가이드 — HA, 보안, 백업, 트러블슈팅

> **난이도**: 고급
> **소요 시간**: 약 3분
> **사전 지식**: [10편: 모니터링과 로깅](10-monitoring-and-logging.md)
> **시리즈**: Docker Swarm 학습 가이드 11/11 (완결)

---

## 개요

실제 프로덕션 환경에서 Swarm을 안정적으로 운영하기 위한 종합 가이드입니다.
고가용성(HA) 구성, 보안 강화, 백업/복구, 그리고 현장에서 자주 겪는 문제 해결법을 다룹니다.

---

## 1. 고가용성(HA) Manager 구성

```
Manager 노드 수에 따른 장애 허용:

  1개: 고가용성 없음 (Manager 장애 → 클러스터 관리 불가)
  3개: 1개 장애 허용  ← 최소 권장
  5개: 2개 장애 허용  ← 중요 서비스 권장
  7개: 3개 장애 허용  (이 이상은 Raft 오버헤드 증가)

  공식: 과반수 = (N/2 + 1) 이상 생존 필요
```

**Manager 노드 추가**:

```bash
# Manager join 토큰 확인
docker swarm join-token manager

# 신규 Manager 노드에서 실행
docker swarm join \
  --token SWMTKN-1-...(manager 토큰) \
  <leader-ip>:2377

# 현재 Manager 목록 확인
docker node ls
# MANAGER STATUS 컬럼: Leader, Reachable, Unreachable
```

**Manager 노드 분산 배치**:

```
프로덕션 권장 구성 (AWS 기준):

  manager1 → ap-northeast-2a (가용 영역 A)
  manager2 → ap-northeast-2b (가용 영역 B)
  manager3 → ap-northeast-2c (가용 영역 C)

  worker1~N → 각 가용 영역에 분산
```

---

## 2. 보안 강화

### 자동 TLS 인증서

Swarm은 기본적으로 노드 간 통신에 TLS를 사용합니다.

```bash
# 인증서 로테이션 주기 확인
docker system info | grep -i "ca expiry"

# 인증서 로테이션 주기 변경 (기본 90일)
docker swarm update --cert-expiry 720h   # 30일로 변경

# 강제 인증서 갱신
docker swarm ca --rotate
```

### 컨테이너 보안 강화

```yaml
services:
  my-app:
    image: my-app:latest
    deploy:
      replicas: 3
    # 보안 옵션
    read_only: true               # 루트 파일시스템 읽기 전용
    tmpfs:
      - /tmp                      # /tmp는 쓰기 허용 (임시)
    security_opt:
      - no-new-privileges:true    # 권한 상승 차단
    user: "1000:1000"             # root 대신 일반 유저로 실행
```

### 네트워크 분리

```yaml
# 외부 접근이 필요한 서비스와 내부 서비스 분리
networks:
  frontend-network:    # 외부 트래픽
    driver: overlay
  backend-network:     # 내부만 (DB, 캐시 등)
    driver: overlay
    internal: true     # 외부 연결 차단!
```

---

## 3. 백업과 복구

### Swarm 상태 백업 (Manager에서)

```bash
#!/bin/bash
# backup-swarm.sh

BACKUP_DIR="/backup/swarm"
DATE=$(date +%Y%m%d_%H%M%S)

# Docker daemon 중지 (데이터 일관성)
systemctl stop docker

# Swarm 상태 디렉토리 백업
tar -czf "$BACKUP_DIR/swarm-$DATE.tar.gz" \
  /var/lib/docker/swarm

# Docker 재시작
systemctl start docker

echo "백업 완료: $BACKUP_DIR/swarm-$DATE.tar.gz"
```

```bash
# cron으로 자동 백업 (매일 새벽 3시)
0 3 * * * /opt/scripts/backup-swarm.sh >> /var/log/swarm-backup.log 2>&1
```

### 복구 절차

```bash
# 시나리오: Manager 전체 장애 후 복구

# 1. 새 서버에 Docker 설치

# 2. 백업 파일 복원
tar -xzf swarm-20260329_030000.tar.gz -C /

# 3. 강제로 새 클러스터로 초기화
docker swarm init --force-new-cluster --advertise-addr <new-ip>

# 4. Worker 노드들 재참가 (새 토큰으로)
docker swarm join-token worker
# 각 Worker에서 새 토큰으로 join
```

---

## 4. 노드 유지보수 절차

```bash
# 1. 노드를 드레인 모드로 전환 (기존 Task 다른 노드로 이전)
docker node update --availability drain worker1

# 2. Task 이전 확인
docker node ps worker1   # 모두 Shutdown 상태 확인

# 3. 유지보수 작업 (OS 업데이트, 재부팅 등)
ssh worker1 "sudo apt update && sudo apt upgrade -y && sudo reboot"

# 4. 재시작 후 Active 복구
docker node update --availability active worker1

# 5. 서비스 재배분 확인
docker service ps <서비스명>
```

---

## 5. 트러블슈팅 가이드

### 문제 1: Task가 계속 재시작되는 경우

```bash
# 실패한 Task 에러 메시지 확인
docker service ps my-service --no-trunc

# 특정 Task 상세 로그
docker service logs my-service --since 10m

# 원인 파악 → 이미지 pull 실패? 메모리 부족? 포트 충돌?
```

### 문제 2: 서비스가 배포되지 않는 경우

```bash
# 배포 안 되는 이유 확인
docker service ps my-service --no-trunc
# "no suitable node" → Constraint 조건 불만족, 리소스 부족

# 노드 리소스 확인
docker node inspect worker1 --pretty | grep -A5 Resources

# Constraint 재확인
docker service inspect my-service --pretty | grep -A5 Placement
```

### 문제 3: Manager Quorum 손실

```bash
# 증상: docker node ls 명령이 응답 없음

# 남은 Manager 노드에서
docker swarm init --force-new-cluster

# ⚠️ 이 명령은 새 클러스터를 강제 생성합니다.
# 기존 Worker들은 재참가 필요
```

### 문제 4: 네트워크 통신 안 되는 경우

```bash
# Overlay 네트워크 목록 확인
docker network ls

# 네트워크 상세 정보 (어떤 서비스가 연결됐는지)
docker network inspect my-overlay

# 포트 확인 (방화벽 이슈)
# 2377, 7946, 4789 포트 열려있는지 확인
netstat -tlnp | grep -E "2377|7946|4789"
```

---

## 프로덕션 체크리스트

```
배포 전:
  [ ] Manager 노드 3개 이상 (홀수) 구성
  [ ] Manager 노드를 여러 가용 영역에 분산
  [ ] 모든 노드에서 2377, 7946, 4789 포트 개방
  [ ] 리소스 limits/reservations 설정
  [ ] Health check 설정
  [ ] Secret/Config로 민감 정보 관리
  [ ] read_only + no-new-privileges 보안 옵션 적용

운영 중:
  [ ] 정기 Swarm 상태 백업 (cron)
  [ ] Prometheus + Grafana 모니터링 가동
  [ ] 로그 드라이버 max-size 설정
  [ ] 인증서 만료일 모니터링
  [ ] 정기 보안 패치 (drain → 업데이트 → active)
```

---

## 요약

- **HA Manager**: 홀수 개, 여러 가용 영역에 분산 배치
- **자동 TLS**: Swarm 기본 제공 — 인증서 로테이션 주기 관리
- **컨테이너 보안**: read_only + no-new-privileges + 일반 유저 실행
- **백업**: `/var/lib/docker/swarm` 정기 백업 (cron)
- **복구**: `docker swarm init --force-new-cluster`로 단일 Manager 복구
- **유지보수**: drain → 작업 → active 순서 준수

---

## 시리즈 완결

이것으로 **Docker Swarm 학습 가이드 11편**을 마무리합니다.

```
학습 경로 요약:
  01 개요 → 02 클러스터 구축 → 03 서비스 기초
  → 04 네트워킹 → 05 Stack/Compose → 06 볼륨
  → 07 Secrets/Configs → 08 롤링 업데이트
  → 09 스케일링/배치 → 10 모니터링/로깅
  → 11 프로덕션 운영 ✅
```

---

## 참고 자료

- [Swarm 관리 가이드](https://docs.docker.com/engine/swarm/admin_guide/) — docs.docker.com
- [Docker Swarm 보안](https://docs.docker.com/engine/swarm/how-swarm-mode-works/pki/) — docs.docker.com
- [Docker Engine v29 릴리즈 노트](https://docs.docker.com/engine/release-notes/29/) — docs.docker.com
