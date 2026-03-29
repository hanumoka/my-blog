# Custom Decorator — 메타데이터와 재사용 로직

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [11편: Exception Filter](11-exception-filter.md)
> **시리즈**: NestJS 학습 가이드 12/15

---

## 개요

NestJS는 TypeScript 데코레이터를 적극 활용합니다.
내장 데코레이터 외에 **직접 만든 데코레이터**로 반복 코드를 줄일 수 있습니다.
Spring의 커스텀 어노테이션(`@interface`) + AOP에 대응합니다.

---

## 데코레이터의 종류

```
NestJS 데코레이터                     Spring 어노테이션
┌─────────────────────────┐          ┌─────────────────────────┐
│ Param Decorator          │   ←→    │ @PathVariable, @Param   │
│ (@CurrentUser 등)        │         │ HandlerMethodArgument   │
│                          │         │ Resolver                │
├─────────────────────────┤          ├─────────────────────────┤
│ Method/Class Decorator   │   ←→    │ @PreAuthorize, @Cached  │
│ (@Roles, @Public 등)     │         │ 커스텀 @interface + AOP │
├─────────────────────────┤          ├─────────────────────────┤
│ 합성 Decorator           │   ←→    │ 메타 어노테이션          │
│ (applyDecorators)        │         │ (@RestController 등)    │
└─────────────────────────┘          └─────────────────────────┘
```

---

## Param Decorator — @CurrentUser 만들기

매 요청마다 `req.user`에서 사용자를 꺼내는 반복 코드를 제거합니다.

```typescript
// 반복 코드 (Before)
@Get('profile')
getProfile(@Req() req: Request) {
  const user = req.user;  // 매번 req.user를 꺼내야 함
  return user;
}
```

```typescript
// src/common/decorators/current-user.decorator.ts
import { createParamDecorator, ExecutionContext } from '@nestjs/common';

export const CurrentUser = createParamDecorator(
  (data: string | undefined, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest();
    const user = request.user;

    // data가 있으면 특정 필드만 반환 (예: @CurrentUser('email'))
    return data ? user?.[data] : user;
  },
);
```

```typescript
// 깔끔한 코드 (After)
@Get('profile')
getProfile(@CurrentUser() user: User) {
  return user;
}

@Get('email')
getEmail(@CurrentUser('email') email: string) {
  return { email };
}
```

> **Spring에서는?**
> `HandlerMethodArgumentResolver`를 구현하거나 Spring Security의 `@AuthenticationPrincipal`을 사용합니다.
> ```java
> @GetMapping("/profile")
> public User getProfile(@AuthenticationPrincipal UserDetails user) {
>     return user;
> }
> ```

---

## Method Decorator — @Roles 만들기

09편에서 만든 `@Roles` 데코레이터를 복습합니다.

```typescript
// src/common/decorators/roles.decorator.ts
import { SetMetadata } from '@nestjs/common';

export const ROLES_KEY = 'roles';
export const Roles = (...roles: string[]) => SetMetadata(ROLES_KEY, roles);

// 사용
@Roles('admin')
@Delete(':id')
remove() { ... }
```

### @Public 데코레이터 — 인증 건너뛰기

```typescript
// src/common/decorators/public.decorator.ts
import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
```

```typescript
// AuthGuard에서 @Public 체크
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    // @Public이 붙어 있으면 인증 건너뛰기
    const isPublic = this.reflector.getAllAndOverride<boolean>(
      IS_PUBLIC_KEY,
      [context.getHandler(), context.getClass()],
    );
    if (isPublic) return true;

    // 일반적인 인증 로직...
    const request = context.switchToHttp().getRequest();
    return this.validateToken(request);
  }
}
```

```typescript
// 사용 — 이 API는 인증 없이 접근 가능
@Public()
@Get('health')
healthCheck() {
  return { status: 'ok' };
}
```

> **Spring에서는?**
> ```java
> http.authorizeHttpRequests(auth -> auth
>     .requestMatchers("/health").permitAll()
>     .anyRequest().authenticated()
> );
> ```
> Security 설정에서 URL 패턴으로 제외하는 방식입니다.

---

## 데코레이터 합성 — applyDecorators

여러 데코레이터를 하나로 묶습니다.

```typescript
// src/common/decorators/auth.decorator.ts
import { applyDecorators, SetMetadata, UseGuards } from '@nestjs/common';
import { AuthGuard } from '../guards/auth.guard';
import { RolesGuard } from '../guards/roles.guard';
import { ROLES_KEY } from './roles.decorator';

export function Auth(...roles: string[]) {
  return applyDecorators(
    SetMetadata(ROLES_KEY, roles),
    UseGuards(AuthGuard, RolesGuard),
  );
}
```

```typescript
// Before — 데코레이터 3개
@SetMetadata('roles', ['admin'])
@UseGuards(AuthGuard, RolesGuard)
@Delete(':id')
remove() { ... }

// After — 합성 데코레이터 1개!
@Auth('admin')
@Delete(':id')
remove() { ... }
```

> **Spring에서는?**
> 메타 어노테이션을 활용합니다:
> ```java
> @Target(ElementType.METHOD)
> @Retention(RetentionPolicy.RUNTIME)
> @PreAuthorize("hasRole('ADMIN')")
> public @interface AdminOnly {}
>
> // 사용
> @AdminOnly
> @DeleteMapping("/{id}")
> public void remove(@PathVariable Long id) { ... }
> ```

---

## 실무 활용 패턴

```typescript
// 자주 쓰이는 커스텀 데코레이터 모음

// 1. @CurrentUser — 현재 로그인한 사용자
@CurrentUser() user: User

// 2. @Auth('admin') — 인증 + 역할 확인
@Auth('admin')

// 3. @Public() — 인증 제외
@Public()

// 4. @ApiPagination() — Swagger + 페이징 파라미터
export function ApiPagination() {
  return applyDecorators(
    ApiQuery({ name: 'page', required: false, type: Number }),
    ApiQuery({ name: 'limit', required: false, type: Number }),
  );
}
```

---

## 요약

- **Param Decorator**: `createParamDecorator()`로 요청에서 데이터 추출 (`@CurrentUser`)
- **Method Decorator**: `SetMetadata()`로 메타데이터 설정 (`@Roles`, `@Public`)
- **합성 Decorator**: `applyDecorators()`로 여러 데코레이터를 하나로 묶기 (`@Auth`)
- Spring의 커스텀 어노테이션 + AOP / `@AuthenticationPrincipal`에 대응
- 반복되는 데코레이터 조합은 합성 데코레이터로 추출하면 코드가 깔끔해짐

---

## 다음 편 예고

지금까지 배운 Middleware, Pipe, Guard, Interceptor, Exception Filter의 **실행 순서를 전체적으로 정리**합니다.

→ **[13편: 요청 라이프사이클](13-request-lifecycle.md)**

---

## 참고 자료

- [NestJS Custom Decorators 공식 문서](https://docs.nestjs.com/custom-decorators) — docs.nestjs.com
- [NestJS Custom Route Decorators](https://docs.nestjs.com/custom-decorators#working-with-pipes) — docs.nestjs.com
