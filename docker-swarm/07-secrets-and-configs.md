# Secrets & Configs — 민감 데이터를 안전하게 관리하기

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [06편: 데이터 영속성 관리](06-volumes-and-data.md)
> **시리즈**: Docker Swarm 학습 가이드 7/11

---

## 개요

비밀번호, API 키, 인증서를 환경변수로 넘기면 `docker inspect`로 노출됩니다.
Swarm의 **Secret**과 **Config**는 이 문제를 해결합니다.
이 편에서는 두 기능의 차이와 실무 적용 방법을 배웁니다.

---

## 왜 환경변수 방식이 위험한가?

```bash
# ❌ 위험한 방식
docker service create \
  --env MYSQL_ROOT_PASSWORD=YOUR_SECRET_PASSWORD \
  mysql:8.0

# 누구나 볼 수 있음!
docker inspect <container_id>
# → "MYSQL_ROOT_PASSWORD=YOUR_SECRET_PASSWORD" 노출 😱
```

---

## Secret vs Config 비교

```
┌──────────────────┬──────────────────────────────────────┐
│                  │  Secret          Config               │
├──────────────────┼──────────────────────────────────────┤
│ 용도             │  비밀번호, 키    설정 파일, 비민감 값  │
│ 저장 위치        │  Manager 암호화 │ Manager 일반 저장   │
│ 전송 방식        │  TLS 암호화     │ TLS 전송            │
│ 컨테이너 내 위치 │  /run/secrets/  │ /run/configs/       │
│ 메모리 저장      │  tmpfs (RAM)    │ tmpfs (RAM)         │
│ 수정 가능        │  불가 (재생성)  │ 불가 (재생성)       │
└──────────────────┴──────────────────────────────────────┘
```

---

## Secret 사용하기

### Secret 생성

```bash
# 방법 1: 파일로 생성
echo "YOUR_SECRET_PASSWORD" | docker secret create db_password -

# 방법 2: 파일에서 생성
echo -n "YOUR_SECRET_PASSWORD" > db_password.txt
docker secret create db_password db_password.txt
rm db_password.txt   # 원본 파일 즉시 삭제!

# Secret 목록 확인
docker secret ls

# Secret 상세 정보 (값은 조회 불가!)
docker secret inspect db_password
```

### 서비스에 Secret 연결

```bash
docker service create \
  --name mysql \
  --secret db_password \
  --env MYSQL_ROOT_PASSWORD_FILE=/run/secrets/db_password \
  mysql:8.0
```

> 💡 MySQL은 `_FILE` 접미사 환경변수를 지원합니다.
> 파일 경로를 환경변수로 넘기고, 앱이 파일을 직접 읽습니다.

### 컨테이너 내부에서 확인

```bash
# 컨테이너 내부에서
cat /run/secrets/db_password
# → YOUR_SECRET_PASSWORD
# (tmpfs에 마운트됨 — 디스크에 저장 안 됨)
```

---

## Config 사용하기

```bash
# nginx 설정 파일을 Config로 등록
docker config create nginx_conf ./nginx.conf

# 서비스에 Config 연결
docker service create \
  --name my-nginx \
  --config source=nginx_conf,target=/etc/nginx/nginx.conf \
  nginx

# Config 목록
docker config ls
```

---

## 실습: Compose 파일에서 Secrets + Config 사용

```yaml
# secure-stack.yml
version: "3.9"

services:
  db:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD_FILE: /run/secrets/db_root_password
      MYSQL_PASSWORD_FILE: /run/secrets/db_user_password
      MYSQL_DATABASE: appdb
      MYSQL_USER: appuser
    secrets:
      - db_root_password
      - db_user_password
    networks:
      - app-network
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.labels.db == true

  app:
    image: my-app:latest
    environment:
      DB_HOST: db
      DB_PASSWORD_FILE: /run/secrets/db_user_password
    secrets:
      - db_user_password
    configs:
      - source: app_config
        target: /app/config.yml
    networks:
      - app-network
    deploy:
      replicas: 3

secrets:
  db_root_password:
    external: true    # 미리 생성된 Secret 사용
  db_user_password:
    external: true

configs:
  app_config:
    external: true

networks:
  app-network:
    driver: overlay
```

**배포 전 Secret/Config 생성**:

```bash
# Secret 생성
echo "YOUR_ROOT_PASSWORD" | docker secret create db_root_password -
echo "YOUR_APP_PASSWORD"  | docker secret create db_user_password -

# Config 생성
docker config create app_config ./config.yml

# Stack 배포
docker stack deploy -c secure-stack.yml myapp
```

---

## Secret 교체 방법

Secret은 수정이 불가능합니다. 새 버전을 만들고 서비스를 업데이트합니다.

```bash
# 1. 새 Secret 생성 (v2)
echo "YOUR_NEW_SECRET_PASSWORD" | docker secret create db_password_v2 -

# 2. 서비스에서 이전 Secret 제거 + 새 Secret 추가
docker service update \
  --secret-rm db_password \
  --secret-add db_password_v2 \
  mysql

# 3. 이전 Secret 삭제
docker secret rm db_password
```

---

## 실무 보안 팁

```
✅ Secret 관리 체크리스트:

  [ ] Secret 파일 생성 후 즉시 삭제
  [ ] .gitignore에 Secret 파일 경로 추가
  [ ] Secret 이름에 버전 포함 (db_password_v1)
  [ ] _FILE 환경변수 패턴 사용 (직접 값 노출 금지)
  [ ] 정기적인 Secret 로테이션 (보안 정책)
  [ ] docker secret ls로 불필요한 Secret 정리
```

---

## 요약

- **Secret**: 비밀번호/키 저장 — 암호화, tmpfs 마운트, `/run/secrets/`
- **Config**: 설정 파일 저장 — tmpfs 마운트, `/run/configs/`
- `_FILE` 환경변수 패턴으로 앱에 Secret 경로 전달
- Secret/Config는 수정 불가 → 새 버전 생성 후 서비스 업데이트
- Compose 파일에서 `external: true`로 미리 생성된 Secret 참조

---

## 다음 편 예고

서비스를 중단 없이 새 버전으로 업데이트하는 **롤링 업데이트**와 문제 발생 시 **롤백** 방법을 배웁니다.

→ **[08편: 롤링 업데이트와 롤백](08-rolling-update.md)**

---

## 참고 자료

- [Docker Secrets 공식 문서](https://docs.docker.com/engine/swarm/secrets/) — docs.docker.com
- [Docker Configs 공식 문서](https://docs.docker.com/engine/swarm/configs/) — docs.docker.com
