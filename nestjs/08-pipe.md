# Pipe — 데이터 변환과 유효성 검증

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [07편: Middleware](07-middleware.md)
> **시리즈**: NestJS 학습 가이드 8/15

---

## 개요

Pipe는 Controller 핸들러의 **인자(argument)**를 변환하거나 검증합니다.
잘못된 데이터가 비즈니스 로직에 도달하기 전에 차단하는 역할입니다.
Spring의 `@Valid` + Bean Validation(JSR-380)에 대응합니다.

---

## Pipe의 두 가지 역할

```
Client 요청: POST /users  { "name": "홍길동", "age": "25" }
                                          │
                                          ▼
                               ┌──────────────────┐
                               │      Pipe         │
                               ├──────────────────┤
                               │ 1. 변환           │ age: "25" → 25 (string → number)
                               │ 2. 검증           │ name이 비어있으면? → 400 에러!
                               └────────┬─────────┘
                                        │ 유효한 데이터만 통과
                                        ▼
                               ┌──────────────────┐
                               │   Controller     │
                               └──────────────────┘
```

---

## 내장 Pipe

NestJS는 자주 쓰이는 Pipe를 기본 제공합니다.

```typescript
import {
  ParseIntPipe,
  ParseBoolPipe,
  ParseUUIDPipe,
  ParseFloatPipe,
  DefaultValuePipe,
  ParseDatePipe,
  ValidationPipe,
} from '@nestjs/common';

@Controller('users')
export class UserController {

  // ParseIntPipe — 문자열 → 숫자 변환
  @Get(':id')
  findOne(@Param('id', ParseIntPipe) id: number) {
    // id는 이미 number 타입 (변환 실패 시 400 에러)
    return this.userService.findOne(id);
  }

  // ParseBoolPipe — 문자열 → boolean
  @Get()
  findAll(@Query('active', ParseBoolPipe) active: boolean) {
    return this.userService.findAll(active);
  }

  // DefaultValuePipe — 기본값 설정
  @Get()
  findPaginated(
    @Query('page', new DefaultValuePipe(1), ParseIntPipe) page: number,
    @Query('limit', new DefaultValuePipe(10), ParseIntPipe) limit: number,
  ) {
    return this.userService.findPaginated(page, limit);
  }

  // ParseDatePipe — 문자열 → Date (v11 신규)
  @Get('by-date')
  findByDate(@Query('date', ParseDatePipe) date: Date) {
    return this.userService.findByDate(date);
  }
}
```

> **Spring에서는?**
> `@PathVariable int id`처럼 타입을 선언하면 Spring이 자동 변환합니다.
> 변환 실패 시 `MethodArgumentTypeMismatchException`이 발생합니다.

---

## ValidationPipe — DTO 유효성 검증

### 1. 패키지 설치

```bash
npm install class-validator class-transformer
```

### 2. DTO 클래스 작성

```typescript
// src/user/dto/create-user.dto.ts
import { IsEmail, IsString, MinLength, IsEnum, IsOptional } from 'class-validator';

export enum UserRole {
  ADMIN = 'admin',
  USER = 'user',
}

export class CreateUserDto {
  @IsEmail({}, { message: '올바른 이메일 형식이 아닙니다' })
  email: string;

  @IsString()
  @MinLength(2, { message: '이름은 2자 이상이어야 합니다' })
  name: string;

  @IsEnum(UserRole)
  @IsOptional()
  role?: UserRole;
}
```

> **Spring에서는?**
> ```java
> public class CreateUserDto {
>     @Email(message = "올바른 이메일 형식이 아닙니다")
>     private String email;
>
>     @NotBlank
>     @Size(min = 2, message = "이름은 2자 이상이어야 합니다")
>     private String name;
> }
> ```
> 거의 동일한 구조입니다! `class-validator`는 Java의 Bean Validation과 매우 유사합니다.

### 3. Controller에서 사용

```typescript
@Controller('users')
export class UserController {
  @Post()
  create(@Body(ValidationPipe) createUserDto: CreateUserDto) {
    // 검증 통과한 데이터만 도달
    return this.userService.create(createUserDto);
  }
}
```

> **Spring에서는?**
> ```java
> @PostMapping("/users")
> public User create(@Valid @RequestBody CreateUserDto dto) { ... }
> ```
> `@Valid`와 `ValidationPipe`가 동일한 역할입니다.

---

## Global ValidationPipe 설정 (권장)

매번 `@Body(ValidationPipe)`를 붙이는 대신 글로벌로 설정합니다.

```typescript
// src/main.ts
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.useGlobalPipes(new ValidationPipe({
    whitelist: true,         // DTO에 없는 속성 자동 제거
    forbidNonWhitelisted: true,  // 허용하지 않은 속성 있으면 에러
    transform: true,         // 자동 타입 변환 활성화
  }));

  await app.listen(3000);
}
```

> 💡 `whitelist: true`는 보안에 매우 중요합니다!
> 클라이언트가 `role: "admin"`을 몰래 보내도 DTO에 없으면 무시됩니다.

---

## Custom Pipe 작성

```typescript
// src/common/pipes/parse-order.pipe.ts
import { PipeTransform, Injectable, BadRequestException } from '@nestjs/common';

@Injectable()
export class ParseOrderPipe implements PipeTransform<string, 'asc' | 'desc'> {
  transform(value: string): 'asc' | 'desc' {
    const val = value?.toLowerCase();
    if (val !== 'asc' && val !== 'desc') {
      throw new BadRequestException(`"${value}"은 유효한 정렬 순서가 아닙니다`);
    }
    return val;
  }
}

// 사용
@Get()
findAll(@Query('order', ParseOrderPipe) order: 'asc' | 'desc') {
  return this.userService.findAll(order);
}
```

---

## 주요 비교

| 항목 | NestJS | Spring |
|------|--------|--------|
| 검증 데코레이터 | `@IsEmail()`, `@MinLength()` | `@Email`, `@Size(min=)` |
| 검증 트리거 | `ValidationPipe` | `@Valid` |
| 전역 설정 | `app.useGlobalPipes()` | `@Validated` (클래스) |
| 타입 변환 | `ParseIntPipe` 등 | Spring 자동 변환 |
| 커스텀 검증 | `PipeTransform` 구현 | `ConstraintValidator` 구현 |

---

## 요약

- **Pipe**: Controller 인자를 변환(transformation)하거나 검증(validation)
- 내장 Pipe: `ParseIntPipe`, `ParseBoolPipe`, `ParseDatePipe`(v11), `ValidationPipe`
- `class-validator` + `ValidationPipe` = Spring의 `@Valid` + Bean Validation
- **글로벌 ValidationPipe** 설정 권장 (`whitelist: true`는 보안 필수)
- Custom Pipe는 `PipeTransform` 인터페이스 구현

---

## 다음 편 예고

요청을 허용할지 거부할지 판단하는 **Guard**를 배웁니다. Spring Security의 인가 필터와 비교합니다.

→ **[09편: Guard](09-guard.md)**

---

## 참고 자료

- [NestJS Pipes 공식 문서](https://docs.nestjs.com/pipes) — docs.nestjs.com
- [class-validator GitHub](https://github.com/typestack/class-validator) — github.com
- [NestJS Validation 공식 문서](https://docs.nestjs.com/techniques/validation) — docs.nestjs.com
