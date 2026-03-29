# 프로젝트 초기 설정 — pnpm + Turborepo로 모노리포 만들기

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [01편: 모노리포란?](01-monorepo-intro.md)
> **시리즈**: NestJS + Next.js + Prisma 모노리포 가이드 2/10

---

## 개요

이번 편에서는 모노리포의 **뼈대**를 실제로 만듭니다.
pnpm 워크스페이스를 설정하고, Turborepo를 추가한 뒤, 빈 앱/패키지 폴더 구조를 갖춥니다.
이 편이 끝나면 `pnpm install` 하나로 모든 의존성이 설치되는 구조가 완성됩니다.

---

## 핵심 개념 — pnpm 워크스페이스

```
pnpm-workspace.yaml 로 워크스페이스를 선언하면:

my-monorepo/
├── pnpm-workspace.yaml   ← "여기가 루트야"
├── apps/*                ← 모든 앱 워크스페이스
└── packages/*            ← 모든 패키지 워크스페이스

pnpm install 시 루트에서 한 번만 실행하면
→ apps/backend/, apps/frontend/, packages/* 모두 설치됨
→ 중복 의존성은 하나의 store에만 저장됨
```

---

## 실습

### 1단계: Node.js 22 + pnpm 설치 확인

```bash
# Node.js 22 LTS 확인
node --version   # v22.x.x

# pnpm 설치 (없는 경우)
npm install -g pnpm@latest

# pnpm 버전 확인
pnpm --version   # 10.x.x
```

### 2단계: 프로젝트 폴더 생성

```bash
mkdir my-monorepo
cd my-monorepo
git init
```

### 3단계: 루트 package.json 작성

```json
{
  "name": "my-monorepo",
  "version": "0.0.1",
  "private": true,
  "scripts": {
    "dev": "turbo run dev",
    "build": "turbo run build",
    "lint": "turbo run lint",
    "test": "turbo run test"
  },
  "devDependencies": {
    "turbo": "^2.8.0",
    "typescript": "^5.8.0"
  },
  "engines": {
    "node": ">=22",
    "pnpm": ">=10"
  }
}
```

> 💡 `"private": true` — 모노리포 루트는 npm에 배포하지 않으므로 필수입니다.

### 4단계: pnpm 워크스페이스 설정

```yaml
# pnpm-workspace.yaml (루트에 생성)
packages:
  - "apps/*"
  - "packages/*"
```

이 파일이 있으면 pnpm이 `apps/`와 `packages/` 아래의 폴더를 모두 워크스페이스로 인식합니다.

### 5단계: Turborepo 설정

```json
// turbo.json (루트에 생성)
{
  "$schema": "https://turbo.build/schema.json",
  "ui": "tui",
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", ".next/**"]
    },
    "dev": {
      "persistent": true,
      "cache": false
    },
    "lint": {
      "dependsOn": ["^build"]
    },
    "test": {
      "dependsOn": ["^build"]
    }
  }
}
```

`"dependsOn": ["^build"]` 의미:
- `^` 접두사 = **의존하는 패키지를 먼저** 빌드하라
- 예: `apps/backend`가 `packages/database`에 의존하면, database를 먼저 빌드

### 6단계: 폴더 구조 생성

```bash
# 앱 폴더
mkdir -p apps/backend
mkdir -p apps/frontend

# 패키지 폴더
mkdir -p packages/database
mkdir -p packages/shared
```

### 7단계: .gitignore 설정

```gitignore
# .gitignore (루트에 생성)
node_modules/
dist/
.next/
.turbo/
*.env
*.env.local
```

### 8단계: 의존성 설치

```bash
# 현재는 루트 devDependencies(turbo, typescript)만 설치됩니다.
# apps/*, packages/* 폴더에 package.json이 아직 없으므로 워크스페이스 패키지는 없습니다.
# 다음 편(03~06)에서 각 패키지를 만든 후 다시 pnpm install을 실행합니다.
pnpm install
```

현재 구조 확인:

```
my-monorepo/
├── apps/
│   ├── backend/
│   └── frontend/
├── packages/
│   ├── database/
│   └── shared/
├── node_modules/       ← 루트 공통 의존성
├── package.json
├── pnpm-workspace.yaml
├── turbo.json
└── .gitignore
```

### 9단계: TypeScript 루트 설정

```json
// tsconfig.json (루트에 생성)
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "lib": ["ES2022"],
    "strict": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "esModuleInterop": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  }
}
```

각 앱/패키지의 `tsconfig.json`은 이 루트 설정을 `extends`로 상속합니다.

---

## 워크스페이스 패키지 참조 방법

다른 워크스페이스 패키지를 의존성으로 추가할 때는 `workspace:*` 프로토콜을 사용합니다.

```bash
# apps/backend 에서 packages/database를 의존성으로 추가
cd apps/backend
pnpm add @my-monorepo/database@workspace:*

# apps/frontend 에서 packages/shared를 의존성으로 추가
cd apps/frontend
pnpm add @my-monorepo/shared@workspace:*
```

`workspace:*` 의미: npm 레지스트리가 아닌 **로컬 워크스페이스**에서 참조.
실제 빌드/배포 시 현재 버전 번호로 자동 교체됩니다.

---

## 요약

- 루트 `package.json`에 `"private": true`와 Turborepo 스크립트 설정
- `pnpm-workspace.yaml`에 `apps/*`, `packages/*` 선언
- `turbo.json`의 `"dependsOn": ["^build"]`으로 빌드 순서 자동 결정
- `workspace:*` 프로토콜로 로컬 패키지 간 의존성 연결
- 루트에서 `pnpm install` 한 번으로 전체 의존성 설치

---

## 다음 편 예고

백엔드와 프론트엔드가 공유할 타입과 유틸리티를 담는 `packages/shared` 패키지를 만듭니다.

→ **[03편: 공유 패키지 만들기](03-shared-package.md)**

---

## 참고 자료

- [pnpm Workspaces 공식 문서](https://pnpm.io/workspaces) — pnpm.io
- [Turborepo Getting Started](https://turbo.build/repo/docs/getting-started) — turbo.build
- [Turborepo turbo.json 레퍼런스](https://turbo.build/repo/docs/reference/configuration) — turbo.build
