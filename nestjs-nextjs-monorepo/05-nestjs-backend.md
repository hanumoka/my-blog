# NestJS 백엔드 셋업 — 모노리포 안의 API 서버

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [04편: Prisma 공유 패키지](04-prisma-package.md)
> **시리즈**: NestJS + Next.js + Prisma 모노리포 가이드 5/10

---

## 개요

`apps/backend`에 NestJS 11 API 서버를 구성합니다.
`packages/database`의 Prisma 클라이언트와 `packages/shared`의 타입을 활용해
사용자 CRUD API를 만드는 전 과정을 다룹니다.

---

## 핵심 개념 — 모노리포 안의 NestJS

```
apps/backend/
├── src/
│   ├── app.module.ts       ← 루트 모듈
│   ├── main.ts             ← 진입점
│   └── users/
│       ├── users.module.ts
│       ├── users.controller.ts
│       └── users.service.ts
├── package.json
└── tsconfig.json

의존 관계:
  apps/backend
    ├─ @my-monorepo/database  (workspace:*)
    └─ @my-monorepo/shared    (workspace:*)
```

---

## 실습

### 1단계: NestJS CLI로 앱 생성

```bash
# 루트에서 (기존 빈 폴더를 삭제 후 생성)
rm -rf apps/backend
pnpm dlx @nestjs/cli new apps/backend --skip-git --package-manager pnpm
```

또는 직접 `package.json`을 작성하는 방법:

```json
// apps/backend/package.json
{
  "name": "@my-monorepo/backend",
  "version": "0.0.1",
  "private": true,
  "scripts": {
    "build": "nest build",
    "dev": "nest start --watch",
    "start": "node dist/main",
    "lint": "eslint src/",
    "test": "vitest"
  },
  "dependencies": {
    "@nestjs/common": "^11.0.0",
    "@nestjs/core": "^11.0.0",
    "@nestjs/platform-express": "^11.0.0",
    "@nestjs/config": "^4.0.0",
    "@my-monorepo/database": "workspace:*",
    "@my-monorepo/shared": "workspace:*",
    "class-validator": "^0.14.0",
    "class-transformer": "^0.5.0",
    "reflect-metadata": "^0.2.0",
    "rxjs": "^7.8.0"
  },
  "devDependencies": {
    "@nestjs/cli": "^11.0.0",
    "@nestjs/schematics": "^11.0.0",
    "typescript": "^5.8.0",
    "vitest": "^3.0.0"
  }
}
```

### 2단계: TypeScript 설정

```json
// apps/backend/tsconfig.json
{
  "extends": "../../tsconfig.json",
  "compilerOptions": {
    "outDir": "./dist",
    "rootDir": "./src",
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    "paths": {
      "@my-monorepo/database": ["../../packages/database/src/index.ts"],
      "@my-monorepo/shared": ["../../packages/shared/src/index.ts"]
    }
  },
  "include": ["src/**/*"],
  "exclude": ["dist", "node_modules", "**/*.spec.ts"]
}
```

> 💡 `paths` 설정으로 `workspace:*` 패키지를 TypeScript가 로컬 소스에서 직접 찾게 합니다.
> 이를 통해 shared 패키지 수정이 빌드 없이 즉시 반영됩니다.

### 3단계: PrismaModule 만들기

```typescript
// apps/backend/src/prisma/prisma.module.ts
import { Global, Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
```

```typescript
// apps/backend/src/prisma/prisma.service.ts
import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@my-monorepo/database';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
```

### 4단계: Users 모듈 구성

```typescript
// apps/backend/src/users/dto/create-user.dto.ts
import { IsEmail, IsString, MinLength, IsEnum, IsOptional } from 'class-validator';
import { CreateUserDto as ICreateUserDto, UserRole } from '@my-monorepo/shared';

// shared의 인터페이스를 기반으로 DTO 클래스 작성
export class CreateUserDto implements ICreateUserDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(2)
  name: string;

  @IsString()
  @MinLength(8)
  password: string;

  @IsEnum(['ADMIN', 'USER', 'GUEST'])
  @IsOptional()
  role?: UserRole;
}
```

```typescript
// apps/backend/src/users/users.service.ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateUserDto } from './dto/create-user.dto';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll() {
    return this.prisma.user.findMany({
      select: {
        id: true,
        email: true,
        name: true,
        role: true,
        createdAt: true,
        updatedAt: true,
        password: false,  // 비밀번호는 절대 반환하지 않음
      },
    });
  }

  async findOne(id: number) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      select: {
        id: true,
        email: true,
        name: true,
        role: true,
        createdAt: true,
        updatedAt: true,
        password: false,
      },
    });
    if (!user) {
      throw new NotFoundException(`User #${id} not found`);
    }
    return user;
  }

  async create(dto: CreateUserDto) {
    return this.prisma.user.create({
      data: {
        email: dto.email,
        name: dto.name,
        password: dto.password,  // 실제 운영에서는 bcrypt로 해시화 필요
        role: dto.role ?? 'USER',
      },
    });
  }

  async remove(id: number) {
    await this.findOne(id);  // 존재 확인
    return this.prisma.user.delete({ where: { id } });
  }
}
```

```typescript
// apps/backend/src/users/users.controller.ts
import {
  Controller, Get, Post, Delete,
  Param, Body, ParseIntPipe, HttpCode, HttpStatus,
} from '@nestjs/common';
import { UsersService } from './users.service';
import { CreateUserDto } from './dto/create-user.dto';

@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get()
  async findAll() {
    const data = await this.usersService.findAll();
    return {
      statusCode: 200,
      data,
      timestamp: new Date().toISOString(),
    };
  }

  @Get(':id')
  async findOne(@Param('id', ParseIntPipe) id: number) {
    const data = await this.usersService.findOne(id);
    return {
      statusCode: 200,
      data,
      timestamp: new Date().toISOString(),
    };
  }

  @Post()
  async create(@Body() dto: CreateUserDto) {
    const data = await this.usersService.create(dto);
    return {
      statusCode: 201,
      data,
      timestamp: new Date().toISOString(),
    };
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(@Param('id', ParseIntPipe) id: number): Promise<void> {
    await this.usersService.remove(id);
  }
}
```

```typescript
// apps/backend/src/users/users.module.ts
import { Module } from '@nestjs/common';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

@Module({
  controllers: [UsersController],
  providers: [UsersService],
})
export class UsersModule {}
```

### 5단계: 루트 모듈과 main.ts

```typescript
// apps/backend/src/app.module.ts
import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { PrismaModule } from './prisma/prisma.module';
import { UsersModule } from './users/users.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    PrismaModule,
    UsersModule,
  ],
})
export class AppModule {}
```

```typescript
// apps/backend/src/main.ts
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.setGlobalPrefix('api/v1');

  app.useGlobalPipes(new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
  }));

  app.enableCors({
    origin: process.env.FRONTEND_URL || 'http://localhost:3000',
  });

  await app.listen(process.env.PORT ?? 3001);
  console.log(`Backend running on http://localhost:3001`);
}
bootstrap();
```

### 6단계: 환경변수 파일

```bash
# apps/backend/.env
DATABASE_URL="postgresql://postgres:YOUR_PASSWORD@localhost:5432/mydb?schema=public"
PORT=3001
FRONTEND_URL=http://localhost:3000
NODE_ENV=development
```

### 7단계: 백엔드 실행

```bash
# 루트에서 backend만 실행
pnpm --filter @my-monorepo/backend dev

# 또는 Turborepo로 전체 dev 실행
pnpm dev
```

---

## 요약

- `apps/backend`는 독립적인 `package.json`을 가진 NestJS 앱
- `tsconfig.json`의 `paths`로 workspace 패키지를 소스에서 직접 참조
- `PrismaModule` (`@Global()`)로 PrismaService를 전체 앱에서 주입 가능
- `packages/shared`의 `ApiResponse<T>` 타입으로 일관된 응답 형식 유지
- 비밀번호 등 민감 데이터는 절대 응답에 포함하지 않도록 `select` 사용

---

## 다음 편 예고

Next.js 프론트엔드를 모노리포에 추가하고 백엔드와 연동합니다.

→ **[06편: Next.js 프론트엔드 셋업](06-nextjs-frontend.md)**

---

## 참고 자료

- [NestJS 공식 문서](https://docs.nestjs.com/) — docs.nestjs.com
- [NestJS Prisma 통합](https://docs.nestjs.com/recipes/prisma) — docs.nestjs.com
- [NestJS ConfigModule](https://docs.nestjs.com/techniques/configuration) — docs.nestjs.com
