# Middleware — 요청 전처리 파이프라인

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [06편: 의존성 주입 심화](06-dependency-injection.md)
> **시리즈**: NestJS 학습 가이드 7/15

---

## 개요

Middleware는 요청이 Controller에 도달하기 전에 실행되는 함수입니다.
로깅, 인증, CORS 처리 등 **공통 전처리 로직**을 담당합니다.
Spring의 `jakarta.servlet.Filter`와 `HandlerInterceptor`에 대응합니다.

---

## Middleware 실행 위치

```
Client 요청
    │
    ▼
┌──────────────┐
│  Middleware   │ ← 여기! (req, res, next)
│  (로깅, 인증) │
└──────┬───────┘
       │ next()
       ▼
┌──────────────┐
│   Guard      │
└──────┬───────┘
       ▼
┌──────────────┐
│  Controller  │
└──────────────┘
```

> **Spring에서는?**
> `jakarta.servlet.Filter` → `HandlerInterceptor.preHandle()` → Controller 순서입니다.
> NestJS의 Middleware는 Spring의 **Filter**에 가장 가깝습니다.

---

## 클래스형 Middleware

```typescript
// src/common/middleware/logger.middleware.ts
import { Injectable, NestMiddleware } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';

@Injectable()
export class LoggerMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    const start = Date.now();

    // 응답 완료 후 로그 출력
    res.on('finish', () => {
      const duration = Date.now() - start;
      console.log(`${req.method} ${req.originalUrl} ${res.statusCode} ${duration}ms`);
    });

    next();  // 다음 미들웨어 또는 라우트 핸들러로 전달
  }
}
```

> 💡 `@Injectable()`이므로 **DI**를 사용할 수 있습니다!
> 다른 Service를 constructor에서 주입받을 수 있습니다.

---

## Middleware 적용 — Module에서 configure

```typescript
// src/app.module.ts
import { Module, NestModule, MiddlewareConsumer } from '@nestjs/common';
import { LoggerMiddleware } from './common/middleware/logger.middleware';
import { UserModule } from './user/user.module';

@Module({
  imports: [UserModule],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer
      .apply(LoggerMiddleware)
      .forRoutes('users');  // /users 경로에만 적용
  }
}
```

### 다양한 적용 방법

```typescript
// 각 예시는 독립적입니다 (forRoutes는 체인의 종결 메서드)

// 1. 특정 경로
consumer.apply(LoggerMiddleware).forRoutes('users');

// 2. 특정 메서드 + 경로
consumer.apply(LoggerMiddleware)
  .forRoutes({ path: 'users', method: RequestMethod.GET });

// 3. 특정 Controller
consumer.apply(LoggerMiddleware).forRoutes(UserController);

// 4. 모든 경로
consumer.apply(LoggerMiddleware).forRoutes('*splat');  // Express v5 문법 (NestJS v11)

// 5. 특정 경로 제외
consumer.apply(LoggerMiddleware)
  .exclude({ path: 'users/health', method: RequestMethod.GET })
  .forRoutes(UserController);
```

> **Spring에서는?**
> `FilterRegistrationBean`에서 `addUrlPatterns("/users/*")`로 URL 패턴을 지정합니다.
> ```java
> @Bean
> public FilterRegistrationBean<LoggingFilter> loggingFilter() {
>     FilterRegistrationBean<LoggingFilter> bean = new FilterRegistrationBean<>();
>     bean.setFilter(new LoggingFilter());
>     bean.addUrlPatterns("/users/*");
>     return bean;
> }
> ```

---

## 함수형 Middleware

DI가 필요 없는 간단한 경우, 함수로 작성할 수 있습니다.

```typescript
// 함수형 미들웨어 (간단한 경우)
export function corsMiddleware(req: Request, res: Response, next: NextFunction) {
  res.header('Access-Control-Allow-Origin', '*');
  next();
}

// Module에서 적용
configure(consumer: MiddlewareConsumer) {
  consumer
    .apply(corsMiddleware)
    .forRoutes('*splat');
}
```

---

## 여러 Middleware 체이닝

```typescript
configure(consumer: MiddlewareConsumer) {
  consumer
    .apply(
      LoggerMiddleware,       // 1번째 실행
      AuthMiddleware,         // 2번째 실행
      RateLimitMiddleware,    // 3번째 실행
    )
    .forRoutes('*splat');
}
```

> **Spring에서는?**
> `@Order` 어노테이션으로 Filter 실행 순서를 지정합니다.

---

## Global Middleware

모든 경로에 적용하는 글로벌 미들웨어는 `main.ts`에서 설정합니다.

```typescript
// src/main.ts
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // 글로벌 미들웨어 (함수형만 가능)
  app.use((req, res, next) => {
    console.log(`[Global] ${req.method} ${req.url}`);
    next();
  });

  // CORS 설정 (내장)
  app.enableCors({
    origin: ['http://localhost:3000'],
    methods: ['GET', 'POST', 'PUT', 'DELETE'],
  });

  await app.listen(3000);
}
bootstrap();
```

> ⚠️ `app.use()`는 DI를 사용할 수 없습니다 (함수형만 가능).
> DI가 필요한 글로벌 미들웨어는 Module의 `configure()`에서 `forRoutes('*splat')`로 적용하세요.

---

## Middleware vs Guard — 언제 무엇을 쓸까?

| 항목 | Middleware | Guard |
|------|-----------|-------|
| 실행 시점 | Guard 이전 | Middleware 이후 |
| 접근 가능 | req, res, next | ExecutionContext |
| 주 용도 | 로깅, CORS, 헤더 수정 | 인증, 인가, 역할 체크 |
| 라우트 정보 | 알 수 없음 | 어떤 핸들러가 실행될지 앎 |
| Spring 대응 | Filter | Security Filter |

---

## 요약

- **Middleware**: 요청이 Controller에 도달하기 전 실행 (로깅, 인증, CORS)
- 클래스형(`@Injectable` + NestMiddleware)은 DI 가능, 함수형은 간단한 경우
- `MiddlewareConsumer.apply().forRoutes()`로 경로별 적용
- 여러 Middleware를 `apply(A, B, C)`로 체이닝
- Spring의 `jakarta.servlet.Filter`에 대응

---

## 다음 편 예고

입력 데이터를 변환하고 검증하는 **Pipe**를 배웁니다. Spring의 `@Valid` + Bean Validation과 비교합니다.

→ **[08편: Pipe](08-pipe.md)**

---

## 참고 자료

- [NestJS Middleware 공식 문서](https://docs.nestjs.com/middleware) — docs.nestjs.com
- [Express v5 마이그레이션 가이드](https://expressjs.com/en/guide/migrating-5.html) — expressjs.com
