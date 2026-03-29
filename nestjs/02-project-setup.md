# 개발 환경 설정 — 프로젝트 생성과 구조 이해

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [01편 — NestJS 소개](./01-nestjs-intro.md)
> **시리즈**: NestJS 학습 가이드 2/15

---

## 개요

Spring Boot에서 Spring Initializr로 프로젝트를 만들듯, NestJS는 CLI로 프로젝트를 생성합니다.
이 편에서는 개발 환경을 설정하고, 생성된 프로젝트 구조를 Spring Boot와 비교하며, Hello World 서버를 실행합니다.

---

## Node.js / npm 설치

NestJS는 Node.js 위에서 동작합니다. Spring에 JDK가 필요하듯, NestJS에는 Node.js가 필요합니다.

```bash
# Node.js v20+ 설치 확인
node -v
# v20.x.x 이상

npm -v
# 10.x.x 이상
```

> **Spring에서는?**
> Spring Boot는 JDK 17+ 설치가 필요합니다.
> Node.js = JDK, npm = Maven/Gradle로 대응됩니다.

| 역할 | Spring | NestJS |
|------|--------|--------|
| 런타임 | JDK | Node.js |
| 패키지 매니저 | Maven / Gradle | npm / yarn / pnpm |
| 프로젝트 생성 | Spring Initializr | NestJS CLI |
| 빌드 도구 | Maven / Gradle | SWC (v11 기본) |

---

## NestJS CLI 설치

```bash
# NestJS CLI 전역 설치
npm i -g @nestjs/cli

# 설치 확인
nest --version
# 11.x.x
```

> **Spring에서는?**
> Spring Boot CLI도 있지만 대부분 IntelliJ + Spring Initializr를 사용합니다.
> NestJS CLI는 프로젝트 생성, 코드 생성, 빌드까지 담당하므로 훨씬 적극적으로 사용됩니다.

---

## 프로젝트 생성

```bash
# 새 프로젝트 생성
nest new my-app

# 패키지 매니저 선택 (npm / yarn / pnpm)
# npm 선택 권장 (초기 학습 시)
```

생성 후 프로젝트 디렉토리로 이동합니다.

```bash
cd my-app
```

---

## 프로젝트 디렉토리 구조 분석

```
┌─ NestJS (my-app/) ─────────────────┐  ┌─ Spring Boot (my-app/) ────────────┐
│                                    │  │                                    │
│  src/                              │  │  src/main/java/com/example/        │
│  ├── main.ts          ← 진입점     │  │  ├── MyAppApplication.java ← 진입점│
│  ├── app.module.ts    ← 루트 모듈  │  │  ├── config/                       │
│  ├── app.controller.ts← 컨트롤러   │  │  ├── controller/                   │
│  ├── app.controller.spec.ts ← 테스트│  │  ├── service/                      │
│  └── app.service.ts   ← 서비스     │  │  └── repository/                   │
│                                    │  │                                    │
│  test/                             │  │  src/test/java/com/example/        │
│  ├── app.e2e-spec.ts  ← E2E 테스트 │  │  └── MyAppApplicationTests.java    │
│  └── vitest-e2e.config.ts          │  │                                    │
│                                    │  │  src/main/resources/               │
│  nest-cli.json        ← CLI 설정   │  │  ├── application.yml  ← 설정       │
│  tsconfig.json        ← TS 설정    │  │  └── static/                       │
│  package.json         ← 의존성     │  │                                    │
│  vitest.config.ts     ← 테스트 설정│  │  pom.xml / build.gradle ← 의존성   │
│                                    │  │                                    │
└────────────────────────────────────┘  └────────────────────────────────────┘
```

### 핵심 파일 분석

#### `src/main.ts` — 애플리케이션 진입점

```typescript
// main.ts — Spring의 main() 메서드와 동일한 역할
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  await app.listen(3000);
}
bootstrap();
```

> **Spring에서는?**
> ```java
> @SpringBootApplication
> public class MyAppApplication {
>     public static void main(String[] args) {
>         SpringApplication.run(MyAppApplication.class, args);
>     }
> }
> ```
> `NestFactory.create(AppModule)` = `SpringApplication.run(MyAppApplication.class)` 입니다.

#### `src/app.module.ts` — 루트 모듈

```typescript
// app.module.ts — Spring의 @SpringBootApplication과 대응
import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';

@Module({
  imports: [],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
```

> **Spring에서는?**
> `@SpringBootApplication`은 `@Configuration` + `@EnableAutoConfiguration` + `@ComponentScan`을 합친 것입니다.
> NestJS의 `AppModule`은 이 중 `@Configuration` + `@ComponentScan` 역할을 합니다.

#### `src/app.controller.ts` — 기본 컨트롤러

```typescript
import { Controller, Get } from '@nestjs/common';
import { AppService } from './app.service';

@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get()
  getHello(): string {
    return this.appService.getHello();
  }
}
```

#### `src/app.service.ts` — 기본 서비스

```typescript
import { Injectable } from '@nestjs/common';

@Injectable()
export class AppService {
  getHello(): string {
    return 'Hello World!';
  }
}
```

---

## NestJS CLI 주요 명령어

```bash
# 리소스 생성 (컨트롤러, 서비스, 모듈 한번에)
nest generate resource users
# → users.module.ts, users.controller.ts, users.service.ts, DTO, 테스트 파일 생성

# 개별 생성
nest generate module users       # 모듈만
nest generate controller users   # 컨트롤러만
nest generate service users      # 서비스만

# 빌드
nest build                       # SWC로 컴파일 (v11 기본)

# 개발 서버 (핫 리로드)
npm run start:dev
```

> **Spring에서는?**
> Spring Boot에는 `nest generate` 같은 CLI 코드 생성 도구가 없습니다.
> IntelliJ의 코드 템플릿이나 Spring Initializr의 의존성 추가가 유사한 역할을 합니다.
> NestJS CLI는 컨벤션에 맞는 파일을 자동 생성하고 모듈에 등록까지 해줍니다.

---

## SWC 컴파일러

NestJS v11부터 **SWC**가 기본 컴파일러입니다.

```
┌─ 컴파일 속도 비교 ──────────────────────────────────┐
│                                                     │
│  TypeScript Compiler (tsc)  ████████████████  ~10초  │
│  SWC Compiler               █               ~0.5초  │
│                                                     │
│  SWC는 Rust로 작성되어 tsc 대비 20배+ 빠릅니다       │
└─────────────────────────────────────────────────────┘
```

`nest-cli.json`에서 확인할 수 있습니다:

```json
{
  "$schema": "https://json.schemastore.org/nest-cli",
  "collection": "@nestjs/schematics",
  "sourceRoot": "src",
  "compilerOptions": {
    "builder": "swc",
    "typeCheck": true
  }
}
```

> **Spring에서는?**
> Java는 `javac`가 유일한 표준 컴파일러입니다 (GraalVM 네이티브 이미지는 별도).
> TypeScript 생태계에서는 tsc, SWC, esbuild 등 다양한 컴파일러가 경쟁하며,
> NestJS v11은 속도를 위해 SWC를 기본으로 채택했습니다.

---

## 실습: Hello World 서버 실행

```bash
# 1. 프로젝트 생성
nest new hello-nestjs

# 2. 디렉토리 이동
cd hello-nestjs

# 3. 개발 서버 시작 (핫 리로드)
npm run start:dev
```

터미널에 다음 로그가 출력됩니다:

```
[Nest] LOG [NestFactory] Starting Nest application...
[Nest] LOG [InstanceLoader] AppModule dependencies initialized
[Nest] LOG [RoutesResolver] AppController {/}:
[Nest] LOG [RouterExplorer] Mapped {/, GET} route
[Nest] LOG [NestApplication] Nest application successfully started
```

```bash
# 4. 테스트
curl http://localhost:3000
# Hello World!
```

> **Spring에서는?**
> `mvn spring-boot:run` 또는 `./gradlew bootRun`과 동일합니다.
> Spring은 8080 포트가 기본이고, NestJS는 3000 포트가 기본입니다.

---

## 요약

- NestJS CLI(`nest new`)로 프로젝트를 생성하면 Controller, Service, Module이 포함된 기본 구조가 만들어집니다.
- `main.ts`는 Spring의 `main()` 메서드, `app.module.ts`는 `@SpringBootApplication`에 대응합니다.
- `nest generate` 명령어로 컨벤션에 맞는 코드를 자동 생성할 수 있습니다.
- NestJS v11은 SWC 컴파일러를 기본으로 사용하여 빠른 빌드 속도를 제공합니다.

## 다음 편 예고

[03편 — Module](./03-module.md)에서는 NestJS 아키텍처의 핵심인 모듈 시스템을 자세히 살펴봅니다. Feature Module, Dynamic Module, @Global 모듈까지 다룹니다.

## 참고 자료

- [NestJS 공식 문서 — First Steps](https://docs.nestjs.com/first-steps) — 프로젝트 생성 가이드
- [NestJS CLI 문서](https://docs.nestjs.com/cli/overview) — CLI 명령어 레퍼런스
- [SWC 공식 사이트](https://swc.rs/) — SWC 컴파일러 소개
- [Node.js 다운로드](https://nodejs.org/) — Node.js 설치
- [Spring Initializr](https://start.spring.io/) — 비교 참조용
