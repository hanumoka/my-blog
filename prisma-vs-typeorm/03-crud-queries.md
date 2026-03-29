# CRUD 쿼리 비교 — Repository 패턴 vs Prisma Client

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [02편: 스키마 정의 비교](02-schema-definition.md)
> **시리즈**: Prisma vs TypeORM 비교 가이드 3/7

---

## 개요

스키마를 정의했으면 이제 데이터를 다뤄야 합니다.
TypeORM은 **Repository 패턴**, Prisma는 **Prisma Client API**로 CRUD를 수행합니다.
같은 작업을 양쪽으로 작성하며 API 차이와 타입 안전성을 비교합니다.

---

## 쿼리 흐름 비교

```
TypeORM:                                Prisma:
  코드 작성                               코드 작성
    │                                      │
    ▼                                      ▼
  Repository.find()                     prisma.user.findMany()
    │                                      │
    ▼                                      ▼
  QueryRunner가 SQL 생성                 Prisma Engine이 SQL 생성
    │                                      │
    ▼                                      ▼
  DB 실행 → any/Entity 타입 반환         DB 실행 → 정확한 타입 반환
                                          (스키마 기반 자동 생성)
```

---

## Create — 데이터 생성

```typescript
// TypeORM
const userRepo = dataSource.getRepository(User);

const user = userRepo.create({
  email: 'hong@example.com',
  name: '홍길동',
  role: UserRole.USER,
});
await userRepo.save(user);

// Post 생성 (관계 포함)
const post = postRepo.create({
  title: '첫 번째 글',
  content: '안녕하세요!',
  authorId: user.id,
});
await postRepo.save(post);
```

```typescript
// Prisma
const user = await prisma.user.create({
  data: {
    email: 'hong@example.com',
    name: '홍길동',
    role: 'USER',
  },
});

// Post 생성 (관계 연결)
const post = await prisma.post.create({
  data: {
    title: '첫 번째 글',
    content: '안녕하세요!',
    author: { connect: { id: user.id } },  // 관계를 명시적으로 연결
  },
});
```

> 💡 Prisma의 `connect`는 기존 레코드와 관계를 연결합니다.
> `authorId: user.id`로 직접 FK를 넣어도 동일하게 동작합니다.

---

## Read — 데이터 조회

### 단일 조회

```typescript
// TypeORM
const user = await userRepo.findOneBy({ id: 1 });
// user 타입: User | null

const userWithPosts = await userRepo.findOne({
  where: { id: 1 },
  relations: ['posts'],  // 관계 로딩을 문자열로 지정
});
```

```typescript
// Prisma
const user = await prisma.user.findUnique({
  where: { id: 1 },
});
// user 타입: User | null (자동 생성된 정확한 타입)

const userWithPosts = await prisma.user.findUnique({
  where: { id: 1 },
  include: { posts: true },  // 타입 안전한 관계 로딩
});
// userWithPosts 타입: User & { posts: Post[] }
```

### 조건부 목록 조회

```typescript
// TypeORM — 발행된 글만 최신순으로 10개
const posts = await postRepo.find({
  where: { published: true },
  order: { createdAt: 'DESC' },
  take: 10,
  skip: 0,
});
```

```typescript
// Prisma — 동일한 쿼리
const posts = await prisma.post.findMany({
  where: { published: true },
  orderBy: { createdAt: 'desc' },
  take: 10,
  skip: 0,
});
```

### 복합 필터링

```typescript
// TypeORM — QueryBuilder 사용
const posts = await postRepo
  .createQueryBuilder('post')
  .leftJoinAndSelect('post.author', 'author')
  .where('post.published = :published', { published: true })
  .andWhere('author.role = :role', { role: 'admin' })
  .orderBy('post.createdAt', 'DESC')
  .getMany();
```

```typescript
// Prisma — 중첩 필터
const posts = await prisma.post.findMany({
  where: {
    published: true,
    author: { role: 'ADMIN' },  // 관계 필터도 타입 안전!
  },
  include: { author: true },
  orderBy: { createdAt: 'desc' },
});
```

---

## Update — 데이터 수정

```typescript
// TypeORM
await postRepo.update(
  { id: 1 },
  { title: '수정된 제목', published: true }
);

// 또는 Entity를 수정 후 save
const post = await postRepo.findOneBy({ id: 1 });
post.title = '수정된 제목';
post.published = true;
await postRepo.save(post);
```

```typescript
// Prisma
const post = await prisma.post.update({
  where: { id: 1 },
  data: {
    title: '수정된 제목',
    published: true,
  },
});
// 수정된 결과가 바로 반환됨 (추가 조회 불필요)
```

---

## Delete — 데이터 삭제

```typescript
// TypeORM
await postRepo.delete({ id: 1 });

// 조건부 삭제
await commentRepo.delete({ postId: 1 });
```

```typescript
// Prisma
await prisma.post.delete({
  where: { id: 1 },
});

// 조건부 삭제
await prisma.comment.deleteMany({
  where: { postId: 1 },
});
```

---

## 나란히 비교

```
TypeORM                              Prisma
──────────────────────               ──────────────────────

생성:                                 생성:
  repo.create() + repo.save()         prisma.model.create()
  (2단계)                              (1단계)

단일 조회:                            단일 조회:
  repo.findOneBy({ id })              prisma.model.findUnique()

목록 조회:                            목록 조회:
  repo.find({ where, order })         prisma.model.findMany()

복합 쿼리:                            복합 쿼리:
  QueryBuilder (문자열 기반)            중첩 객체 (타입 안전)

수정:                                 수정:
  repo.update() 또는 save()            prisma.model.update()

삭제:                                 삭제:
  repo.delete()                       prisma.model.delete()
```

---

## 핵심 차이 분석

### 1. 타입 안전성

| 항목 | TypeORM | Prisma |
|------|---------|--------|
| 쿼리 필드명 | 문자열 (오타 → 런타임 에러) | 자동완성 (오타 → 컴파일 에러) |
| 반환 타입 | Entity 클래스 (부분적) | 쿼리별 정확한 타입 |
| 관계 로딩 | `relations: ['posts']` (문자열) | `include: { posts: true }` (타입) |
| 필터 조건 | QueryBuilder는 문자열 | 중첩 객체로 타입 체크 |

### 2. API 설계 철학

```
TypeORM:
  "전통적 ORM 패턴"
  → Repository 패턴 + Active Record 패턴 중 선택
  → QueryBuilder로 복잡한 쿼리 작성
  → SQL과 유사한 사고방식

Prisma:
  "쿼리를 데이터처럼 작성"
  → 하나의 일관된 API
  → JavaScript 객체로 쿼리 표현
  → 중첩 객체로 관계까지 한 번에
```

### 3. 에러 감지 시점

```typescript
// TypeORM — 런타임에야 발견되는 오류
const posts = await postRepo.find({
  relations: ['posst'],  // 오타! → 런타임 에러 💥
});

// Prisma — 컴파일 시점에 발견
const posts = await prisma.post.findMany({
  include: { posst: true },  // 오타! → 컴파일 에러 ✅
  // TypeScript: 'posst' does not exist in type...
});
```

---

## 요약

- **TypeORM**: Repository 패턴 + QueryBuilder, 문자열 기반 관계 로딩, SQL 친화적
- **Prisma**: 단일 Client API, 객체 기반 쿼리, 완전한 타입 안전성
- Prisma는 쿼리 필드명 오타를 **컴파일 시점**에 잡아줌
- TypeORM의 QueryBuilder는 유연하지만 타입 안전성이 부족
- Prisma는 `include`/`select`로 필요한 데이터만 정확하게 로딩

---

## 다음 편 예고

1:1, 1:N, N:M 관계를 양쪽 ORM으로 정의하고 쿼리하는 방법을 깊이 비교합니다.

→ **[04편: 관계(Relations) 비교](04-relations.md)**

---

## 참고 자료

- [Prisma CRUD 공식 문서](https://www.prisma.io/docs/orm/prisma-client/queries/crud) — prisma.io
- [TypeORM Repository API](https://typeorm.io/repository-api) — typeorm.io
- [TypeORM QueryBuilder](https://typeorm.io/select-query-builder) — typeorm.io
