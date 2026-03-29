# NestJS 통합 비교 — Module과 Service 구성

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [05편: 마이그레이션 비교](05-migrations.md)
> **시리즈**: Prisma vs TypeORM 비교 가이드 6/7

---

## 개요

NestJS에서 ORM을 사용하려면 Module과 Service를 구성해야 합니다.
TypeORM은 **공식 패키지**(`@nestjs/typeorm`)로 통합하고, Prisma는 **커스텀 모듈**로 통합합니다.
실제 NestJS 프로젝트에서 두 ORM을 셋업하는 전체 과정을 비교합니다.

---

## 아키텍처 비교

```
TypeORM + NestJS:                       Prisma + NestJS:
┌──────────────────────┐               ┌──────────────────────┐
│  AppModule           │               │  AppModule           │
│  ├─ TypeOrmModule    │               │  ├─ PrismaModule     │
│  │   .forRoot()      │               │  │   (@Global)       │
│  │                   │               │  │                   │
│  ├─ UserModule       │               │  ├─ UserModule       │
│  │  ├─ TypeOrmModule │               │  │  ├─ UserService   │
│  │  │  .forFeature() │               │  │  │  (PrismaService│
│  │  ├─ UserService   │               │  │  │   주입)         │
│  │  │  (Repository   │               │  │  └─ UserController│
│  │  │   주입)         │               │  └───────────────────┘
│  │  └─ UserController│               └──────────────────────┘
│  └───────────────────┘
└──────────────────────┘
```

---

## 설치

```bash
# TypeORM
npm install @nestjs/typeorm typeorm pg

# Prisma
npm install prisma --save-dev
npm install @prisma/client
npx prisma init
```

---

## TypeORM — NestJS 통합

### AppModule 설정

```typescript
// src/app.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { UserModule } from './user/user.module';

@Module({
  imports: [
    TypeOrmModule.forRoot({
      type: 'postgres',
      host: process.env.DB_HOST || 'localhost',
      port: 5432,
      username: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD,  // 환경변수에서 로드
      database: process.env.DB_NAME || 'blogdb',
      entities: [__dirname + '/**/*.entity{.ts,.js}'],
      synchronize: false,  // 운영에서는 반드시 false!
    }),
    UserModule,
  ],
})
export class AppModule {}
```

### Feature Module 설정

```typescript
// src/user/user.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { User } from '../entities/user.entity';
import { Post } from '../entities/post.entity';
import { UserService } from './user.service';
import { UserController } from './user.controller';

@Module({
  imports: [
    TypeOrmModule.forFeature([User, Post]),  // 사용할 Entity 등록
  ],
  providers: [UserService],
  controllers: [UserController],
})
export class UserModule {}
```

### Service 구현

```typescript
// src/user/user.service.ts
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User } from '../entities/user.entity';

@Injectable()
export class UserService {
  constructor(
    @InjectRepository(User)
    private userRepo: Repository<User>,  // Repository 주입
  ) {}

  async findAll(): Promise<User[]> {
    return this.userRepo.find({
      relations: ['posts'],
    });
  }

  async findOne(id: number): Promise<User | null> {
    return this.userRepo.findOne({
      where: { id },
      relations: ['posts'],
    });
  }

  async create(email: string, name: string): Promise<User> {
    const user = this.userRepo.create({ email, name });
    return this.userRepo.save(user);
  }
}
```

---

## Prisma — NestJS 통합

### PrismaService 생성

```typescript
// src/prisma/prisma.service.ts
import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  async onModuleInit() {
    await this.$connect();  // 앱 시작 시 DB 연결
  }

  async onModuleDestroy() {
    await this.$disconnect();  // 앱 종료 시 연결 해제
  }
}
```

### PrismaModule 생성

```typescript
// src/prisma/prisma.module.ts
import { Global, Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Global()  // 전역 모듈 — 어디서든 PrismaService 사용 가능
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
```

### AppModule 설정

```typescript
// src/app.module.ts
import { Module } from '@nestjs/common';
import { PrismaModule } from './prisma/prisma.module';
import { UserModule } from './user/user.module';

@Module({
  imports: [
    PrismaModule,  // 전역 등록 — 이것만으로 끝!
    UserModule,
  ],
})
export class AppModule {}
```

### Feature Module 설정

```typescript
// src/user/user.module.ts
import { Module } from '@nestjs/common';
import { UserService } from './user.service';
import { UserController } from './user.controller';

@Module({
  // PrismaModule이 @Global이므로 import 불필요!
  providers: [UserService],
  controllers: [UserController],
})
export class UserModule {}
```

### Service 구현

```typescript
// src/user/user.service.ts
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UserService {
  constructor(private prisma: PrismaService) {}  // 직접 주입!

  async findAll() {
    return this.prisma.user.findMany({
      include: { posts: true },
    });
  }

  async findOne(id: number) {
    return this.prisma.user.findUnique({
      where: { id },
      include: { posts: true },
    });
  }

  async create(email: string, name: string) {
    return this.prisma.user.create({
      data: { email, name },
    });
  }
}
```

---

## Controller (공통)

```typescript
// src/user/user.controller.ts — 양쪽 동일한 구조
import { Controller, Get, Post, Param, Body } from '@nestjs/common';
import { UserService } from './user.service';

@Controller('users')
export class UserController {
  constructor(private userService: UserService) {}

  @Get()
  findAll() {
    return this.userService.findAll();
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.userService.findOne(+id);
  }

  @Post()
  create(@Body() body: { email: string; name: string }) {
    return this.userService.create(body.email, body.name);
  }
}
```

> 💡 Controller 코드는 **양쪽 모두 동일**합니다.
> ORM 차이는 Service 레이어에만 영향을 미칩니다.

---

## 테스트 비교

### TypeORM 테스트

```typescript
// user.service.spec.ts
const mockUserRepo = {
  find: jest.fn().mockResolvedValue([mockUser]),
  findOne: jest.fn().mockResolvedValue(mockUser),
  create: jest.fn().mockReturnValue(mockUser),
  save: jest.fn().mockResolvedValue(mockUser),
};

const module = await Test.createTestingModule({
  providers: [
    UserService,
    { provide: getRepositoryToken(User), useValue: mockUserRepo },
  ],
}).compile();
```

### Prisma 테스트

```typescript
// user.service.spec.ts
const mockPrisma = {
  user: {
    findMany: jest.fn().mockResolvedValue([mockUser]),
    findUnique: jest.fn().mockResolvedValue(mockUser),
    create: jest.fn().mockResolvedValue(mockUser),
  },
};

const module = await Test.createTestingModule({
  providers: [
    UserService,
    { provide: PrismaService, useValue: mockPrisma },
  ],
}).compile();
```

---

## 통합 비교 표

| 항목 | TypeORM | Prisma |
|------|---------|--------|
| 패키지 | `@nestjs/typeorm` (공식) | `@prisma/client` + 커스텀 모듈 |
| 초기 설정 | `forRoot()` + `forFeature()` | PrismaModule (전역 1회) |
| DI 방식 | `@InjectRepository(Entity)` | `PrismaService` 직접 주입 |
| Module 등록 | 매 모듈마다 `forFeature()` | `@Global`로 한 번만 |
| 보일러플레이트 | 많음 | 적음 |
| 테스트 목킹 | `getRepositoryToken()` | 직접 mock 객체 |
| 연결 관리 | TypeORM 내부 관리 | `onModuleInit/Destroy` |

---

## 요약

- **TypeORM**: `@nestjs/typeorm` 공식 패키지, `forRoot()` + `forFeature()` 패턴, `@InjectRepository`
- **Prisma**: 커스텀 `PrismaModule` + `PrismaService`, `@Global`로 전역 등록, 직접 주입
- Prisma가 **보일러플레이트가 적고** Module 등록이 간단
- Controller 코드는 양쪽 **동일** — ORM 차이는 Service에만 영향
- TypeORM은 Entity마다 `forFeature()` 필요, Prisma는 전역 모듈 한 번으로 끝

---

## 다음 편 예고

시리즈 최종편! 두 ORM의 장단점을 종합 정리하고, 어떤 상황에서 어떤 ORM을 선택해야 하는지 실무 기준으로 가이드합니다.

→ **[07편: 실무 가이드 — 어떤 걸 선택할까?](07-practical-guide.md)**

---

## 참고 자료

- [NestJS TypeORM 공식 문서](https://docs.nestjs.com/techniques/database) — docs.nestjs.com
- [NestJS Prisma Recipe](https://docs.nestjs.com/recipes/prisma) — docs.nestjs.com
- [Prisma NestJS 통합 가이드](https://www.prisma.io/docs/orm/overview/databases/nestjs) — prisma.io
