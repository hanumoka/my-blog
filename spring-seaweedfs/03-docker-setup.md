# Docker로 SeaweedFS 로컬 환경 구축 — 5분 안에 실행하기

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [02편: 아키텍처 심화](02-architecture.md), Docker 기본 사용법
> **시리즈**: Spring Boot + SeaweedFS 학습 가이드 3/10

---

## 개요

이번 편에서는 Docker Compose로 SeaweedFS를 로컬에 실행합니다.
Master, Volume, Filer, S3 Gateway를 모두 띄우고, 브라우저와 curl로 파일 업로드/다운로드를 직접 해봅니다.
이 환경이 이후 편의 실습 기반이 됩니다.

---

## 실습 환경

```
필요 도구:
  ├─ Docker Desktop 4.x (Windows/Mac) 또는 Docker Engine 27.x (Linux)
  ├─ Docker Compose V2 (docker compose 명령어)
  └─ curl (테스트용)

SeaweedFS Docker 이미지: chrislusf/seaweedfs (Docker Hub에서 최신 태그 확인)
```

---

## 실습

### 1단계: 프로젝트 폴더 생성

```bash
mkdir seaweedfs-local
cd seaweedfs-local
mkdir -p data/master data/volume1 data/filer
```

### 2단계: docker-compose.yml 작성

```yaml
# docker-compose.yml
services:
  # Master 서버 — 볼륨 위치 관리
  seaweedfs-master:
    image: chrislusf/seaweedfs:3.73
    ports:
      - "9333:9333"   # HTTP API
      - "19333:19333" # gRPC
    volumes:
      - ./data/master:/data
    command: "master -ip=seaweedfs-master -port=9333 -mdir=/data"
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:9333/cluster/status"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Volume 서버 — 실제 파일 데이터 저장
  seaweedfs-volume:
    image: chrislusf/seaweedfs:3.73
    ports:
      - "8080:8080"
      - "18080:18080"
    volumes:
      - ./data/volume1:/data
    command: "volume -mserver=seaweedfs-master:9333 -port=8080 -dir=/data -max=10"
    depends_on:
      seaweedfs-master:
        condition: service_healthy

  # Filer 서버 — 경로 기반 파일 접근
  seaweedfs-filer:
    image: chrislusf/seaweedfs:3.73
    ports:
      - "8888:8888"   # HTTP REST API
      - "18888:18888" # gRPC
    volumes:
      - ./data/filer:/data
    command: "filer -master=seaweedfs-master:9333 -port=8888"
    depends_on:
      seaweedfs-master:
        condition: service_healthy
      seaweedfs-volume:
        condition: service_started

  # S3 Gateway — AWS S3 호환 API
  seaweedfs-s3:
    image: chrislusf/seaweedfs:3.73
    ports:
      - "8333:8333"
    command: "s3 -filer=seaweedfs-filer:8888 -port=8333"
    depends_on:
      - seaweedfs-filer
```

> 💡 `latest` 태그 대신 특정 버전을 명시해 재현 가능한 환경을 유지합니다.
> [Docker Hub](https://hub.docker.com/r/chrislusf/seaweedfs/tags)에서 최신 태그를 확인하세요.

### 3단계: 실행

```bash
# 전체 서비스 시작 (백그라운드)
docker compose up -d

# 로그 확인
docker compose logs -f

# 상태 확인
docker compose ps
```

정상 실행 시 출력:

```
NAME                    STATUS
seaweedfs-master        Up (healthy)
seaweedfs-volume        Up
seaweedfs-filer         Up
seaweedfs-s3            Up
```

### 4단계: 상태 확인 — 브라우저

| URL | 설명 |
|-----|------|
| http://localhost:9333/cluster/status | Master 상태 |
| http://localhost:9333/vol/status | Volume 목록 |
| http://localhost:8888/ | Filer 웹 UI (파일 탐색) |

**Master 상태 응답 예시**:

```json
{
  "IsLeader": true,
  "Leader": "seaweedfs-master:9333",
  "Peers": [],
  "Volumes": 7
}
```

### 5단계: 파일 업로드/다운로드 테스트 (Filer)

**파일 업로드**:

```bash
# 테스트 파일 생성
echo "Hello, SeaweedFS!" > hello.txt

# Filer에 업로드 (PUT 방식)
curl -X PUT \
  -F "file=@hello.txt" \
  "http://localhost:8888/test/hello.txt"
```

응답:

```json
{
  "name": "hello.txt",
  "size": 18
}
```

**파일 다운로드**:

```bash
curl "http://localhost:8888/test/hello.txt"
# Hello, SeaweedFS!
```

**디렉토리 목록 조회**:

```bash
curl "http://localhost:8888/test/?pretty=y"
```

응답:

```json
{
  "Path": "/test",
  "Entries": [
    {
      "FullPath": "/test/hello.txt",
      "Crtime": 1711708800,
      "Mtime": 1711708800,
      "FileSize": 18
    }
  ]
}
```

**파일 삭제**:

```bash
curl -X DELETE "http://localhost:8888/test/hello.txt"
```

### 6단계: S3 API 테스트

S3 Gateway는 `pathStyle` URL(`http://host:port/bucket/key`)을 사용합니다.

```bash
# 버킷 생성
curl -X PUT "http://localhost:8333/my-bucket"

# 파일 업로드
curl -X PUT \
  --data-binary "@hello.txt" \
  "http://localhost:8333/my-bucket/test/hello.txt"

# 파일 다운로드
curl "http://localhost:8333/my-bucket/test/hello.txt"

# 버킷 내 파일 목록
curl "http://localhost:8333/my-bucket/?list-type=2&max-keys=10"
```

> 💡 S3 API는 기본 설정에서 인증 없이 동작합니다. 운영 환경에서는 반드시 인증을 설정하세요. ([10편](10-production-guide.md))

### 7단계: 이미지 업로드 테스트

```bash
# 이미지 다운로드 (테스트용)
curl -o test.jpg "https://via.placeholder.com/300x200.jpg"

# Filer에 이미지 업로드
curl -X PUT \
  -F "file=@test.jpg" \
  "http://localhost:8888/images/test.jpg"

# 브라우저에서 확인
# http://localhost:8888/images/test.jpg
```

---

## 컨테이너 관리

```bash
# 서비스 중지 (데이터 유지)
docker compose stop

# 서비스 재시작
docker compose start

# 완전 삭제 (데이터도 삭제하려면 ./data/ 폴더 삭제)
docker compose down

# 특정 서비스만 재시작
docker compose restart seaweedfs-volume
```

---

## 로컬 환경 구조 요약

```
seaweedfs-local/
├── docker-compose.yml
└── data/
    ├── master/    ← Master 메타데이터 (볼륨 레지스트리)
    ├── volume1/   ← 실제 파일 데이터 (.dat, .idx)
    └── filer/     ← Filer 메타데이터 (LevelDB)

포트 맵핑:
  9333 → Master HTTP
  8080 → Volume HTTP
  8888 → Filer HTTP (REST API)
  8333 → S3 Gateway HTTP
```

---

## 요약

- `docker compose up -d`로 Master/Volume/Filer/S3 4개 서비스를 한 번에 실행
- Filer: `PUT /path/file` 업로드, `GET /path/file` 다운로드, `DELETE /path/file` 삭제
- S3: Path-style URL (`http://host:8333/bucket/key`)로 S3 API 사용
- `./data/` 폴더에 데이터가 영속 저장됨

---

## 다음 편 예고

Filer REST API의 다양한 기능(디렉토리 관리, 태깅, 파일 복사/이동)을 상세히 실습합니다.

→ **[04편: Filer REST API 실습](04-filer-api.md)**

---

## 참고 자료

- [SeaweedFS Docker Hub](https://hub.docker.com/r/chrislusf/seaweedfs) — hub.docker.com
- [SeaweedFS Getting Started](https://github.com/seaweedfs/seaweedfs/wiki/Getting-Started) — github.com
- [SeaweedFS Filer REST API](https://github.com/seaweedfs/seaweedfs/wiki/Filer-Server-API) — github.com
