# 요청 라이프사이클 — 전체 흐름 완전 정리

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [12편: Custom Decorator](12-custom-decorator.md)
> **시리즈**: NestJS 학습 가이드 13/15

---

## 개요

지금까지 Middleware, Guard, Pipe, Interceptor, Exception Filter를 개별적으로 배웠습니다.
이 편에서는 **모든 계층이 어떤 순서로 실행되는지** 전체 그림을 정리합니다.
Spring의 요청 처리 흐름과 나란히 비교합니다.

---

## NestJS 요청 라이프사이클

```
Client 요청
    │
    ▼
┌──────────────────────────────────────────────┐
│ 1. Global Middleware                         │
│ 2. Module Middleware                         │
│    (로깅, CORS, 헤더 수정)                    │
├──────────────────────────────────────────────┤
│ 3. Global Guard                              │
│ 4. Controller Guard                          │
│ 5. Route Guard                               │
│    (인증/인가 — 요청 허용 여부 결정)           │
├──────────────────────────────────────────────┤
│ 6. Global Interceptor (Before)               │
│ 7. Controller Interceptor (Before)           │
│ 8. Route Interceptor (Before)                │
│    (요청 전처리 — 로깅 시작, 캐시 확인)       │
├──────────────────────────────────────────────┤
│ 9. Global Pipe                               │
│ 10. Controller Pipe                          │
│ 11. Route Pipe                               │
│    (데이터 변환/검증 — DTO 유효성 검사)       │
├──────────────────────────────────────────────┤
│ 12. Controller Method (Route Handler)        │
│     → Service → Repository                   │
│    (비즈니스 로직 실행)                       │
├──────────────────────────────────────────────┤
│ 13. Route Interceptor (After)                │
│ 14. Controller Interceptor (After)           │
│ 15. Global Interceptor (After)               │
│    (응답 후처리 — 응답 변환, 로깅 종료)       │
├──────────────────────────────────────────────┤
│ 16. Exception Filter (에러 발생 시)           │
│    Route → Controller → Global 순서로 탐색   │
└──────────────────────────────────────────────┘
    │
    ▼
Client 응답
```

> 💡 **핵심 순서**: Middleware → Guard → Interceptor(전) → Pipe → Handler → Interceptor(후) → Filter(에러 시)
>
> 같은 계층 내에서는 **Global → Controller → Route** 순서로 실행됩니다.

---

## Spring과 나란히 비교

```
NestJS:                                Spring:
──────                                 ──────
1. Middleware                     →    1. Filter (javax.servlet.Filter)
2. Guard                          →    2. Security FilterChain
3. Interceptor (Before)           →    3. HandlerInterceptor.preHandle()
                                       3.5. AOP @Before / @Around (진입)
4. Pipe                           →    4. @Valid + ArgumentResolver
5. Controller → Service           →    5. @Controller → @Service
6. Interceptor (After)            →    6. AOP @Around (복귀)
                                       6.5. HandlerInterceptor.postHandle()
7. Exception Filter               →    7. @ControllerAdvice + @ExceptionHandler
```

---

## 각 계층의 역할 정리

| 순서 | 계층 | 역할 | "이것을 할 때 쓴다" | Spring 대응 |
|------|------|------|---------------------|-------------|
| 1 | Middleware | 요청 전처리 | 로깅, CORS, 헤더 수정 | Filter |
| 2 | Guard | 접근 제어 | 인증, 인가, 역할 체크 | Security Filter |
| 3 | Interceptor(전) | 요청 가로채기 | 실행 시간 측정, 캐시 확인 | preHandle / AOP |
| 4 | Pipe | 데이터 처리 | 타입 변환, DTO 검증 | @Valid |
| 5 | Handler | 비즈니스 로직 | CRUD, 핵심 로직 | @Controller |
| 6 | Interceptor(후) | 응답 가로채기 | 응답 래핑, 로깅 완료 | postHandle / AOP |
| 7 | Exception Filter | 에러 처리 | 에러 응답 포맷팅 | @ControllerAdvice |

---

## 의사결정 가이드 — 어디에 넣을까?

```
"로그를 남기고 싶다"
  └─ Middleware (요청 정보만) 또는 Interceptor (응답까지)

"인증/인가를 체크하고 싶다"
  └─ Guard

"입력 데이터를 검증하고 싶다"
  └─ Pipe + class-validator

"응답 형식을 통일하고 싶다"
  └─ Interceptor (TransformInterceptor)

"에러 응답을 커스터마이징하고 싶다"
  └─ Exception Filter

"특정 URL에만 전처리를 하고 싶다"
  └─ Middleware (forRoutes) 또는 Guard (@UseGuards)

"요청 데이터에서 현재 사용자를 추출하고 싶다"
  └─ Custom Param Decorator (@CurrentUser)
```

---

## 실습: 전체 라이프사이클 로그 확인

```typescript
// 각 계층에 console.log를 추가하면 실행 순서를 확인할 수 있습니다

// Middleware
use(req, res, next) {
  console.log('[1] Middleware');
  next();
}

// Guard
canActivate(context) {
  console.log('[2] Guard');
  return true;
}

// Interceptor
intercept(context, next) {
  console.log('[3] Interceptor - Before');
  return next.handle().pipe(
    tap(() => console.log('[6] Interceptor - After')),
  );
}

// Pipe
transform(value) {
  console.log('[4] Pipe');
  return value;
}

// Controller
@Get()
findAll() {
  console.log('[5] Controller');
  return [];
}
```

**출력 결과**:

```
[1] Middleware
[2] Guard
[3] Interceptor - Before
[4] Pipe
[5] Controller
[6] Interceptor - After
```

---

## 에러 발생 시 흐름

```
정상 흐름:
  Middleware → Guard → Interceptor(전) → Pipe → Handler → Interceptor(후)

Pipe에서 에러 발생 시:
  Middleware → Guard → Interceptor(전) → Pipe 💥 → Exception Filter

Guard에서 거부 시:
  Middleware → Guard 🚫 → Exception Filter

Handler에서 에러 발생 시:
  Middleware → Guard → Interceptor(전) → Pipe → Handler 💥 → Exception Filter
```

> 💡 에러가 어디서 발생하든 **Exception Filter**가 최종 처리합니다.

---

## 요약

- **실행 순서**: Middleware → Guard → Interceptor(전) → Pipe → Handler → Interceptor(후)
- 에러 발생 시 **Exception Filter**가 최종 처리
- 같은 계층 내에서는 **Global → Controller → Route** 순서
- Spring과 1:1 대응: Filter → Security → preHandle/AOP → @Valid → Controller → postHandle/AOP → @ControllerAdvice
- 각 계층의 역할을 정확히 알면 **어디에 코드를 넣을지** 바로 판단 가능

---

## 다음 편 예고

이론을 모두 마쳤으니, **Prisma와 함께 실제 CRUD API**를 처음부터 끝까지 구현합니다.

→ **[14편: Database 연동 — Prisma로 CRUD 구현](14-database-prisma.md)**

---

## 참고 자료

- [NestJS Request Lifecycle 공식 문서](https://docs.nestjs.com/faq/request-lifecycle) — docs.nestjs.com
- [NestJS Execution Context 공식 문서](https://docs.nestjs.com/fundamentals/execution-context) — docs.nestjs.com
