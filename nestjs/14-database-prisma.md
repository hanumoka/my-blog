# Database 연동 — Prisma로 CRUD 구현

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [13편: 요청 라이프사이클](13-request-lifecycle.md)
> **시리즈**: NestJS 학습 가이드 14/15

---

## 개요

이론을 모두 마쳤으니, 이제 실제 데이터베이스와 연동합니다.
NestJS + **Prisma**를 사용해 User CRUD API를 처음부터 끝까지 구현합니다.
Spring Data JPA의 Repository 패턴과 비교합니다.

---

## 아키텍처 비교

```
NestJS + Prisma:                     Spring + JPA:
┌──────────────────┐                ┌──────────────────┐
│  UserController   │                │  UserController   │
│  (@Controller)    │                │  (@RestController) │
└────────┬─────────┘                └────────┬─────────┘
         │                                   │
┌────────▼─────────┐                ┌────────▼─────────┐
│  UserService      │                │  UserService      │
│  (@Injectable)    │                │  (@Service)       │
└────────┬─────────┘                └────────┬─────────┘
         │                                   │
┌────────▼─────────┐                ┌────────▼─────────┐
│  PrismaService    │                │  UserRepository   │
│  (Prisma Client)  │                │  (JpaRepository)  │
└────────┬─────────┘                └────────┬─────────┘
         │                                   │
    ┌────▼────┐                         ┌────▼────┐
    │   DB    │                         │   DB    │
    └─────────┘                         └─────────┘
```

---

## 1단계: 프로젝트 셋업

```bash
# NestJS 프로젝트 생성
nest new user-api
cd user-api

# Prisma 설치
npm install prisma --save-dev
npm install @prisma/client

# Prisma 초기화
npx prisma init
```

---

## 2단계: 스키마 정의

```prisma
// prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  name      String   @db.VarChar(100)
  role      Role     @default(USER)
  createdAt DateTime @default(now()) @map("created_at")
  updatedAt DateTime @updatedAt @map("updated_at")

  posts Post[]

  @@map("users")
}

model Post {
  id        Int      @id @default(autoincrement())
  title     String   @db.VarChar(255)
  content   String   @db.Text
  published Boolean  @default(false)
  createdAt DateTime @default(now()) @map("created_at")

  author   User @relation(fields: [authorId], references: [id])
  authorId Int  @map("author_id")

  @@map("posts")
}

enum Role {
  USER
  ADMIN
}
```

> **Spring에서는?**
> ```java
> @Entity
> @Table(name = "users")
> public class User {
>     @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
>     private Long id;
>     @Column(unique = true)
>     private String email;
>     @Column(length = 100)
>     private String name;
> }
> ```
> Prisma는 **schema.prisma 파일 하나**에 모든 모델을 선언합니다.

```bash
# .env 파일 설정
# DATABASE_URL="postgresql://YOUR_USER:YOUR_PASSWORD@localhost:5432/userdb"

# 마이그레이션 생성 + 적용
npx prisma migrate dev --name init

# Prisma Client 생성
npx prisma generate
```

---

## 3단계: PrismaModule 생성

```typescript
// src/prisma/prisma.service.ts
import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient
  implements OnModuleInit, OnModuleDestroy {
  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
```

```typescript
// src/prisma/prisma.module.ts
import { Global, Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
```

> **Spring에서는?**
> `spring-boot-starter-data-jpa`를 추가하면 DataSource가 자동 설정됩니다.
> NestJS에서는 PrismaModule을 직접 만들어야 합니다.

---

## 4단계: DTO 정의

```typescript
// src/user/dto/create-user.dto.ts
import { IsEmail, IsString, MinLength, IsEnum, IsOptional } from 'class-validator';

export class CreateUserDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(2)
  name: string;

  @IsEnum(['USER', 'ADMIN'])
  @IsOptional()
  role?: 'USER' | 'ADMIN';
}

// src/user/dto/update-user.dto.ts
import { IsString, MinLength, IsEnum, IsOptional } from 'class-validator';

export class UpdateUserDto {
  @IsString()
  @MinLength(2)
  @IsOptional()
  name?: string;

  @IsEnum(['USER', 'ADMIN'])
  @IsOptional()
  role?: 'USER' | 'ADMIN';
}
```

---

## 5단계: UserService 구현

```typescript
// src/user/user.service.ts
import { Injectable, NotFoundException, ConflictException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';

@Injectable()
export class UserService {
  constructor(private prisma: PrismaService) {}

  async create(dto: CreateUserDto) {
    const exists = await this.prisma.user.findUnique({
      where: { email: dto.email },
    });
    if (exists) {
      throw new ConflictException('이미 존재하는 이메일입니다');
    }

    return this.prisma.user.create({
      data: dto,
    });
  }

  async findAll() {
    return this.prisma.user.findMany({
      include: { posts: true },
    });
  }

  async findOne(id: number) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      include: { posts: true },
    });
    if (!user) {
      throw new NotFoundException(`ID ${id} 사용자를 찾을 수 없습니다`);
    }
    return user;
  }

  async update(id: number, dto: UpdateUserDto) {
    await this.findOne(id);  // 존재 여부 확인
    return this.prisma.user.update({
      where: { id },
      data: dto,
    });
  }

  async remove(id: number) {
    await this.findOne(id);
    return this.prisma.user.delete({
      where: { id },
    });
  }
}
```

> **Spring에서는?**
> ```java
> @Service
> public class UserService {
>     private final UserRepository userRepository;
>
>     public User create(CreateUserDto dto) {
>         if (userRepository.existsByEmail(dto.getEmail())) {
>             throw new ConflictException("이미 존재하는 이메일");
>         }
>         return userRepository.save(new User(dto));
>     }
>
>     public List<User> findAll() {
>         return userRepository.findAll();
>     }
> }
> ```
> Spring Data JPA는 `JpaRepository`의 메서드를 상속받고,
> Prisma는 Client API를 직접 호출합니다.

---

## 6단계: UserController 구현

```typescript
// src/user/user.controller.ts
import {
  Controller, Get, Post, Put, Delete,
  Body, Param, ParseIntPipe,
} from '@nestjs/common';
import { UserService } from './user.service';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';

@Controller('users')
export class UserController {
  constructor(private userService: UserService) {}

  @Post()
  create(@Body() dto: CreateUserDto) {
    return this.userService.create(dto);
  }

  @Get()
  findAll() {
    return this.userService.findAll();
  }

  @Get(':id')
  findOne(@Param('id', ParseIntPipe) id: number) {
    return this.userService.findOne(id);
  }

  @Put(':id')
  update(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateUserDto,
  ) {
    return this.userService.update(id, dto);
  }

  @Delete(':id')
  remove(@Param('id', ParseIntPipe) id: number) {
    return this.userService.remove(id);
  }
}
```

---

## 7단계: Module 연결 및 실행

```typescript
// src/user/user.module.ts
import { Module } from '@nestjs/common';
import { UserController } from './user.controller';
import { UserService } from './user.service';

@Module({
  controllers: [UserController],
  providers: [UserService],
})
export class UserModule {}
```

```typescript
// src/app.module.ts
import { Module } from '@nestjs/common';
import { PrismaModule } from './prisma/prisma.module';
import { UserModule } from './user/user.module';

@Module({
  imports: [PrismaModule, UserModule],
})
export class AppModule {}
```

```bash
# 서버 실행
npm run start:dev

# API 테스트
curl -X POST http://localhost:3000/users \
  -H "Content-Type: application/json" \
  -d '{"email":"hong@example.com","name":"홍길동"}'

curl http://localhost:3000/users
curl http://localhost:3000/users/1
```

---

## 요약

- **Prisma + NestJS**: PrismaModule(전역) + PrismaService(PrismaClient 확장) + Service에서 직접 사용
- Spring Data JPA의 `JpaRepository` 대신 **Prisma Client API**로 CRUD 수행
- 전체 흐름: Controller → Service → PrismaService → DB
- DTO + `ValidationPipe`로 입력 검증, `NotFoundException`/`ConflictException`으로 에러 처리
- `@Global()` 모듈로 PrismaService를 어디서든 주입 가능

---

## 다음 편 예고

시리즈 최종편! Spring 개발자가 NestJS로 실무 전환할 때 알아야 할 **실전 팁과 체크리스트**를 정리합니다.

→ **[15편: 실무 전환 가이드](15-practical-transition.md)**

---

## 참고 자료

- [NestJS Prisma Recipe 공식 문서](https://docs.nestjs.com/recipes/prisma) — docs.nestjs.com
- [Prisma CRUD 공식 문서](https://www.prisma.io/docs/orm/prisma-client/queries/crud) — prisma.io
- [Prisma NestJS 통합 가이드](https://www.prisma.io/docs/orm/overview/databases/nestjs) — prisma.io
