# NestJS 소개 — Spring 개발자를 위한 첫걸음

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: Spring Boot 기본 경험, TypeScript 기초
> **시리즈**: NestJS 학습 가이드 1/15

---

## 개요

NestJS는 Node.js 위에서 동작하는 서버사이드 프레임워크로, Spring Boot와 놀랍도록 유사한 아키텍처를 가지고 있습니다.
Spring 개발자라면 Module, DI, 데코레이터 같은 익숙한 개념 덕분에 빠르게 적응할 수 있습니다.
이 편에서는 NestJS가 무엇인지, 왜 배워야 하는지, Spring Boot와 어떻게 다른지 살펴봅니다.

---

## NestJS란 무엇인가

NestJS는 **TypeScript 기반의 서버사이드 프레임워크**입니다. Angular에서 영감을 받아 만들어졌지만, 실제 아키텍처는 Spring Boot에 더 가깝습니다.

```
┌─────────────────────────────────────────────────────┐
│                    NestJS 아키텍처                    │
├─────────────────────────────────────────────────────┤
│                                                     │
│   ┌───────────┐    ┌───────────┐    ┌───────────┐   │
│   │ Controller│───▶│  Service  │───▶│Repository │   │
│   │ (라우팅)   │    │(비즈니스)  │    │ (데이터)   │   │
│   └───────────┘    └───────────┘    └───────────┘   │
│         │                │                │         │
│         ▼                ▼                ▼         │
│   ┌─────────────────────────────────────────────┐   │
│   │              Module (조립 단위)              │   │
│   └─────────────────────────────────────────────┘   │
│         │                                           │
│         ▼                                           │
│   ┌─────────────────────────────────────────────┐   │
│   │     HTTP 플랫폼 (Express v5 / Fastify v5)    │   │
│   └─────────────────────────────────────────────┘   │
│         │                                           │
│         ▼                                           │
│   ┌─────────────────────────────────────────────┐   │
│   │           Node.js 런타임 (v20+)              │   │
│   └─────────────────────────────────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

핵심 특징:
- **TypeScript 우선**: 타입 안전성을 기본으로 제공
- **모듈 기반 아키텍처**: Spring의 `@Configuration`처럼 모듈 단위로 애플리케이션을 구성
- **DI 컨테이너 내장**: Spring IoC 컨테이너와 동일한 역할
- **Express/Fastify 기반**: 검증된 HTTP 라이브러리 위에 구축

---

## 왜 NestJS를 배워야 하는가

### Spring 개발자가 NestJS를 배우면 좋은 이유

1. **풀스택 확장**: 프론트엔드(React, Vue)와 동일한 언어(TypeScript)로 백엔드를 작성
2. **빠른 프로토타이핑**: Node.js의 가벼운 시작과 핫 리로드로 개발 속도 향상
3. **마이크로서비스**: gRPC, MQTT, Redis 등 다양한 전송 계층을 네이티브 지원
4. **이직/협업**: Node.js 생태계는 2026년 기준 가장 큰 백엔드 생태계 중 하나

### 2026년 NestJS v11 현황

| 지표 | 수치 |
|------|------|
| npm 주간 다운로드 | ~8.5M |
| GitHub Stars | 75,000+ |
| 기본 컴파일러 | SWC (TypeScript보다 20배+ 빠름) |
| 기본 테스트 러너 | Vitest |
| HTTP 플랫폼 | Express v5 / Fastify v5 |
| 로거 | JSON Logger 내장 |
| ESM | First-class 지원 |

---

## Spring Boot와 아키텍처 비교

### 데코레이터 vs 어노테이션

NestJS의 **데코레이터**는 Spring의 **어노테이션**과 동일한 역할을 합니다.

```typescript
// NestJS — 데코레이터
@Controller('users')
export class UserController {
  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.userService.findOne(id);
  }
}
```

> **Spring에서는?**
> ```java
> // Spring Boot — 어노테이션
> @RestController
> @RequestMapping("/users")
> public class UserController {
>     @GetMapping("/{id}")
>     public User findOne(@PathVariable String id) {
>         return userService.findOne(id);
>     }
> }
> ```

### Module vs @Configuration

```typescript
// NestJS — @Module로 구성 요소를 묶음
@Module({
  imports: [DatabaseModule],
  controllers: [UserController],
  providers: [UserService],
  exports: [UserService],
})
export class UserModule {}
```

> **Spring에서는?**
> ```java
> // Spring Boot — @Configuration + @ComponentScan
> @Configuration
> @ComponentScan(basePackages = "com.example.user")
> public class UserConfig {
>     @Bean
>     public UserService userService() {
>         return new UserService();
>     }
> }
> ```

### DI 컨테이너 비교

| 기능 | NestJS | Spring Boot |
|------|--------|-------------|
| DI 방식 | 생성자 주입 (기본) | 생성자 주입 (권장) |
| 등록 | `@Injectable()` + Module providers | `@Component` / `@Service` |
| 스코프 | Singleton (기본), Request, Transient | Singleton (기본), Prototype, Request |
| 설정 주입 | `ConfigService` | `@Value` / `@ConfigurationProperties` |

---

## Node.js 이벤트 루프 vs Java 멀티스레드

Spring 개발자가 NestJS로 전환할 때 가장 큰 패러다임 차이입니다.

```
┌─ Java / Spring Boot ──────────────┐  ┌─ Node.js / NestJS ─────────────────┐
│                                   │  │                                    │
│  요청 1 ──▶ Thread-1 (블로킹)      │  │  요청 1 ──▶ 이벤트 루프 (논블로킹)   │
│  요청 2 ──▶ Thread-2 (블로킹)      │  │  요청 2 ──▶ 이벤트 루프 (논블로킹)   │
│  요청 3 ──▶ Thread-3 (블로킹)      │  │  요청 3 ──▶ 이벤트 루프 (논블로킹)   │
│  ...                              │  │                                    │
│  요청 N ──▶ Thread-N (스레드풀 한계)│  │  I/O 작업 ──▶ Worker Pool (비동기)  │
│                                   │  │                                    │
│  장점: CPU 집약 작업에 강함         │  │  장점: I/O 집약 작업에 강함          │
│  단점: 스레드당 메모리 소비         │  │  단점: CPU 집약 작업 시 블로킹       │
└───────────────────────────────────┘  └────────────────────────────────────┘
```

> **Spring에서는?**
> Spring은 요청마다 스레드를 할당합니다 (Tomcat 기본 200개).
> NestJS는 **단일 스레드**에서 모든 요청을 처리하되, I/O 작업은 비동기로 위임합니다.
> 따라서 NestJS에서는 **절대로 메인 스레드를 블로킹하면 안 됩니다** (`while(true)`, 동기 파일 읽기 등 금지).
> Spring WebFlux(Reactor)를 사용해봤다면 비슷한 모델로 이해할 수 있습니다.

---

## 시리즈 로드맵

| 편 | 제목 | 난이도 |
|----|------|--------|
| **01** | **NestJS 소개 (현재 편)** | 입문 |
| 02 | 개발 환경 설정 — 프로젝트 생성과 구조 이해 | 입문 |
| 03 | Module — 애플리케이션 구조의 기본 단위 | 입문 |
| 04 | Controller — 요청을 처리하는 관문 | 입문 |
| 05 | Provider와 Service — 비즈니스 로직의 핵심 | 입문 |
| 06 | 의존성 주입(DI) 심화 — Custom Provider와 Scope | 중급 |
| 07 | Middleware — 요청 전처리 파이프라인 | 중급 |
| 08 | Pipe — 데이터 변환과 유효성 검증 | 중급 |
| 09 | Guard — 인증과 인가의 관문 | 중급 |
| 10 | Interceptor — 요청과 응답을 가로채기 | 중급 |
| 11 | Exception Filter — 에러 처리 전략 | 중급 |
| 12 | Custom Decorator — 메타데이터와 재사용 로직 | 중급 |
| 13 | 요청 라이프사이클 — 전체 흐름 완전 정리 | 중급 |
| 14 | Database 연동 — Prisma로 CRUD 구현 | 중급 |
| 15 | 실무 전환 가이드 — Spring 개발자의 적응 전략 | 입문 |

---

## 요약

- NestJS는 Spring Boot와 매우 유사한 아키텍처를 가진 Node.js/TypeScript 프레임워크입니다.
- 데코레이터 = 어노테이션, Module = @Configuration, @Injectable = @Component로 대응됩니다.
- Node.js는 단일 스레드 + 이벤트 루프 모델이므로, Spring의 멀티스레드 모델과 근본적으로 다릅니다.
- 2026년 v11 기준, SWC 컴파일러와 Vitest가 기본이며, ESM을 완전 지원합니다.

## 다음 편 예고

[02편 — 개발 환경 설정](./02-project-setup.md)에서는 NestJS CLI로 프로젝트를 생성하고, Spring Boot 프로젝트와 디렉토리 구조를 비교합니다.

## 참고 자료

- [NestJS 공식 문서](https://docs.nestjs.com/) — NestJS v11 기준
- [NestJS GitHub](https://github.com/nestjs/nest) — 소스 코드 및 릴리즈 노트
- [Spring Boot 공식 문서](https://docs.spring.io/spring-boot/reference/) — 비교 참조용
- [Node.js 이벤트 루프 가이드](https://nodejs.org/en/learn/asynchronous-work/event-loop-timers-and-nexttick) — 이벤트 루프 동작 원리
