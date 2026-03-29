# Exception Filter — 에러 처리 전략

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [10편: Interceptor](10-interceptor.md)
> **시리즈**: NestJS 학습 가이드 11/15

---

## 개요

NestJS는 처리되지 않은 예외를 자동으로 잡아 HTTP 응답으로 변환합니다.
**Exception Filter**를 사용하면 이 에러 응답 형식을 커스터마이징할 수 있습니다.
Spring의 `@ExceptionHandler`와 `@ControllerAdvice`에 대응합니다.

---

## 기본 예외 처리 흐름

```
Controller에서 예외 발생!
    │
    ▼
┌─────────────────────────────────┐
│  Exception Filter               │
│  ┌─────────────────────────┐   │
│  │ Custom Filter 있는가?    │   │
│  │ ├─ Yes → Custom Filter  │   │
│  │ └─ No  → 기본 Filter    │   │
│  └─────────────────────────┘   │
└────────────┬────────────────────┘
             ▼
┌─────────────────────────────────┐
│  HTTP 응답 (JSON)               │
│  {                              │
│    "statusCode": 404,           │
│    "message": "User not found", │
│    "timestamp": "..."           │
│  }                              │
└─────────────────────────────────┘
```

---

## NestJS 내장 예외 클래스

```typescript
import {
  HttpException,
  BadRequestException,       // 400
  UnauthorizedException,     // 401
  ForbiddenException,        // 403
  NotFoundException,         // 404
  ConflictException,         // 409
  InternalServerErrorException, // 500
} from '@nestjs/common';

@Controller('users')
export class UserController {
  @Get(':id')
  async findOne(@Param('id', ParseIntPipe) id: number) {
    const user = await this.userService.findOne(id);
    if (!user) {
      throw new NotFoundException(`ID ${id} 사용자를 찾을 수 없습니다`);
    }
    return user;
  }

  @Post()
  async create(@Body() dto: CreateUserDto) {
    const exists = await this.userService.findByEmail(dto.email);
    if (exists) {
      throw new ConflictException('이미 존재하는 이메일입니다');
    }
    return this.userService.create(dto);
  }
}
```

**기본 응답 형식**:

```json
{
  "statusCode": 404,
  "message": "ID 99 사용자를 찾을 수 없습니다",
  "error": "Not Found"
}
```

> **Spring에서는?**
> ```java
> throw new ResponseStatusException(HttpStatus.NOT_FOUND, "사용자를 찾을 수 없습니다");
> ```
> 또는 커스텀 예외 + `@ResponseStatus(HttpStatus.NOT_FOUND)` 사용

---

## Custom Exception Filter

에러 응답 형식을 커스터마이징합니다.

```typescript
// src/common/filters/http-exception.filter.ts
import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { Request, Response } from 'express';

@Catch(HttpException)  // HttpException만 처리
export class HttpExceptionFilter implements ExceptionFilter {
  catch(exception: HttpException, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();
    const status = exception.getStatus();

    response.status(status).json({
      success: false,
      statusCode: status,
      message: exception.message,
      path: request.url,
      timestamp: new Date().toISOString(),
    });
  }
}
```

> **Spring에서는?**
> ```java
> @ControllerAdvice
> public class GlobalExceptionHandler {
>     @ExceptionHandler(NotFoundException.class)
>     public ResponseEntity<ErrorResponse> handleNotFound(
>         NotFoundException ex, HttpServletRequest request) {
>         ErrorResponse error = new ErrorResponse(
>             false, 404, ex.getMessage(),
>             request.getRequestURI(), LocalDateTime.now()
>         );
>         return ResponseEntity.status(404).body(error);
>     }
> }
> ```
> NestJS의 `@Catch` + `ExceptionFilter` = Spring의 `@ControllerAdvice` + `@ExceptionHandler`

---

## 모든 예외를 처리하는 Filter

```typescript
// src/common/filters/all-exceptions.filter.ts
import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
} from '@nestjs/common';

@Catch()  // 인자 없음 → 모든 예외 처리
export class AllExceptionsFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse();
    const request = ctx.getRequest();

    const status =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;

    const message =
      exception instanceof HttpException
        ? exception.message
        : '서버 내부 오류가 발생했습니다';

    console.error('Unhandled Exception:', exception);

    response.status(status).json({
      success: false,
      statusCode: status,
      message,
      path: request.url,
      timestamp: new Date().toISOString(),
    });
  }
}
```

---

## 비즈니스 예외 클래스

```typescript
// src/common/exceptions/business.exception.ts
import { HttpException, HttpStatus } from '@nestjs/common';

export class BusinessException extends HttpException {
  constructor(
    public readonly errorCode: string,
    message: string,
    status: HttpStatus = HttpStatus.BAD_REQUEST,
  ) {
    super({ errorCode, message }, status);
  }
}

// 사용
throw new BusinessException('USER_001', '탈퇴한 사용자입니다');

// 응답: { "errorCode": "USER_001", "message": "탈퇴한 사용자입니다" }
```

> **Spring에서는?**
> 커스텀 예외 클래스를 만들고 `@ExceptionHandler`에서 처리하는 패턴과 동일합니다.

---

## Filter 적용 방법

```typescript
// 1. 메서드 레벨
@UseFilters(HttpExceptionFilter)
@Get(':id')
findOne() { ... }

// 2. Controller 레벨
@UseFilters(HttpExceptionFilter)
@Controller('users')
export class UserController { ... }

// 3. 글로벌 (main.ts)
app.useGlobalFilters(new AllExceptionsFilter());

// 4. 글로벌 (Module — DI 가능, 권장)
@Module({
  providers: [
    { provide: APP_FILTER, useClass: AllExceptionsFilter },
  ],
})
export class AppModule {}
```

---

## 요약

- NestJS는 `HttpException` 계층 구조로 예외를 관리 (404, 400, 403 등)
- **Exception Filter**: `@Catch()` + `ExceptionFilter`로 에러 응답 커스터마이징
- `@Catch()` 인자 없으면 모든 예외 처리, `@Catch(HttpException)`이면 HTTP 예외만
- Spring의 `@ControllerAdvice` + `@ExceptionHandler`에 대응
- 글로벌 적용 시 `APP_FILTER`를 Module에 등록하면 DI 가능

---

## 다음 편 예고

반복되는 로직을 재사용 가능한 **Custom Decorator**로 추출하는 방법을 배웁니다.

→ **[12편: Custom Decorator](12-custom-decorator.md)**

---

## 참고 자료

- [NestJS Exception Filters 공식 문서](https://docs.nestjs.com/exception-filters) — docs.nestjs.com
- [NestJS Built-in HTTP Exceptions](https://docs.nestjs.com/exception-filters#built-in-http-exceptions) — docs.nestjs.com
