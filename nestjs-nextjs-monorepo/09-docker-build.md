# Docker 빌드 전략 — 모노리포의 멀티스테이지 Dockerfile

> **난이도**: 고급
> **소요 시간**: 약 3분
> **사전 지식**: [08편: 개발 환경 구성](08-dev-environment.md)
> **시리즈**: NestJS + Next.js + Prisma 모노리포 가이드 9/10

---

## 개요

모노리포를 Docker 이미지로 빌드할 때 가장 큰 문제는 **불필요한 파일**입니다.
전체 모노리포를 그대로 이미지에 담으면 수 GB가 될 수 있습니다.
`turbo prune` + 멀티스테이지 빌드로 **필요한 것만** 포함한 최소 이미지를 만드는 방법을 배웁니다.

---

## 핵심 개념 — turbo prune

```
문제: Docker build context에 전체 모노리포를 넣으면?
  my-monorepo/ (전체)     Docker image (backend용)
  ├── apps/backend/   →   apps/backend/ ✅ 필요
  ├── apps/frontend/  →   apps/frontend/ ❌ 불필요!
  ├── packages/*      →   packages/* (일부만 필요)
  └── node_modules/  →   모든 의존성 ❌ 낭비!

해결: turbo prune
  $ turbo prune @my-monorepo/backend --docker
  → out/
      ├── json/    (필요한 package.json만)
      └── full/    (필요한 소스 파일만)

  backend에 필요한 것만 정확히 추출!
```

---

## 실습

### 1단계: 멀티스테이지 Dockerfile — 백엔드

```dockerfile
# apps/backend/Dockerfile

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Stage 1: Prune — 필요한 파일만 추출
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FROM node:22-alpine AS pruner

# turbo 전역 설치
RUN npm install -g turbo@^2.8.0

WORKDIR /app

# 전체 모노리포 복사
COPY . .

# backend에 필요한 파일만 추출
RUN turbo prune @my-monorepo/backend --docker

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Stage 2: Install & Build
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FROM node:22-alpine AS builder

# pnpm 설치
RUN npm install -g pnpm@^10.0.0

WORKDIR /app

# pnpm workspace 설정 복사
COPY --from=pruner /app/out/json/ .
COPY --from=pruner /app/out/pnpm-lock.yaml ./pnpm-lock.yaml
COPY --from=pruner /app/out/pnpm-workspace.yaml ./pnpm-workspace.yaml

# 의존성 설치 (lockfile 기반으로 정확히)
RUN pnpm install --frozen-lockfile

# 소스 복사 (의존성 이후에 복사해야 캐시 효율 극대화)
COPY --from=pruner /app/out/full/ .

# Prisma 클라이언트 생성
RUN pnpm --filter @my-monorepo/database generate

# 빌드
RUN pnpm --filter @my-monorepo/backend build

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Stage 3: Production
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FROM node:22-alpine AS runner

# 보안: root가 아닌 node 사용자로 실행
RUN addgroup -S -g 1001 nodejs
RUN adduser -S -u 1001 nestjs

WORKDIR /app

# pnpm 설치 (production 의존성 설치용)
RUN npm install -g pnpm@^10.0.0

# production 의존성만 설치 (pruner의 package.json들 재사용)
COPY --from=pruner /app/out/json/ .
COPY --from=pruner /app/out/pnpm-lock.yaml ./pnpm-lock.yaml
COPY --from=pruner /app/out/pnpm-workspace.yaml ./pnpm-workspace.yaml
RUN pnpm install --frozen-lockfile --prod

# 빌드 결과물 복사
COPY --from=builder /app/apps/backend/dist ./apps/backend/dist

# Prisma 파일 복사 (마이그레이션 + 생성된 클라이언트)
COPY --from=builder /app/packages/database/prisma ./packages/database/prisma
COPY --from=builder /app/packages/database/src/generated ./packages/database/src/generated

USER nestjs

EXPOSE 3001

CMD ["node", "apps/backend/dist/main.js"]
```

### 2단계: 멀티스테이지 Dockerfile — 프론트엔드

```dockerfile
# apps/frontend/Dockerfile

# Stage 1: Prune
FROM node:22-alpine AS pruner
RUN npm install -g turbo@^2.8.0
WORKDIR /app
COPY . .
RUN turbo prune @my-monorepo/frontend --docker

# Stage 2: Install & Build
FROM node:22-alpine AS builder
RUN npm install -g pnpm@^10.0.0
WORKDIR /app

COPY --from=pruner /app/out/json/ .
COPY --from=pruner /app/out/pnpm-lock.yaml ./pnpm-lock.yaml
COPY --from=pruner /app/out/pnpm-workspace.yaml ./pnpm-workspace.yaml
RUN pnpm install --frozen-lockfile

COPY --from=pruner /app/out/full/ .

# Next.js 빌드 시 필요한 환경변수
ARG BACKEND_URL=http://backend:3001
ENV BACKEND_URL=$BACKEND_URL
ENV NEXT_TELEMETRY_DISABLED=1

RUN pnpm --filter @my-monorepo/frontend build

# Stage 3: Production (Next.js standalone)
FROM node:22-alpine AS runner

RUN addgroup -S -g 1001 nodejs
RUN adduser -S -u 1001 -G nodejs nextjs

WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Next.js standalone 모드 결과물 복사
COPY --from=builder /app/apps/frontend/.next/standalone ./
COPY --from=builder /app/apps/frontend/.next/static ./apps/frontend/.next/static
COPY --from=builder /app/apps/frontend/public ./apps/frontend/public

USER nextjs

EXPOSE 3000

CMD ["node", "apps/frontend/server.js"]
```

> 💡 Next.js standalone 모드 활성화 (`next.config.ts`에 추가):
> ```typescript
> const nextConfig: NextConfig = {
>   output: 'standalone',
>   // ...
> };
> ```

### 3단계: .dockerignore 설정

```dockerignore
# .dockerignore (루트에 생성)
node_modules/
.next/
dist/
.turbo/
.git/
*.env
*.env.local
*.md
.vscode/
infra/
```

### 4단계: 이미지 빌드

```bash
# 루트에서 실행 (전체 모노리포를 build context로 전달)

# 백엔드 이미지 빌드
docker build -f apps/backend/Dockerfile -t my-monorepo/backend:latest .

# 프론트엔드 이미지 빌드
docker build -f apps/frontend/Dockerfile \
  --build-arg BACKEND_URL=http://backend:3001 \
  -t my-monorepo/frontend:latest .
```

> ⚠️ Docker build는 **반드시 루트 디렉토리**에서 실행해야 합니다.
> `turbo prune`이 루트의 전체 모노리포에 접근해야 하기 때문입니다.

### 5단계: 프로덕션 docker-compose

```yaml
# infra/prod/docker-compose.yml
services:
  backend:
    image: my-monorepo/backend:latest
    container_name: backend
    environment:
      NODE_ENV: production
      DATABASE_URL: ${DATABASE_URL}
      REDIS_URL: ${REDIS_URL}
      FRONTEND_URL: ${FRONTEND_URL}
    ports:
      - "3001:3001"
    depends_on:
      postgres:
        condition: service_healthy

  frontend:
    image: my-monorepo/frontend:latest
    container_name: frontend
    environment:
      NODE_ENV: production
      BACKEND_URL: http://backend:3001
    ports:
      - "3000:3000"
    depends_on:
      - backend

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

---

## 이미지 크기 비교

```
최적화 전 (단순 COPY 빌드):
  backend image: ~1.2 GB
  frontend image: ~800 MB

최적화 후 (turbo prune + 멀티스테이지):
  backend image: ~180 MB
  frontend image: ~120 MB

약 6~8배 감소!
```

---

## 요약

- `turbo prune --docker`로 특정 앱에 필요한 파일만 추출 (불필요한 앱 제외)
- 멀티스테이지 빌드 3단계: Prune → Install+Build → Production
- 의존성 설치(`COPY json/ + pnpm install`) 후 소스 복사 → 레이어 캐시 극대화
- Next.js `output: 'standalone'` 모드로 production 이미지 최소화
- Docker build는 항상 **모노리포 루트**에서 실행

---

## 다음 편 예고

모노리포 운영의 모범 사례와 CI/CD, 의존성 관리, 트러블슈팅을 정리합니다.

→ **[10편: 모범 사례와 운영 가이드](10-best-practices.md)**

---

## 참고 자료

- [Turborepo Docker 공식 가이드](https://turbo.build/repo/docs/guides/tools/docker) — turbo.build
- [Next.js standalone 모드](https://nextjs.org/docs/app/api-reference/next-config-js/output) — nextjs.org
- [Docker 멀티스테이지 빌드](https://docs.docker.com/build/guide/multi-stage/) — docs.docker.com
