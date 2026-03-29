# SeaweedFS 아키텍처 심화 — Master, Volume, Filer, S3 완전 이해

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [01편: SeaweedFS란?](01-what-is-seaweedfs.md)
> **시리즈**: Spring Boot + SeaweedFS 학습 가이드 2/10

---

## 개요

01편에서 SeaweedFS의 3계층 구조를 간략히 살펴봤습니다.
이번 편에서는 각 컴포넌트(Master, Volume, Filer, S3 Gateway)가 **내부에서 어떻게 동작하는지** 깊이 이해합니다.
파일 저장 흐름을 단계별로 추적하면, 왜 SeaweedFS가 빠른지 자연스럽게 이해됩니다.

---

## Master 서버 — 클러스터의 두뇌

Master 서버는 Volume 서버들의 위치와 상태를 관리합니다.
**파일을 직접 저장하지 않고**, 어디에 저장해야 하는지만 알려줍니다.

```
Master 서버의 역할:

1. 볼륨 레지스트리 관리
   ┌─────────────────────────────────────┐
   │ Volume ID │ 서버 주소    │ 남은 공간 │
   │     1     │ 192.168.1.10 │  45 GB   │
   │     2     │ 192.168.1.11 │  38 GB   │
   │     3     │ 192.168.1.10 │  12 GB   │
   └─────────────────────────────────────┘

2. File ID 발급 (전역 유일)
   클라이언트가 "저장할 곳 알려줘" → Master가 FID 발급
   FID: 3,01637037d6  ← Volume 3번에 이 ID로 저장하세요

3. 볼륨 상태 모니터링
   Volume 서버들이 주기적으로 heartbeat 전송
   → Master가 죽은 서버 감지, 자동으로 레플리카 재생성
```

### Master 고가용성 (HA)

운영 환경에서는 **Raft 합의 알고리즘**으로 Master를 여러 대 운영합니다.
3대 중 2대가 살아 있으면 서비스가 유지됩니다.

```
        ┌──────────────┐
        │  Master 1    │ ← Leader (쓰기 처리)
        │  (포트 9333)  │
        └──────┬───────┘
               │  Raft
        ┌──────▼───────┐   ┌──────────────┐
        │  Master 2    │   │  Master 3    │
        │  (포트 9334)  │   │  (포트 9335)  │
        └──────────────┘   └──────────────┘
        Follower           Follower
        (Leader 죽으면 자동 승격)
```

---

## Volume 서버 — 실제 데이터 창고

Volume 서버는 **실제 파일 데이터를 저장**합니다.
핵심 아이디어는 **여러 파일을 하나의 큰 파일(Needle Container)에 묶어 저장**하는 것입니다.

```
일반 파일 시스템 vs SeaweedFS Volume:

일반 방식:
  /data/1.jpg  (디스크 inode 소비)
  /data/2.jpg  (디스크 inode 소비)
  /data/3.jpg  (디스크 inode 소비)
  → 파일 수가 많아질수록 inode 부족, 메모리 낭비

SeaweedFS Volume:
  volume_001.dat  ← 여러 파일을 하나로 묶음
  ┌────────────────────────────────────────┐
  │ Needle 1: [헤더][1.jpg 데이터][패딩]    │
  │ Needle 2: [헤더][2.jpg 데이터][패딩]    │
  │ Needle 3: [헤더][3.jpg 데이터][패딩]    │
  └────────────────────────────────────────┘
  volume_001.idx  ← 인덱스 (offset 위치 기록)

  → 파일 위치를 메모리에 캐시 → O(1) 접근
  → inode 소비 최소화 (볼륨 파일 1개만)
```

### Volume의 쓰기/읽기 흐름

```
쓰기:
  클라이언트 → Volume 서버
  Volume이 .dat 파일 끝에 Needle 추가 (append-only)
  .idx 파일에 offset 기록

읽기:
  클라이언트 → Volume 서버에 FID 전달
  .idx에서 offset 조회 (메모리 캐시)
  .dat 파일의 해당 offset으로 seek → 데이터 반환

삭제:
  실제로 지우지 않고 "삭제 표시(tombstone)"만 함
  → 이후 Compaction 작업에서 실제 제거
```

---

## Filer 서버 — 파일 경로 인터페이스

Filer는 FID 기반의 SeaweedFS 위에 **경로(path) 기반 접근**을 추가합니다.
`/images/2026/photo.jpg` 같은 경로를 FID와 매핑하는 **메타데이터 레이어**입니다.

```
Filer 메타데이터 저장 구조:

  /images/photo.jpg → FID: 3,01637037d6
  /docs/report.pdf  → FID: 1,02abc12345
  /videos/intro.mp4 → FID: 2,03def67890

메타데이터 백엔드 (선택 가능):
  ├─ 내장 LevelDB (기본, 단일 서버)
  ├─ MySQL / PostgreSQL
  ├─ Redis
  ├─ Cassandra
  └─ etcd (분산 환경)
```

### Filer 접근 방식

```
Filer REST API:
  PUT  /path/to/file    → 파일 업로드
  GET  /path/to/file    → 파일 다운로드
  DELETE /path/to/file  → 파일 삭제
  GET  /path/to/dir/    → 디렉토리 목록 (JSON)

POSIX 마운트 (FUSE):
  weed mount -filer=localhost:8888 -dir=/mnt/seaweed
  → 일반 파일 시스템처럼 ls, cp, mv 가능
```

---

## S3 Gateway — AWS S3 호환 레이어

S3 Gateway는 Filer 위에서 **AWS S3 프로토콜**을 구현합니다.
Spring Boot의 AWS SDK를 그대로 사용할 수 있게 해주는 핵심 컴포넌트입니다.

```
S3 API 지원 목록:

  버킷 관리:
    CreateBucket, DeleteBucket, ListBuckets, HeadBucket

  객체 관리:
    PutObject, GetObject, DeleteObject, HeadObject
    ListObjects, ListObjectsV2, CopyObject

  멀티파트 업로드 (대용량 파일):
    CreateMultipartUpload, UploadPart
    CompleteMultipartUpload, AbortMultipartUpload

  메타데이터:
    GetObjectTagging, PutObjectTagging

  ⚠ 미지원: ACL 상세 설정, S3 이벤트 알림, 람다 트리거
```

---

## 전체 파일 저장 흐름 (완전 정리)

```
시나리오: /images/photo.jpg 파일을 Filer로 업로드

1. 클라이언트
   PUT http://filer:8888/images/photo.jpg
   (파일 데이터 첨부)
            │
            ▼
2. Filer 서버 (포트 8888)
   "이 파일 어디에 저장하지?"
   → Master에게 File ID 요청
            │
            ▼
3. Master 서버 (포트 9333)
   "Volume 3에 저장하세요"
   → FID: 3,01637037d6 발급
   → Volume 3 주소: 192.168.1.10:8080
            │
            ▼
4. Filer 서버
   → Volume 서버(192.168.1.10:8080)에 파일 전송
   → 메타데이터 저장: /images/photo.jpg → 3,01637037d6
            │
            ▼
5. Volume 서버 (포트 8080)
   → volume_3.dat에 Needle 추가
   → volume_3.idx에 offset 기록
   → 완료 응답


나중에 읽을 때:
   GET http://filer:8888/images/photo.jpg
   Filer → 메타데이터 조회 → FID: 3,01637037d6
   Filer → Volume 3에서 데이터 읽어 반환
```

---

## 컴포넌트별 포트 정리

| 컴포넌트 | 기본 포트 | 프로토콜 | 용도 |
|----------|-----------|----------|------|
| Master | 9333 | HTTP/gRPC | 볼륨 관리, FID 발급 |
| Volume | 8080 | HTTP | 파일 데이터 읽기/쓰기 |
| Filer | 8888 | HTTP | 경로 기반 파일 접근 |
| Filer gRPC | 18888 | gRPC | 내부 통신 |
| S3 Gateway | 8333 | HTTP | S3 호환 API |

---

## 요약

- **Master**: 볼륨 위치 관리 + File ID 발급 (파일 저장 안 함), Raft HA 지원
- **Volume**: 파일 데이터를 Needle Container에 append-only 저장, O(1) 읽기
- **Filer**: 경로↔FID 매핑 메타데이터 레이어, REST/FUSE 접근 지원
- **S3 Gateway**: Filer 위에서 AWS S3 API 구현, Spring AWS SDK 호환
- 파일 저장 흐름: 클라이언트 → Filer → Master(FID 요청) → Volume(데이터 저장)

---

## 다음 편 예고

실제로 Docker Compose로 SeaweedFS를 로컬에 띄우고, 브라우저에서 파일을 업로드해봅니다.

→ **[03편: Docker로 로컬 환경 구축](03-docker-setup.md)**

---

## 참고 자료

- [SeaweedFS Architecture Wiki](https://github.com/seaweedfs/seaweedfs/wiki/Architecture) — github.com
- [SeaweedFS Filer Wiki](https://github.com/seaweedfs/seaweedfs/wiki/Filer) — github.com
- [Facebook Haystack 논문](https://www.usenix.org/legacy/event/osdi10/tech/full_papers/Beaver.pdf) — usenix.org
