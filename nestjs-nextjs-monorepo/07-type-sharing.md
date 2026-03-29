# 타입 안전한 API 통신 — FE와 BE가 같은 타입을 쓴다

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [06편: Next.js 프론트엔드 셋업](06-nextjs-frontend.md)
> **시리즈**: NestJS + Next.js + Prisma 모노리포 가이드 7/10

---

## 개요

모노리포의 최대 장점 중 하나는 **엔드투엔드 타입 안전성**입니다.
백엔드 API 응답 구조가 바뀌면 프론트엔드가 **컴파일 타임**에 즉시 에러를 냅니다.
이 편에서는 FE↔BE 타입 공유 패턴과, 더 강력한 API 타입 안전성을 위한 전략을 배웁니다.

---

## 핵심 개념 — 타입 불일치 문제

```
모노리포 이전:
  BE: { user: { id: number, email: string, userName: string } }
  FE: interface User { id: number, email: string, name: string }
                                                  ↑ 이름이 다름!
  → 런타임 에러 (빌드 성공, 실행 시 undefined)

모노리포 이후:
  packages/shared: interface User { id: number, email: string, name: string }
  BE: 이 타입 사용 → name을 userName으로 바꾸면?
  FE: 즉시 컴파일 에러! "Property 'name' does not exist"
  → 런타임 에러 0개, 컴파일 에러로 사전 차단
```

---

## 패턴 1: 기본 타입 공유 (03편에서 구축)

```typescript
// packages/shared/src/types/user.ts
export interface User {
  id: number;
  email: string;
  name: string;
  role: UserRole;
  createdAt: string;
}

export type UserRole = 'ADMIN' | 'USER' | 'GUEST';
```

FE와 BE 모두 이 타입을 import → 타입이 자동으로 일치.

---

## 패턴 2: API 응답 타입 공유

```typescript
// packages/shared/src/types/api.ts

// 단일 항목 응답
export interface ApiResponse<T> {
  statusCode: number;
  data: T;
  message?: string;
  timestamp: string;
}

// 목록 + 페이지네이션 응답
export interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}

// 에러 응답
export interface ApiError {
  statusCode: number;
  message: string | string[];
  error: string;
  timestamp: string;
}
```

백엔드에서 사용:

```typescript
// apps/backend/src/users/users.controller.ts
import { ApiResponse, PaginatedResponse, User } from '@my-monorepo/shared';

@Get()
findAll(): ApiResponse<User[]> {
  // 반환 타입이 ApiResponse<User[]>로 강제됨
}
```

프론트엔드에서 사용:

```typescript
// apps/frontend/lib/api-client.ts
import { ApiResponse, User } from '@my-monorepo/shared';

const response: ApiResponse<User[]> = await fetch(...).then(r => r.json());
const users: User[] = response.data;  // 타입 자동 추론
```

---

## 패턴 3: 요청 DTO 타입 공유

```typescript
// packages/shared/src/types/user.ts 에 추가

// 생성 요청 타입 (FE 폼 + BE DTO 모두 활용)
export interface CreateUserDto {
  email: string;
  name: string;
  password: string;
  role?: UserRole;
}

// 수정 요청 타입
export interface UpdateUserDto {
  name?: string;
  role?: UserRole;
}
```

백엔드 DTO가 이 인터페이스를 `implements`:

```typescript
// apps/backend/src/users/dto/create-user.dto.ts
import { IsEmail, IsString, MinLength } from 'class-validator';
import { CreateUserDto } from '@my-monorepo/shared';

export class CreateUserDto implements CreateUserDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(2)
  name: string;

  @IsString()
  @MinLength(8)
  password: string;
}
// CreateUserDto에 필드를 추가하면 → DTO도 컴파일 에러!
```

프론트엔드 폼도 같은 타입 사용:

```typescript
// apps/frontend/components/UserForm.tsx
import { CreateUserDto } from '@my-monorepo/shared';

const [form, setForm] = useState<CreateUserDto>({
  email: '', name: '', password: ''
});
```

---

## 패턴 4: 타입 안전 API 클라이언트

```typescript
// packages/shared/src/api/endpoints.ts
// API 엔드포인트 + 요청/응답 타입을 한 곳에서 정의

import type { User, CreateUserDto, ApiResponse, PaginatedResponse } from '../types';

// API 엔드포인트 레지스트리
export interface ApiEndpoints {
  'GET /users': {
    request: { page?: number; limit?: number };
    response: ApiResponse<PaginatedResponse<User>>;
  };
  'GET /users/:id': {
    request: { id: number };
    response: ApiResponse<User>;
  };
  'POST /users': {
    request: CreateUserDto;
    response: ApiResponse<User>;
  };
  'DELETE /users/:id': {
    request: { id: number };
    response: void;
  };
}
```

`packages/shared/src/index.ts`에 export를 추가합니다:

```typescript
// packages/shared/src/index.ts 에 추가
export * from './api/endpoints';
```

```typescript
// apps/frontend/lib/typed-api-client.ts
import type { ApiEndpoints } from '@my-monorepo/shared';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:3001';
type Method = 'GET' | 'POST' | 'PUT' | 'DELETE';

// 타입 안전 fetch 래퍼
async function apiCall<K extends keyof ApiEndpoints>(
  endpoint: K,
  request: ApiEndpoints[K]['request'],
): Promise<ApiEndpoints[K]['response']> {
  const [method, rawPath] = (endpoint as string).split(' ') as [Method, string];

  // URL 파라미터 치환 (:id → 실제 값)
  let path = rawPath;
  const reqObj = request as Record<string, unknown>;
  path = path.replace(/:(\w+)/g, (_, key) => String(reqObj[key]));

  // GET 쿼리 파라미터 처리
  let url = `${BACKEND_URL}/api/v1${path}`;
  if (method === 'GET' && request) {
    const params = new URLSearchParams(
      Object.entries(reqObj)
        .filter(([k, v]) => v !== undefined && !rawPath.includes(`:${k}`))
        .map(([k, v]) => [k, String(v)])
    );
    if (params.toString()) url += `?${params}`;
  }

  const response = await fetch(url, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: method !== 'GET' ? JSON.stringify(request) : undefined,
  });

  if (!response.ok) throw new Error(`API error: ${response.status}`);
  if (response.status === 204) return undefined as ApiEndpoints[K]['response'];
  return response.json();
}

// 사용 예시 (자동완성 + 타입 체크!)
const result = await apiCall('GET /users', { page: 1, limit: 10 });
// result 타입: ApiResponse<PaginatedResponse<User>>
// result.data.items 타입: User[]
```

---

## 타입 공유 흐름 전체 그림

```
packages/shared/
  types/user.ts → User, CreateUserDto, UserRole
  types/api.ts  → ApiResponse<T>, PaginatedResponse<T>
        │
        ├──── apps/backend/
        │       DTO implements CreateUserDto
        │       Controller returns ApiResponse<User>
        │       Service returns User (from Prisma)
        │
        └──── apps/frontend/
                Form uses CreateUserDto
                API client returns ApiResponse<User[]>
                Component renders User[]

변경 사항 전파:
  shared 타입 변경 → BE + FE 동시에 컴파일 에러
  → 누락 없이 모든 변경 지점 파악 가능
```

---

## 요약

- `packages/shared`의 타입으로 FE↔BE 타입을 **단일 진실 공급원(SSOT)**으로 관리
- 요청 DTO, 응답 타입, API 엔드포인트 타입 모두 공유 가능
- BE DTO가 shared 인터페이스를 `implements` → 타입 불일치 시 컴파일 에러
- 타입 안전 API 클라이언트로 엔드포인트별 요청/응답 타입 자동 추론
- 런타임 버그 대신 컴파일 타임에 문제 발견 → 개발 생산성 향상

---

## 다음 편 예고

로컬 개발에 필요한 PostgreSQL, Redis를 Docker Compose로 구성합니다.

→ **[08편: 개발 환경 구성](08-dev-environment.md)**

---

## 참고 자료

- [TypeScript 고급 타입](https://www.typescriptlang.org/docs/handbook/2/types-from-types.html) — typescriptlang.org
- [TypeScript satisfies / implements 패턴](https://www.typescriptlang.org/docs/handbook/2/classes.html#implements-clauses) — typescriptlang.org
- [Single Source of Truth 패턴](https://en.wikipedia.org/wiki/Single_source_of_truth) — wikipedia.org
