# 개발 환경 구성 — Docker Compose로 DB와 Redis 셋업

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [07편: 타입 안전한 API 통신](07-type-sharing.md)
> **시리즈**: NestJS + Next.js + Prisma 모노리포 가이드 8/10

---

## 개요

개발 환경에서 PostgreSQL과 Redis를 Docker Compose로 띄우는 방법을 배웁니다.
로컬 PC에 직접 DB를 설치하지 않고, Docker로 깔끔하게 관리합니다.
팀원 모두가 `docker compose up` 하나로 동일한 환경을 구축할 수 있습니다.

---

## 핵심 개념 — 개발 인프라 구성

```
로컬 개발 환경 전체 그림:

┌──────────────────────────────────────────────────┐
│                  로컬 머신                        │
│                                                  │
│  터미널 1: pnpm dev (앱들 실행)                  │
│    ├─ apps/backend  → localhost:3001             │
│    └─ apps/frontend → localhost:3000             │
│                                                  │
│  터미널 2: docker compose up (인프라 실행)       │
│    ├─ PostgreSQL    → localhost:5432             │
│    └─ Redis         → localhost:6379             │
│                                                  │
│  앱 ─────────────────────→ DB/Redis              │
│         (DATABASE_URL / REDIS_URL)               │
└──────────────────────────────────────────────────┘
```

---

## 실습

### 1단계: 인프라 폴더 구성

```bash
# 루트에서
mkdir -p infra/local
```

```
my-monorepo/
├── apps/
├── packages/
├── infra/
│   └── local/
│       ├── docker-compose.yml
│       └── .env              ← 로컬 전용 환경변수
└── ...
```

### 2단계: Docker Compose 파일 작성

```yaml
# infra/local/docker-compose.yml
services:
  postgres:
    image: postgres:16-alpine
    container_name: my-monorepo-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-YOUR_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB:-mydb}
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-postgres}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: my-monorepo-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD:-YOUR_REDIS_PASSWORD}
    ports:
      - "${REDIS_PORT:-6379}:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD:-YOUR_REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

volumes:
  postgres_data:
  redis_data:
```

> ⚠️ `${VAR:-default}` 문법: 환경변수가 없으면 기본값 사용.
> 비밀번호 기본값은 예시이며, 실제로는 `.env` 파일에 직접 설정하세요.

### 3단계: 환경변수 파일

```bash
# infra/local/.env (Git에 커밋하지 마세요!)
POSTGRES_USER=postgres
POSTGRES_PASSWORD=YOUR_LOCAL_PASSWORD
POSTGRES_DB=mydb
POSTGRES_PORT=5432

REDIS_PASSWORD=YOUR_LOCAL_REDIS_PASSWORD
REDIS_PORT=6379
```

```bash
# infra/local/.gitignore
.env
```

### 4단계: 각 앱의 환경변수 설정

```bash
# packages/database/.env
DATABASE_URL="postgresql://postgres:YOUR_LOCAL_PASSWORD@localhost:5432/mydb?schema=public"

# apps/backend/.env
DATABASE_URL="postgresql://postgres:YOUR_LOCAL_PASSWORD@localhost:5432/mydb?schema=public"
REDIS_URL="redis://:YOUR_LOCAL_REDIS_PASSWORD@localhost:6379"
PORT=3001
FRONTEND_URL=http://localhost:3000
NODE_ENV=development

# apps/frontend/.env.local
BACKEND_URL=http://localhost:3001
NODE_ENV=development
```

### 5단계: 루트 package.json에 편의 스크립트 추가

```json
// package.json (루트)
{
  "scripts": {
    "dev": "turbo run dev",
    "build": "turbo run build",
    "infra:up": "docker compose -f infra/local/docker-compose.yml up -d",
    "infra:down": "docker compose -f infra/local/docker-compose.yml down",
    "infra:logs": "docker compose -f infra/local/docker-compose.yml logs -f",
    "db:migrate": "pnpm --filter @my-monorepo/database db:migrate",
    "db:generate": "pnpm --filter @my-monorepo/database generate",
    "db:studio": "pnpm --filter @my-monorepo/database db:studio",
    "db:seed": "pnpm --filter @my-monorepo/database db:seed"
  }
}
```

### 6단계: 개발 시작 순서

```bash
# 1. 인프라 실행 (DB + Redis)
pnpm infra:up

# 2. DB 마이그레이션 (처음 실행 시)
pnpm db:migrate

# 3. (선택) 시드 데이터 삽입
pnpm db:seed

# 4. 앱 실행
pnpm dev
```

### 7단계: 시드 데이터 스크립트

```typescript
// packages/database/prisma/seed.ts
import { PrismaClient } from '../src/generated/prisma';

const prisma = new PrismaClient();

async function main() {
  // 기존 데이터 정리
  await prisma.post.deleteMany();
  await prisma.user.deleteMany();

  // 테스트 유저 생성
  const admin = await prisma.user.create({
    data: {
      email: 'admin@example.com',
      name: '관리자',
      password: 'hashed_password_here',  // 실제로는 bcrypt 해시
      role: 'ADMIN',
    },
  });

  const user = await prisma.user.create({
    data: {
      email: 'user@example.com',
      name: '일반 사용자',
      password: 'hashed_password_here',
      role: 'USER',
      posts: {
        create: [
          { title: '첫 번째 포스트', content: '내용입니다.', published: true },
          { title: '두 번째 포스트', content: '초안입니다.', published: false },
        ],
      },
    },
  });

  console.log('Seed 완료:', { admin, user });
}

main()
  .catch(console.error)
  .finally(() => prisma.$disconnect());
```

```json
// packages/database/package.json에 추가
{
  "prisma": {
    "seed": "ts-node prisma/seed.ts"
  }
}
```

---

## 컨테이너 상태 확인

```bash
# 실행 중인 컨테이너 확인
docker ps

# PostgreSQL 접속 테스트
docker exec -it my-monorepo-postgres psql -U postgres -d mydb

# Redis 접속 테스트
docker exec -it my-monorepo-redis redis-cli -a YOUR_LOCAL_REDIS_PASSWORD ping
# → PONG

# 로그 확인
pnpm infra:logs
```

---

## 요약

- `infra/local/docker-compose.yml`에 PostgreSQL 16 + Redis 7 설정
- `${VAR:-default}` 문법으로 환경변수 기반 유연한 설정
- 루트 `package.json`에 `infra:up/down`, `db:migrate` 스크립트 통합
- 각 앱의 `.env`에 `DATABASE_URL`, `REDIS_URL` 설정 (Git 커밋 금지!)
- 시드 스크립트로 개발용 초기 데이터 자동 삽입

---

## 다음 편 예고

모노리포를 Docker 이미지로 빌드하는 멀티스테이지 Dockerfile 전략을 배웁니다.

→ **[09편: Docker 빌드 전략](09-docker-build.md)**

---

## 참고 자료

- [Docker Compose 공식 문서](https://docs.docker.com/compose/) — docs.docker.com
- [Prisma Seeding 공식 문서](https://www.prisma.io/docs/guides/database/seed-database) — prisma.io
- [PostgreSQL Docker Hub](https://hub.docker.com/_/postgres) — hub.docker.com
