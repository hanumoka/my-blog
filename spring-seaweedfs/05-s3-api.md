# S3 호환 API 실습 — AWS CLI로 SeaweedFS 다루기

> **난이도**: 입문
> **소요 시간**: 약 3분
> **사전 지식**: [04편: Filer REST API 실습](04-filer-api.md)
> **시리즈**: Spring Boot + SeaweedFS 학습 가이드 5/10

---

## 개요

SeaweedFS S3 Gateway는 AWS S3와 동일한 API를 제공합니다.
AWS CLI, AWS SDK, boto3 등 S3 호환 도구를 그대로 SeaweedFS에 사용할 수 있습니다.
이번 편에서는 AWS CLI v2로 S3 API를 실습하고, Spring Boot에서 사용할 설정 방법을 미리 살펴봅니다.
(03편의 Docker 환경이 실행 중이어야 합니다.)

---

## S3 vs Filer — 언제 무엇을 쓸까?

```
Filer REST API:
  ├─ SeaweedFS 전용 (범용 도구 호환 안 됨)
  ├─ 경로 기반 접근 (POSIX 스타일)
  ├─ 태그, TTL 등 SeaweedFS 고유 기능 직접 사용
  └─ 추천: SeaweedFS 특화 기능이 필요할 때

S3 API (S3 Gateway):
  ├─ AWS SDK, AWS CLI, boto3 등 기존 도구 재사용
  ├─ 버킷/오브젝트 스타일 (S3 스타일)
  ├─ AWS에서 SeaweedFS로 마이그레이션 시 코드 변경 최소화
  └─ 추천: Spring Boot 연동 (AWS SDK v2 활용), 기존 S3 코드 재사용

이 시리즈에서는 Spring Boot ↔ SeaweedFS S3 API 방식을 사용합니다.
```

---

## AWS CLI 설치 및 설정

### AWS CLI v2 설치

```bash
# Linux/Mac
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Windows (MSI 설치 파일 사용)
# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

# 설치 확인
aws --version
# aws-cli/2.x.x Python/3.x.x
```

### SeaweedFS용 프로필 설정

SeaweedFS S3는 인증 없이도 동작하지만, AWS CLI는 AccessKey/SecretKey를 요구합니다.
임의의 값을 사용하면 됩니다.

```bash
aws configure --profile seaweedfs
# AWS Access Key ID: any_access_key
# AWS Secret Access Key: any_secret_key
# Default region name: us-east-1
# Default output format: json
```

---

## 실습 1: 버킷 관리

```bash
# SeaweedFS S3 엔드포인트 변수 설정
ENDPOINT="http://localhost:8333"
PROFILE="--profile seaweedfs --endpoint-url $ENDPOINT"

# 버킷 생성
aws s3 mb s3://my-bucket $PROFILE

# 버킷 목록 조회
aws s3 ls $PROFILE

# 버킷 존재 여부 확인
aws s3api head-bucket --bucket my-bucket $PROFILE
```

버킷 목록 응답:

```
2026-03-29 10:00:00 my-bucket
```

---

## 실습 2: 파일(오브젝트) 업로드/다운로드

```bash
# 파일 생성
echo "Hello, S3!" > test.txt

# 파일 업로드
aws s3 cp test.txt s3://my-bucket/files/test.txt $PROFILE

# 파일 다운로드
aws s3 cp s3://my-bucket/files/test.txt downloaded.txt $PROFILE

# 파일 내용 확인
cat downloaded.txt
# Hello, S3!
```

### 폴더 통째로 업로드

```bash
# 로컬 디렉토리 통째로 업로드
aws s3 sync ./images/ s3://my-bucket/images/ $PROFILE

# 다운로드
aws s3 sync s3://my-bucket/images/ ./downloaded-images/ $PROFILE
```

---

## 실습 3: 오브젝트 목록 및 관리

```bash
# 버킷 내 파일 목록
aws s3 ls s3://my-bucket/ $PROFILE

# 특정 경로 하위 목록
aws s3 ls s3://my-bucket/files/ $PROFILE

# 재귀적 목록 조회
aws s3 ls s3://my-bucket/ --recursive $PROFILE

# 파일 삭제
aws s3 rm s3://my-bucket/files/test.txt $PROFILE

# 경로 전체 삭제
aws s3 rm s3://my-bucket/files/ --recursive $PROFILE
```

---

## 실습 4: 오브젝트 메타데이터

```bash
# 파일 정보 확인 (HEAD)
aws s3api head-object \
  --bucket my-bucket \
  --key files/test.txt \
  $PROFILE
```

응답:

```json
{
  "ContentLength": 11,
  "ContentType": "text/plain",
  "ETag": "\"abc123...\"",
  "LastModified": "2026-03-29T10:00:00.000Z",
  "Metadata": {}
}
```

```bash
# 커스텀 메타데이터와 함께 업로드
aws s3 cp test.txt s3://my-bucket/files/test.txt \
  --metadata "author=Alice,category=test" \
  $PROFILE

# 태그와 함께 업로드
aws s3 cp test.txt s3://my-bucket/files/test.txt \
  --tagging "Author=Alice&Year=2026" \
  $PROFILE

# 태그 조회
aws s3api get-object-tagging \
  --bucket my-bucket \
  --key files/test.txt \
  $PROFILE
```

---

## 실습 5: 멀티파트 업로드 (대용량 파일)

AWS CLI는 5MB 이상 파일에 자동으로 멀티파트 업로드를 사용합니다.

```bash
# 100MB 테스트 파일 생성 (Linux/Mac)
dd if=/dev/zero of=large_file.bin bs=1M count=100

# Windows PowerShell의 경우:
# fsutil file createNew large_file.bin 104857600

# 자동으로 멀티파트 업로드 적용 (8MB 이상 시 자동)
aws s3 cp large_file.bin s3://my-bucket/files/large_file.bin $PROFILE

# 멀티파트 청크 크기 변경 (AWS CLI 설정)
aws configure set s3.multipart_chunksize 10MB --profile seaweedfs
aws s3 cp large_file.bin s3://my-bucket/files/large_file.bin $PROFILE
```

---

## Spring Boot에서 S3 API 사용 미리보기

다음 편(06~07편)에서 자세히 다루지만, 핵심 설정을 미리 살펴봅니다.

```java
// SeaweedFS S3 클라이언트 설정 (핵심 포인트)
// import software.amazon.awssdk.services.s3.S3Configuration;
S3Client s3Client = S3Client.builder()
    .endpointOverride(URI.create("http://localhost:8333"))
    .credentialsProvider(
        StaticCredentialsProvider.create(
            AwsBasicCredentials.create("any_key", "any_secret")
        )
    )
    .serviceConfiguration(
        S3Configuration.builder()
            .pathStyleAccessEnabled(true) // ← 이것이 핵심! Path-style URL 강제
            .build()
    )
    .region(Region.US_EAST_1)
    .build();
```

> ⚠️ `pathStyleAccessEnabled(true)`가 없으면 SDK가 `http://bucket.localhost:8333/key` 형태의 URL을 생성합니다.
> SeaweedFS는 `http://localhost:8333/bucket/key` (path-style)만 지원하므로, 반드시 이 옵션을 켜야 합니다.

---

## S3 API 주요 동작 요약

```
┌────────────────────────────────────────────────────────────┐
│  SeaweedFS S3 API 치트시트                                   │
│                                                            │
│  버킷:                                                      │
│    PUT    /bucket              버킷 생성                    │
│    DELETE /bucket              버킷 삭제                    │
│    GET    /                    버킷 목록                    │
│    HEAD   /bucket              버킷 존재 확인               │
│                                                            │
│  오브젝트:                                                   │
│    PUT    /bucket/key          업로드                       │
│    GET    /bucket/key          다운로드                     │
│    DELETE /bucket/key          삭제                        │
│    HEAD   /bucket/key          메타데이터                   │
│    GET    /bucket/?list-type=2 목록 조회                    │
│                                                            │
│  멀티파트:                                                   │
│    POST   /bucket/key?uploads  멀티파트 시작                │
│    PUT    /bucket/key?partNumber=N  파트 업로드             │
│    POST   /bucket/key?uploadId=UID  완료                    │
│    DELETE /bucket/key?uploadId=UID  취소                    │
│                                                            │
│  핵심 주의:                                                  │
│    Path-style URL 필수 (pathStyleAccessEnabled=true)               │
│    인증 키는 임의 값 사용 가능 (기본 설정 시)                  │
└────────────────────────────────────────────────────────────┘
```

---

## 요약

- AWS CLI `--endpoint-url`로 SeaweedFS S3 엔드포인트 지정
- S3 API: `CreateBucket`, `PutObject`, `GetObject`, `DeleteObject`, `ListObjects` 지원
- **`pathStyleAccessEnabled(true)` 필수** — SeaweedFS는 path-style URL만 지원
- 8MB 이상 파일은 자동으로 멀티파트 업로드 적용
- Spring Boot에서 AWS SDK v2를 그대로 사용 가능 (06~07편)

---

## 다음 편 예고

Spring Boot 프로젝트에 AWS SDK v2를 추가하고, SeaweedFS S3 클라이언트를 빈으로 등록합니다.

→ **[06편: Spring Boot 프로젝트 설정](06-spring-boot-setup.md)**

---

## 참고 자료

- [SeaweedFS S3 API](https://github.com/seaweedfs/seaweedfs/wiki/Amazon-S3-API) — github.com
- [AWS CLI v2 설치](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) — docs.aws.amazon.com
- [AWS S3 CLI 명령어](https://docs.aws.amazon.com/cli/latest/reference/s3/) — docs.aws.amazon.com
