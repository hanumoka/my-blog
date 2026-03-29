# 관계(Relations) 비교 — 1:1, 1:N, N:M 완전 정복

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [03편: CRUD 쿼리 비교](03-crud-queries.md)
> **시리즈**: Prisma vs TypeORM 비교 가이드 4/7

---

## 개요

데이터베이스에서 테이블 간 관계는 핵심입니다.
TypeORM은 **데코레이터 조합**, Prisma는 **스키마 선언**으로 관계를 정의합니다.
세 가지 관계 유형(1:1, 1:N, N:M)을 양쪽으로 구현하며 차이를 비교합니다.

---

## 관계 유형 한눈에 보기

```
1:1 (One-to-One)         1:N (One-to-Many)         N:M (Many-to-Many)
┌──────┐  ┌──────┐      ┌──────┐  ┌──────┐        ┌──────┐  ┌──────┐
│ User │──│Profile│      │ User │──┤ Post │        │ Post │──┤ Tag  │
└──────┘  └──────┘      └──────┘  ├──────┤        └──┬───┘  └──┬───┘
  한 명 = 하나의 프로필    한 명 = 여러 개 글          │         │
                                                  ┌──┴─────────┴──┐
                                                  │  PostTag (중간) │
                                                  └───────────────┘
                                                   여러 글 ↔ 여러 태그
```

---

## 1:1 — One-to-One 관계

### 예제: User ↔ Profile

```typescript
// TypeORM — user.entity.ts
@Entity('users')
export class User {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  email: string;

  @OneToOne(() => Profile, (profile) => profile.user)
  profile: Profile;
}

// TypeORM — profile.entity.ts
@Entity('profiles')
export class Profile {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  bio: string;

  @Column({ nullable: true })
  avatarUrl: string;

  @OneToOne(() => User, (user) => user.profile)
  @JoinColumn({ name: 'user_id' })  // FK를 가진 쪽에 JoinColumn
  user: User;

  @Column({ name: 'user_id' })
  userId: number;
}
```

```prisma
// Prisma — schema.prisma
model User {
  id      Int      @id @default(autoincrement())
  email   String   @unique
  profile Profile?  // 선택적 1:1 관계
}

model Profile {
  id        Int     @id @default(autoincrement())
  bio       String
  avatarUrl String? @map("avatar_url")

  user   User @relation(fields: [userId], references: [id])
  userId Int  @unique @map("user_id")  // @unique로 1:1 보장

  @@map("profiles")
}
```

> 💡 Prisma에서 `@unique`를 FK에 붙이면 1:1 관계가 됩니다.
> 빼면 1:N이 됩니다 — 매우 직관적!

---

## 1:N — One-to-Many 관계

### 예제: User ↔ Post (02편에서 사용한 모델)

```typescript
// TypeORM
// user.entity.ts
@OneToMany(() => Post, (post) => post.author)
posts: Post[];

// post.entity.ts
@ManyToOne(() => User, (user) => user.posts)
@JoinColumn({ name: 'author_id' })
author: User;

@Column({ name: 'author_id' })
authorId: number;
```

```prisma
// Prisma
model User {
  id    Int    @id @default(autoincrement())
  posts Post[]  // 역방향 (FK 없음)
}

model Post {
  id       Int  @id @default(autoincrement())
  author   User @relation(fields: [authorId], references: [id])
  authorId Int  @map("author_id")  // FK가 여기에
}
```

### 관계 데이터 쿼리

```typescript
// TypeORM — 사용자의 글 목록 조회
const user = await userRepo.findOne({
  where: { id: 1 },
  relations: ['posts'],             // 문자열!
});
console.log(user.posts);           // Post[]

// QueryBuilder로 조건부 관계 로딩
const users = await userRepo
  .createQueryBuilder('user')
  .leftJoinAndSelect('user.posts', 'post', 'post.published = :pub', { pub: true })
  .getMany();
```

```typescript
// Prisma — 사용자의 글 목록 조회
const user = await prisma.user.findUnique({
  where: { id: 1 },
  include: {
    posts: {
      where: { published: true },   // 관계 내 필터링!
      orderBy: { createdAt: 'desc' },
    },
  },
});
console.log(user.posts);           // Post[] (타입 자동 추론)
```

---

## N:M — Many-to-Many 관계

### 예제: Post ↔ Tag

```
┌──────────┐     ┌──────────────┐     ┌──────────┐
│   Post   │     │   PostTag    │     │   Tag    │
├──────────┤     │  (중간 테이블) │     ├──────────┤
│ id       │◄───┤ postId       │     │ id       │
│ title    │     │ tagId        ├───►│ name     │
└──────────┘     │ assignedAt   │     └──────────┘
                 └──────────────┘
```

### TypeORM — 암시적 N:M

```typescript
// TypeORM — 자동 중간 테이블 (간단하지만 중간 테이블에 컬럼 추가 불가)
@Entity('posts')
export class Post {
  @ManyToMany(() => Tag, (tag) => tag.posts)
  @JoinTable({
    name: 'post_tags',
    joinColumn: { name: 'post_id' },
    inverseJoinColumn: { name: 'tag_id' },
  })
  tags: Tag[];
}

@Entity('tags')
export class Tag {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  name: string;

  @ManyToMany(() => Post, (post) => post.tags)
  posts: Post[];
}
```

### TypeORM — 명시적 N:M (중간 테이블에 컬럼 추가 시)

```typescript
// post-tag.entity.ts — 중간 테이블을 Entity로 직접 정의
@Entity('post_tags')
export class PostTag {
  @PrimaryGeneratedColumn()
  id: number;

  @ManyToOne(() => Post, (post) => post.postTags)
  @JoinColumn({ name: 'post_id' })
  post: Post;

  @ManyToOne(() => Tag, (tag) => tag.postTags)
  @JoinColumn({ name: 'tag_id' })
  tag: Tag;

  @CreateDateColumn()
  assignedAt: Date;  // 중간 테이블에 추가 컬럼!
}
```

### Prisma — 암시적 N:M

```prisma
// Prisma — 자동 중간 테이블 (_PostToTag)
model Post {
  id   Int   @id @default(autoincrement())
  tags Tag[]  // 중간 테이블 자동 생성
}

model Tag {
  id    Int    @id @default(autoincrement())
  name  String @unique
  posts Post[]
}
```

### Prisma — 명시적 N:M

```prisma
// Prisma — 중간 테이블에 추가 필드가 필요할 때
model Post {
  id       Int       @id @default(autoincrement())
  postTags PostTag[]
}

model Tag {
  id       Int       @id @default(autoincrement())
  name     String    @unique
  postTags PostTag[]
}

model PostTag {
  id         Int      @id @default(autoincrement())
  assignedAt DateTime @default(now()) @map("assigned_at")

  post   Post @relation(fields: [postId], references: [id])
  postId Int  @map("post_id")

  tag   Tag @relation(fields: [tagId], references: [id])
  tagId Int @map("tag_id")

  @@unique([postId, tagId])
  @@map("post_tags")
}
```

### N:M 관계 쿼리

**암시적 N:M 사용 시** (위의 간단한 모델 기준):

```typescript
// TypeORM — 태그와 함께 글 조회
const posts = await postRepo.find({
  relations: ['tags'],
});

// TypeORM — 특정 태그가 달린 글 조회 (QueryBuilder 필요)
const posts = await postRepo
  .createQueryBuilder('post')
  .innerJoinAndSelect('post.tags', 'tag')
  .where('tag.name = :name', { name: 'NestJS' })
  .getMany();
```

```typescript
// Prisma — 태그와 함께 글 조회
const posts = await prisma.post.findMany({
  include: { tags: true },
});

// Prisma — 특정 태그가 달린 글 조회
const posts = await prisma.post.findMany({
  where: {
    tags: { some: { name: 'NestJS' } },  // 관계 필터!
  },
  include: { tags: true },
});
```

> 💡 **명시적 N:M**(PostTag 모델)을 사용하면 쿼리 방식이 달라집니다:
> `include: { postTags: { include: { tag: true } } }` 형태로 중간 테이블을 거쳐 조회합니다.

---

## N+1 문제 비교

```
N+1 문제란?
  사용자 10명 조회 → 1번 쿼리
  각 사용자의 글 조회 → 10번 쿼리
  총 11번 쿼리 실행 → 성능 저하! 💥
```

```typescript
// TypeORM — N+1 발생 가능
// ❌ Lazy Loading (각 접근 시 쿼리 발생)
for (const user of users) {
  console.log(await user.posts);  // 매번 쿼리 실행!
}

// ✅ Eager Loading (한 번에 조인)
const users = await userRepo.find({
  relations: ['posts'],  // LEFT JOIN으로 한 번에 로딩
});
```

```typescript
// Prisma — N+1 방지가 기본
// ✅ include 사용 시 자동으로 최적화된 쿼리 실행
const users = await prisma.user.findMany({
  include: { posts: true },
  // → SELECT * FROM users
  // → SELECT * FROM posts WHERE userId IN (1,2,3,...) ← IN 쿼리로 최적화!
});
```

> 💡 Prisma는 기본적으로 JOIN 대신 **IN 쿼리**를 사용합니다.
> `relationLoadStrategy: "join"` 옵션으로 JOIN 방식으로 전환할 수도 있습니다.
> 상황에 따라 적절한 전략을 선택하세요.

---

## 핵심 비교 표

| 항목 | TypeORM | Prisma |
|------|---------|--------|
| 1:1 정의 | `@OneToOne` + `@JoinColumn` (양쪽) | `@relation` + `@unique` (한쪽) |
| 1:N 정의 | `@OneToMany` + `@ManyToOne` (양쪽) | `@relation` + `[]` (한쪽) |
| N:M 암시적 | `@ManyToMany` + `@JoinTable` | 배열 필드만 선언 |
| N:M 명시적 | 중간 Entity 직접 생성 | 중간 model 생성 |
| 관계 필터링 | QueryBuilder 필요 | 중첩 where로 간단 |
| N+1 방지 | relations 옵션 수동 | include로 자동 최적화 |

---

## 요약

- **1:1**: Prisma는 `@unique`로, TypeORM은 `@OneToOne` + `@JoinColumn`으로 정의
- **1:N**: Prisma가 더 간결 — FK 쪽에만 `@relation` 선언
- **N:M**: 양쪽 모두 암시적/명시적 방식 지원, Prisma가 코드량 적음
- **N+1 문제**: Prisma는 IN 쿼리로 자동 최적화, TypeORM은 수동 관리
- **관계 필터링**: Prisma의 중첩 where가 TypeORM의 QueryBuilder보다 직관적

---

## 다음 편 예고

스키마 변경 시 마이그레이션을 생성하고 적용하는 과정을 양쪽으로 비교합니다.

→ **[05편: 마이그레이션 비교](05-migrations.md)**

---

## 참고 자료

- [Prisma Relations 공식 문서](https://www.prisma.io/docs/orm/prisma-schema/data-model/relations) — prisma.io
- [TypeORM Relations 공식 문서](https://typeorm.io/relations) — typeorm.io
- [TypeORM Many-to-Many 공식 문서](https://typeorm.io/many-to-many-relations) — typeorm.io
