# Filer REST API 실습 — 경로 기반 파일 관리 완전 정복

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [03편: Docker로 로컬 환경 구축](03-docker-setup.md)
> **시리즈**: Spring Boot + SeaweedFS 학습 가이드 4/10

---

## 개요

Filer는 SeaweedFS에서 가장 자주 사용하는 인터페이스입니다.
HTTP REST API로 파일을 업로드/다운로드하고, 디렉토리를 관리하고, 파일에 태그를 붙이는 등 풍부한 기능을 제공합니다.
이번 편에서는 Filer REST API를 체계적으로 실습합니다.
(03편의 Docker 환경이 실행 중이어야 합니다.)

---

## API 기본 구조

```
Filer REST API 엔드포인트:

  http://localhost:8888/{경로}

  메서드별 동작:
  ┌────────┬───────────────────────────────────────────┐
  │ PUT    │ 파일 업로드 (경로에 파일 생성/덮어쓰기)     │
  │ GET    │ 파일 다운로드 또는 디렉토리 목록 조회        │
  │ DELETE │ 파일 또는 디렉토리 삭제                     │
  └────────┴───────────────────────────────────────────┘

  경로 규칙:
  /path/to/file.jpg  ← 파일 (끝에 슬래시 없음)
  /path/to/dir/      ← 디렉토리 (끝에 슬래시 있음)
```

---

## 실습 1: 파일 업로드

### 기본 업로드

```bash
# 텍스트 파일 업로드
echo "안녕하세요, SeaweedFS!" > greeting.txt

curl -X PUT \
  -F "file=@greeting.txt" \
  "http://localhost:8888/documents/greeting.txt"
```

응답:

```json
{
  "name": "greeting.txt",
  "size": 31
}
```

### 여러 파일 업로드

```bash
# 이미지 업로드
curl -X PUT \
  -F "file=@profile.jpg" \
  "http://localhost:8888/images/users/profile.jpg"

# PDF 업로드
curl -X PUT \
  -F "file=@report.pdf" \
  "http://localhost:8888/documents/2026/report.pdf"
```

### Content-Type 지정 업로드

```bash
curl -X PUT \
  -H "Content-Type: image/jpeg" \
  --data-binary "@photo.jpg" \
  "http://localhost:8888/photos/photo.jpg"
```

> 💡 `-F "file=@..."` 방식(multipart/form-data)과 `--data-binary`(raw binary) 방식 모두 지원합니다.
> Spring에서는 주로 multipart 방식을 사용합니다.

---

## 실습 2: 파일 다운로드

```bash
# 파일 다운로드
curl "http://localhost:8888/documents/greeting.txt"
# 안녕하세요, SeaweedFS!

# 파일을 로컬에 저장
curl -o downloaded.txt "http://localhost:8888/documents/greeting.txt"

# 파일 정보만 확인 (HEAD 요청)
curl -I "http://localhost:8888/documents/greeting.txt"
```

HEAD 응답 헤더:

```
HTTP/1.1 200 OK
Content-Disposition: inline; filename="greeting.txt"
Content-Length: 31
Content-Type: text/plain; charset=utf-8
Last-Modified: Sun, 29 Mar 2026 10:00:00 GMT
Seaweedfs-File-Id: 3,01637037d6
```

> 💡 `Seaweedfs-File-Id` 헤더로 파일의 실제 FID를 확인할 수 있습니다.

---

## 실습 3: 디렉토리 관리

### 디렉토리 목록 조회

```bash
# 기본 목록 (JSON)
curl "http://localhost:8888/documents/?pretty=y"
```

응답:

```json
{
  "Path": "/documents",
  "Entries": [
    {
      "FullPath": "/documents/greeting.txt",
      "Crtime": 1711708800,
      "Mtime": 1711708800,
      "FileSize": 31,
      "Mime": "text/plain; charset=utf-8",
      "Uid": 0,
      "Gid": 0,
      "Replication": "",
      "Collection": "",
      "TtlSec": 0,
      "UserName": "",
      "GroupNames": null,
      "SymlinkTarget": "",
      "Md5": "abc123...",
      "FileMode": 420,
      "Inode": 0
    }
  ],
  "Limit": 100,
  "LastFileName": "",
  "ShouldDisplayLoadMore": false
}
```

### 페이지네이션

```bash
# 처음 10개
curl "http://localhost:8888/images/?limit=10&pretty=y"

# 다음 10개 (lastFileName으로 커서 지정)
curl "http://localhost:8888/images/?limit=10&lastFileName=photo009.jpg&pretty=y"
```

### 하위 디렉토리 포함 재귀 조회

```bash
curl "http://localhost:8888/images/?recursive=true&pretty=y"
```

---

## 실습 4: 파일 복사와 이동

파일 복사는 다운로드 후 새 경로에 업로드하는 방식으로 처리합니다.

```bash
# 파일 복사 (다운로드 → 새 경로에 업로드)
curl "http://localhost:8888/documents/greeting.txt" \
  | curl -X PUT --data-binary @- \
  "http://localhost:8888/archive/greeting_copy.txt"

# 파일 이동 (복사 → 원본 삭제)
curl "http://localhost:8888/documents/greeting.txt" \
  | curl -X PUT --data-binary @- \
  "http://localhost:8888/archive/greeting.txt"
curl -X DELETE "http://localhost:8888/documents/greeting.txt"
```

> 💡 SeaweedFS Filer는 서버 사이드 이동/복사를 직접 지원하지 않습니다.
> 대용량 파일의 경우 `weed shell`의 `fs.mv` 명령을 사용할 수 있습니다.

---

## 실습 5: 커스텀 헤더(메타데이터)

Filer 업로드 시 커스텀 HTTP 헤더를 첨부하면 파일 메타데이터로 저장됩니다.

```bash
# 업로드할 때 커스텀 메타데이터 함께 설정
curl -X PUT \
  -F "file=@photo.jpg" \
  -H "X-Author: Alice" \
  -H "X-Category: profile" \
  "http://localhost:8888/images/photo.jpg"
```

S3 API를 사용하면 S3 태깅 기능을 활용할 수 있습니다. ([05편](05-s3-api.md)에서 AWS CLI 프로필 설정 방법을 다룹니다.)

```bash
# S3 API로 태그 추가
aws s3api put-object-tagging \
  --bucket my-bucket \
  --key images/photo.jpg \
  --tagging 'TagSet=[{Key=Author,Value=Alice},{Key=Category,Value=profile}]' \
  --profile seaweedfs --endpoint-url http://localhost:8333

# S3 API로 태그 조회
aws s3api get-object-tagging \
  --bucket my-bucket \
  --key images/photo.jpg \
  --profile seaweedfs --endpoint-url http://localhost:8333
```

---

## 실습 6: 파일 삭제

```bash
# 파일 삭제
curl -X DELETE "http://localhost:8888/documents/greeting.txt"

# 디렉토리 삭제 (비어 있어야 함)
curl -X DELETE "http://localhost:8888/empty-dir/"

# 디렉토리 강제 삭제 (하위 파일 포함)
curl -X DELETE "http://localhost:8888/documents/?recursive=true"
```

> ⚠️ `?recursive=true`는 하위 파일/폴더를 모두 삭제합니다. 주의해서 사용하세요.

---

## 실습 7: TTL (자동 만료)

파일에 만료 시간을 설정하면 SeaweedFS가 자동으로 삭제합니다.
임시 파일, 캐시 파일에 유용합니다.

```bash
# 1분 후 자동 삭제 (TTL: 1m)
curl -X PUT \
  -F "file=@temp.txt" \
  "http://localhost:8888/temp/temp.txt?ttl=1m"

# TTL 단위:
# m = 분 (e.g., 30m = 30분)
# h = 시간 (e.g., 24h = 24시간)
# d = 일 (e.g., 7d = 7일)
# M = 월 (e.g., 1M = 1개월)
# y = 년
```

---

## Filer API 전체 요약

```
┌──────────────────────────────────────────────────────────────┐
│  Filer REST API 치트시트                                       │
│                                                              │
│  파일 관리:                                                    │
│    PUT  /path/file              업로드                         │
│    GET  /path/file              다운로드                       │
│    HEAD /path/file              메타데이터만 확인               │
│    DELETE /path/file            삭제                          │
│    이동/복사: 다운로드 후 새 경로에 업로드                      │
│                                                              │
│  디렉토리:                                                     │
│    GET  /path/dir/              목록 조회                      │
│    GET  /path/dir/?recursive=true  재귀 조회                   │
│    GET  /path/dir/?limit=N&lastFileName=F  페이지네이션        │
│                                                              │
│  메타데이터:                                                   │
│    업로드 시 커스텀 X-* 헤더 첨부 가능                          │
│    S3 API로 태깅 사용 권장                                     │
│                                                              │
│  특수 기능:                                                    │
│    PUT /path/file?ttl=1m       자동 만료 설정                  │
└──────────────────────────────────────────────────────────────┘
```

---

## 요약

- Filer URL 패턴: `http://filer:8888/{경로}` (파일은 슬래시 없음, 디렉토리는 슬래시로 끝냄)
- 업로드: `PUT` + multipart 또는 raw binary
- 목록 조회: `GET /dir/` + `limit`/`lastFileName`으로 페이지네이션
- 이동/복사: 다운로드 후 새 경로에 업로드 (서버 사이드 미지원)
- 메타데이터: 업로드 시 커스텀 `X-*` 헤더 또는 S3 API 태깅 사용
- TTL: `?ttl=1m` 쿼리 파라미터로 자동 만료 설정

---

## 다음 편 예고

AWS SDK와 완전 호환되는 S3 Gateway API를 실습합니다. Spring Boot에서 사용할 방식을 미리 체험합니다.

→ **[05편: S3 호환 API 실습](05-s3-api.md)**

---

## 참고 자료

- [SeaweedFS Filer Server API](https://github.com/seaweedfs/seaweedfs/wiki/Filer-Server-API) — github.com
- [SeaweedFS Filer TTL](https://github.com/seaweedfs/seaweedfs/wiki/Filer-Server-API) — github.com
