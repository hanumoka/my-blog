# Next.js 프론트엔드 셋업 — 모노리포 안의 웹 앱

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [05편: NestJS 백엔드 셋업](05-nestjs-backend.md)
> **시리즈**: NestJS + Next.js + Prisma 모노리포 가이드 6/10

---

## 개요

`apps/frontend`에 Next.js 16 웹 앱을 구성합니다.
App Router 기반으로 서버 컴포넌트에서 백엔드 API를 호출하고,
`packages/shared`의 타입을 그대로 사용해 타입 안전한 UI를 만드는 방법을 배웁니다.

---

## 핵심 개념 — Next.js 16 App Router

```
Next.js 16 App Router 구조:

apps/frontend/app/
├── layout.tsx          ← 전체 레이아웃 (서버 컴포넌트)
├── page.tsx            ← 홈 페이지
└── users/
    ├── page.tsx        ← 유저 목록 (서버 컴포넌트, SSR)
    └── [id]/
        └── page.tsx    ← 유저 상세 (서버 컴포넌트, SSR)

서버 컴포넌트: 백엔드 API를 직접 fetch (async/await)
클라이언트 컴포넌트: 'use client' 선언 (브라우저에서 실행)
```

---

## 실습

### 1단계: Next.js 앱 생성

```bash
# 루트에서
pnpm dlx create-next-app@latest apps/frontend \
  --typescript \
  --tailwind \
  --eslint \
  --app \
  --no-src-dir \
  --no-import-alias
```

### 2단계: package.json 수정

```json
// apps/frontend/package.json
{
  "name": "@my-monorepo/frontend",
  "version": "0.0.1",
  "private": true,
  "scripts": {
    "build": "next build",
    "dev": "next dev --port 3000",
    "start": "next start --port 3000",
    "lint": "next lint"
  },
  "dependencies": {
    "next": "^16.0.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "@my-monorepo/shared": "workspace:*"
  },
  "devDependencies": {
    "@types/node": "^22.0.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "typescript": "^5.8.0",
    "tailwindcss": "^4.0.0",
    "@tailwindcss/postcss": "^4.0.0"
  }
}
```

### 3단계: TypeScript 설정

```json
// apps/frontend/tsconfig.json
{
  "extends": "../../tsconfig.json",
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["dom", "dom.iterable", "esnext"],
    "module": "esnext",
    "moduleResolution": "bundler",
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": {
      "@/*": ["./*"],
      "@my-monorepo/shared": ["../../packages/shared/src/index.ts"]
    }
  },
  "include": ["**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
```

### 4단계: Next.js 설정

```typescript
// apps/frontend/next.config.ts
import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // 모노리포 내 workspace 패키지 transpile 설정
  transpilePackages: ['@my-monorepo/shared'],

  // Docker 배포 시 standalone 모드 (09편에서 사용)
  output: 'standalone',

  env: {
    BACKEND_URL: process.env.BACKEND_URL || 'http://localhost:3001',
  },
};

export default nextConfig;
```

> 💡 `transpilePackages`로 workspace 패키지의 TypeScript 소스를 Next.js가 직접 컴파일합니다.

### 5단계: API 클라이언트 작성

```typescript
// apps/frontend/lib/api-client.ts
import type { User } from '@my-monorepo/shared';
import { ApiResponse, ApiError } from '@my-monorepo/shared';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:3001';

async function fetchApi<T>(path: string, options?: RequestInit): Promise<T> {
  const response = await fetch(`${BACKEND_URL}/api/v1${path}`, {
    headers: {
      'Content-Type': 'application/json',
      ...options?.headers,
    },
    ...options,
  });

  if (!response.ok) {
    const error: ApiError = await response.json();
    throw new Error(error.message as string);
  }

  const result: ApiResponse<T> = await response.json();
  return result.data;
}

// 유저 API
export const usersApi = {
  getAll: () => fetchApi<User[]>('/users'),
  getOne: (id: number) => fetchApi<User>(`/users/${id}`),
};
```

### 6단계: 서버 컴포넌트로 유저 목록 페이지

```typescript
// apps/frontend/app/users/page.tsx
import { usersApi } from '@/lib/api-client';
import { User } from '@my-monorepo/shared';

// 서버 컴포넌트 — 빌드 시 또는 요청 시 서버에서 실행
export default async function UsersPage() {
  const users = await usersApi.getAll();

  return (
    <div className="container mx-auto p-8">
      <h1 className="text-3xl font-bold mb-6">사용자 목록</h1>

      <div className="grid gap-4">
        {users.map((user: User) => (
          <UserCard key={user.id} user={user} />
        ))}
      </div>
    </div>
  );
}

// 서버 컴포넌트 — 별도 파일로 분리 권장
function UserCard({ user }: { user: User }) {
  return (
    <div className="p-4 border rounded-lg shadow-sm">
      <h2 className="text-xl font-semibold">{user.name}</h2>
      <p className="text-gray-500">{user.email}</p>
      <span className="inline-block px-2 py-1 text-sm bg-blue-100 text-blue-800 rounded">
        {user.role}
      </span>
    </div>
  );
}
```

### 7단계: 클라이언트 컴포넌트 (인터랙션이 있는 경우)

```typescript
// apps/frontend/components/UserForm.tsx
'use client';  // ← 클라이언트 컴포넌트 선언 필수

import { useState } from 'react';
import { CreateUserDto } from '@my-monorepo/shared';

interface UserFormProps {
  onSubmit: (data: CreateUserDto) => Promise<void>;
}

export function UserForm({ onSubmit }: UserFormProps) {
  const [form, setForm] = useState<CreateUserDto>({
    email: '',
    name: '',
    password: '',
  });
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    try {
      await onSubmit(form);
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <input
        type="email"
        placeholder="이메일"
        value={form.email}
        onChange={e => setForm(prev => ({ ...prev, email: e.target.value }))}
        className="w-full p-2 border rounded"
        required
      />
      <input
        type="text"
        placeholder="이름"
        value={form.name}
        onChange={e => setForm(prev => ({ ...prev, name: e.target.value }))}
        className="w-full p-2 border rounded"
        required
      />
      <input
        type="password"
        placeholder="비밀번호"
        value={form.password}
        onChange={e => setForm(prev => ({ ...prev, password: e.target.value }))}
        className="w-full p-2 border rounded"
        required
      />
      <button
        type="submit"
        disabled={loading}
        className="w-full p-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
      >
        {loading ? '처리 중...' : '사용자 추가'}
      </button>
    </form>
  );
}
```

### 8단계: 환경변수 설정

```bash
# apps/frontend/.env.local
BACKEND_URL=http://localhost:3001
```

### 9단계: 프론트엔드 실행

```bash
# 루트에서
pnpm --filter @my-monorepo/frontend dev

# 또는 전체 dev
pnpm dev
```

---

## 서버 컴포넌트 vs 클라이언트 컴포넌트

```
서버 컴포넌트 (기본):              클라이언트 컴포넌트 ('use client'):
  async/await 사용 가능             useState, useEffect 사용 가능
  DB/API 직접 접근                  브라우저 API 사용 가능
  번들 크기에 포함 안 됨             번들에 포함됨
  인터랙션 불가                     인터랙션 가능

원칙: 가능한 한 서버 컴포넌트 사용
     인터랙션이 필요한 부분만 클라이언트로 분리
```

---

## 요약

- `transpilePackages`로 workspace 패키지를 Next.js가 직접 컴파일
- `tsconfig.json`의 `paths`로 workspace 패키지 경로 연결
- **서버 컴포넌트**: async/await로 백엔드 API 직접 호출 (SSR)
- **클라이언트 컴포넌트**: `'use client'` + React hooks (인터랙션 필요 시만)
- `packages/shared`의 타입으로 FE/BE 타입 일치 보장

---

## 다음 편 예고

FE↔BE 사이의 타입 안전한 API 통신 패턴을 더 깊이 살펴봅니다.

→ **[07편: 타입 안전한 API 통신](07-type-sharing.md)**

---

## 참고 자료

- [Next.js App Router 공식 문서](https://nextjs.org/docs/app) — nextjs.org
- [Next.js 서버 컴포넌트](https://nextjs.org/docs/app/building-your-application/rendering/server-components) — nextjs.org
- [Next.js transpilePackages](https://nextjs.org/docs/app/api-reference/next-config-js/transpilePackages) — nextjs.org
