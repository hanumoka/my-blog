# ORM이란? — NestJS 개발자를 위한 첫걸음

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: JavaScript/TypeScript 기초, SQL 기본 개념
> **시리즈**: Prisma vs TypeORM 비교 가이드 1/7

---

## 개요

NestJS로 백엔드를 개발하면 반드시 데이터베이스를 다루게 됩니다.
SQL을 직접 작성할 수도 있지만, **ORM(Object-Relational Mapping)**을 사용하면 TypeScript 코드로 DB를 조작할 수 있습니다.
이 편에서는 ORM이 무엇인지, 왜 필요한지, 그리고 NestJS에서 가장 많이 쓰이는 두 ORM을 소개합니다.

---

## ORM이 없다면?

```typescript
// ❌ Raw SQL — 타입 안전성 없음, 오타 = 런타임 에러
const result = await connection.query(
  `SELECT id, email, name FROM users WHERE id = $1`,
  [userId]
);
// result 타입이 any — email을 eamil로 오타 내도 컴파일 에러 없음
console.log(result.rows[0].eamil); // undefined (런타임에야 발견!)
```

## ORM이 있다면?

```typescript
// ✅ ORM — 타입 안전, 자동 완성, 컴파일 시 에러 감지
const user = await prisma.user.findUnique({
  where: { id: userId },
});
console.log(user.eamil); // ← 컴파일 에러! 'eamil' 속성이 없습니다
```

---

## ORM의 역할

```
┌─────────────────┐                    ┌──────────────┐
│  TypeScript 코드 │                    │  데이터베이스  │
│                 │                    │              │
│  user.findMany()│ ──── ORM 변환 ──→  │ SELECT * FROM│
│  user.create()  │      (자동)        │ INSERT INTO  │
│  user.update()  │ ←── 결과 매핑 ──── │ 쿼리 결과     │
│                 │   (타입 안전)       │              │
└─────────────────┘                    └──────────────┘

ORM이 해주는 일:
  1. TypeScript 코드 → SQL 변환
  2. 쿼리 결과 → TypeScript 객체 매핑
  3. 타입 안전성 보장
  4. 마이그레이션 관리
```

---

## NestJS의 두 가지 대표 ORM

### TypeORM — 데코레이터 기반의 전통적 ORM

```typescript
// TypeORM: 클래스 + 데코레이터로 테이블 정의
@Entity()
export class User {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ unique: true })
  email: string;

  @Column()
  name: string;

  @CreateDateColumn()
  createdAt: Date;
}
```

### Prisma — 스키마 파일 기반의 현대적 ORM

```prisma
// Prisma: 전용 스키마 파일(schema.prisma)로 테이블 정의
model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  name      String
  createdAt DateTime @default(now())
}
```

---

## 핵심 차이 한눈에 보기

```
TypeORM:                            Prisma:
  "코드가 곧 스키마"                   "스키마가 곧 코드를 생성"

  ┌──────────────────┐               ┌──────────────────┐
  │  Entity 클래스    │               │  schema.prisma   │
  │  (데코레이터)     │               │  (선언적 파일)    │
  └────────┬─────────┘               └────────┬─────────┘
           │                                  │
           ▼                                  ▼ npx prisma generate
  ┌──────────────────┐               ┌──────────────────┐
  │  Repository      │               │  Prisma Client   │
  │  (직접 작성)      │               │  (자동 생성)      │
  └──────────────────┘               └──────────────────┘
```

| 항목 | TypeORM | Prisma |
|------|---------|--------|
| 접근 방식 | 코드 퍼스트 (데코레이터) | 스키마 퍼스트 (DSL 파일) |
| 타입 안전성 | 부분적 | 완전 자동 |
| 학습 곡선 | Java/Spring 경험자에게 친숙 | 새로운 패러다임 (쉬움) |
| NestJS 통합 | 공식 1순위 (`@nestjs/typeorm`) | 공식 지원 (`@nestjs/prisma`는 커뮤니티) |
| 최신 버전 (2026) | v0.3.28 | v7.4 |
| 쿼리 방식 | QueryBuilder + Active Record | Prisma Client API |

---

## 2026년 현재 트렌드

```
npm 다운로드 추이 (2024~2026):

  Prisma:    ████████████████████████████  ↗ 빠르게 성장
  TypeORM:   ████████████████████          → 안정적 유지
  Drizzle:   ████████████                  ↗ 신흥 강자
```

- **Prisma v7** (2026): Rust 엔진 제거 → 순수 TypeScript로 재구축, 번들 90% 축소, 쿼리 3배 빨라짐
- **TypeORM v0.3.28**: 안정적이지만 메이저 업데이트 속도가 느림
- **실무 권장**: 신규 프로젝트에서는 Prisma가 점점 더 선호됨

> 💡 **왜 Prisma를 권장할까?**
> - 타입 안전성이 **완전 자동** (실수할 수 없는 구조)
> - 마이그레이션이 **선언적** (스키마 수정 → 자동 감지)
> - 러닝 커브가 낮음 (ORM 패턴 학습 불필요)
> - Edge 환경(Vercel, Cloudflare Workers) 지원

---

## 이 시리즈에서 배우는 것

| 편 | 주제 |
|----|------|
| **01** | ORM이란? (현재 편) |
| **02** | 스키마 정의 비교 — Entity vs schema.prisma |
| **03** | CRUD 쿼리 비교 — 생성/조회/수정/삭제 |
| **04** | 관계(Relations) 비교 — 1:1, 1:N, N:M |
| **05** | 마이그레이션 비교 — 스키마 변경 관리 |
| **06** | NestJS 통합 비교 — Module/Service 구성 |
| **07** | 실무 가이드 — 어떤 걸 선택할까? |

---

## 요약

- **ORM** = TypeScript 코드로 데이터베이스를 조작하는 도구
- **TypeORM**: 데코레이터 기반, 전통적 ORM 패턴, NestJS 공식 1순위
- **Prisma**: 스키마 파일 기반, 자동 타입 생성, 현대적 개발 경험
- 2026년 기준 **신규 프로젝트에서는 Prisma가 선호**되는 추세
- 이 시리즈에서 두 ORM을 같은 예제로 비교하며 차이를 체감합니다

---

## 다음 편 예고

동일한 데이터 모델을 TypeORM 데코레이터와 Prisma 스키마로 각각 정의하며 차이를 직접 비교합니다.

→ **[02편: 스키마 정의 비교](02-schema-definition.md)**

---

## 참고 자료

- [Prisma vs TypeORM 공식 비교](https://www.prisma.io/docs/orm/more/comparisons/prisma-and-typeorm) — prisma.io
- [Prisma 7 릴리즈 공지](https://www.prisma.io/blog/announcing-prisma-orm-7-0-0) — prisma.io
- [NestJS Database 공식 문서](https://docs.nestjs.com/techniques/database) — docs.nestjs.com
- [Prisma or TypeORM in 2026?](https://medium.com/@Nexumo_/prisma-or-typeorm-in-2026-the-nestjs-data-layer-call-ae47b5cfdd73) — Medium
