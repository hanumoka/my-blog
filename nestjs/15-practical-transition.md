# 실무 전환 가이드 — Spring 개발자의 NestJS 적응 전략

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [01~14편 전체](01-nestjs-intro.md)
> **시리즈**: NestJS 학습 가이드 15/15 (최종편)

---

## 개요

14편에 걸쳐 NestJS의 핵심 개념을 Spring과 비교하며 배웠습니다.
이 최종편에서는 **Spring 개발자가 NestJS 실무에 진입할 때** 알아야 할 핵심 차이, 실무 체크리스트, 흔한 함정을 정리합니다.

---

## Spring ↔ NestJS 개념 대응표 (종합)

```
┌──────────────────────────┬──────────────────────────┐
│       Spring Boot         │        NestJS            │
├──────────────────────────┼──────────────────────────┤
│ @SpringBootApplication   │ AppModule                │
│ @Configuration           │ @Module                  │
│ @RestController          │ @Controller              │
│ @Service / @Component    │ @Injectable              │
│ @Autowired               │ constructor 주입          │
│ @Qualifier / @Primary    │ useClass / useExisting    │
│ @Value("${key}")         │ @Inject('TOKEN')         │
│ @Bean                    │ useFactory               │
│ @Profile                 │ useClass (환경 분기)      │
│ javax.servlet.Filter     │ Middleware               │
│ Security FilterChain     │ Guard                    │
│ @PreAuthorize            │ @Roles + RolesGuard      │
│ HandlerInterceptor       │ Interceptor              │
│ AOP @Around              │ Interceptor (RxJS)       │
│ @Valid + Bean Validation  │ ValidationPipe           │
│ @ExceptionHandler        │ @Catch + ExceptionFilter │
│ @ControllerAdvice        │ Global ExceptionFilter   │
│ @interface (커스텀)       │ Custom Decorator         │
│ JpaRepository            │ PrismaService            │
│ application.yml          │ @nestjs/config + .env    │
│ JUnit + Mockito          │ Vitest (v11 기본)        │
│ Gradle / Maven           │ npm / pnpm               │
└──────────────────────────┴──────────────────────────┘
```

---

## 핵심 패러다임 차이

### 1. 멀티스레드 vs 이벤트 루프

```
Spring (Java):                       NestJS (Node.js):
┌─────────────────┐                 ┌─────────────────┐
│ 요청 1 → Thread 1│                 │ 요청 1 ─┐       │
│ 요청 2 → Thread 2│                 │ 요청 2 ─┤ Event │
│ 요청 3 → Thread 3│                 │ 요청 3 ─┘ Loop  │
│   (각각 독립)     │                 │  (단일 스레드)   │
└─────────────────┘                 └─────────────────┘

Spring: 동시 요청을 여러 스레드로 처리 (블로킹 I/O OK)
NestJS: 단일 스레드로 비동기 처리 (블로킹 I/O 금지!)
```

> ⚠️ **가장 중요한 차이**: NestJS에서 `Thread.sleep()` 같은 블로킹 코드를 쓰면
> **전체 서버가 멈춥니다**. 모든 I/O는 `async/await`로 비동기 처리해야 합니다.

### 2. 동기 → 비동기

```typescript
// ❌ Spring 습관 — 동기적 사고
function getUser(id: number) {
  const user = db.query(`SELECT * FROM users WHERE id = ${id}`);  // 블로킹!
  return user;
}

// ✅ NestJS 방식 — 비동기
async function getUser(id: number) {
  const user = await prisma.user.findUnique({ where: { id } });  // 논블로킹
  return user;
}
```

### 3. 타입 시스템 차이

```
Java:                               TypeScript:
  컴파일 시 타입 보장 ✅               컴파일 시 타입 체크 ✅
  런타임에도 타입 존재 ✅              런타임에는 타입 없음 ❌ (지워짐)
  리플렉션으로 타입 조회 가능           class-transformer로 보완
  Generic 타입 소거 (Type Erasure)     Generic 타입 소거 (동일)

  → TypeScript는 "신뢰하되 검증"하는 자세가 필요
  → ValidationPipe + class-validator로 런타임 검증 보완
```

---

## 실무 프로젝트 체크리스트

### 필수 패키지

```bash
# 환경변수 관리
npm install @nestjs/config

# API 문서 자동 생성 (Swagger)
npm install @nestjs/swagger

# 헬스체크
npm install @nestjs/terminus

# 유효성 검증
npm install class-validator class-transformer

# 데이터베이스
npm install prisma --save-dev
npm install @prisma/client
```

### main.ts 필수 설정

```typescript
// src/main.ts
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // 1. Global ValidationPipe
  app.useGlobalPipes(new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
  }));

  // 2. CORS
  app.enableCors();

  // 3. API Prefix
  app.setGlobalPrefix('api/v1');

  // 4. Swagger
  const config = new DocumentBuilder()
    .setTitle('My API')
    .setVersion('1.0')
    .addBearerAuth()
    .build();
  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('docs', app, document);

  // 5. Graceful Shutdown
  app.enableShutdownHooks();

  await app.listen(3000);
}
bootstrap();
```

> **Spring에서는?**
> `application.yml`에서 대부분 설정합니다. NestJS는 `main.ts`에서 코드로 설정합니다.

---

## Spring 개발자가 흔히 빠지는 함정

```
❌ 함정 1: 동기 코드 작성
  Spring 습관으로 동기 DB 드라이버 사용
  → Node.js에서는 전체 서버가 블로킹됨
  ✅ 해결: 항상 async/await 사용, Prisma/TypeORM 등 비동기 ORM 사용

❌ 함정 2: any 타입 남용
  "Java처럼 Object로 받으면 되지"
  → TypeScript의 타입 안전성이 무력화됨
  ✅ 해결: strict 모드 유지, DTO 클래스 적극 활용

❌ 함정 3: 과도한 추상화
  Spring의 Interface + Impl 패턴을 그대로 적용
  → NestJS에서는 불필요한 복잡성
  ✅ 해결: 구현체가 1개면 인터페이스 불필요, 직접 Service 클래스 사용

❌ 함정 4: Spring Security 패턴 그대로 적용
  복잡한 SecurityConfig를 NestJS에서 재현하려 함
  → NestJS는 Guard + Decorator 조합이 더 간결
  ✅ 해결: @Auth('admin') 합성 데코레이터 패턴 활용

❌ 함정 5: application.yml 찾기
  Spring의 설정 파일을 찾으려 함
  → NestJS는 .env + @nestjs/config 조합
  ✅ 해결: ConfigModule.forRoot() + ConfigService 사용
```

---

## 2026년 NestJS 생태계

```
NestJS v11 (2026 최신):
  ├─ SWC 기본 컴파일러 (빌드 20배 빨라짐)
  ├─ Vitest 기본 테스트 러너
  ├─ Express v5 / Fastify v5 지원
  ├─ ESM 퍼스트 클래스 지원
  └─ JSON Logger (컨테이너 환경)

커뮤니티:
  ├─ npm 주간 다운로드: ~8,500,000회
  ├─ GitHub Stars: 75,000+
  ├─ 채용 시장: 전년 대비 45% 성장
  └─ Series A 펀딩 → 2030년까지 유지보수 보장
```

---

## 요약

- **패러다임 전환**: 멀티스레드 → 이벤트 루프, 동기 → 비동기, 블로킹 → 논블로킹
- **1:1 대응**: Spring의 모든 핵심 개념에 NestJS 대응 개념이 존재
- **핵심 함정**: 동기 코드, any 남용, 과도한 추상화, Spring Security 패턴 그대로 적용
- **실무 필수**: ValidationPipe, @nestjs/config, Swagger, 헬스체크, Graceful Shutdown
- NestJS는 Spring과 **철학이 매우 유사**하므로 적응이 빠를 것!

---

## 시리즈 마무리

15편에 걸쳐 NestJS의 핵심을 Spring과 비교하며 학습했습니다.

| 편 | 주제 | 핵심 |
|----|------|------|
| [01](01-nestjs-intro.md) | NestJS 소개 | 아키텍처, Spring과의 공통점 |
| [02](02-project-setup.md) | 개발 환경 설정 | CLI, 프로젝트 구조 |
| [03](03-module.md) | Module | 애플리케이션 구조 단위 |
| [04](04-controller.md) | Controller | HTTP 요청 처리 |
| [05](05-provider-service.md) | Provider & Service | 비즈니스 로직, DI |
| [06](06-dependency-injection.md) | DI 심화 | Custom Provider, Scope |
| [07](07-middleware.md) | Middleware | 요청 전처리 |
| [08](08-pipe.md) | Pipe | 데이터 변환/검증 |
| [09](09-guard.md) | Guard | 인증/인가 |
| [10](10-interceptor.md) | Interceptor | 요청/응답 가로채기 |
| [11](11-exception-filter.md) | Exception Filter | 에러 처리 |
| [12](12-custom-decorator.md) | Custom Decorator | 재사용 로직 |
| [13](13-request-lifecycle.md) | 요청 라이프사이클 | 전체 흐름 정리 |
| [14](14-database-prisma.md) | Database + Prisma | CRUD 구현 |
| [15](15-practical-transition.md) | 실무 전환 가이드 | 적응 전략 (현재 편) |

Spring 개발자라면 NestJS는 **가장 친숙한 Node.js 프레임워크**입니다. 이 시리즈가 전환에 도움이 되기를 바랍니다!

---

## 참고 자료

- [NestJS 공식 문서](https://docs.nestjs.com/) — docs.nestjs.com
- [NestJS 11 릴리즈 공지](https://trilon.io/blog/announcing-nestjs-11-whats-new) — trilon.io
- [Spring Boot vs NestJS 2026](https://trilon.io/blog/spring-boot-vs-nestjs-2026-performance) — trilon.io
- [NestJS GitHub](https://github.com/nestjs/nest) — github.com
