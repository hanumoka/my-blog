# Provider와 Service — 비즈니스 로직의 핵심

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [04편 — Controller](./04-controller.md)
> **시리즈**: NestJS 학습 가이드 5/15

---

## 개요

Controller가 요청을 받는 관문이라면, **Service**는 실제 비즈니스 로직을 처리하는 핵심 계층입니다.
NestJS에서는 Service를 포함한 모든 주입 가능한 클래스를 **Provider**라고 부릅니다.
이 편에서는 Provider의 개념, `@Injectable` 데코레이터, 생성자 주입을 Spring과 비교하며 학습합니다.

---

## Provider 개념

Provider는 NestJS DI 컨테이너가 관리하는 클래스의 총칭입니다. Spring의 **Bean**과 동일한 개념입니다.

```
┌──────────────────────────────────────────────────┐
│                 Provider의 종류                   │
│                                                  │
│  ┌───────────┐  ┌─────────────┐  ┌───────────┐  │
│  │  Service  │  │ Repository  │  │  Factory   │  │
│  │비즈니스로직│  │ 데이터 접근  │  │ 객체 생성  │  │
│  └───────────┘  └─────────────┘  └───────────┘  │
│                                                  │
│  ┌───────────┐  ┌─────────────┐  ┌───────────┐  │
│  │  Helper   │  │   Guard     │  │   Pipe     │  │
│  │ 유틸리티   │  │ 인증/인가   │  │ 변환/검증  │  │
│  └───────────┘  └─────────────┘  └───────────┘  │
│                                                  │
│  공통점: 모두 @Injectable() 데코레이터를 사용      │
│         모두 Module의 providers 배열에 등록        │
└──────────────────────────────────────────────────┘
```

> **Spring에서는?**
> Spring에서는 `@Component`, `@Service`, `@Repository`, `@Controller` 등 역할별 어노테이션이 있습니다.
> NestJS에서는 **모두 `@Injectable()`** 하나로 통일합니다.
> 클래스 이름에 `Service`, `Repository` 등을 붙여 역할을 구분하는 것은 컨벤션입니다.

| NestJS | Spring | 역할 |
|--------|--------|------|
| `@Injectable()` + `XxxService` | `@Service` | 비즈니스 로직 |
| `@Injectable()` + `XxxRepository` | `@Repository` | 데이터 접근 |
| `@Injectable()` + `XxxFactory` | `@Component` + 팩토리 패턴 | 객체 생성 |
| `@Injectable()` + `XxxHelper` | `@Component` | 유틸리티 |

---

## @Injectable 데코레이터

`@Injectable()`은 이 클래스가 NestJS DI 컨테이너에 의해 **생성되고 주입될 수 있음**을 선언합니다.

```typescript
import { Injectable } from '@nestjs/common';

@Injectable()
export class UserService {
  private users = [
    { id: 1, name: '홍길동', email: 'hong@example.com' },
    { id: 2, name: '김철수', email: 'kim@example.com' },
  ];

  findAll() {
    return this.users;
  }

  findOne(id: number) {
    return this.users.find((user) => user.id === id);
  }
}
```

> **Spring에서는?**
> ```java
> @Service  // = @Component의 특수화
> public class UserService {
>     public List<User> findAll() { ... }
>     public User findOne(Long id) { ... }
> }
> ```
> `@Injectable()` = `@Component` (또는 `@Service`, `@Repository`)
> Spring은 역할별 어노테이션을 제공하지만, NestJS는 `@Injectable()` 하나입니다.

---

## 생성자 주입 (Constructor Injection)

NestJS는 **생성자 주입**이 기본이며, Spring에서도 생성자 주입이 권장 패턴입니다.

```typescript
// NestJS — 생성자 주입
@Controller('users')
export class UserController {
  constructor(private readonly userService: UserService) {}
  //          ^^^^^^^ ^^^^^^^^
  //          private + readonly = Spring의 final 필드와 동일

  @Get()
  findAll() {
    return this.userService.findAll();
  }
}
```

> **Spring에서는?**
> ```java
> @RestController
> @RequestMapping("/users")
> public class UserController {
>     private final UserService userService;
>
>     // Spring 4.3+ 단일 생성자면 @Autowired 생략 가능
>     public UserController(UserService userService) {
>         this.userService = userService;
>     }
>
>     @GetMapping
>     public List<User> findAll() {
>         return userService.findAll();
>     }
> }
> ```
> NestJS의 `private readonly`는 TypeScript의 **파라미터 프로퍼티** 문법입니다.
> 생성자 파라미터에 접근 제한자를 붙이면 자동으로 클래스 필드로 선언됩니다.
> Spring에서 Lombok `@RequiredArgsConstructor`를 쓰는 것과 비슷한 편의 기능입니다.

### TypeScript 파라미터 프로퍼티

```typescript
// 이 코드는...
class UserController {
  constructor(private readonly userService: UserService) {}
}

// 이것과 동일합니다
class UserController {
  private readonly userService: UserService;
  constructor(userService: UserService) {
    this.userService = userService;
  }
}
```

---

## Provider 등록

Provider는 Module의 `providers` 배열에 등록해야 DI 컨테이너가 관리합니다.

```typescript
@Module({
  controllers: [UserController],
  providers: [UserService],     // ← 여기에 등록
  exports: [UserService],       // ← 다른 모듈에 공유 시
})
export class UserModule {}
```

등록하지 않으면 다음 에러가 발생합니다:

```
Error: Nest can't resolve dependencies of the UserController (?).
Please make sure that the argument UserService at index [0]
is available in the UserModule context.
```

> **Spring에서는?**
> Spring은 `@ComponentScan`으로 패키지 내 `@Service`, `@Component` 등을 **자동 스캔**합니다.
> NestJS는 반드시 `providers`에 **명시적으로 등록**해야 합니다.
> 장점: 어디서 뭐가 등록되는지 명확. 단점: 등록을 빠뜨리면 런타임 에러.

---

## Provider 종류별 Spring 비교

### Service — 비즈니스 로직

```typescript
// NestJS
@Injectable()
export class OrderService {
  constructor(
    private readonly userService: UserService,
    private readonly paymentService: PaymentService,
  ) {}

  async createOrder(userId: number, items: OrderItem[]) {
    const user = await this.userService.findOne(userId);
    const payment = await this.paymentService.charge(user, items);
    // 주문 생성 로직...
  }
}
```

> **Spring에서는?**
> ```java
> @Service
> public class OrderService {
>     private final UserService userService;
>     private final PaymentService paymentService;
>
>     public OrderService(UserService userService, PaymentService paymentService) {
>         this.userService = userService;
>         this.paymentService = paymentService;
>     }
>
>     public Order createOrder(Long userId, List<OrderItem> items) { ... }
> }
> ```
> 구조가 거의 동일합니다. `@Injectable()` = `@Service`, 생성자 주입 동일.

### Repository — 데이터 접근

```typescript
// NestJS
@Injectable()
export class UserRepository {
  private users: Map<number, User> = new Map();

  save(user: User): User {
    this.users.set(user.id, user);
    return user;
  }

  findById(id: number): User | undefined {
    return this.users.get(id);
  }

  findAll(): User[] {
    return Array.from(this.users.values());
  }
}
```

> **Spring에서는?**
> ```java
> @Repository
> public class UserRepository {
>     // 또는 JpaRepository<User, Long>을 extends
> }
> ```
> Spring의 `@Repository`는 데이터 접근 계층 예외를 `DataAccessException`으로 변환하는 추가 기능이 있습니다.
> NestJS의 `@Injectable()`에는 그런 구분이 없으며, 클래스명으로만 역할을 표현합니다.

### Factory — 객체 생성

```typescript
// NestJS — 커스텀 Provider (팩토리)
@Module({
  providers: [
    {
      provide: 'LOGGER',
      useFactory: () => {
        const isProd = process.env.NODE_ENV === 'production';
        return isProd ? new JsonLogger() : new ConsoleLogger();
      },
    },
  ],
})
export class AppModule {}
```

> **Spring에서는?**
> ```java
> @Configuration
> public class LoggerConfig {
>     @Bean
>     public Logger logger(@Value("${spring.profiles.active}") String profile) {
>         return "prod".equals(profile)
>             ? new JsonLogger()
>             : new ConsoleLogger();
>     }
> }
> ```
> NestJS의 `useFactory`는 Spring의 `@Bean` 팩토리 메서드와 동일합니다.

---

## 계층 구조

```
┌─────────────────────────────────────────────────────────────┐
│                      NestJS 계층 구조                        │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Controller 계층 (HTTP 요청/응답)                    │    │
│  │  @Controller()                                      │    │
│  │  Spring: @RestController                            │    │
│  └────────────────────────┬────────────────────────────┘    │
│                           │ 의존성 주입                      │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Service 계층 (비즈니스 로직)                        │    │
│  │  @Injectable()                                      │    │
│  │  Spring: @Service                                   │    │
│  └────────────────────────┬────────────────────────────┘    │
│                           │ 의존성 주입                      │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Repository 계층 (데이터 접근)                       │    │
│  │  @Injectable()                                      │    │
│  │  Spring: @Repository                                │    │
│  └────────────────────────┬────────────────────────────┘    │
│                           │                                 │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Database / External Service                        │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## 실습: UserService 구현 + Controller 연결

### 1. DTO 정의

```typescript
// user/dto/create-user.dto.ts
export class CreateUserDto {
  name: string;
  email: string;
}

// user/dto/update-user.dto.ts
export class UpdateUserDto {
  name?: string;
  email?: string;
}
```

### 2. UserService 구현

```typescript
// user/user.service.ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';

interface User {
  id: number;
  name: string;
  email: string;
  createdAt: Date;
}

@Injectable()
export class UserService {
  private users: User[] = [];
  private idCounter = 1;

  findAll(page: number, limit: number): { data: User[]; total: number } {
    const start = (page - 1) * limit;
    const data = this.users.slice(start, start + limit);
    return { data, total: this.users.length };
  }

  findOne(id: number): User {
    const user = this.users.find((u) => u.id === id);
    if (!user) {
      throw new NotFoundException(`사용자 #${id}를 찾을 수 없습니다`);
    }
    return user;
  }

  create(dto: CreateUserDto): User {
    const user: User = {
      id: this.idCounter++,
      name: dto.name,
      email: dto.email,
      createdAt: new Date(),
    };
    this.users.push(user);
    return user;
  }

  update(id: number, dto: UpdateUserDto): User {
    const user = this.findOne(id);
    if (dto.name !== undefined) user.name = dto.name;
    if (dto.email !== undefined) user.email = dto.email;
    return user;
  }

  remove(id: number): void {
    const index = this.users.findIndex((u) => u.id === id);
    if (index === -1) {
      throw new NotFoundException(`사용자 #${id}를 찾을 수 없습니다`);
    }
    this.users.splice(index, 1);
  }
}
```

> **Spring에서는?**
> ```java
> @Service
> public class UserService {
>     private final List<User> users = new ArrayList<>();
>     private long idCounter = 1;
>
>     public User findOne(Long id) {
>         return users.stream()
>             .filter(u -> u.getId().equals(id))
>             .findFirst()
>             .orElseThrow(() -> new ResponseStatusException(
>                 HttpStatus.NOT_FOUND, "사용자 #" + id + "를 찾을 수 없습니다"
>             ));
>     }
>     // ...
> }
> ```
> NestJS의 `NotFoundException`은 Spring의 `ResponseStatusException(NOT_FOUND)`에 대응합니다.

### 3. UserController 연결

```typescript
// user/user.controller.ts
import {
  Controller,
  Get,
  Post,
  Put,
  Delete,
  Body,
  Param,
  Query,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { UserService } from './user.service';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';

@Controller('users')
export class UserController {
  constructor(private readonly userService: UserService) {}

  @Get()
  findAll(
    @Query('page') page = '1',
    @Query('limit') limit = '10',
  ) {
    return this.userService.findAll(Number(page), Number(limit));
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.userService.findOne(Number(id));
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@Body() createUserDto: CreateUserDto) {
    return this.userService.create(createUserDto);
  }

  @Put(':id')
  update(
    @Param('id') id: string,
    @Body() updateUserDto: UpdateUserDto,
  ) {
    return this.userService.update(Number(id), updateUserDto);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('id') id: string) {
    this.userService.remove(Number(id));
  }
}
```

### 4. UserModule 등록

```typescript
// user/user.module.ts
import { Module } from '@nestjs/common';
import { UserController } from './user.controller';
import { UserService } from './user.service';

@Module({
  controllers: [UserController],
  providers: [UserService],
  exports: [UserService],
})
export class UserModule {}
```

### 5. 실행 및 테스트

```bash
npm run start:dev

# 사용자 생성
curl -X POST http://localhost:3000/users \
  -H "Content-Type: application/json" \
  -d '{"name": "홍길동", "email": "hong@example.com"}'
# → {"id":1,"name":"홍길동","email":"hong@example.com","createdAt":"2026-03-29T..."}

# 전체 조회
curl http://localhost:3000/users
# → {"data":[{"id":1,...}],"total":1}

# 단건 조회
curl http://localhost:3000/users/1
# → {"id":1,"name":"홍길동",...}

# 존재하지 않는 사용자 조회
curl http://localhost:3000/users/999
# → {"statusCode":404,"message":"사용자 #999를 찾을 수 없습니다"}
```

---

## 요약

- Provider는 NestJS DI 컨테이너가 관리하는 클래스의 총칭이며, Spring의 Bean에 해당합니다.
- `@Injectable()`은 Spring의 `@Component`/`@Service`/`@Repository`를 하나로 통합한 데코레이터입니다.
- 생성자 주입은 NestJS와 Spring 모두 권장하는 DI 패턴입니다.
- Provider는 Module의 `providers` 배열에 명시적으로 등록해야 합니다 (Spring의 자동 스캔과 다름).
- Controller → Service → Repository 계층 구조는 Spring과 동일합니다.

## 다음 편 예고

[06편 — Dependency Injection 심화](./06-dependency-injection.md)에서는 커스텀 Provider, Provider 스코프(Singleton/Request/Transient), 인터페이스 기반 주입 등 DI의 고급 기능을 다룹니다.

## 참고 자료

- [NestJS 공식 문서 — Providers](https://docs.nestjs.com/providers) — Provider 가이드
- [NestJS 공식 문서 — Custom Providers](https://docs.nestjs.com/fundamentals/custom-providers) — 커스텀 Provider
- [Spring @Service 문서](https://docs.spring.io/spring-framework/reference/core/beans/classpath-scanning.html) — 비교 참조용
- [TypeScript Handbook — Parameter Properties](https://www.typescriptlang.org/docs/handbook/2/classes.html#parameter-properties) — 파라미터 프로퍼티 문법
