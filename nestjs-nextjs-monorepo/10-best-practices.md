# 모범 사례와 운영 가이드 — 모노리포 실무 핵심 정리

> **난이도**: 고급
> **소요 시간**: 약 3분
> **사전 지식**: [09편: Docker 빌드 전략](09-docker-build.md)
> **시리즈**: NestJS + Next.js + Prisma 모노리포 가이드 10/10 (최종편)

---

## 개요

9편에 걸쳐 모노리포의 핵심을 배웠습니다.
이 최종편에서는 실무에서 자주 마주치는 **의존성 관리**, **CI/CD**, **트러블슈팅**, 그리고 **흔한 함정**을 정리합니다.

---

## 실전 프로젝트 구조 전체 요약

```
my-monorepo/
├── apps/
│   ├── backend/              NestJS 11 API (포트 3001)
│   │   ├── src/
│   │   ├── Dockerfile
│   │   ├── package.json      @my-monorepo/backend
│   │   └── tsconfig.json
│   └── frontend/             Next.js 16 (포트 3000)
│       ├── app/
│       ├── Dockerfile
│       ├── next.config.ts
│       ├── package.json      @my-monorepo/frontend
│       └── tsconfig.json
├── packages/
│   ├── database/             Prisma 공유 (스키마 + 클라이언트)
│   │   ├── prisma/
│   │   ├── src/
│   │   └── package.json      @my-monorepo/database
│   └── shared/               공유 타입 + 유틸
│       ├── src/
│       └── package.json      @my-monorepo/shared
├── infra/
│   ├── local/                docker-compose (개발용)
│   └── prod/                 docker-compose (운영용)
├── package.json              루트 (scripts, devDependencies)
├── pnpm-workspace.yaml       워크스페이스 선언
├── turbo.json                빌드 파이프라인
├── tsconfig.json             루트 TS 설정
└── .dockerignore
```

---

## 의존성 관리 모범 사례

### pnpm catalogs — 버전 통일

pnpm 9.5+의 `catalogs` 기능으로 버전을 한 곳에서 관리합니다.

```yaml
# pnpm-workspace.yaml
packages:
  - "apps/*"
  - "packages/*"

catalogs:
  default:
    typescript: ^5.8.0
    "@types/node": ^22.0.0
  react:
    react: ^19.0.0
    react-dom: ^19.0.0
    "@types/react": ^19.0.0
```

앱에서 사용:

```json
// apps/frontend/package.json
{
  "dependencies": {
    "react": "catalog:react",           // catalogs.react.react 사용
    "react-dom": "catalog:react"
  },
  "devDependencies": {
    "typescript": "catalog:",           // catalogs.default.typescript 사용
    "@types/react": "catalog:react"
  }
}
```

이렇게 하면 모든 앱이 **동일한 버전**을 보장합니다.

### 의존성 추가 방법

```bash
# 특정 앱에만 추가
pnpm add axios --filter @my-monorepo/frontend

# 특정 앱의 dev 의존성
pnpm add -D @types/node --filter @my-monorepo/backend

# 모든 워크스페이스에 추가 (루트)
pnpm add -w turbo

# workspace 패키지 참조
pnpm add @my-monorepo/shared@workspace:* --filter @my-monorepo/backend
```

---

## Turborepo 캐시 활용

```json
// turbo.json
{
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", ".next/**", "src/generated/**"],
      "inputs": ["src/**", "prisma/**", "package.json", "tsconfig.json"]
    },
    "test": {
      "dependsOn": ["^build"],
      "outputs": ["coverage/**"],
      "inputs": ["src/**", "test/**"]
    }
  }
}
```

`inputs` 명시 → 관련 파일이 변경되지 않으면 캐시 히트 → 빌드 생략.

---

## CI/CD 파이프라인 (GitHub Actions)

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2  # Turborepo diff 감지용

      - uses: pnpm/action-setup@v4
        with:
          version: 10

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: 'pnpm'

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      - name: Generate Prisma Client
        run: pnpm db:generate

      - name: Build (캐시 활용)
        run: pnpm build
        env:
          TURBO_TOKEN: ${{ secrets.TURBO_TOKEN }}  # Remote Cache
          TURBO_TEAM: ${{ vars.TURBO_TEAM }}

      - name: Lint
        run: pnpm lint

      - name: Test
        run: pnpm test
        env:
          DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}

  docker-build:
    runs-on: ubuntu-latest
    needs: build-and-test
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4

      - name: Build backend image
        run: |
          docker build -f apps/backend/Dockerfile \
            -t ${{ vars.REGISTRY }}/backend:${{ github.sha }} .

      - name: Build frontend image
        run: |
          docker build -f apps/frontend/Dockerfile \
            --build-arg BACKEND_URL=${{ vars.BACKEND_URL }} \
            -t ${{ vars.REGISTRY }}/frontend:${{ github.sha }} .
```

---

## 흔한 함정과 해결책

```
❌ 함정 1: packages/database를 빌드하지 않고 사용
  → "Cannot find module @my-monorepo/database" 에러
  ✅ 해결: tsconfig.json의 paths 설정으로 소스 직접 참조

❌ 함정 2: Prisma Client가 앱마다 다른 경로에 생성됨
  → 타입 불일치, 런타임 에러
  ✅ 해결: schema.prisma의 output을 custom path로 지정
            ("../src/generated/prisma")

❌ 함정 3: docker build를 앱 폴더에서 실행
  → "turbo prune: turbo.json not found"
  ✅ 해결: docker build는 반드시 모노리포 루트에서 실행

❌ 함정 4: node_modules 있는 폴더를 Docker context에 포함
  → 빌드 context가 수 GB로 늘어남
  ✅ 해결: .dockerignore에 node_modules/, .next/, dist/ 추가

❌ 함정 5: 워크스페이스 의존성을 version으로 참조
  "dependencies": { "@my-monorepo/shared": "0.0.1" }
  → pnpm이 npm 레지스트리에서 찾으려 함 (없음!)
  ✅ 해결: workspace:* 프로토콜 사용

❌ 함정 6: 루트 node_modules의 패키지와 앱 node_modules 충돌
  → 같은 패키지의 서로 다른 인스턴스
  ✅ 해결: 루트 package.json에서 공통 dev 의존성만 관리
```

---

## 로컬 개발 워크플로우 요약

```bash
# 최초 셋업
git clone <repo>
cd my-monorepo
pnpm install              # 전체 의존성 설치
pnpm db:generate          # Prisma 클라이언트 생성
pnpm infra:up             # DB + Redis 시작
pnpm db:migrate           # 마이그레이션 실행
pnpm db:seed              # 시드 데이터 삽입
pnpm dev                  # 전체 앱 개발 서버 시작

# 일상적인 개발
pnpm dev                  # 개발 서버
pnpm build                # 전체 빌드 (캐시 활용)
pnpm test                 # 전체 테스트
pnpm lint                 # 전체 린트

# 스키마 변경 시
# 1. packages/database/prisma/schema.prisma 수정
pnpm db:migrate           # 마이그레이션 생성 + 적용
pnpm db:generate          # 클라이언트 재생성
# 2. packages/shared/src/types/ 타입 업데이트
# 3. apps/backend, apps/frontend 컴파일 에러 확인 + 수정
```

---

## 시리즈 마무리

| 편 | 주제 | 핵심 |
|----|------|------|
| [01](01-monorepo-intro.md) | 모노리포 소개 | 모노리포 vs 멀티리포, pnpm, Turborepo |
| [02](02-project-setup.md) | 초기 설정 | pnpm-workspace.yaml, turbo.json |
| [03](03-shared-package.md) | shared 패키지 | 공유 타입, 유틸, 상수 |
| [04](04-prisma-package.md) | database 패키지 | Prisma 스키마, custom output |
| [05](05-nestjs-backend.md) | NestJS 백엔드 | PrismaService, CRUD API |
| [06](06-nextjs-frontend.md) | Next.js 프론트엔드 | App Router, transpilePackages |
| [07](07-type-sharing.md) | 타입 공유 | SSOT, 엔드투엔드 타입 안전성 |
| [08](08-dev-environment.md) | 개발 환경 | Docker Compose, 시드 데이터 |
| [09](09-docker-build.md) | Docker 빌드 | turbo prune, 멀티스테이지 |
| [10](10-best-practices.md) | 모범 사례 | 의존성 관리, CI/CD, 함정 정리 |

모노리포는 초기 설정이 복잡하지만, 한 번 잘 구축하면 **팀 생산성**과 **코드 일관성**이 크게 향상됩니다!

---

## 참고 자료

- [pnpm Catalogs 공식 문서](https://pnpm.io/catalogs) — pnpm.io
- [Turborepo Remote Caching](https://turbo.build/repo/docs/core-concepts/remote-caching) — turbo.build
- [GitHub Actions pnpm 설정](https://pnpm.io/continuous-integration#github-actions) — pnpm.io
- [Turborepo + GitHub Actions](https://turbo.build/repo/docs/ci/github-actions) — turbo.build
