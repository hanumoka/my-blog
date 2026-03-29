# SeaweedFS란? — 분산 파일 시스템 입문

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: 파일 저장의 기본 개념
> **시리즈**: Spring Boot + SeaweedFS 학습 가이드 1/10

---

## 개요

웹 서비스에서 이미지, 동영상, 문서 등의 파일을 저장해야 할 때 어떻게 할까요?
로컬 디스크에 저장하면 서버가 여러 대일 때 문제가 생깁니다.
**SeaweedFS**는 이 문제를 해결하는 **분산 파일 시스템**입니다.
이 편에서는 분산 파일 시스템이 왜 필요한지, SeaweedFS가 무엇인지 알아봅니다.

---

## 왜 분산 파일 시스템이 필요한가?

```
문제 상황: 서버 2대에서 파일 업로드를 처리한다면?

사용자 A → 서버 1에 이미지 업로드 → /data/img/photo.jpg (서버 1에만 존재!)
사용자 B → 서버 2에서 이미지 다운로드 → /data/img/photo.jpg (없음! 404 에러)

┌───────────┐     ┌───────────┐
│  서버 1    │     │  서버 2    │
│  photo.jpg │     │  (없음!)   │
└───────────┘     └───────────┘

해결: 파일을 중앙 저장소에 보관
┌───────────┐     ┌───────────┐
│  서버 1    │     │  서버 2    │
└─────┬─────┘     └─────┬─────┘
      │                 │
      └────────┬────────┘
         ┌─────▼─────┐
         │  분산 파일  │
         │  시스템     │  ← SeaweedFS
         │  (공유 저장)│
         └───────────┘
```

---

## SeaweedFS란?

SeaweedFS는 Facebook의 **Haystack** 논문에서 영감을 받은 **오픈소스 분산 파일 시스템**입니다.
수십억 개의 파일을 빠르게 저장하고 읽을 수 있도록 설계되었습니다.

```
SeaweedFS v4.17 (2026년 3월 기준 최신)

핵심 특징:
  ├─ 수십억 개 파일 처리 가능
  ├─ O(1) 디스크 접근 (파일 수와 무관하게 빠름)
  ├─ AWS S3 호환 API 지원
  ├─ POSIX 파일 시스템 인터페이스 (FUSE 마운트)
  ├─ 데이터 복제 + Erasure Coding (데이터 보호)
  ├─ 적은 메모리 사용 (소규모는 수백 MB, 대규모도 2~4GB)
  └─ Apache 2.0 라이선스 (무료)
```

---

## SeaweedFS의 3계층 아키텍처

SeaweedFS는 3가지 핵심 컴포넌트로 구성됩니다.

```
┌──────────────────────────────────────────────────────────┐
│                      SeaweedFS                           │
│                                                          │
│  ┌──────────────────────────────┐                        │
│  │      S3 Gateway (선택)        │ ← AWS S3 호환 API     │
│  │       (포트 8333)             │                        │
│  └──────────────┬───────────────┘                        │
│                 │  (Filer 위에서 동작)                     │
│  ┌──────────────▼───────────────┐                        │
│  │         Filer (선택)          │ ← 경로 기반 접근       │
│  │       (포트 8888)             │   /images/photo.jpg    │
│  └──────────────┬───────────────┘                        │
│                 │  (Master에 FID 요청, Volume에 저장)      │
│  ┌──────────────▼───────────────┐                        │
│  │          Master               │ ← 볼륨 위치 관리       │
│  │        (포트 9333)            │   File ID 발급         │
│  └──────┬───────────────┬───────┘                        │
│         │               │                                │
│  ┌──────▼──────┐ ┌──────▼──────┐                         │
│  │  Volume 1   │ │  Volume 2   │ ← 실제 데이터 저장소    │
│  │ (포트 8080) │ │ (포트 8081) │                         │
│  └─────────────┘ └─────────────┘                         │
└──────────────────────────────────────────────────────────┘
```

### 각 컴포넌트 역할

| 컴포넌트 | 역할 | 비유 |
|----------|------|------|
| **Master** | 볼륨 위치 관리, File ID 발급 | 도서관 안내 데스크 |
| **Volume** | 실제 파일 데이터 저장 | 도서관 책장 |
| **Filer** | 경로 기반 파일 접근 (`/images/photo.jpg`) | 도서관 목록 카탈로그 |
| **S3 Gateway** | AWS S3 호환 API 제공 | 도서관의 온라인 주문 시스템 |

---

## 파일 저장 원리 — File ID (FID)

SeaweedFS는 파일마다 고유한 **File ID (FID)**를 부여합니다.

```
FID 구조: 3,01637037d6

3          = Volume ID (어떤 볼륨에 저장되었는지)
01637037d6 = File Key + Cookie (볼륨 내 위치 + 보안 토큰)

파일 저장 흐름:
1. 클라이언트 → Master에게 "파일 저장할 곳 알려줘" 요청
2. Master → "Volume 3에 저장해, FID는 3,01637037d6야" 응답
3. 클라이언트 → Volume 3에 실제 파일 업로드
4. 완료! FID를 DB에 저장해두면 나중에 파일을 찾을 수 있음
```

> 💡 **Filer**를 사용하면 FID 대신 `/images/photo.jpg` 같은 경로로 접근할 수 있습니다.
> **S3 Gateway**를 사용하면 AWS S3 API (`s3://bucket/key`)로 접근할 수 있습니다.

---

## SeaweedFS vs MinIO vs NFS

| 항목 | SeaweedFS | MinIO | NFS |
|------|-----------|-------|-----|
| 아키텍처 | Master-Volume | 서버 풀 | 클라이언트-서버 |
| 소형 파일 최적화 | O(1) 접근 | 최적화 없음 | 확장 한계 |
| S3 호환 | 핵심 기능 지원 | 가장 완전 | 미지원 |
| POSIX 지원 | FUSE 마운트 | 미지원 | 네이티브 |
| RAM 요구 | 2~4 GB | 4~32 GB | 가변 |
| 확장성 | 볼륨 추가만으로 확장 | 스토리지 레이아웃 고정 | 수직 확장 |
| 라이선스 | Apache 2.0 | AGPLv3 | - |
| 추천 상황 | 대량 소형 파일 | S3 완전 호환 필요 | 소규모 레거시 |

---

## 이 시리즈에서 배울 것

| 편 | 주제 |
|----|------|
| [01](01-what-is-seaweedfs.md) | SeaweedFS 소개 (현재) |
| [02](02-architecture.md) | 아키텍처 심화 |
| [03](03-docker-setup.md) | Docker로 로컬 환경 구축 |
| [04](04-filer-api.md) | Filer REST API 실습 |
| [05](05-s3-api.md) | S3 호환 API 실습 |
| [06](06-spring-boot-setup.md) | Spring Boot 프로젝트 설정 |
| [07](07-file-upload-download.md) | 파일 업로드/다운로드 구현 |
| [08](08-large-file-handling.md) | 대용량 파일 처리 |
| [09](09-replication-ec.md) | 데이터 안정성 (복제 + EC) |
| [10](10-production-guide.md) | 프로덕션 운영 가이드 |

---

## 요약

- **분산 파일 시스템**: 여러 서버에서 파일을 공유할 수 있는 중앙 저장소
- **SeaweedFS**: Facebook Haystack 기반, 수십억 파일을 O(1)로 처리하는 오픈소스
- **3계층 구조**: Filer(경로 인터페이스) → Master(위치 관리) → Volume(데이터 저장)
- **S3 호환**: AWS S3 API로 접근 가능 → Spring Boot에서 AWS SDK로 연동

---

## 다음 편 예고

SeaweedFS의 Master, Volume, Filer, S3 Gateway 각 컴포넌트의 동작 원리를 더 깊이 살펴봅니다.

→ **[02편: 아키텍처 심화](02-architecture.md)**

---

## 참고 자료

- [SeaweedFS GitHub](https://github.com/seaweedfs/seaweedfs) — github.com
- [SeaweedFS Wiki](https://github.com/seaweedfs/seaweedfs/wiki) — github.com
- [Facebook Haystack 논문](https://www.usenix.org/legacy/event/osdi10/tech/full_papers/Beaver.pdf) — usenix.org
