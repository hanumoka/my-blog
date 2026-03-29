# Prisma 공유 패키지 — 데이터베이스 스키마를 모노리포에서 관리

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [03편: 공유 패키지 만들기](03-shared-package.md)
> **시리즈**: NestJS + Next.js + Prisma 모노리포 가이드 4/10

---

## 개요

`packages/database`는 Prisma 스키마와 생성된 클라이언트를 담는 패키지입니다.
백엔드(NestJS)가 이 패키지를 통해 데이터베이스에 접근합니다.
스키마를 한 곳에서 관리하므로 여러 백엔드 앱이 있어도 스키마가 분산되지 않습니다.

---

## 핵심 개념 — 모노리포에서 Prisma 배치 전략

```
나쁜 예 (스키마 분산):                좋은 예 (스키마 중앙화):

apps/backend/prisma/               packages/database/
  schema.prisma  ←─ 여기만?           schema.prisma   ← 한 곳에만!
                                      ↓ prisma generate
                                    packages/database/
                                      src/generated/   ← 클라이언트

apps/backend 에서 import             apps/backend 에서 import
  from '@prisma/client'              from '@my-monorepo/database'
  (경로 모호)                         (명확한 패키지 참조)
```

---

## 실습

### 1단계: packages/database 초기화

```json
// packages/database/package.json
{
  "name": "@my-monorepo/database",
  "version": "0.0.1",
  "private": true,
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "exports": {
    ".": "./src/index.ts"
  },
  "scripts": {
    "generate": "prisma generate",
    "db:push": "prisma db push",
    "db:migrate": "prisma migrate dev",
    "db:migrate:deploy": "prisma migrate deploy",
    "db:studio": "prisma studio",
    "db:seed": "ts-node prisma/seed.ts"
  },
  "dependencies": {
    "@prisma/client": "^7.0.0"
  },
  "devDependencies": {
    "prisma": "^7.0.0",
    "ts-node": "^10.9.0",
    "typescript": "^5.8.0"
  }
}
```

> 💡 `"main": "./src/index.ts"` — 빌드 없이 TypeScript 소스 직접 참조.
> NestJS의 `ts-jest`나 SWC가 런타임에 컴파일하므로 별도 빌드 불필요합니다.

### 2단계: Prisma 설치 및 초기화

```bash
# packages/database 폴더에서
pnpm add @prisma/client
pnpm add -D prisma ts-node

# Prisma 초기화 (prisma/ 폴더 생성)
pnpm dlx prisma init
```

### 3단계: Prisma 스키마 작성

```prisma
// packages/database/prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
  output   = "../src/generated/prisma"  // ← 커스텀 output 경로!
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  name      String
  password  String
  role      Role     @default(USER)
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  posts     Post[]
}

model Post {
  id        Int      @id @default(autoincrement())
  title     String
  content   String?
  published Boolean  @default(false)
  author    User     @relation(fields: [authorId], references: [id])
  authorId  Int
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
}

enum Role {
  ADMIN
  USER
  GUEST
}
```

> ⚠️ `output = "../src/generated/prisma"` — 기본 `node_modules/.prisma`가 아닌 커스텀 경로에 생성.
> 모노리포에서 각 앱의 node_modules가 달라서 발생하는 문제를 방지합니다.

### 4단계: 환경변수 파일

```bash
# packages/database/.env
DATABASE_URL="postgresql://postgres:YOUR_PASSWORD@localhost:5432/mydb?schema=public"
```

> ⚠️ 실제 비밀번호는 `.env`에만 넣고, 절대 Git에 커밋하지 마세요!

### 5단계: Prisma 클라이언트 생성

```bash
# packages/database에서
pnpm generate
```

생성 결과:

```
packages/database/
├── prisma/
│   └── schema.prisma
├── src/
│   ├── generated/
│   │   └── prisma/       ← 자동 생성됨 (Git에 포함 가능)
│   │       ├── index.js
│   │       └── index.d.ts
│   └── index.ts          ← 직접 작성
└── package.json
```

### 6단계: 진입점(index.ts) 작성

```typescript
// packages/database/src/index.ts
// Prisma 클라이언트 및 enum 재내보내기
export { PrismaClient, Prisma, Role } from './generated/prisma';

// Prisma 타입 재내보내기 (model 타입)
export type { User, Post } from './generated/prisma';

// 싱글톤 PrismaClient 인스턴스 (앱에서 직접 사용 가능하도록)
import { PrismaClient } from './generated/prisma';

// 개발 환경에서의 핫리로드로 인한 다중 인스턴스 방지
const globalForPrisma = globalThis as unknown as { prisma: PrismaClient };

export const prisma =
  globalForPrisma.prisma ||
  new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['query', 'error'] : ['error'],
  });

if (process.env.NODE_ENV !== 'production') {
  globalForPrisma.prisma = prisma;
}
```

### 7단계: 마이그레이션 실행

```bash
# 개발 환경 — 마이그레이션 생성 + 적용
pnpm --filter @my-monorepo/database db:migrate

# 마이그레이션 이름 입력 시: "init"

# 결과:
# packages/database/prisma/migrations/
#   20260329000000_init/
#     migration.sql
```

### 8단계: backend에서 database 패키지 사용

```bash
# 루트에서
pnpm add @my-monorepo/database@workspace:* --filter @my-monorepo/backend
```

```typescript
// apps/backend/src/users/users.service.ts
import { Injectable } from '@nestjs/common';
import { prisma, User } from '@my-monorepo/database';

@Injectable()
export class UsersService {
  async findAll(): Promise<User[]> {
    return prisma.user.findMany();
  }

  async findOne(id: number): Promise<User | null> {
    return prisma.user.findUnique({ where: { id } });
  }
}
```

---

## .gitignore 설정

```gitignore
# packages/database/.gitignore

# 환경변수 (절대 커밋 금지!)
.env

# 생성된 Prisma 클라이언트 (팀 협약에 따라 선택)
# src/generated/  ← 포함하는 게 권장 (CI에서 generate 불필요)
```

> 💡 `src/generated/`는 Git에 포함하는 것을 권장합니다.
> CI/CD에서 `prisma generate`를 실행할 필요가 없어 빌드가 단순해집니다.

---

## 요약

- `packages/database`에 Prisma 스키마와 클라이언트를 중앙화
- `output = "../src/generated/prisma"` — 모노리포 환경에서 경로 충돌 방지
- `prisma generate`로 타입 안전한 클라이언트 자동 생성
- 싱글톤 패턴으로 PrismaClient 인스턴스 관리 (다중 인스턴스 방지)
- `workspace:*`로 backend에서 database 패키지 참조

---

## 다음 편 예고

database 패키지를 활용해 NestJS 백엔드를 구성합니다.

→ **[05편: NestJS 백엔드 셋업](05-nestjs-backend.md)**

---

## 참고 자료

- [Prisma 공식 문서](https://www.prisma.io/docs) — prisma.io
- [Prisma in Monorepos](https://www.prisma.io/docs/guides/other/troubleshooting-orm/help-articles/prisma-monorepo) — prisma.io
- [Prisma Client 커스텀 output](https://www.prisma.io/docs/orm/prisma-client/setup-and-configuration/generating-prisma-client#using-a-custom-output-path) — prisma.io
