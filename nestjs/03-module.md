# Module — 애플리케이션 구조의 기본 단위

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [02편 — 개발 환경 설정](./02-project-setup.md)
> **시리즈**: NestJS 학습 가이드 3/15

---

## 개요

NestJS에서 **Module**은 관련된 컨트롤러, 서비스, 기타 프로바이더를 하나로 묶는 조직 단위입니다.
Spring의 `@Configuration` + `@ComponentScan`과 유사하며, 애플리케이션을 기능별로 분리하는 핵심 메커니즘입니다.
이 편에서는 @Module 데코레이터, Feature Module, Dynamic Module을 배우고 직접 만들어봅니다.

---

## @Module 데코레이터

모든 NestJS 애플리케이션은 최소 하나의 모듈(루트 모듈)을 가집니다.

```typescript
@Module({
  imports: [],       // 이 모듈이 사용할 다른 모듈
  controllers: [],   // 이 모듈의 컨트롤러
  providers: [],     // 이 모듈의 서비스/프로바이더
  exports: [],       // 다른 모듈에 공개할 프로바이더
})
export class AppModule {}
```

각 속성의 역할:

| 속성 | 역할 | Spring 대응 |
|------|------|-------------|
| `imports` | 다른 모듈 가져오기 | `@Import` / 의존성 모듈 |
| `controllers` | HTTP 요청 처리 클래스 등록 | `@ComponentScan`이 `@Controller`를 스캔 |
| `providers` | 서비스, 리포지토리 등 등록 | `@ComponentScan`이 `@Service`를 스캔 |
| `exports` | 다른 모듈에 공유할 프로바이더 | `@Bean`의 public 접근 |

> **Spring에서는?**
> Spring Boot는 `@ComponentScan`으로 패키지 내 빈을 **자동 스캔**합니다.
> NestJS는 **명시적 등록**이 필요합니다 — `providers`에 넣지 않으면 DI에 등록되지 않습니다.
> 이 차이가 NestJS의 장점이자 단점입니다: 명시적이라 추적이 쉽지만, 등록을 빠뜨리면 에러가 납니다.

---

## Feature Module 생성

실제 애플리케이션은 기능별로 모듈을 나눕니다.

```bash
# CLI로 UserModule 생성
nest generate module user
nest generate controller user
nest generate service user
```

생성된 `UserModule`:

```typescript
// user/user.module.ts
import { Module } from '@nestjs/common';
import { UserController } from './user.controller';
import { UserService } from './user.service';

@Module({
  controllers: [UserController],
  providers: [UserService],
  exports: [UserService],  // 다른 모듈에서 UserService를 사용할 수 있게 공개
})
export class UserModule {}
```

루트 모듈에 등록:

```typescript
// app.module.ts
import { Module } from '@nestjs/common';
import { UserModule } from './user/user.module';
import { PostModule } from './post/post.module';

@Module({
  imports: [UserModule, PostModule],  // Feature Module 등록
})
export class AppModule {}
```

> **Spring에서는?**
> Spring Boot는 `@SpringBootApplication`이 있는 패키지 하위를 모두 자동 스캔합니다.
> NestJS는 `imports`에 명시적으로 등록해야 합니다.
> ```java
> // Spring — 자동 스캔 (별도 등록 불필요)
> @SpringBootApplication  // com.example 패키지 하위 전체 스캔
> public class MyApp { ... }
> ```

---

## 모듈 의존성 트리

```
┌──────────────────────────────────────────────────────┐
│                     AppModule                        │
│                    (루트 모듈)                        │
│                                                      │
│         ┌──────────────┬──────────────┐              │
│         ▼              ▼              ▼              │
│   ┌──────────┐  ┌──────────┐  ┌──────────────┐      │
│   │UserModule│  │PostModule│  │ CommonModule │      │
│   │          │  │          │  │  (@Global)   │      │
│   │Controller│  │Controller│  │              │      │
│   │ Service  │  │ Service ─┼──▶ UserService  │      │
│   │          │  │          │  │  (import)     │      │
│   └──────────┘  └──────────┘  └──────────────┘      │
│                       │                              │
│                       │ imports                      │
│                       ▼                              │
│                ┌──────────┐                          │
│                │UserModule│                          │
│                │(exports: │                          │
│                │UserService)                         │
│                └──────────┘                          │
└──────────────────────────────────────────────────────┘

PostModule이 UserService를 사용하려면:
  1. UserModule이 exports에 UserService를 공개
  2. PostModule이 imports에 UserModule을 등록
```

### 모듈 간 의존성 예제

```typescript
// post/post.module.ts
import { Module } from '@nestjs/common';
import { UserModule } from '../user/user.module';
import { PostController } from './post.controller';
import { PostService } from './post.service';

@Module({
  imports: [UserModule],  // UserModule을 가져와서 UserService 사용 가능
  controllers: [PostController],
  providers: [PostService],
})
export class PostModule {}
```

```typescript
// post/post.service.ts
import { Injectable } from '@nestjs/common';
import { UserService } from '../user/user.service';

@Injectable()
export class PostService {
  // UserModule이 exports한 UserService를 주입받음
  constructor(private readonly userService: UserService) {}

  async createPost(userId: string, title: string) {
    const user = await this.userService.findOne(userId);
    // 게시글 생성 로직...
  }
}
```

> **Spring에서는?**
> Spring은 모든 빈이 하나의 ApplicationContext에 있으므로, 모듈 간 `exports`/`imports`가 불필요합니다.
> `@Autowired`만 하면 어디서든 주입됩니다.
> NestJS의 모듈 시스템은 **캡슐화**를 강제하여, 모듈 간 의존성을 명확하게 만듭니다.

---

## @Global 모듈

모든 모듈에서 공통으로 사용하는 서비스는 `@Global()`로 선언하면 `imports` 없이 사용할 수 있습니다.

```typescript
import { Global, Module } from '@nestjs/common';
import { LoggerService } from './logger.service';

@Global()
@Module({
  providers: [LoggerService],
  exports: [LoggerService],  // exports는 여전히 필요
})
export class CommonModule {}
```

> **Spring에서는?**
> Spring에서는 모든 빈이 기본적으로 글로벌입니다.
> NestJS의 `@Global()`은 Spring의 기본 동작을 명시적으로 활성화하는 것과 같습니다.
> 남용하면 모듈 간 결합도가 높아지므로, 로거/설정 같은 인프라 모듈에만 사용합니다.

---

## Dynamic Module

런타임에 설정값을 받아 모듈을 구성하는 패턴입니다. Spring의 `@Bean` 팩토리 메서드와 유사합니다.

```typescript
// database/database.module.ts
import { Module, DynamicModule } from '@nestjs/common';

@Module({})
export class DatabaseModule {
  static forRoot(options: { host: string; port: number }): DynamicModule {
    return {
      module: DatabaseModule,
      providers: [
        {
          provide: 'DATABASE_OPTIONS',
          useValue: options,
        },
        DatabaseService,
      ],
      exports: [DatabaseService],
      global: true,  // 전역 모듈로 등록
    };
  }
}
```

사용:

```typescript
// app.module.ts
@Module({
  imports: [
    DatabaseModule.forRoot({
      host: 'YOUR_HOST',
      port: 5432,
    }),
    UserModule,
    PostModule,
  ],
})
export class AppModule {}
```

> **Spring에서는?**
> ```java
> @Configuration
> public class DatabaseConfig {
>     @Bean
>     public DataSource dataSource(
>         @Value("${db.host}") String host,
>         @Value("${db.port}") int port
>     ) {
>         // DataSource 생성 및 반환
>     }
> }
> ```
> Spring은 `@Value`나 `@ConfigurationProperties`로 외부 설정을 주입합니다.
> NestJS의 `forRoot()`/`forRootAsync()` 패턴은 모듈 레벨에서 설정을 전달하는 관용적 방식입니다.

### forRootAsync 패턴

비동기 설정(환경 변수, 외부 설정 서비스)이 필요한 경우:

```typescript
// app.module.ts
@Module({
  imports: [
    ConfigModule.forRoot(),  // 환경 변수 로드
    DatabaseModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        host: config.get('DB_HOST'),
        port: config.getOrThrow<number>('DB_PORT'),
      }),
    }),
  ],
})
export class AppModule {}
```

---

## 실습: UserModule + PostModule 생성

```bash
# 1. 프로젝트 생성
nest new module-practice
cd module-practice

# 2. User 리소스 생성
nest generate module user
nest generate controller user
nest generate service user

# 3. Post 리소스 생성
nest generate module post
nest generate controller post
nest generate service post
```

`user/user.service.ts`:

```typescript
import { Injectable } from '@nestjs/common';

interface User {
  id: number;
  name: string;
  email: string;
}

@Injectable()
export class UserService {
  private users: User[] = [
    { id: 1, name: '홍길동', email: 'hong@example.com' },
    { id: 2, name: '김철수', email: 'kim@example.com' },
  ];

  findAll(): User[] {
    return this.users;
  }

  findOne(id: number): User | undefined {
    return this.users.find((user) => user.id === id);
  }
}
```

`user/user.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { UserController } from './user.controller';
import { UserService } from './user.service';

@Module({
  controllers: [UserController],
  providers: [UserService],
  exports: [UserService],  // PostModule에서 사용할 수 있도록 공개
})
export class UserModule {}
```

`post/post.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { UserModule } from '../user/user.module';
import { PostController } from './post.controller';
import { PostService } from './post.service';

@Module({
  imports: [UserModule],  // UserService를 사용하기 위해 UserModule 가져오기
  controllers: [PostController],
  providers: [PostService],
})
export class PostModule {}
```

`post/post.service.ts`:

```typescript
import { Injectable } from '@nestjs/common';
import { UserService } from '../user/user.service';

@Injectable()
export class PostService {
  constructor(private readonly userService: UserService) {}

  getPostsWithAuthor() {
    const user = this.userService.findOne(1);
    return {
      title: 'NestJS 학습기',
      author: user?.name ?? 'Unknown',
      content: 'Module 시스템을 배워봅시다!',
    };
  }
}
```

`app.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { UserModule } from './user/user.module';
import { PostModule } from './post/post.module';

@Module({
  imports: [UserModule, PostModule],
})
export class AppModule {}
```

```bash
# 실행
npm run start:dev

# 테스트
curl http://localhost:3000/post
```

---

## 요약

- NestJS의 Module은 관련 컨트롤러, 서비스를 묶는 조직 단위로, Spring의 `@Configuration`에 대응합니다.
- `providers`에 등록하지 않으면 DI가 되지 않습니다 (Spring의 자동 스캔과 다른 점).
- 모듈 간 서비스 공유는 `exports` + `imports`로 명시적으로 처리합니다.
- `@Global()` 모듈은 인프라성 서비스에만 제한적으로 사용합니다.
- `forRoot()` / `forRootAsync()` 패턴은 설정 기반 모듈 구성에 사용됩니다.

## 다음 편 예고

[04편 — Controller](./04-controller.md)에서는 HTTP 요청을 처리하는 컨트롤러를 자세히 다룹니다. @Get, @Post 데코레이터부터 DTO 패턴까지 Spring @RestController와 1:1 비교합니다.

## 참고 자료

- [NestJS 공식 문서 — Modules](https://docs.nestjs.com/modules) — 모듈 시스템 가이드
- [NestJS 공식 문서 — Dynamic Modules](https://docs.nestjs.com/fundamentals/dynamic-modules) — forRoot/forRootAsync 패턴
- [Spring @Configuration 문서](https://docs.spring.io/spring-framework/reference/core/beans/java/configuration.html) — 비교 참조용
