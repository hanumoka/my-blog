# 모노리포란? — 왜 하나의 저장소에 모든 것을 담는가

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: Git 기본 사용법
> **시리즈**: NestJS + Next.js + Prisma 모노리포 가이드 1/10

---

## 개요

백엔드(NestJS), 프론트엔드(Next.js), 데이터베이스 스키마(Prisma)를 **하나의 Git 저장소**에서 관리하는 방식을 **모노리포(Monorepo)**라고 합니다.
이 편에서는 모노리포가 무엇인지, 왜 사용하는지, 그리고 우리가 만들 프로젝트 구조를 살펴봅니다.

---

## 모노리포 vs 멀티리포

### 멀티리포 (Polyrepo) — 전통적인 방식

```
GitHub Repositories:
  my-company/backend    ← NestJS API 서버
  my-company/frontend   ← Next.js 웹앱
  my-company/database   ← Prisma 스키마
  my-company/shared     ← 공유 타입

각각 독립적인 Git 저장소
```

멀티리포의 문제점:
- 백엔드 API 변경 → 프론트엔드에서 수동으로 타입 업데이트
- 공유 패키지 수정 → npm publish → 각 저장소에서 버전 업데이트
- 전체 기능 하나 추가하는데 4개 저장소를 넘나들어야 함

### 모노리포 (Monorepo) — 우리가 선택한 방식

```
┌─────────────────────────────────────────────────────┐
│                  my-project/ (Git)                  │
│                                                     │
│  apps/                  packages/                   │
│  ├─ backend/            ├─ database/   ← Prisma     │
│  │  └─ (NestJS 11)      │  └─ schema.prisma        │
│  └─ frontend/           └─ shared/    ← 공유 타입   │
│     └─ (Next.js 16)        └─ types.ts              │
│                                                     │
│  하나의 저장소, 하나의 커밋, 하나의 PR              │
└─────────────────────────────────────────────────────┘
```

모노리포의 장점:
- **타입 공유**: 백엔드 DTO가 바뀌면 프론트엔드가 즉시 컴파일 에러로 알 수 있음
- **원자적 커밋**: 기능 하나를 하나의 커밋으로 전체 변경 가능
- **의존성 통일**: 모든 앱이 같은 버전의 TypeScript, ESLint 사용
- **코드 재사용**: 공통 유틸, 상수, 타입을 패키지로 분리해서 공유

---

## 핵심 도구 — pnpm + Turborepo

이 시리즈에서는 두 가지 핵심 도구를 사용합니다.

### pnpm — 효율적인 패키지 매니저

```
npm/yarn:                        pnpm:
node_modules/                    node_modules/ (심볼릭 링크)
  ├─ express/ (복사본 A)          ├─ express/ ─→ ~/.pnpm-store/
  ├─ express/ (복사본 B)          (전역 스토어에 1개만 저장!)
  └─ express/ (복사본 C)
```

- 디스크 사용량 60~80% 절감
- `workspace:*` 프로토콜로 로컬 패키지 참조
- npm보다 2~3배 빠른 설치 속도

### Turborepo — 모노리포 빌드 오케스트레이터

```
빌드 순서 자동 최적화:

packages/database  →  apps/backend   ┐
    (먼저 빌드)         (나중 빌드)   ├─ 병렬 빌드!
packages/shared    →  apps/frontend  ┘
    (먼저 빌드)         (나중 빌드)

+ 캐시: 변경 없으면 이전 결과 재사용
```

---

## 우리가 만들 프로젝트

이 시리즈를 통해 다음 구조의 풀스택 모노리포를 처음부터 만듭니다.

```
my-monorepo/
├── apps/
│   ├── backend/          NestJS 11 — REST API 서버 (포트 3001)
│   └── frontend/         Next.js 16 — 웹 앱 (포트 3000)
├── packages/
│   ├── database/         Prisma 7 — DB 스키마 + 클라이언트
│   └── shared/           공유 타입, 유틸리티
├── package.json          워크스페이스 루트
├── pnpm-workspace.yaml   pnpm 워크스페이스 설정
└── turbo.json            Turborepo 파이프라인 설정
```

| 편 | 주제 |
|----|------|
| [01](01-monorepo-intro.md) | 모노리포 개요 (현재) |
| [02](02-project-setup.md) | pnpm + Turborepo 초기 설정 |
| [03](03-shared-package.md) | shared 패키지 만들기 |
| [04](04-prisma-package.md) | database 패키지 (Prisma) |
| [05](05-nestjs-backend.md) | NestJS 백엔드 셋업 |
| [06](06-nextjs-frontend.md) | Next.js 프론트엔드 셋업 |
| [07](07-type-sharing.md) | 타입 안전한 API 통신 |
| [08](08-dev-environment.md) | Docker Compose 개발 환경 |
| [09](09-docker-build.md) | Docker 멀티스테이지 빌드 |
| [10](10-best-practices.md) | 모범 사례와 운영 가이드 |

---

## 요약

- **모노리포**: 여러 앱/패키지를 하나의 Git 저장소에서 관리
- **핵심 장점**: 타입 공유, 원자적 커밋, 의존성 통일, 코드 재사용
- **pnpm**: 효율적인 패키지 매니저 (디스크 절감 + 빠른 설치)
- **Turborepo**: 빌드 순서 최적화 + 캐시로 빌드 속도 향상
- 구조: `apps/` (실행 앱) + `packages/` (공유 라이브러리)

---

## 다음 편 예고

실제로 폴더를 만들고, pnpm + Turborepo를 설치하고, 워크스페이스를 구성합니다.

→ **[02편: 프로젝트 초기 설정](02-project-setup.md)**

---

## 참고 자료

- [pnpm Workspaces 공식 문서](https://pnpm.io/workspaces) — pnpm.io
- [Turborepo 공식 문서](https://turbo.build/repo/docs) — turbo.build
- [Monorepo Tools 비교](https://monorepo.tools/) — monorepo.tools
