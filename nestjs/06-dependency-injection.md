# 의존성 주입(DI) 심화 — Custom Provider와 Scope

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [05편: Provider와 Service](05-provider-service.md)
> **시리즈**: NestJS 학습 가이드 6/15

---

## 개요

05편에서 기본적인 Provider 등록과 주입을 배웠습니다.
이 편에서는 **Custom Provider**, **Provider Scope**, **순환 의존성** 등 DI의 심화 기능을 다룹니다.
Spring의 `@Qualifier`, `@Primary`, `prototype scope`와 대응하며 비교합니다.

---

## Custom Provider — 4가지 방식

기본 방식(`providers: [UserService]`)은 사실 축약 문법입니다.

```typescript
// 축약 문법
providers: [UserService]

// 실제 전체 문법 (useClass)
providers: [
  {
    provide: UserService,    // 토큰 (주입 시 식별자)
    useClass: UserService,   // 실제 클래스
  },
]
```

### 1. useClass — 클래스 교체

```typescript
// 환경에 따라 다른 구현체 주입
providers: [
  {
    provide: ConfigService,
    useClass:
      process.env.NODE_ENV === 'production'
        ? ProdConfigService
        : DevConfigService,
  },
]
```

> **Spring에서는?**
> `@Profile("prod")` + `@Profile("dev")`로 환경별 Bean을 분리합니다.
> ```java
> @Profile("prod")
> @Service
> public class ProdConfigService implements ConfigService { }
> ```

### 2. useValue — 고정 값 주입

```typescript
// 상수, 목 객체, 외부 라이브러리 인스턴스 주입
providers: [
  {
    provide: 'API_KEY',
    useValue: process.env.API_KEY || 'YOUR_API_KEY',
  },
]

// 사용 시
constructor(@Inject('API_KEY') private apiKey: string) {}
```

> **Spring에서는?**
> `@Value("${api.key}")` 어노테이션으로 프로퍼티를 주입합니다.

### 3. useFactory — 동적 생성

```typescript
// 다른 Provider에 의존하는 동적 생성
providers: [
  {
    provide: 'DATABASE_CONNECTION',
    useFactory: async (configService: ConfigService) => {
      const options = configService.get('database');
      return createConnection(options);
    },
    inject: [ConfigService],  // Factory에 주입할 의존성
  },
]
```

> **Spring에서는?**
> `@Bean` 메서드가 동일한 역할을 합니다.
> ```java
> @Bean
> public DataSource dataSource(ConfigService config) {
>     return new HikariDataSource(config.getDbOptions());
> }
> ```

### 4. useExisting — 별칭 (Alias)

```typescript
// 하나의 Provider를 여러 토큰으로 접근
providers: [
  UserService,
  {
    provide: 'AliasedUserService',
    useExisting: UserService,  // 같은 인스턴스를 공유
  },
]
```

> **Spring에서는?**
> `@Primary` + `@Qualifier`로 같은 타입의 Bean을 구분합니다.

---

## Provider Scope — 인스턴스 생명주기

```
NestJS Scope:                          Spring Scope:
┌─────────────────────────────┐       ┌─────────────────────────────┐
│ DEFAULT (Singleton)         │  ←→   │ singleton (기본)             │
│  앱 전체에서 1개 인스턴스     │       │  ApplicationContext당 1개    │
├─────────────────────────────┤       ├─────────────────────────────┤
│ REQUEST                     │  ←→   │ request                     │
│  HTTP 요청마다 새 인스턴스    │       │  HTTP 요청마다 새 인스턴스    │
├─────────────────────────────┤       ├─────────────────────────────┤
│ TRANSIENT                   │  ←→   │ prototype                   │
│  주입할 때마다 새 인스턴스    │       │  getBean 할 때마다 새 인스턴스│
└─────────────────────────────┘       └─────────────────────────────┘
```

```typescript
import { Injectable, Scope } from '@nestjs/common';

// REQUEST scope — 요청마다 새 인스턴스
@Injectable({ scope: Scope.REQUEST })
export class RequestScopedService {
  private requestId = Math.random();

  getRequestId() {
    return this.requestId;  // 요청마다 다른 값
  }
}
```

> ⚠️ REQUEST/TRANSIENT scope는 성능에 영향을 줍니다.
> 대부분의 경우 **DEFAULT (Singleton)**을 사용하세요.

---

## Injection Token — 문자열 vs 클래스 vs Symbol

```typescript
// 클래스 토큰 (가장 일반적)
constructor(private userService: UserService) {}

// 문자열 토큰 (@Inject 필요)
constructor(@Inject('API_KEY') private apiKey: string) {}

// Symbol 토큰 (충돌 방지)
export const DB_CONNECTION = Symbol('DB_CONNECTION');
// ...
constructor(@Inject(DB_CONNECTION) private db: Connection) {}
```

> **Spring에서는?**
> 같은 타입의 Bean이 여러 개일 때 `@Qualifier("beanName")`으로 구분합니다.

---

## 순환 의존성 해결 — forwardRef

```typescript
// A가 B를 필요로 하고, B도 A를 필요로 할 때
// a.service.ts
@Injectable()
export class AService {
  constructor(
    @Inject(forwardRef(() => BService))
    private bService: BService,
  ) {}
}

// b.service.ts
@Injectable()
export class BService {
  constructor(
    @Inject(forwardRef(() => AService))
    private aService: AService,
  ) {}
}
```

> **Spring에서는?**
> `@Lazy` 어노테이션으로 지연 주입하여 해결합니다.
> Spring Boot 2.6+에서는 순환 의존성이 기본적으로 금지됩니다.

> ⚠️ 순환 의존성은 **설계 문제의 신호**입니다.
> 가능하면 공통 모듈을 분리하여 해결하세요.

---

## 요약

- **Custom Provider**: useClass(교체), useValue(상수), useFactory(동적 생성), useExisting(별칭)
- **Scope**: DEFAULT(싱글톤), REQUEST(요청별), TRANSIENT(주입별) — Spring의 singleton/request/prototype과 대응
- **Injection Token**: 클래스, 문자열(`@Inject`), Symbol로 Provider를 식별
- **forwardRef**: 순환 의존성 해결 (Spring의 `@Lazy`와 유사)
- 대부분의 경우 **기본 Singleton + 클래스 토큰**이 최선

---

## 다음 편 예고

HTTP 요청이 Controller에 도달하기 전에 실행되는 **Middleware**를 배웁니다.

→ **[07편: Middleware](07-middleware.md)**

---

## 참고 자료

- [NestJS Custom Providers 공식 문서](https://docs.nestjs.com/fundamentals/custom-providers) — docs.nestjs.com
- [NestJS Injection Scopes 공식 문서](https://docs.nestjs.com/fundamentals/injection-scopes) — docs.nestjs.com
- [NestJS Circular Dependency 공식 문서](https://docs.nestjs.com/fundamentals/circular-dependency) — docs.nestjs.com
