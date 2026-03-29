# Controller — 요청을 처리하는 관문

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [03편 — Module](./03-module.md)
> **시리즈**: NestJS 학습 가이드 4/15

---

## 개요

Controller는 클라이언트의 HTTP 요청을 받아 적절한 서비스로 전달하는 역할을 합니다.
Spring의 `@RestController`와 거의 동일한 개념이며, 데코레이터 기반으로 라우트를 정의합니다.
이 편에서는 NestJS 컨트롤러의 모든 기능을 Spring과 1:1 비교하며 학습합니다.

---

## @Controller 데코레이터

```typescript
import { Controller, Get } from '@nestjs/common';

@Controller('users')  // 기본 라우트 경로: /users
export class UserController {
  @Get()  // GET /users
  findAll() {
    return '모든 사용자 목록';
  }
}
```

> **Spring에서는?**
> ```java
> @RestController
> @RequestMapping("/users")
> public class UserController {
>     @GetMapping
>     public String findAll() {
>         return "모든 사용자 목록";
>     }
> }
> ```
> `@Controller('users')` = `@RestController` + `@RequestMapping("/users")`
> NestJS의 `@Controller`는 기본적으로 JSON 응답을 반환합니다 (Spring의 `@RestController`와 동일).

---

## HTTP 메서드 데코레이터

```
┌─────────────────────────────────────────────────────────────────┐
│                    요청 흐름                                     │
│                                                                 │
│  Client ──HTTP Request──▶ Controller ──비즈니스 로직──▶ Service  │
│         ◀─HTTP Response──           ◀──결과 반환────            │
│                                                                 │
│  GET    /users        → findAll()     목록 조회                  │
│  GET    /users/:id    → findOne()     단건 조회                  │
│  POST   /users        → create()      생성                      │
│  PUT    /users/:id    → update()      전체 수정                  │
│  PATCH  /users/:id    → patch()       부분 수정                  │
│  DELETE /users/:id    → remove()      삭제                      │
└─────────────────────────────────────────────────────────────────┘
```

| NestJS 데코레이터 | Spring 어노테이션 | HTTP 메서드 |
|-------------------|-------------------|-------------|
| `@Get()` | `@GetMapping` | GET |
| `@Post()` | `@PostMapping` | POST |
| `@Put()` | `@PutMapping` | PUT |
| `@Patch()` | `@PatchMapping` | PATCH |
| `@Delete()` | `@DeleteMapping` | DELETE |

```typescript
@Controller('users')
export class UserController {
  @Get()           // GET /users
  findAll() { ... }

  @Get(':id')      // GET /users/:id
  findOne() { ... }

  @Post()          // POST /users
  create() { ... }

  @Put(':id')      // PUT /users/:id
  update() { ... }

  @Delete(':id')   // DELETE /users/:id
  remove() { ... }
}
```

---

## 라우트 파라미터

### @Param — 경로 파라미터

```typescript
// NestJS
@Get(':id')
findOne(@Param('id') id: string) {
  return `사용자 #${id}`;
}
```

> **Spring에서는?**
> ```java
> @GetMapping("/{id}")
> public String findOne(@PathVariable String id) {
>     return "사용자 #" + id;
> }
> ```
> `@Param('id')` = `@PathVariable("id")`

### @Query — 쿼리 파라미터

```typescript
// GET /users?page=1&limit=10
@Get()
findAll(
  @Query('page') page: string,
  @Query('limit') limit: string,
) {
  return `페이지: ${page}, 개수: ${limit}`;
}
```

> **Spring에서는?**
> ```java
> @GetMapping
> public String findAll(
>     @RequestParam("page") String page,
>     @RequestParam("limit") String limit
> ) { ... }
> ```
> `@Query()` = `@RequestParam`

### @Body — 요청 본문

```typescript
// POST /users
@Post()
create(@Body() body: CreateUserDto) {
  return body;
}
```

> **Spring에서는?**
> ```java
> @PostMapping
> public CreateUserDto create(@RequestBody CreateUserDto body) { ... }
> ```
> `@Body()` = `@RequestBody`

### @Headers — 요청 헤더

```typescript
@Get()
findAll(@Headers('authorization') auth: string) {
  return `인증: ${auth}`;
}
```

> **Spring에서는?**
> ```java
> @GetMapping
> public String findAll(@RequestHeader("authorization") String auth) { ... }
> ```
> `@Headers()` = `@RequestHeader`

### 파라미터 데코레이터 종합 비교

| NestJS | Spring | 용도 |
|--------|--------|------|
| `@Param()` | `@PathVariable` | URL 경로 파라미터 |
| `@Query()` | `@RequestParam` | 쿼리 스트링 |
| `@Body()` | `@RequestBody` | 요청 본문 (JSON) |
| `@Headers()` | `@RequestHeader` | HTTP 헤더 |
| `@Ip()` | `HttpServletRequest.getRemoteAddr()` | 클라이언트 IP |
| `@Req()` | `HttpServletRequest` | 원본 요청 객체 |
| `@Res()` | `HttpServletResponse` | 원본 응답 객체 |

---

## DTO (Data Transfer Object) 패턴

요청/응답 데이터의 형태를 정의하는 클래스입니다. Spring과 동일한 개념입니다.

```typescript
// user/dto/create-user.dto.ts
export class CreateUserDto {
  name: string;
  email: string;
  password: string;  // 예제용 — 실제로는 YOUR_PASSWORD
}
```

```typescript
// user/dto/update-user.dto.ts
export class UpdateUserDto {
  name?: string;
  email?: string;
}
```

> **Spring에서는?**
> ```java
> // Spring에서는 record 또는 클래스로 DTO를 정의
> public record CreateUserDto(
>     String name,
>     String email,
>     String password
> ) {}
> ```
> NestJS의 DTO는 일반 클래스이며, `class-validator`를 추가하면 Spring의 `@Valid` + Bean Validation과 동일한 검증이 가능합니다 (Pipe 편에서 다룹니다).

---

## 응답 처리

### 자동 직렬화 (기본 방식)

NestJS는 반환값을 **자동으로 JSON 직렬화**합니다.

```typescript
@Get(':id')
findOne(@Param('id') id: string) {
  // 객체를 반환하면 자동으로 JSON 응답
  return { id: Number(id), name: '홍길동', email: 'hong@example.com' };
}
// 응답: { "id": 1, "name": "홍길동", "email": "hong@example.com" }
```

> **Spring에서는?**
> `@RestController`를 사용하면 동일하게 Jackson이 자동 직렬화합니다.
> NestJS도 객체/배열을 반환하면 JSON, 문자열을 반환하면 텍스트로 응답합니다.

### HTTP 상태 코드

```typescript
import { HttpCode, HttpStatus } from '@nestjs/common';

@Post()
@HttpCode(HttpStatus.CREATED)  // 201
create(@Body() dto: CreateUserDto) {
  return { id: 1, ...dto };
}

@Delete(':id')
@HttpCode(HttpStatus.NO_CONTENT)  // 204
remove(@Param('id') id: string) {
  // 삭제 로직
}
```

> **Spring에서는?**
> ```java
> @PostMapping
> @ResponseStatus(HttpStatus.CREATED)
> public User create(@RequestBody CreateUserDto dto) { ... }
>
> // 또는 ResponseEntity 사용
> @PostMapping
> public ResponseEntity<User> create(@RequestBody CreateUserDto dto) {
>     return ResponseEntity.status(HttpStatus.CREATED).body(user);
> }
> ```
> `@HttpCode()` = `@ResponseStatus`

### @Res 직접 응답 (비권장)

```typescript
import { Res } from '@nestjs/common';
import { Response } from 'express';

@Get(':id')
findOne(@Param('id') id: string, @Res() res: Response) {
  // Express의 Response 객체를 직접 사용
  res.status(200).json({ id, name: '홍길동' });
}
```

> **주의**: `@Res()`를 사용하면 NestJS의 자동 직렬화, Interceptor 등이 비활성화됩니다.
> 특별한 이유가 없다면 **자동 직렬화**(객체 반환)를 사용하세요.

---

## 실습: UserController CRUD 엔드포인트

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

  // GET /users?page=1&limit=10
  @Get()
  findAll(@Query('page') page = '1', @Query('limit') limit = '10') {
    return this.userService.findAll(Number(page), Number(limit));
  }

  // GET /users/:id
  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.userService.findOne(Number(id));
  }

  // POST /users
  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@Body() createUserDto: CreateUserDto) {
    return this.userService.create(createUserDto);
  }

  // PUT /users/:id
  @Put(':id')
  update(@Param('id') id: string, @Body() updateUserDto: UpdateUserDto) {
    return this.userService.update(Number(id), updateUserDto);
  }

  // DELETE /users/:id
  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('id') id: string) {
    this.userService.remove(Number(id));
  }
}
```

```bash
# 테스트
# 전체 조회
curl http://localhost:3000/users

# 단건 조회
curl http://localhost:3000/users/1

# 생성
curl -X POST http://localhost:3000/users \
  -H "Content-Type: application/json" \
  -d '{"name": "이영희", "email": "lee@example.com"}'

# 수정
curl -X PUT http://localhost:3000/users/1 \
  -H "Content-Type: application/json" \
  -d '{"name": "홍길동(수정)"}'

# 삭제
curl -X DELETE http://localhost:3000/users/1
```

---

## 요약

- NestJS의 `@Controller`는 Spring의 `@RestController` + `@RequestMapping`에 대응합니다.
- HTTP 메서드 데코레이터(`@Get`, `@Post` 등)는 Spring의 `@GetMapping`, `@PostMapping`과 동일합니다.
- 파라미터 데코레이터(`@Param`, `@Query`, `@Body`)로 요청 데이터를 추출합니다.
- 객체를 반환하면 자동 JSON 직렬화되며, `@HttpCode()`로 상태 코드를 제어합니다.

## 다음 편 예고

[05편 — Provider와 Service](./05-provider-service.md)에서는 비즈니스 로직을 담당하는 Service 계층을 다룹니다. `@Injectable` 데코레이터와 DI(의존성 주입)를 Spring의 `@Service`/`@Autowired`와 비교합니다.

## 참고 자료

- [NestJS 공식 문서 — Controllers](https://docs.nestjs.com/controllers) — 컨트롤러 가이드
- [NestJS 공식 문서 — Route Parameters](https://docs.nestjs.com/controllers#route-parameters) — 라우트 파라미터
- [Spring @RestController 문서](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-controller.html) — 비교 참조용
