# 네트워크 이해하기 — Overlay, Ingress, 서비스 디스커버리

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [03편: 서비스 기초](03-service-basics.md)
> **시리즈**: Docker Swarm 학습 가이드 4/11

---

## 개요

서비스들이 서로 통신하려면 네트워크가 필요합니다.
Swarm에는 **Overlay 네트워크**와 **Ingress 네트워크** 두 가지가 핵심입니다.
이 편에서는 두 네트워크의 차이와 서비스 간 DNS 통신 방법을 배웁니다.

---

## Swarm 네트워크 전체 구조

```
외부 클라이언트
      │
      ▼ :8080
┌─────────────────────────────────────────────────────┐
│                  ingress 네트워크                    │
│  (자동 생성 — 외부 → 내부 로드밸런싱)                 │
│                                                     │
│   manager1:80   worker1:80   worker2:80             │
│       │              │            │                 │
└───────┼──────────────┼────────────┼─────────────────┘
        │              │            │
┌───────┼──────────────┼────────────┼─────────────────┐
│                  my-overlay 네트워크                 │
│  (직접 생성 — 서비스 간 내부 통신)                    │
│                                                     │
│  ┌──────────┐     ┌──────────┐  ┌──────────┐       │
│  │frontend  │────▶│ backend  │  │  redis   │       │
│  │ :3000    │     │  :8000   │  │  :6379   │       │
│  └──────────┘     └──────────┘  └──────────┘       │
└─────────────────────────────────────────────────────┘
```

---

## 1. Ingress 네트워크 (자동 생성)

### Ingress란?

Ingress는 **"외부에서 내부로 들어오는 트래픽"**을 뜻하는 네트워크 용어다. 반대로 내부에서 외부로 나가는 트래픽은 **Egress**라고 한다.

```
  외부 (인터넷, 클라이언트)
    │
    │  Ingress = 들어오는 트래픽 (inbound)
    ▼
  ┌─────────────────────────┐
  │      Swarm 클러스터       │
  └─────────────────────────┘
    │
    │  Egress = 나가는 트래픽 (outbound)
    ▼
  외부 API, DB 등
```

Docker Swarm에서 `ingress`는 이 **인바운드 트래픽을 받아서 적절한 컨테이너로 전달하는 자동 네트워크**다. `docker swarm init`을 하면 자동으로 생성되며, 별도 설정 없이 동작한다.

**역할**: 외부 트래픽을 클러스터 내 어느 노드로든 전달하는 **라우팅 메시(Routing Mesh)**

```
외부 요청 → :8080 (어느 노드든)
    │
    ▼
  ingress 네트워크가 로드밸런싱
    │          │          │
    ▼          ▼          ▼
  Task1      Task2      Task3
(manager1) (worker1)  (worker2)
```

> 💡 **핵심**: `worker2`에 Task가 없어도 `worker2:8080`으로 접근하면 동작합니다.
> Ingress 네트워크가 자동으로 Task가 있는 노드로 전달합니다.

---

### Ingress의 동작 원리 — Routing Mesh

```
서비스: nginx (replicas=2, port 8080:80)
Task는 node-2, node-3에만 있음

  외부 클라이언트
    │
    │ http://any-node:8080
    ▼
  ┌──────────────────────────────────────────────────────────┐
  │                    ingress 네트워크                        │
  │              (모든 노드가 8080을 리스닝)                    │
  │                                                          │
  │   node-1              node-2              node-3          │
  │  ┌──────────┐       ┌──────────┐       ┌──────────┐      │
  │  │ :8080    │       │ :8080    │       │ :8080    │      │
  │  │ [IPVS]   │       │ [IPVS]  │       │ [IPVS]  │      │
  │  │ Task 없음 │       │ [nginx] │       │ [nginx] │      │
  │  └────┬─────┘       └──────────┘       └──────────┘      │
  │       │                                                  │
  │       └──── IPVS가 node-2 또는 node-3으로 전달 ──────▶   │
  └──────────────────────────────────────────────────────────┘
```

동작 단계:

1. `docker service create -p 8080:80 nginx` → Swarm이 **모든 노드**에서 8080 포트를 열음
2. 외부 요청이 node-1:8080으로 도착 → node-1에는 nginx Task가 없음
3. node-1의 IPVS(커널 로드밸런서)가 ingress 네트워크를 통해 Task가 있는 node-2 또는 node-3으로 전달
4. nginx가 응답 → 같은 경로로 클라이언트에게 반환

> Ingress는 별도 Task/컨테이너가 아니라 **Docker Engine에 내장된 커널 레벨(IPVS) 기능**이다. 설치나 설정 없이 자동으로 동작한다.

### Ingress는 L4 — 포트 기반만 가능

Swarm Ingress는 **L4(포트 기반)** 로드밸런서다. 포트 번호로만 서비스를 구분한다.

```
Ingress로 할 수 있는 것:
  :8080 → nginx 서비스         ✅ 포트 기반 라우팅
  :3000 → react 서비스          ✅ 다른 포트, 다른 서비스

Ingress로 할 수 없는 것:
  api.example.com → API 서비스   ❌ 도메인 기반 라우팅
  /api/* → backend               ❌ URL 경로 기반 라우팅
  SSL 인증서 → HTTPS 종료        ❌ TLS termination
```

그래서 실무에서는 Swarm Ingress **앞에** 리버스 프록시를 둔다:

```
실무 구성:

  클라이언트
    │
    ▼
  ┌──────────────────────────────────┐
  │  nginx / traefik (리버스 프록시)   │  ← L7 라우팅 + SSL 처리
  │                                  │
  │  api.example.com → :8001         │
  │  web.example.com → :8002         │
  │  SSL 인증서 관리                   │
  └──────────┬───────────────────────┘
             │
  ┌──────────▼───────────────────────┐
  │  Swarm Ingress (L4)              │  ← 포트별 Task 분배
  │  :8001 → api-service             │
  │  :8002 → web-service             │
  └──────────────────────────────────┘
```

### Docker Swarm Ingress vs Kubernetes Ingress

이름은 같지만 **완전히 다른 개념**이다.

| 항목 | Docker Swarm Ingress | Kubernetes Ingress |
|------|---------------------|-------------------|
| **동작 계층** | L4 (TCP/UDP 포트) | L7 (HTTP 도메인/경로) |
| **설치** | 자동 (`swarm init` 시 생성) | 별도 Ingress Controller 설치 필요 |
| **라우팅 기준** | **포트 번호**만 | 도메인, URL 경로, 헤더 등 |
| **설정** | `-p 8080:80`이면 끝 | YAML로 Ingress 리소스 정의 |
| **SSL 종료** | 지원 안 함 (별도 리버스 프록시 필요) | Ingress Controller에서 처리 |
| **구현체** | Docker Engine 내장 IPVS | nginx, traefik, HAProxy 등 선택 |

```yaml
# Kubernetes Ingress 리소스 예시 (Swarm에는 이런 개념 자체가 없음)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
spec:
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
  - host: web.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 3000
```

정리하면:

- **Docker Swarm Ingress** = "어떤 노드로 요청해도 알아서 Task로 보내주는 **자동 포트 라우터**" (L4, 설정 불필요)
- **Kubernetes Ingress** = "도메인/경로별로 트래픽을 분배하는 **설정 가능한 HTTP 라우터**" (L7, Controller 설치 필요)

---

## 2. Overlay 네트워크 (직접 생성)

서비스 간 내부 통신을 위한 네트워크입니다.
물리적으로 다른 서버에 있는 컨테이너들이 같은 네트워크에 있는 것처럼 통신합니다.

```bash
# Overlay 네트워크 생성
docker network create \
  --driver overlay \
  --attachable \
  my-app-network

# 생성된 네트워크 확인
docker network ls
# DRIVER 컬럼에 overlay 표시
```

---

## 3. 서비스 디스커버리 (DNS)

같은 Overlay 네트워크에 있는 서비스는 **서비스 이름**으로 통신합니다.
IP를 외울 필요 없이 `http://backend:8000` 처럼 이름으로 접근합니다.

```
frontend 서비스에서:
  curl http://backend:8000/api    ← "backend"는 서비스 이름
  redis.connect("redis", 6379)    ← "redis"는 서비스 이름

  Swarm 내부 DNS가 자동으로
  "backend" → 172.18.0.X 로 변환
```

---

## 실습: 프론트엔드 + 백엔드 서비스 연결

```bash
# Step 1: Overlay 네트워크 생성
docker network create \
  --driver overlay \
  my-app-network

# Step 2: 백엔드 서비스 배포 (외부 노출 없음)
docker service create \
  --name backend \
  --network my-app-network \
  --replicas 2 \
  nginx

# Step 3: 프론트엔드 서비스 배포 (외부 포트 노출)
docker service create \
  --name frontend \
  --network my-app-network \
  --replicas 2 \
  --publish published=8080,target=80 \
  nginx

# Step 4: 네트워크 확인
docker network inspect my-app-network

# Step 5: 프론트엔드 컨테이너 내부에서 백엔드로 DNS 통신 확인
docker exec -it $(docker ps -q -f name=frontend) \
  curl http://backend:80
```

---

## 로드밸런싱: VIP vs DNSRR

Swarm 서비스에는 두 가지 내부 로드밸런싱 방식이 있습니다.

```
VIP (기본값):                    DNS Round Robin:
  "backend" → 가상 IP            "backend" → Task IP들을 순서대로
  가상 IP가 Task로 분산           클라이언트가 직접 선택
  ┌──────────────────┐           ┌──────────────────┐
  │  backend VIP     │           │  DNS 조회 결과:  │
  │  10.0.0.5 (가상) │           │  172.18.0.2      │
  │     ↙    ↘      │           │  172.18.0.3      │
  │ Task1   Task2   │           │  172.18.0.4      │
  └──────────────────┘           └──────────────────┘
```

```bash
# DNS Round Robin 방식으로 서비스 생성
docker service create \
  --name my-service \
  --endpoint-mode dnsrr \
  --network my-app-network \
  nginx
```

> 💡 **실무 팁**: 대부분의 경우 기본값 VIP를 사용하세요.
> DNSRR은 클라이언트가 DNS TTL을 잘 처리할 때만 안정적입니다.

---

## 암호화된 Overlay 네트워크

민감한 서비스 간 통신은 암호화할 수 있습니다.

```bash
docker network create \
  --driver overlay \
  --opt encrypted \
  secure-network
```

> ⚠️ `--opt encrypted` 사용 시 IPSec ESP(IP Protocol 50) 포트도 허용해야 합니다.

---

## 요약

- **Ingress 네트워크**: 자동 생성, 외부 → 내부 라우팅 메시 (어느 노드로 와도 OK)
- **Overlay 네트워크**: 직접 생성, 서비스 간 내부 통신용
- **서비스 디스커버리**: 서비스 이름 = DNS 이름 (IP 없이 통신)
- **VIP** (기본): Swarm이 로드밸런싱 / **DNSRR**: DNS가 IP 목록 반환
- `--opt encrypted`로 네트워크 트래픽 암호화 가능

---

## 다음 편 예고

서비스를 하나씩 만드는 건 번거롭습니다.
Docker Compose 파일로 여러 서비스를 한 번에 배포하는 **Stack** 기능을 배웁니다.

→ **[05편: Stack과 Compose 파일](05-stack-and-compose.md)**

---

## 참고 자료

- [Overlay 네트워크 공식 문서](https://docs.docker.com/engine/swarm/networking/) — docs.docker.com
- [Swarm 서비스 디스커버리](https://docs.docker.com/engine/swarm/key-concepts/) — docs.docker.com
