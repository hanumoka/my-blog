# 프로덕션 운영 가이드 — 보안, 모니터링, 스케일링

> **난이도**: 고급
> **소요 시간**: 약 3분
> **사전 지식**: [09편: 데이터 안정성](09-replication-ec.md)
> **시리즈**: Spring Boot + SeaweedFS 학습 가이드 10/10 (최종편)

---

## 개요

9편에 걸쳐 SeaweedFS의 핵심을 배웠습니다.
이 최종편에서는 실무 운영에 꼭 필요한 **보안 설정**, **모니터링**, **스케일 아웃**, **백업 전략**, 그리고 **흔한 함정**을 정리합니다.

---

## 프로덕션 아키텍처 전체 그림

```
                        인터넷
                          │
                    ┌─────▼──────┐
                    │  로드밸런서  │ (Nginx / AWS ALB)
                    └─────┬──────┘
                          │
              ┌───────────┴───────────┐
              │                       │
     ┌────────▼────────┐   ┌──────────▼────────┐
     │  Spring Boot 1   │   │  Spring Boot 2    │
     │  (API 서버)       │   │  (API 서버)        │
     └────────┬────────┘   └──────────┬─────────┘
              │                       │
              └───────────┬───────────┘
                          │
              ┌───────────▼──────────────┐
              │    SeaweedFS S3 (8333)   │
              └───────────┬──────────────┘
                          │
              ┌───────────▼──────────────┐
              │    SeaweedFS Filer (8888)│
              └───────────┬──────────────┘
                          │
         ┌────────────────┼────────────────┐
         │                │                │
┌────────▼──────┐ ┌───────▼───────┐ ┌─────▼──────────┐
│  Master 1     │ │  Master 2     │ │  Master 3      │
│  (Raft Leader)│ │  (Follower)   │ │  (Follower)    │
└────────┬──────┘ └───────────────┘ └────────────────┘
         │
         ├── Volume 1 (DC1, Rack1)
         ├── Volume 2 (DC1, Rack2)
         ├── Volume 3 (DC2, Rack1)
         └── Volume 4 (DC2, Rack2)
```

---

## 보안 설정

### S3 Gateway 인증 (AccessKey/SecretKey)

```json
// s3.json (S3 Gateway 인증 설정 파일)
{
  "identities": [
    {
      "name": "app-user",
      "credentials": [
        {
          "accessKey": "YOUR_ACCESS_KEY",
          "secretKey": "YOUR_SECRET_KEY"
        }
      ],
      "actions": ["Read", "Write", "List", "Tagging"],
      "buckets": ["my-bucket"]
    }
  ]
}
```

> ⚠️ `YOUR_ACCESS_KEY`와 `YOUR_SECRET_KEY`는 반드시 실제 비밀 값으로 교체하세요.
> 운영 환경에서는 Docker secrets 또는 환경변수로 주입하는 것을 권장합니다.

S3 Gateway 실행 시 설정 파일 지정:

```yaml
# docker-compose.yml
seaweedfs-s3:
  image: chrislusf/seaweedfs:3.73
  volumes:
    - ./config/s3.json:/etc/seaweedfs/s3.json
  command: "s3 -filer=seaweedfs-filer:8888 -port=8333 -config=/etc/seaweedfs/s3.json"
```

### Spring Boot 설정 업데이트

```yaml
# application-prod.yml
seaweedfs:
  s3:
    endpoint: ${SEAWEEDFS_ENDPOINT}
    access-key: ${SEAWEEDFS_ACCESS_KEY}  # s3.json의 accessKey와 일치해야 함
    secret-key: ${SEAWEEDFS_SECRET_KEY}
    region: us-east-1
    bucket: ${SEAWEEDFS_BUCKET}
```

### TLS/HTTPS 설정

Nginx를 앞단에 두어 TLS를 처리하는 방식을 권장합니다.

```nginx
# nginx.conf
server {
    listen 443 ssl;
    server_name storage.example.com;

    ssl_certificate     /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

    # S3 Gateway 프록시
    location / {
        proxy_pass http://seaweedfs-s3:8333;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        client_max_body_size 5g;  # 대용량 파일 업로드
        proxy_read_timeout 3600;  # 1시간
    }
}
```

---

## 모니터링

### 1. SeaweedFS 기본 메트릭

SeaweedFS는 Prometheus 메트릭을 기본 제공합니다.

```yaml
# docker-compose.yml에 메트릭 포트 추가
seaweedfs-master:
  ports:
    - "9333:9333"
    - "9301:9301"  # Prometheus metrics
  command: "master -ip=seaweedfs-master -port=9333 -mdir=/data -metricsPort=9301"

seaweedfs-volume1:
  ports:
    - "8080:8080"
    - "9302:9302"  # Prometheus metrics
  command: "volume -mserver=seaweedfs-master:9333 -port=8080 -dir=/data -metricsPort=9302"
```

### 2. Prometheus 설정

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'seaweedfs-master'
    static_configs:
      - targets: ['seaweedfs-master:9301']

  - job_name: 'seaweedfs-volume'
    static_configs:
      - targets: ['seaweedfs-volume1:9302', 'seaweedfs-volume2:9302']
```

### 3. 주요 모니터링 지표

```
모니터링 대상 지표 (실제 메트릭명은 /metrics 엔드포인트에서 확인):

Master:
  ├─ seaweedfs_master_volumeCount          볼륨 수
  ├─ seaweedfs_master_maxVolumeCount       최대 볼륨 수
  └─ seaweedfs_master_freeVolumeCount      여유 볼륨 수

Volume:
  ├─ seaweedfs_volumeServer_diskSizeGB     디스크 사용량
  ├─ seaweedfs_volumeServer_requestPerSec  초당 요청 수
  └─ seaweedfs_volumeServer_bytesPerSec       처리량

Spring Boot (Actuator):
  ├─ http.server.requests (파일 업로드/다운로드 지연 시간)
  └─ jvm.memory.used (힙 메모리 사용량)
```

### 4. 스토리지 용량 경보

```yaml
# Prometheus alerting rules (alert_rules.yml)
- alert: SeaweedFSDiskFull
  expr: >
    seaweedfs_volumeServer_diskSizeGB /
    seaweedfs_volumeServer_maxDiskSizeGB > 0.85
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "SeaweedFS 디스크 85% 초과"
```

---

## 스케일 아웃

### Volume 서버 추가 (무중단)

SeaweedFS의 가장 큰 장점 — 서비스 중단 없이 스토리지를 확장할 수 있습니다.

```bash
# 새 Volume 서버 추가 (기존 서비스 영향 없음)
docker run -d \
  --name seaweedfs-volume3 \
  --network seaweedfs-local_default \
  -p 8082:8080 \
  -v $(pwd)/data/volume3:/data \
  chrislusf/seaweedfs:3.73 \
  volume -mserver=seaweedfs-master:9333 -port=8080 -dir=/data

# Master가 자동으로 감지 (heartbeat)
curl http://localhost:9333/vol/status
# 새 볼륨 서버가 목록에 나타남
```

### Master HA 구성 (3대)

```yaml
# docker-compose.yml — Master 3대 HA
services:
  seaweedfs-master1:
    image: chrislusf/seaweedfs:3.73
    ports:
      - "9333:9333"
    volumes:
      - ./data/master1:/data
    command: >
      master
      -ip=seaweedfs-master1
      -port=9333
      -mdir=/data
      -peers=seaweedfs-master2:9334,seaweedfs-master3:9335

  seaweedfs-master2:
    image: chrislusf/seaweedfs:3.73
    ports:
      - "9334:9334"
    volumes:
      - ./data/master2:/data
    command: >
      master
      -ip=seaweedfs-master2
      -port=9334
      -mdir=/data
      -peers=seaweedfs-master1:9333,seaweedfs-master3:9335

  seaweedfs-master3:
    image: chrislusf/seaweedfs:3.73
    ports:
      - "9335:9335"
    volumes:
      - ./data/master3:/data
    command: >
      master
      -ip=seaweedfs-master3
      -port=9335
      -mdir=/data
      -peers=seaweedfs-master1:9333,seaweedfs-master2:9334
```

Spring Boot는 Master 목록을 모두 지정 (failover 자동):

```yaml
seaweedfs:
  s3:
    endpoint: http://seaweedfs-s3:8333  # S3 Gateway는 단일 엔드포인트
```

---

## 백업 전략

### Volume 스냅샷 (파일 시스템 기반)

```bash
# Volume 서버 데이터 디렉토리 백업
# 가장 단순한 방법: 파일 시스템 스냅샷 또는 rsync

# rsync로 백업
rsync -avz --delete \
  ./data/volume1/ \
  backup-server:/backup/seaweedfs/volume1/

# AWS S3로 백업 (콜드 스토리지)
aws s3 sync ./data/volume1/ s3://backup-bucket/seaweedfs/volume1/ \
  --storage-class GLACIER
```

### Filer 메타데이터 백업

```bash
# LevelDB 기반 Filer 메타데이터 백업 (컨테이너 중지 후 복사 권장)
docker compose stop seaweedfs-filer
cp -r ./data/filer/ ./backup/filer-$(date +%Y%m%d)/
docker compose start seaweedfs-filer

# 또는 Filer가 MySQL/PostgreSQL을 메타데이터 백엔드로 사용하면
# 일반 DB 백업 도구 사용 (pg_dump, mysqldump 등)
```

---

## 흔한 함정과 해결책

```
❌ 함정 1: pathStyleAccessEnabled 누락
   → "The specified bucket does not exist" 오류
   ✅ 해결: S3Client 빌더에 serviceConfiguration(pathStyleAccessEnabled=true) 추가

❌ 함정 2: Volume 서버 1대만 운영
   → Volume 서버 장애 시 데이터 손실
   ✅ 해결: 최소 2대 운영 + defaultReplication=001

❌ 함정 3: Master 단일 운영
   → Master 장애 시 전체 서비스 중단
   ✅ 해결: Master 3대 HA 구성 (Raft)

❌ 함정 4: 대용량 파일 Tomcat 타임아웃
   → 1GB 이상 업로드 시 연결 끊김
   ✅ 해결: connection-timeout 증가, S3TransferManager 사용

❌ 함정 5: Filer 메타데이터 백업 누락
   → Volume 데이터는 있는데 경로를 모름
   ✅ 해결: Filer 메타데이터(LevelDB) 정기 백업

❌ 함정 6: HTTP로만 운영
   → 파일 전송 중 도청/변조 위험
   ✅ 해결: Nginx SSL 프록시 + 내부망 통신

❌ 함정 7: 무제한 파일 업로드 허용
   → 디스크 풀 공격 가능
   ✅ 해결: Spring multipart.max-file-size 제한 + 용량 경보
```

---

## 시리즈 마무리

| 편 | 주제 | 핵심 |
|----|------|------|
| [01](01-what-is-seaweedfs.md) | SeaweedFS 소개 | 분산 파일 시스템, 3계층 구조 |
| [02](02-architecture.md) | 아키텍처 심화 | Master/Volume/Filer/S3 동작 원리 |
| [03](03-docker-setup.md) | Docker 환경 구축 | docker-compose, 4개 서비스 실행 |
| [04](04-filer-api.md) | Filer REST API | 업로드/다운로드/태그/TTL |
| [05](05-s3-api.md) | S3 호환 API | AWS CLI, path-style URL |
| [06](06-spring-boot-setup.md) | Spring Boot 설정 | AWS SDK v2, S3Client Bean |
| [07](07-file-upload-download.md) | 업로드/다운로드 구현 | MultipartFile, 스트리밍 |
| [08](08-large-file-handling.md) | 대용량 파일 처리 | S3TransferManager, 멀티파트 |
| [09](09-replication-ec.md) | 데이터 안정성 | 복제 ZYX, EC RS(10,4) |
| [10](10-production-guide.md) | 프로덕션 운영 | 보안, 모니터링, 스케일링 |

SeaweedFS는 설정이 간단하면서도 강력한 분산 파일 시스템입니다.
이 시리즈를 통해 개념부터 운영까지 전체를 이해하셨길 바랍니다!

---

## 참고 자료

- [SeaweedFS GitHub](https://github.com/seaweedfs/seaweedfs) — github.com
- [SeaweedFS Production Tips](https://github.com/seaweedfs/seaweedfs/wiki/Optimization) — github.com
- [SeaweedFS Security](https://github.com/seaweedfs/seaweedfs/wiki/Security-Configuration) — github.com
- [Prometheus + SeaweedFS](https://github.com/seaweedfs/seaweedfs/wiki/System-Metrics) — github.com
