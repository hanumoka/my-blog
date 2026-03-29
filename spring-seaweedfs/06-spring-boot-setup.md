# Spring Boot 프로젝트 설정 — AWS SDK v2로 SeaweedFS 연동

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [05편: S3 호환 API 실습](05-s3-api.md), Spring Boot 기본 지식
> **시리즈**: Spring Boot + SeaweedFS 학습 가이드 6/10

---

## 개요

이번 편부터 본격적인 Spring Boot 연동을 시작합니다.
AWS SDK v2를 사용해 SeaweedFS S3 클라이언트를 Spring Bean으로 등록하고, 설정 파일을 구성합니다.
Spring Boot 3.x + Java 21 기준으로 작성되었습니다.

---

## 왜 AWS SDK v2인가?

```
Spring Boot + SeaweedFS 연동 방법 3가지:

방법 1: Filer REST API 직접 호출
  ├─ Spring의 RestClient/WebClient 사용
  ├─ SeaweedFS 전용 기능(태그, TTL) 직접 접근
  └─ 단점: SeaweedFS 전용 코드, AWS S3 마이그레이션 시 변경 필요

방법 2: AWS SDK v2 (S3 Gateway)
  ├─ S3Client 빈 하나만 설정하면 끝
  ├─ AWS S3와 100% 코드 호환 (endpointOverride만 바꾸면 됨)
  ├─ 풍부한 기능 (멀티파트, 비동기 등)
  └─ 추천 ✅

방법 3: Spring Cloud AWS
  ├─ AWS SDK 래퍼 라이브러리
  ├─ 자동 설정(AutoConfiguration) 지원
  └─ 오버엔지니어링이 될 수 있음 (단순 연동 시)

→ 이 시리즈는 방법 2 (AWS SDK v2)를 사용합니다.
```

---

## 실습

### 1단계: Spring Boot 프로젝트 생성

[Spring Initializr](https://start.spring.io)에서 또는 IntelliJ로 생성:

```
Project: Gradle - Kotlin (또는 Maven)
Language: Java
Spring Boot: 3.4.x
Java: 21

Dependencies:
  - Spring Web
  - Spring Boot DevTools
  - Lombok
```

### 2단계: 의존성 추가

```kotlin
// build.gradle.kts
dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    compileOnly("org.projectlombok:lombok")
    annotationProcessor("org.projectlombok:lombok")

    // AWS SDK v2 - S3
    implementation(platform("software.amazon.awssdk:bom:2.30.0"))
    implementation("software.amazon.awssdk:s3")
    implementation("software.amazon.awssdk:s3-transfer-manager") // 대용량 파일 전송

    testImplementation("org.springframework.boot:spring-boot-starter-test")
}
```

Maven을 사용하는 경우:

```xml
<!-- pom.xml -->
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>bom</artifactId>
            <version>2.30.0</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>

<dependencies>
    <dependency>
        <groupId>software.amazon.awssdk</groupId>
        <artifactId>s3</artifactId>
    </dependency>
    <dependency>
        <groupId>software.amazon.awssdk</groupId>
        <artifactId>s3-transfer-manager</artifactId>
    </dependency>
</dependencies>
```

### 3단계: 설정 파일 (application.yml)

```yaml
# src/main/resources/application.yml
spring:
  application:
    name: seaweedfs-demo

seaweedfs:
  s3:
    endpoint: http://localhost:8333
    access-key: any_access_key    # 개발 환경 (임의 값)
    secret-key: any_secret_key    # 개발 환경 (임의 값)
    region: us-east-1
    bucket: my-bucket
```

운영 환경용 (환경변수로 주입):

```yaml
# src/main/resources/application-prod.yml
seaweedfs:
  s3:
    endpoint: ${SEAWEEDFS_ENDPOINT}
    access-key: ${SEAWEEDFS_ACCESS_KEY}
    secret-key: ${SEAWEEDFS_SECRET_KEY}
    region: us-east-1
    bucket: ${SEAWEEDFS_BUCKET}
```

### 4단계: 설정 프로퍼티 클래스

```java
// src/main/java/com/example/demo/config/SeaweedFsProperties.java
package com.example.demo.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Getter
@Setter
@Component
@ConfigurationProperties(prefix = "seaweedfs.s3")
public class SeaweedFsProperties {
    private String endpoint;
    private String accessKey;
    private String secretKey;
    private String region;
    private String bucket;
}
```

### 5단계: S3Client Bean 등록

```java
// src/main/java/com/example/demo/config/SeaweedFsConfig.java
package com.example.demo.config;

import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;

import java.net.URI;

@Configuration
@RequiredArgsConstructor
public class SeaweedFsConfig {

    private final SeaweedFsProperties properties;

    @Bean
    public S3Client s3Client() {
        return S3Client.builder()
            .endpointOverride(URI.create(properties.getEndpoint()))
            .credentialsProvider(
                StaticCredentialsProvider.create(
                    AwsBasicCredentials.create(
                        properties.getAccessKey(),
                        properties.getSecretKey()
                    )
                )
            )
            .region(Region.of(properties.getRegion()))
            .serviceConfiguration(
                S3Configuration.builder()
                    .pathStyleAccessEnabled(true) // ← SeaweedFS 필수 설정!
                    .build()
            )
            .build();
    }
}
```

> ⚠️ `pathStyleAccessEnabled(true)` 없이는 동작하지 않습니다.
> AWS SDK v2의 기본 URL 형식은 `http://bucket.host/key`이지만
> SeaweedFS는 `http://host/bucket/key` (path-style)만 지원합니다.

### 6단계: 프로젝트 구조

```
src/main/java/com/example/demo/
├── DemoApplication.java
├── config/
│   ├── SeaweedFsConfig.java     ← S3Client Bean 설정
│   └── SeaweedFsProperties.java ← 설정 프로퍼티
├── service/
│   └── FileStorageService.java  ← 파일 저장 서비스 (07편)
├── controller/
│   └── FileController.java      ← REST API (07편)
└── dto/
    ├── FileUploadResponse.java
    └── FileMetadataResponse.java
```

### 7단계: 애플리케이션 실행 및 연결 확인

```java
// src/main/java/com/example/demo/DemoApplication.java
package com.example.demo;

import lombok.RequiredArgsConstructor;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.ListBucketsResponse;

@SpringBootApplication
@RequiredArgsConstructor
public class DemoApplication implements CommandLineRunner {

    private final S3Client s3Client;

    public static void main(String[] args) {
        SpringApplication.run(DemoApplication.class, args);
    }

    @Override
    public void run(String... args) {
        // 시작 시 SeaweedFS 연결 확인
        ListBucketsResponse response = s3Client.listBuckets();
        System.out.println("SeaweedFS 연결 성공! 버킷 수: " + response.buckets().size());
    }
}
```

```bash
# Docker 환경이 실행 중인 상태에서
./gradlew bootRun
```

출력:

```
SeaweedFS 연결 성공! 버킷 수: 0
```

### 8단계: 버킷 초기화

```java
// src/main/java/com/example/demo/config/BucketInitializer.java
package com.example.demo.config;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

@Slf4j
@Component
@RequiredArgsConstructor
public class BucketInitializer {

    private final S3Client s3Client;
    private final SeaweedFsProperties properties;

    @EventListener(ApplicationReadyEvent.class)
    public void initBucket() {
        String bucket = properties.getBucket();
        try {
            // 버킷 존재 확인
            s3Client.headBucket(r -> r.bucket(bucket));
            log.info("버킷 '{}' 이미 존재합니다.", bucket);
        } catch (NoSuchBucketException e) {
            // 버킷 생성
            s3Client.createBucket(r -> r.bucket(bucket));
            log.info("버킷 '{}' 생성 완료.", bucket);
        }
    }
}
```

---

## 설정 요약

```
핵심 설정 체크리스트:

  ✅ AWS SDK v2 bom 의존성 추가 (버전 통일)
  ✅ software.amazon.awssdk:s3 의존성 추가
  ✅ S3Client Bean 등록
  ✅ endpointOverride = SeaweedFS S3 주소
  ✅ pathStyleAccessEnabled(true) 필수!
  ✅ region = us-east-1 (아무 리전이나 가능)
  ✅ 버킷 자동 초기화 (BucketInitializer)
```

---

## 요약

- AWS SDK v2 BOM으로 의존성 버전 일괄 관리
- `serviceConfiguration(S3Configuration.builder().pathStyleAccessEnabled(true).build())` 필수
- `@ConfigurationProperties`로 설정값 타입 안전하게 바인딩
- `BucketInitializer`로 앱 시작 시 버킷 자동 생성

---

## 다음 편 예고

실제로 파일 업로드/다운로드 API를 구현합니다. MultipartFile을 받아 SeaweedFS에 저장하고, 서명된 URL을 반환하는 서비스를 만듭니다.

→ **[07편: 파일 업로드/다운로드 구현](07-file-upload-download.md)**

---

## 참고 자료

- [AWS SDK for Java v2 S3 문서](https://docs.aws.amazon.com/sdk-for-java/latest/developer-guide/examples-s3.html) — docs.aws.amazon.com
- [AWS SDK v2 Maven BOM](https://mvnrepository.com/artifact/software.amazon.awssdk/bom) — mvnrepository.com
- [SeaweedFS S3 API 호환 목록](https://github.com/seaweedfs/seaweedfs/wiki/Amazon-S3-API) — github.com
