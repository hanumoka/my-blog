# 실무 가이드 — 어떤 ORM을 선택할까?

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [01~06편 전체](01-orm-overview.md)
> **시리즈**: Prisma vs TypeORM 비교 가이드 7/7 (최종편)

---

## 개요

6편에 걸쳐 두 ORM을 같은 예제로 비교했습니다.
이 최종편에서는 **실무 관점**에서 종합 평가하고, 상황별 선택 기준을 제시합니다.
"무조건 Prisma"가 아닌, **프로젝트 상황에 맞는 판단 기준**을 배웁니다.

---

## 시리즈 총정리

```
┌─────────────────────────────────────────────────────┐
│           TypeORM vs Prisma 종합 비교               │
├──────────────┬──────────────────┬───────────────────┤
│     항목     │    TypeORM       │     Prisma        │
├──────────────┼──────────────────┼───────────────────┤
│ 스키마 정의  │ 클래스+데코레이터 │ schema.prisma     │
│ 코드량       │ 많음 (3파일 90줄) │ 적음 (1파일 50줄) │
│ 타입 안전성  │ 부분적           │ 완전 자동          │
│ CRUD API    │ Repository+QB    │ Prisma Client     │
│ 관계 쿼리   │ QueryBuilder     │ 중첩 객체          │
│ 마이그레이션 │ 수동 생성/적용    │ 자동 감지/적용     │
│ NestJS 통합 │ 공식 패키지       │ 커스텀 모듈        │
│ 에러 감지   │ 런타임           │ 컴파일 타임        │
└──────────────┴──────────────────┴───────────────────┘
```

---

## 2026년 현재 상황

```
버전 현황:
  Prisma:  v7.4  (2026) — Rust 엔진 제거, 순수 TypeScript 재구축
  TypeORM: v0.3.28 (2025) — 안정적이지만 메이저 업데이트 느림

번들 크기:
  Prisma v7: 기존 대비 90% 축소 (Rust 바이너리 제거)
  TypeORM:   변화 없음

쿼리 성능:
  Prisma v7: 기존 대비 최대 3배 향상
  TypeORM:   안정적

커뮤니티 (npm 주간 다운로드):
  Prisma:    ████████████████████████████  ~2.5M
  TypeORM:   ████████████████████          ~1.8M
  Drizzle:   ████████████                  ~800K (신흥)
```

---

## 상황별 선택 가이드

### Prisma를 선택해야 하는 경우

```
✅ Prisma가 적합한 상황:

  1. 신규 NestJS 프로젝트
     → 처음부터 타입 안전한 구조로 시작

  2. 빠른 개발 속도가 중요할 때
     → 보일러플레이트 적음, 자동완성으로 생산성 높음

  3. 주니어 개발자가 많은 팀
     → 컴파일 타임 에러로 실수 방지
     → 직관적인 API, 낮은 러닝 커브

  4. Serverless / Edge 환경
     → Prisma v7의 경량화된 번들
     → Vercel, Cloudflare Workers 공식 지원

  5. 스키마 변경이 잦은 초기 스타트업
     → 선언적 마이그레이션으로 빠른 반복
```

### TypeORM을 선택해야 하는 경우

```
✅ TypeORM이 적합한 상황:

  1. 기존 TypeORM 프로젝트 유지보수
     → 마이그레이션 비용 > 전환 이익

  2. Java/Spring 경험이 풍부한 팀
     → JPA/Hibernate와 유사한 패턴
     → 데코레이터 기반이 친숙

  3. 복잡한 Raw SQL이 많이 필요할 때
     → QueryBuilder의 유연한 SQL 제어
     → Raw Query 지원이 더 자연스러움

  4. Active Record 패턴을 선호할 때
     → Entity에서 직접 쿼리 메서드 호출
     → user.save(), User.findOne() 등

  5. 다중 데이터베이스 동시 연결
     → TypeORM의 다중 DataSource 지원이 더 성숙
```

---

## 선택 의사결정 플로우

```
신규 프로젝트인가?
  │
  ├─ Yes ──→ 팀에 Java/Spring 배경이 강한가?
  │           ├─ Yes ──→ TypeORM 고려 (친숙함)
  │           └─ No  ──→ ✅ Prisma 권장
  │
  └─ No (기존 프로젝트) ──→ 현재 TypeORM 사용 중인가?
                             ├─ Yes ──→ 큰 문제 없으면 유지
                             │          문제가 심각하면 점진적 전환 고려
                             └─ No  ──→ 현재 ORM 유지
```

---

## TypeORM → Prisma 전환 시 고려사항

기존 TypeORM 프로젝트를 Prisma로 전환하려면:

```
1. Prisma 초기화
   npx prisma init

2. 기존 DB에서 스키마 추출
   npx prisma db pull
   → 현재 DB 구조가 schema.prisma로 자동 변환!

3. Prisma Client 생성
   npx prisma generate

4. 점진적 전환 (권장)
   → 새로운 기능부터 Prisma로 작성
   → 기존 코드는 TypeORM 유지
   → 두 ORM을 한 프로젝트에서 동시 사용 가능!

5. 완전 전환
   → 모든 Repository를 PrismaService로 교체
   → TypeORM 의존성 제거
```

> 💡 `prisma db pull`은 기존 데이터베이스를 Prisma 스키마로
> 자동 변환해줍니다. 빈 상태에서 스키마를 다시 작성할 필요가 없습니다.

---

## 실무에서 Prisma가 선호되는 이유

```
1. 타입 안전성 — "실수할 수 없는 구조"
   TypeORM: relations: ['posst'] → 런타임 에러 (배포 후 발견!)
   Prisma:  include: { posst: true } → 컴파일 에러 (개발 중 발견!)

2. 생산성 — "적은 코드, 빠른 개발"
   TypeORM: Entity 3파일 + Module forFeature + Repository 주입
   Prisma:  schema 1파일 + Global Module + 직접 주입

3. 마이그레이션 — "선언하면 알아서"
   TypeORM: 수동 생성 → 검토 → 수동 실행 (4단계)
   Prisma:  스키마 수정 → migrate dev (2단계)

4. 개발자 경험 — "쓰기 편하다"
   자동완성이 완벽하게 동작
   쿼리 결과 타입이 쿼리에 따라 자동 변경
   include 추가하면 반환 타입에 자동 반영
```

---

## 주의: Prisma의 한계

```
⚠️ 알아야 할 점:

  1. 복잡한 SQL
     → GROUP BY, HAVING, 서브쿼리 등은 $queryRaw 필요
     → TypeORM의 QueryBuilder가 더 유연한 경우 있음

  2. 커스텀 모듈 필요
     → NestJS 공식 패키지가 아님 (커뮤니티 레시피)
     → PrismaModule을 직접 만들어야 함

  3. 스키마 파일이 길어질 수 있음
     → 모델이 수십 개면 schema.prisma가 길어짐
     → prismaSchemaFolder 기능으로 여러 파일에 분리 가능 (v5.15+ GA)

  4. DB별 기능 차이
     → 일부 DB 고유 기능은 제한적 지원
```

---

## 최종 권장

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  2026년 기준 신규 NestJS 프로젝트라면            │
│                                                  │
│         ✅ Prisma를 권장합니다                    │
│                                                  │
│  이유:                                           │
│  • 완전한 타입 안전성 (실수 방지)                 │
│  • 적은 보일러플레이트 (빠른 개발)                │
│  • 선언적 마이그레이션 (안전한 스키마 관리)        │
│  • 활발한 생태계 (v7 대규모 개선)                 │
│  • 낮은 러닝 커브 (초보자 친화적)                 │
│                                                  │
│  단, 기존 TypeORM 프로젝트는                     │
│  큰 문제가 없다면 유지하는 것이 합리적입니다       │
│                                                  │
└──────────────────────────────────────────────────┘
```

---

## 요약

- **신규 프로젝트**: Prisma 권장 (타입 안전성, 생산성, 현대적 개발 경험)
- **기존 TypeORM 프로젝트**: 유지 또는 점진적 전환 (`prisma db pull`로 시작)
- **TypeORM 강점**: 복잡한 SQL, Active Record 패턴, Java/Spring 친숙한 팀
- **Prisma 강점**: 타입 안전성, 적은 코드량, 선언적 마이그레이션, Edge 지원
- 어떤 ORM이든 **핵심은 일관된 패턴**과 **팀의 합의**

---

## 시리즈 마무리

7편에 걸쳐 Prisma와 TypeORM을 같은 블로그 모델로 비교했습니다.

| 편 | 주제 | 핵심 |
|----|------|------|
| [01](01-orm-overview.md) | ORM이란? | ORM 개념, 두 ORM 소개 |
| [02](02-schema-definition.md) | 스키마 정의 | Entity vs schema.prisma |
| [03](03-crud-queries.md) | CRUD 쿼리 | Repository vs Prisma Client |
| [04](04-relations.md) | 관계 | 1:1, 1:N, N:M 비교 |
| [05](05-migrations.md) | 마이그레이션 | 명령적 vs 선언적 |
| [06](06-nestjs-integration.md) | NestJS 통합 | Module/Service 구성 |
| [07](07-practical-guide.md) | 실무 가이드 | 선택 기준 (현재 편) |

이 시리즈가 ORM 선택에 도움이 되기를 바랍니다!

---

## 참고 자료

- [Prisma vs TypeORM 공식 비교](https://www.prisma.io/docs/orm/more/comparisons/prisma-and-typeorm) — prisma.io
- [Prisma 7 릴리즈 공지](https://www.prisma.io/blog/announcing-prisma-orm-7-0-0) — prisma.io
- [NestJS Database 공식 문서](https://docs.nestjs.com/techniques/database) — docs.nestjs.com
- [npm trends: Prisma vs TypeORM](https://npmtrends.com/prisma-vs-typeorm) — npmtrends.com
