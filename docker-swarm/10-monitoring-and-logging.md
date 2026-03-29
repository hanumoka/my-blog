# 모니터링과 로깅 — Swarm 클러스터 상태 파악하기

> **난이도**: 고급
> **소요 시간**: 약 3분
> **사전 지식**: [09편: 스케일링과 배치 전략](09-scaling-and-placement.md)
> **시리즈**: Docker Swarm 학습 가이드 10/11

---

## 개요

운영 중인 Swarm 클러스터의 이상을 빠르게 감지하고 원인을 파악해야 합니다.
이 편에서는 기본 로그 확인부터 Prometheus + Grafana 모니터링 스택 구성까지 다룹니다.

---

## 기본 로그 확인

```bash
# 서비스 로그 (모든 Task 통합)
docker service logs my-web

# 실시간 스트리밍
docker service logs -f my-web

# 마지막 100줄
docker service logs --tail 100 my-web

# 타임스탬프 포함
docker service logs --timestamps my-web

# 특정 Task 로그만
docker service logs my-web.1
```

---

## 클러스터 상태 확인 명령어

```bash
# 노드 상태
docker node ls

# 서비스 전체 상태
docker service ls

# 특정 서비스의 Task 상태
docker service ps my-web --no-trunc   # 에러 메시지 전체 표시

# 이벤트 스트림 실시간 모니터링
docker events --filter type=service
docker events --filter type=node

# 시스템 리소스 사용량
docker stats $(docker ps -q)
```

---

## Prometheus + Grafana 모니터링 스택 구성

```
모니터링 아키텍처:

  ┌─────────────────────────────────────────────────────┐
  │                   Swarm 클러스터                     │
  │                                                     │
  │  ┌─────────────────┐   ┌──────────────────────────┐ │
  │  │   각 노드        │   │    Manager 노드           │ │
  │  │ ┌─────────────┐ │   │ ┌────────┐ ┌──────────┐  │ │
  │  │ │node-exporter│ │──▶│ │Prometheus│ │ Grafana  │ │ │
  │  │ │  (metrics)  │ │   │ │(수집/저장)│ │(시각화)  │ │ │
  │  │ └─────────────┘ │   │ └────────┘ └──────────┘  │ │
  │  └─────────────────┘   └──────────────────────────┘ │
  └─────────────────────────────────────────────────────┘

  브라우저 → Grafana:3000 → 대시보드
```

**monitoring-stack.yml**:

```yaml
version: "3.9"

services:
  # 각 노드의 시스템 메트릭 수집 (프로덕션에서는 버전 고정 권장)
  node-exporter:
    image: prom/node-exporter:v1.9.1
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
    networks:
      - monitoring
    deploy:
      mode: global    # 모든 노드에 배포

  # Swarm 서비스 메트릭 수집
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.52.1
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    networks:
      - monitoring
    deploy:
      mode: global    # 모든 노드에 배포

  # 메트릭 저장소
  prometheus:
    image: prom/prometheus:v3.10.0
    configs:
      - source: prometheus_config
        target: /etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
    networks:
      - monitoring
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager

  # 시각화 대시보드
  grafana:
    image: grafana/grafana:12.4.2
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD__FILE=/run/secrets/grafana_password
    secrets:
      - grafana_password
    volumes:
      - grafana_data:/var/lib/grafana
    networks:
      - monitoring
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager

configs:
  prometheus_config:
    external: true

secrets:
  grafana_password:
    external: true

volumes:
  grafana_data:

networks:
  monitoring:
    driver: overlay
    attachable: true
```

**prometheus.yml** (Config로 등록):

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node-exporter'
    dns_sd_configs:
      - names:
          - 'tasks.node-exporter'  # Swarm DNS로 모든 Task 자동 감지
        type: A
        port: 9100

  - job_name: 'cadvisor'
    dns_sd_configs:
      - names:
          - 'tasks.cadvisor'
        type: A
        port: 8080
```

**prometheus.yml (대안: 네이티브 Swarm 서비스 디스커버리)**:

Prometheus 2.20.0+부터 Docker Swarm 네이티브 서비스 디스커버리를 지원합니다.
`dns_sd_configs` 대신 `dockerswarm_sd_configs`를 사용하면 노드/서비스/태스크 메타데이터까지 자동으로 수집됩니다.

```yaml
# prometheus.yml (네이티브 Swarm SD)
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'swarm-tasks'
    dockerswarm_sd_configs:
      - host: unix:///var/run/docker.sock
        role: tasks    # nodes, services, tasks 중 선택
    relabel_configs:
      - source_labels: [__meta_dockerswarm_service_name]
        target_label: service_name
```

> 이 방식을 사용하려면 Prometheus가 Docker 소켓에 접근 가능해야 합니다.
> 볼륨에 `/var/run/docker.sock:/var/run/docker.sock:ro`를 추가하세요.

**배포**:

```bash
# Config 및 Secret 생성
docker config create prometheus_config ./prometheus.yml
echo "YOUR_GRAFANA_PASSWORD" | docker secret create grafana_password -

# 스택 배포
docker stack deploy -c monitoring-stack.yml monitoring

# 접속
# Grafana: http://manager-ip:3000 (admin / YOUR_GRAFANA_PASSWORD)
# Prometheus: http://manager-ip:9090
```

---

## 로그 드라이버 설정

기본 `json-file` 드라이버 대신 중앙 집중 로깅을 설정합니다.

```yaml
# compose.yml
services:
  my-app:
    image: my-app:latest
    logging:
      driver: "json-file"
      options:
        max-size: "10m"    # 로그 파일 최대 크기
        max-file: "3"      # 최대 파일 수 (순환)

    # Loki로 전송 (Grafana Loki 사용 시)
    # logging:
    #   driver: loki
    #   options:
    #     loki-url: "http://loki:3100/loki/api/v1/push"
    #     loki-batch-size: "400"
```

---

## 알림 설정 (Alertmanager)

```
Prometheus → 조건 충족 → Alertmanager → Slack/이메일 알림

예시 알람:
  - 노드 CPU > 80% 5분 지속
  - 서비스 replica < 목표치
  - 컨테이너 재시작 3회 이상
```

---

## 요약

- `docker service logs -f <이름>` — 실시간 서비스 로그 확인
- `docker service ps --no-trunc` — Task 실패 에러 메시지 전체 확인
- **node-exporter** + **cAdvisor** (Global 모드) — 모든 노드 메트릭 수집
- **Prometheus** — 메트릭 수집/저장 (Manager 노드)
- **Grafana** — 대시보드 시각화 (Manager 노드)
- 로그 드라이버: `max-size` + `max-file`로 로그 용량 제한 필수

---

## 다음 편 예고

마지막 편에서는 프로덕션 환경에서 Swarm을 안정적으로 운영하는 고가용성, TLS, 백업/복구 방법을 다룹니다.

→ **[11편: 프로덕션 운영 가이드](11-production-guide.md)**

---

## 참고 자료

- [Docker Service Logs](https://docs.docker.com/reference/cli/docker/service/logs/) — docs.docker.com
- [Prometheus 공식 문서](https://prometheus.io/docs/introduction/overview/) — prometheus.io
- [Prometheus Docker Swarm 가이드](https://prometheus.io/docs/guides/dockerswarm/) — 네이티브 Swarm SD 설정
- [Grafana 공식 문서](https://grafana.com/docs/) — grafana.com
