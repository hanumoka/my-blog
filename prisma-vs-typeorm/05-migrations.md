# 마이그레이션 비교 — 스키마 변경을 안전하게 관리하기

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [04편: 관계(Relations) 비교](04-relations.md)
> **시리즈**: Prisma vs TypeORM 비교 가이드 5/7

---

## 개요

운영 중인 서비스에서 테이블 구조를 바꾸려면 **마이그레이션**이 필수입니다.
TypeORM은 **마이그레이션 파일을 직접 관리**하고, Prisma는 **스키마 변경을 자동 감지**합니다.
같은 변경 작업을 양쪽으로 수행하며 워크플로우 차이를 비교합니다.

---

## 마이그레이션 워크플로우 비교

```
TypeORM:                                Prisma:
  1. Entity 클래스 수정                    1. schema.prisma 수정
       │                                       │
       ▼                                       ▼
  2. CLI로 마이그레이션 생성               2. prisma migrate dev
     migration:generate                     (자동 감지 + 생성 + 적용)
       │                                       │
       ▼                                       ▼
  3. 생성된 SQL 파일 검토/수정             3. 생성된 SQL 파일 검토
       │                                       │
       ▼                                       ▼
  4. migration:run 실행                    4. (이미 적용됨!)
       │                                       │
       ▼                                       ▼
  5. DB에 반영                             5. prisma generate (클라이언트 갱신)
```

---

## 예제: 기존 User 모델에 `phone` 컬럼 추가

### TypeORM 방식

**1단계 — Entity 수정**:

```typescript
// src/entities/user.entity.ts
@Entity('users')
export class User {
  // ... 기존 필드들

  @Column({ type: 'varchar', length: 20, nullable: true })
  phone: string;  // 새 필드 추가
}
```

**2단계 — 마이그레이션 생성**:

```bash
npx typeorm migration:generate -d src/data-source.ts src/migrations/AddUserPhone
```

**3단계 — 생성된 마이그레이션 파일 확인**:

```typescript
// src/migrations/1234567890-AddUserPhone.ts
import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddUserPhone1234567890 implements MigrationInterface {
  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "users" ADD "phone" varchar(20)`
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "users" DROP COLUMN "phone"`
    );
  }
}
```

**4단계 — 마이그레이션 실행**:

```bash
# 적용
npx typeorm migration:run -d src/data-source.ts

# 롤백 (필요 시)
npx typeorm migration:revert -d src/data-source.ts
```

### Prisma 방식

**1단계 — 스키마 수정**:

```prisma
// prisma/schema.prisma
model User {
  // ... 기존 필드들
  phone String? @db.VarChar(20)  // 새 필드 추가 (? = nullable)
}
```

**2단계 — 마이그레이션 생성 + 적용 (한 번에!)**:

```bash
npx prisma migrate dev --name add-user-phone
```

**자동 생성된 SQL 파일**:

```sql
-- prisma/migrations/20260329120000_add_user_phone/migration.sql
ALTER TABLE "users" ADD COLUMN "phone" VARCHAR(20);
```

**3단계 — Prisma Client 갱신**:

```bash
npx prisma generate
# 이제 prisma.user.create({ data: { phone: '010-1234-5678' } })
# phone 필드가 자동완성됨!
```

---

## TypeORM의 synchronize 옵션 ⚠️

```typescript
// data-source.ts
export const AppDataSource = new DataSource({
  // ...
  synchronize: true,  // ⚠️ Entity와 DB를 자동 동기화
});
```

```
⚠️ synchronize: true 의 위험성:

  개발 환경에서는 편리함:
    Entity 수정 → 서버 재시작 → DB 자동 반영

  운영 환경에서는 재앙:
    컬럼 삭제 시 → 데이터 손실! 복구 불가! 💥
    타입 변경 시 → 예기치 않은 데이터 변환!

  ✅ 규칙: synchronize는 개발 전용, 운영은 반드시 migration 사용
```

> 💡 Prisma에는 `synchronize` 같은 옵션이 없습니다.
> 대신 `prisma db push`가 프로토타이핑용으로 제공됩니다.

---

## Prisma의 프로토타이핑 도구: db push

```bash
# 마이그레이션 파일 없이 스키마를 DB에 바로 반영
npx prisma db push
```

```
prisma migrate dev vs prisma db push:

  migrate dev:                        db push:
    마이그레이션 파일 생성 ✅             파일 생성 안 함 ❌
    히스토리 추적 ✅                     히스토리 없음 ❌
    팀 공유 가능 ✅                      팀 공유 불가 ❌
    운영 배포 가능 ✅                    운영 사용 금지 ❌

  → db push는 개발 초기 프로토타이핑에만 사용!
  → 스키마가 확정되면 migrate dev로 전환
```

---

## 운영 환경 마이그레이션

```bash
# TypeORM — 운영 배포
npx typeorm migration:run -d src/data-source.ts

# Prisma — 운영 배포
npx prisma migrate deploy
# migrate dev와 달리:
#   - 새 마이그레이션 생성 안 함
#   - 미적용 마이그레이션만 순서대로 실행
#   - CI/CD 파이프라인에서 사용
```

---

## 마이그레이션 관리 비교

| 항목 | TypeORM | Prisma |
|------|---------|--------|
| 생성 방식 | CLI로 수동 생성 | 스키마 diff 자동 감지 |
| 파일 형식 | TypeScript 클래스 | SQL 파일 |
| up/down | generate 시 자동 생성 (수동 수정 가능) | 자동 생성 (down은 `migrate diff`로 별도) |
| 롤백 | `migration:revert` (1개씩) | `migrate reset` (전체) 또는 `migrate diff`로 롤백 SQL 생성 |
| 프로토타이핑 | `synchronize: true` | `prisma db push` |
| 운영 배포 | `migration:run` | `migrate deploy` |
| 상태 추적 | migrations 테이블 | _prisma_migrations 테이블 |

---

## 핵심 차이

```
TypeORM — "명령적(Imperative)"
  개발자가 up/down SQL을 직접 제어
  세밀한 컨트롤 가능하지만 실수 여지도 큼
  마이그레이션 파일을 직접 수정/커스터마이징 가능

Prisma — "선언적(Declarative)"
  "이 상태가 되어야 한다"만 선언
  Prisma가 현재 DB와 비교해서 SQL 자동 생성
  개발자는 결과 SQL만 검토하면 됨
```

---

## 요약

- **TypeORM**: Entity 수정 → `migration:generate` → SQL 검토 → `migration:run` (4단계)
- **Prisma**: 스키마 수정 → `prisma migrate dev` (2단계, 자동 감지+적용)
- `synchronize: true`와 `db push`는 **개발 전용** — 운영 금지!
- 운영 배포: TypeORM은 `migration:run`, Prisma는 `migrate deploy`
- Prisma의 선언적 접근이 실수를 줄이고 워크플로우를 단순화

---

## 다음 편 예고

NestJS 프로젝트에서 두 ORM을 실제로 통합하는 방법을 Module과 Service 구성으로 비교합니다.

→ **[06편: NestJS 통합 비교](06-nestjs-integration.md)**

---

## 참고 자료

- [Prisma Migrate 공식 문서](https://www.prisma.io/docs/orm/prisma-migrate) — prisma.io
- [TypeORM Migration 공식 문서](https://typeorm.io/migrations) — typeorm.io
- [Prisma db push vs migrate dev](https://www.prisma.io/docs/orm/prisma-migrate/workflows/prototyping-your-schema) — prisma.io
