# Interceptor — 요청과 응답을 가로채기

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [09편: Guard](09-guard.md)
> **시리즈**: NestJS 학습 가이드 10/15

---

## 개요

Interceptor는 요청 **전**과 응답 **후**에 추가 로직을 실행합니다.
로깅, 응답 변환, 캐싱, 타임아웃 등에 활용됩니다.
Spring의 `HandlerInterceptor`와 AOP `@Around`에 대응합니다.

---

## Interceptor 실행 위치

```
Client 요청
    │
    ▼
  Middleware → Guard → ┌─────────────────────┐
                       │    Interceptor       │
                       │   (Before 로직)      │
                       └────────┬────────────┘
                                │
                       ┌────────▼────────────┐
                       │  Pipe → Controller   │
                       │      → Service       │
                       └────────┬────────────┘
                                │
                       ┌────────▼────────────┐
                       │    Interceptor       │
                       │   (After 로직)       │
                       └────────┬────────────┘
                                │
                                ▼
                          Client 응답
```

> **Spring에서는?**
> ```
> Filter → preHandle() → Controller → postHandle() → afterCompletion()
>                   └── AOP @Around ──┘
> ```
> NestJS Interceptor ≈ Spring `HandlerInterceptor` + AOP `@Around`의 결합

---

## Interceptor 기본 구조

```typescript
// src/common/interceptors/logging.interceptor.ts
import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';

@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const request = context.switchToHttp().getRequest();
    const method = request.method;
    const url = request.url;
    const now = Date.now();

    console.log(`[Request] ${method} ${url}`);

    return next.handle().pipe(
      tap(() => {
        console.log(`[Response] ${method} ${url} — ${Date.now() - now}ms`);
      }),
    );
  }
}
```

> 💡 `next.handle()`이 **Controller 실행**을 의미합니다.
> `pipe()` 안에서 응답 데이터를 가공할 수 있습니다.

> **Spring에서는?**
> ```java
> @Component
> public class LoggingInterceptor implements HandlerInterceptor {
>     @Override
>     public boolean preHandle(HttpServletRequest request, ...) {
>         request.setAttribute("startTime", System.currentTimeMillis());
>         return true;
>     }
>     @Override
>     public void afterCompletion(HttpServletRequest request, ...) {
>         long duration = System.currentTimeMillis() - (long) request.getAttribute("startTime");
>         log.info("{} {} — {}ms", request.getMethod(), request.getRequestURI(), duration);
>     }
> }
> ```

---

## 응답 변환 Interceptor

API 응답을 일관된 형식으로 래핑합니다.

```typescript
// src/common/interceptors/transform.interceptor.ts
import { Injectable, NestInterceptor, ExecutionContext, CallHandler } from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

export interface ApiResponse<T> {
  statusCode: number;
  data: T;
  timestamp: string;
}

@Injectable()
export class TransformInterceptor<T> implements NestInterceptor<T, ApiResponse<T>> {
  intercept(context: ExecutionContext, next: CallHandler): Observable<ApiResponse<T>> {
    return next.handle().pipe(
      map((data) => ({
        statusCode: context.switchToHttp().getResponse().statusCode,
        data,
        timestamp: new Date().toISOString(),
      })),
    );
  }
}
```

**적용 전/후 비교**:

```
적용 전:                          적용 후:
{ "id": 1, "name": "홍길동" }    {
                                    "statusCode": 200,
                                    "data": { "id": 1, "name": "홍길동" },
                                    "timestamp": "2026-03-29T12:00:00.000Z"
                                  }
```

> **Spring에서는?**
> `ResponseBodyAdvice<Object>`를 구현하거나 AOP `@Around`로 동일한 응답 래핑을 합니다.

---

## 타임아웃 Interceptor

```typescript
// src/common/interceptors/timeout.interceptor.ts
import { Injectable, NestInterceptor, ExecutionContext, CallHandler, RequestTimeoutException } from '@nestjs/common';
import { Observable, throwError, TimeoutError } from 'rxjs';
import { timeout, catchError } from 'rxjs/operators';

@Injectable()
export class TimeoutInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    return next.handle().pipe(
      timeout(5000),  // 5초 타임아웃
      catchError((err) => {
        if (err instanceof TimeoutError) {
          return throwError(() => new RequestTimeoutException());
        }
        return throwError(() => err);
      }),
    );
  }
}
```

---

## Interceptor 적용 방법

```typescript
// 1. 메서드 레벨
@UseInterceptors(LoggingInterceptor)
@Get()
findAll() { ... }

// 2. Controller 레벨
@UseInterceptors(LoggingInterceptor, TransformInterceptor)
@Controller('users')
export class UserController { ... }

// 3. 글로벌 레벨 (main.ts)
app.useGlobalInterceptors(new TransformInterceptor());

// 4. 글로벌 레벨 (Module — DI 가능)
@Module({
  providers: [
    { provide: APP_INTERCEPTOR, useClass: TransformInterceptor },
  ],
})
export class AppModule {}
```

---

## RxJS — 왜 Observable인가?

NestJS Interceptor는 **RxJS**의 `Observable`을 사용합니다.

```typescript
return next.handle().pipe(
  tap(data => ...),     // 사이드 이펙트 (로깅)
  map(data => ...),     // 데이터 변환
  timeout(5000),        // 타임아웃 설정
  catchError(err => ...), // 에러 처리
);
```

> **Spring에서는?**
> 동기적으로 `preHandle` → Controller → `postHandle` 순서로 실행됩니다.
> NestJS는 RxJS의 스트림 방식으로 더 유연한 조합이 가능합니다.
> RxJS를 모르더라도 `tap`, `map`, `catchError` 세 연산자만 알면 충분합니다.

---

## 요약

- **Interceptor**: 요청 전/후에 로직을 추가 (로깅, 응답 변환, 캐싱, 타임아웃)
- `NestInterceptor` 인터페이스 구현, `next.handle()`이 Controller 실행 지점
- RxJS의 `pipe()` + 연산자(`tap`, `map`, `catchError`)로 응답 가공
- Spring의 `HandlerInterceptor` + AOP `@Around`에 대응
- 글로벌 적용 시 `APP_INTERCEPTOR`를 Module에 등록하면 DI 가능

---

## 다음 편 예고

에러가 발생했을 때 응답 형식을 제어하는 **Exception Filter**를 배웁니다.

→ **[11편: Exception Filter](11-exception-filter.md)**

---

## 참고 자료

- [NestJS Interceptors 공식 문서](https://docs.nestjs.com/interceptors) — docs.nestjs.com
- [RxJS 공식 문서](https://rxjs.dev/) — rxjs.dev
