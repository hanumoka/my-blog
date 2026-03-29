# 스키마 정의 비교 — Entity 데코레이터 vs schema.prisma

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [01편: ORM이란?](01-orm-overview.md)
> **시리즈**: Prisma vs TypeORM 비교 가이드 2/7

---

## 개요

데이터베이스 테이블을 코드로 정의하는 것이 ORM의 출발점입니다.
TypeORM은 **클래스 + 데코레이터**, Prisma는 **전용 스키마 파일**로 정의합니다.
같은 모델을 양쪽으로 구현하며 차이를 체감해봅니다.

---

## 예제 모델: 블로그 시스템

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    User      │     │    Post     │     │   Comment   │
├─────────────┤     ├─────────────┤     ├─────────────┤
│ id (PK)     │     │ id (PK)     │     │ id (PK)     │
│ email       │──┐  │ title       │──┐  │ content     │
│ name        │  └─▶│ content     │  └─▶│ postId (FK) │
│ role        │     │ published   │     │ authorId(FK)│
│ createdAt   │     │ authorId(FK)│     │ createdAt   │
└─────────────┘     │ createdAt   │     └─────────────┘
                    └─────────────┘
```

---

## TypeORM — 데코레이터 방식

```typescript
// src/entities/user.entity.ts
import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  OneToMany,
} from 'typeorm';
import { Post } from './post.entity';

export enum UserRole {
  ADMIN = 'admin',
  USER = 'user',
}

@Entity('users')
export class User {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ type: 'varchar', length: 255, unique: true })
  email: string;

  @Column({ type: 'varchar', length: 100 })
  name: string;

  @Column({ type: 'enum', enum: UserRole, default: UserRole.USER })
  role: UserRole;

  @CreateDateColumn()
  createdAt: Date;

  @OneToMany(() => Post, (post) => post.author)
  posts: Post[];
}
```

```typescript
// src/entities/post.entity.ts
import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  OneToMany,
  JoinColumn,
} from 'typeorm';
import { User } from './user.entity';
import { Comment } from './comment.entity';

@Entity('posts')
export class Post {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ type: 'varchar', length: 255 })
  title: string;

  @Column({ type: 'text' })
  content: string;

  @Column({ default: false })
  published: boolean;

  @ManyToOne(() => User, (user) => user.posts)
  @JoinColumn({ name: 'author_id' })
  author: User;

  @Column({ name: 'author_id' })
  authorId: number;

  @CreateDateColumn()
  createdAt: Date;

  @OneToMany(() => Comment, (comment) => comment.post)
  comments: Comment[];
}
```

```typescript
// src/entities/comment.entity.ts
import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { Post } from './post.entity';
import { User } from './user.entity';

@Entity('comments')
export class Comment {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ type: 'text' })
  content: string;

  @ManyToOne(() => Post, (post) => post.comments)
  @JoinColumn({ name: 'post_id' })
  post: Post;

  @Column({ name: 'post_id' })
  postId: number;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'author_id' })
  author: User;

  @Column({ name: 'author_id' })
  authorId: number;

  @CreateDateColumn()
  createdAt: Date;
}
```

> **파일 3개**, 총 약 90줄

---

## Prisma — 스키마 파일 방식

```prisma
// prisma/schema.prisma

generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

enum UserRole {
  ADMIN
  USER
}

model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  name      String   @db.VarChar(100)
  role      UserRole @default(USER)
  createdAt DateTime @default(now()) @map("created_at")

  posts    Post[]
  comments Comment[]

  @@map("users")
}

model Post {
  id        Int      @id @default(autoincrement())
  title     String   @db.VarChar(255)
  content   String   @db.Text
  published Boolean  @default(false)
  createdAt DateTime @default(now()) @map("created_at")

  author   User @relation(fields: [authorId], references: [id])
  authorId Int  @map("author_id")

  comments Comment[]

  @@map("posts")
}

model Comment {
  id        Int      @id @default(autoincrement())
  content   String   @db.Text
  createdAt DateTime @default(now()) @map("created_at")

  post     Post @relation(fields: [postId], references: [id])
  postId   Int  @map("post_id")

  author   User @relation(fields: [authorId], references: [id])
  authorId Int  @map("author_id")

  @@map("comments")
}
```

> **파일 1개**, 총 약 50줄

---

## 나란히 비교

```
TypeORM                              Prisma
──────────────────────               ──────────────────────

파일 구조:                            파일 구조:
  src/entities/                       prisma/
    user.entity.ts                      schema.prisma ← 전부 여기
    post.entity.ts
    comment.entity.ts

PK 정의:                             PK 정의:
  @PrimaryGeneratedColumn()            @id @default(autoincrement())

컬럼 타입:                            컬럼 타입:
  @Column({ type: 'varchar' })         String @db.VarChar(255)

관계 정의:                            관계 정의:
  @ManyToOne(() => User)               author User @relation(
  @JoinColumn({ name: 'author_id' })    fields: [authorId],
                                         references: [id])

기본값:                               기본값:
  @Column({ default: false })          Boolean @default(false)

테이블 이름:                          테이블 이름:
  @Entity('users')                     @@map("users")
```

---

## 핵심 차이 분석

### 1. 코드량과 구조

| 항목 | TypeORM | Prisma |
|------|---------|--------|
| 파일 수 | 모델당 1개 (3개) | 전체 1개 |
| 코드량 | ~90줄 | ~50줄 |
| import 문 | 매 파일마다 필요 | 없음 |
| 보일러플레이트 | 많음 (데코레이터 반복) | 적음 |

### 2. 관계 정의의 직관성

```typescript
// TypeORM: 양쪽 Entity에서 각각 정의해야 함
// user.entity.ts
@OneToMany(() => Post, (post) => post.author)
posts: Post[];

// post.entity.ts
@ManyToOne(() => User, (user) => user.posts)
@JoinColumn({ name: 'author_id' })
author: User;
```

```prisma
// Prisma: 한 파일에서 양쪽 관계가 자동 연결
model User {
  posts Post[]       // 역방향 자동 인식
}

model Post {
  author   User @relation(fields: [authorId], references: [id])
  authorId Int
}
```

> 💡 Prisma는 `npx prisma format` 명령으로 관계 필드를 자동 생성/검증합니다.

### 3. 타입 생성 방식

```
TypeORM:
  Entity 클래스 = 타입 (수동 관리)
  → 실제 DB 컬럼과 타입이 불일치할 수 있음

Prisma:
  schema.prisma → npx prisma generate → Prisma Client (자동 생성)
  → 스키마와 타입이 항상 100% 일치 보장
```

---

## 실습: Prisma 스키마 작성 해보기

```bash
# 1. 프로젝트 초기화
mkdir blog-app && cd blog-app
npm init -y
npm install prisma --save-dev

# 2. Prisma 초기화
npx prisma init

# 3. prisma/schema.prisma 파일이 생성됨 → 위 예제 코드 복사

# 4. .env 파일에 DB URL 설정
# DATABASE_URL="postgresql://YOUR_USER:YOUR_PASSWORD@localhost:5432/blogdb"

# 5. Prisma Client 생성
npx prisma generate
```

---

## 요약

- **TypeORM**: 클래스 + 데코레이터로 정의, 파일 분산, import 반복, 양쪽 관계 수동 정의
- **Prisma**: 단일 스키마 파일, 선언적 구문, 관계 자동 인식, 코드 40% 이상 절약
- Prisma는 스키마 수정 시 `prisma generate`로 타입 자동 동기화
- TypeORM은 Entity 클래스를 직접 관리해야 하므로 DB 실제 상태와 불일치 위험

---

## 다음 편 예고

같은 블로그 모델에서 CRUD(생성/조회/수정/삭제) 쿼리를 양쪽으로 작성하며 API 차이를 비교합니다.

→ **[03편: CRUD 쿼리 비교](03-crud-queries.md)**

---

## 참고 자료

- [Prisma vs TypeORM 공식 비교](https://www.prisma.io/docs/orm/more/comparisons/prisma-and-typeorm) — prisma.io
- [TypeORM Entity 공식 문서](https://typeorm.io/entities) — typeorm.io
- [Prisma Schema 공식 문서](https://www.prisma.io/docs/orm/prisma-schema) — prisma.io
