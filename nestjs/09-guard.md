# Guard — 인증과 인가의 관문

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [08편: Pipe](08-pipe.md)
> **시리즈**: NestJS 학습 가이드 9/15

---

## 개요

Guard는 **요청을 허용할지 거부할지** 결정합니다.
주로 인증(Authentication)과 인가(Authorization)를 담당합니다.
Spring Security의 `SecurityFilterChain`과 `@PreAuthorize`에 대응합니다.

---

## Guard vs Middleware — 왜 Guard를 쓸까?

```
Middleware:                          Guard:
  req, res, next만 접근 가능          ExecutionContext에 접근 가능
  → 어떤 핸들러가 실행될지 모름         → 어떤 Controller/메서드인지 앎
  → 메타데이터 접근 불가               → @SetMetadata로 설정한 역할 정보 접근 가능!

  ∴ 로깅, CORS 같은 범용 작업         ∴ "이 사용자가 이 API를 호출할 수 있는가?" 판단
```

---

## Guard 기본 구조

```typescript
// src/common/guards/auth.guard.ts
import { Injectable, CanActivate, ExecutionContext, UnauthorizedException } from '@nestjs/common';

@Injectable()
export class AuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    const token = request.headers['authorization'];

    if (!token) {
      throw new UnauthorizedException('인증 토큰이 필요합니다');
      // Guard에서 false를 반환하면 기본적으로 403입니다.
      // 인증 실패는 401이 적절하므로 UnauthorizedException을 던집니다.
    }

    // 토큰 검증 로직
    return this.validateToken(token);
  }

  private validateToken(token: string): boolean {
    // JWT 검증 등의 로직
    return token.startsWith('Bearer ');
  }
}
```

> **Spring에서는?**
> Spring Security의 `SecurityFilterChain`으로 인증을 처리합니다.
> ```java
> @Bean
> public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
>     return http
>         .authorizeHttpRequests(auth -> auth
>             .requestMatchers("/public/**").permitAll()
>             .anyRequest().authenticated()
>         )
>         .addFilterBefore(jwtAuthFilter, UsernamePasswordAuthenticationFilter.class)
>         .build();
> }
> ```

---

## Guard 적용 방법

```typescript
// 1. 메서드 레벨
@UseGuards(AuthGuard)
@Get('profile')
getProfile() { ... }

// 2. Controller 레벨
@UseGuards(AuthGuard)
@Controller('users')
export class UserController { ... }

// 3. 글로벌 레벨 (main.ts)
app.useGlobalGuards(new AuthGuard());
```

---

## Role-based Guard 구현

### 1. 역할 메타데이터 설정

```typescript
// src/common/decorators/roles.decorator.ts
import { SetMetadata } from '@nestjs/common';

export const ROLES_KEY = 'roles';
export const Roles = (...roles: string[]) => SetMetadata(ROLES_KEY, roles);
```

### 2. RolesGuard 구현

```typescript
// src/common/guards/roles.guard.ts
import { Injectable, CanActivate, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ROLES_KEY } from '../decorators/roles.decorator';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    // 핸들러에 설정된 역할 메타데이터 조회
    const requiredRoles = this.reflector.getAllAndOverride<string[]>(
      ROLES_KEY,
      [context.getHandler(), context.getClass()],
    );

    // 역할이 설정되지 않았으면 모두 허용
    if (!requiredRoles) {
      return true;
    }

    // 요청에서 사용자 정보 추출 (AuthGuard에서 미리 설정)
    const { user } = context.switchToHttp().getRequest();
    return requiredRoles.some((role) => user?.roles?.includes(role));
  }
}
```

### 3. Controller에서 사용

```typescript
@Controller('users')
@UseGuards(AuthGuard, RolesGuard)  // AuthGuard 먼저, RolesGuard 다음
export class UserController {

  @Get()
  @Roles('user', 'admin')  // user 또는 admin 역할만 접근
  findAll() {
    return this.userService.findAll();
  }

  @Delete(':id')
  @Roles('admin')  // admin만 삭제 가능
  remove(@Param('id', ParseIntPipe) id: number) {
    return this.userService.remove(id);
  }
}
```

> **Spring에서는?**
> ```java
> @PreAuthorize("hasAnyRole('USER', 'ADMIN')")
> @GetMapping("/users")
> public List<User> findAll() { ... }
>
> @PreAuthorize("hasRole('ADMIN')")
> @DeleteMapping("/users/{id}")
> public void remove(@PathVariable Long id) { ... }
> ```
> NestJS의 `@Roles()` + `RolesGuard` = Spring의 `@PreAuthorize`

---

## Guard 판단 흐름

```
요청 도착
    │
    ▼
┌─────────────────────┐
│  AuthGuard           │
│  토큰 있는가?         │
│  ├─ No  → 403       │
│  └─ Yes → 다음      │
└────────┬────────────┘
         ▼
┌─────────────────────┐
│  RolesGuard          │
│  @Roles 메타데이터?  │
│  ├─ 없음 → 통과     │
│  ├─ 있음            │
│  │  역할 일치?       │
│  │  ├─ No  → 403   │
│  │  └─ Yes → 통과  │
└────────┬────────────┘
         ▼
┌─────────────────────┐
│  Controller 실행     │
└─────────────────────┘
```

---

## 요약

- **Guard**: 요청의 허용/거부를 결정 (인증/인가)
- `CanActivate` 인터페이스 구현, `true`=허용 `false`=거부
- **ExecutionContext**로 어떤 핸들러가 실행될지 알 수 있음 (Middleware와의 핵심 차이)
- `@SetMetadata` + `Reflector`로 역할 기반 인가 구현
- Spring의 `SecurityFilterChain` + `@PreAuthorize`에 대응

---

## 다음 편 예고

요청과 응답을 가로채서 변환하는 **Interceptor**를 배웁니다. Spring AOP의 `@Around`와 비교합니다.

→ **[10편: Interceptor](10-interceptor.md)**

---

## 참고 자료

- [NestJS Guards 공식 문서](https://docs.nestjs.com/guards) — docs.nestjs.com
- [NestJS Authorization 공식 문서](https://docs.nestjs.com/security/authorization) — docs.nestjs.com
