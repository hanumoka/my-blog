# 공유 패키지 만들기 — 타입과 유틸리티를 한 곳에서 관리

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [02편: 프로젝트 초기 설정](02-project-setup.md)
> **시리즈**: NestJS + Next.js + Prisma 모노리포 가이드 3/10

---

## 개요

`packages/shared`는 백엔드와 프론트엔드가 **함께 쓰는 코드**를 담는 패키지입니다.
공통 타입 정의, 유틸리티 함수, 상수 등을 여기에 두면 중복 없이 양쪽에서 사용할 수 있습니다.
이 편에서는 shared 패키지를 만들고, NestJS/Next.js에서 참조하는 방법을 배웁니다.

---

## 핵심 개념 — 왜 shared 패키지인가

```
shared 패키지 없는 경우 (중복 발생):

apps/backend/src/types/user.ts
  export type UserRole = 'admin' | 'user';

apps/frontend/src/types/user.ts
  export type UserRole = 'admin' | 'user';   ← 똑같은 코드!

→ 한쪽을 바꾸면 다른 쪽도 직접 수정해야 함
→ 불일치 발생 → 런타임 버그 → 디버깅 지옥

shared 패키지 있는 경우:

packages/shared/src/types/user.ts
  export type UserRole = 'admin' | 'user';   ← 한 곳에만!

apps/backend + apps/frontend 모두 여기서 import
→ 변경은 한 번, 효과는 전체 적용
```

---

## 실습

### 1단계: packages/shared 초기화

```bash
cd packages/shared
```

```json
// packages/shared/package.json
{
  "name": "@my-monorepo/shared",
  "version": "0.0.1",
  "private": true,
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "import": "./dist/index.js",
      "require": "./dist/index.js",
      "types": "./dist/index.d.ts"
    }
  },
  "scripts": {
    "build": "tsc",
    "dev": "tsc --watch",
    "lint": "eslint src/"
  },
  "devDependencies": {
    "typescript": "^5.8.0"
  }
}
```

### 2단계: TypeScript 설정

```json
// packages/shared/tsconfig.json
{
  "extends": "../../tsconfig.json",
  "compilerOptions": {
    "outDir": "./dist",
    "rootDir": "./src",
    "declaration": true,
    "declarationMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["dist", "node_modules"]
}
```

### 3단계: 공유 타입 작성

```typescript
// packages/shared/src/types/user.ts
// Prisma의 Role enum과 일치하는 값 사용
export type UserRole = 'ADMIN' | 'USER' | 'GUEST';

export interface User {
  id: number;
  email: string;
  name: string;
  role: UserRole;
  createdAt: string;  // ISO 8601 문자열 (JSON 직렬화 시 Date → string)
}

export interface CreateUserDto {
  email: string;
  name: string;
  password: string;
  role?: UserRole;
}

export interface UpdateUserDto {
  name?: string;
  role?: UserRole;
}
```

```typescript
// packages/shared/src/types/api.ts
// API 응답의 공통 형식
export interface ApiResponse<T> {
  statusCode: number;
  data: T;
  message?: string;
  timestamp: string;
}

export interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}

// API 에러 응답 형식
export interface ApiError {
  statusCode: number;
  message: string | string[];
  error: string;
  timestamp: string;
}
```

```typescript
// packages/shared/src/constants/index.ts
export const API_ROUTES = {
  USERS: '/users',
  AUTH: '/auth',
  HEALTH: '/health',
} as const;

export const PAGINATION = {
  DEFAULT_PAGE: 1,
  DEFAULT_LIMIT: 10,
  MAX_LIMIT: 100,
} as const;
```

```typescript
// packages/shared/src/utils/format.ts
// 날짜 포맷 유틸 (FE/BE 공통)
export function formatDate(date: Date | string): string {
  return new Date(date).toISOString();
}

// 페이지네이션 계산
export function calcTotalPages(total: number, limit: number): number {
  return Math.ceil(total / limit);
}
```

### 4단계: 진입점(index.ts) 작성

```typescript
// packages/shared/src/index.ts
// 타입 내보내기
export * from './types/user';
export * from './types/api';

// 상수 내보내기
export * from './constants';

// 유틸리티 내보내기
export * from './utils/format';
```

### 5단계: shared 패키지 빌드

```bash
# 루트에서
pnpm --filter @my-monorepo/shared build
```

```
packages/shared/
├── src/
│   ├── types/
│   │   ├── user.ts
│   │   └── api.ts
│   ├── constants/
│   │   └── index.ts
│   ├── utils/
│   │   └── format.ts
│   └── index.ts
├── dist/            ← 빌드 결과물 (자동 생성)
│   ├── index.js
│   └── index.d.ts
├── package.json
└── tsconfig.json
```

### 6단계: 다른 앱에서 사용

shared 패키지를 앱에 추가합니다.

```bash
# 루트에서 실행
pnpm add @my-monorepo/shared@workspace:* --filter @my-monorepo/backend
pnpm add @my-monorepo/shared@workspace:* --filter @my-monorepo/frontend
```

백엔드에서 사용:

```typescript
// apps/backend/src/users/users.controller.ts
import { User, CreateUserDto, ApiResponse } from '@my-monorepo/shared';

@Controller('users')
export class UsersController {
  @Post()
  create(@Body() dto: CreateUserDto): ApiResponse<User> {
    // shared 패키지의 타입을 그대로 사용!
    ...
  }
}
```

프론트엔드에서 사용:

```typescript
// apps/frontend/src/app/users/page.tsx
import { User, API_ROUTES } from '@my-monorepo/shared';

async function getUsers(): Promise<User[]> {
  const res = await fetch(`http://localhost:3001/api/v1${API_ROUTES.USERS}`);
  return res.json();
}
```

---

## 개발 모드에서의 핫리로드

```bash
# packages/shared를 watch 모드로 실행
pnpm --filter @my-monorepo/shared dev

# 별도 터미널에서 앱 실행
pnpm --filter @my-monorepo/backend dev
```

> 💡 shared 코드를 수정하면 → tsc --watch가 자동 재빌드 → 앱이 변경 감지

---

## 요약

- `packages/shared`는 FE/BE가 공유하는 **타입, 상수, 유틸** 저장소
- `package.json`의 `"name": "@my-monorepo/shared"`로 패키지명 지정
- `exports` 필드로 `import` 방식 지정 (ESM/CJS 모두 지원)
- `workspace:*` 프로토콜로 로컬 패키지 참조 (`pnpm add ... --filter`)
- shared 수정 시 빌드 필요 → `tsc --watch`로 자동화 가능

---

## 다음 편 예고

데이터베이스 스키마를 공유하는 `packages/database` (Prisma) 패키지를 만듭니다.

→ **[04편: Prisma 공유 패키지](04-prisma-package.md)**

---

## 참고 자료

- [pnpm Filtering 공식 문서](https://pnpm.io/filtering) — pnpm.io
- [TypeScript Project References](https://www.typescriptlang.org/docs/handbook/project-references.html) — typescriptlang.org
- [package.json exports 필드](https://nodejs.org/api/packages.html#exports) — nodejs.org
