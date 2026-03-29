# 대용량 파일 처리 — 멀티파트 업로드와 스트리밍 다운로드

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [07편: 파일 업로드/다운로드 구현](07-file-upload-download.md)
> **시리즈**: Spring Boot + SeaweedFS 학습 가이드 8/10

---

## 개요

07편의 단순 업로드 방식은 파일 전체를 메모리에 올려 전송합니다.
100MB 이상의 파일을 이 방식으로 처리하면 **OutOfMemoryError**가 발생하거나 업로드가 중간에 끊깁니다.
이번 편에서는 AWS SDK v2의 **S3TransferManager**를 활용해 대용량 파일을 청크 단위로 안전하게 처리합니다.

---

## 왜 멀티파트 업로드인가?

```
단순 업로드의 문제:

  파일(1GB)
      │
      │  전체를 메모리에 올림
      ▼
  Spring Boot (JVM 힙 부족 → OOM!)
      │
      │  네트워크 끊기면 처음부터 재전송
      ▼
  SeaweedFS

멀티파트 업로드의 해결책:

  파일(1GB)
      │
      │  5MB씩 청크로 분할
      ▼
  Part 1 (5MB) → SeaweedFS ✅
  Part 2 (5MB) → SeaweedFS ✅
  Part 3 (5MB) → SeaweedFS ✅
  ...
  Part 200 (5MB) → SeaweedFS ✅
      │
      │  모든 파트 완료 후 병합
      ▼
  완성된 1GB 파일

장점:
  ├─ 메모리 사용량 최소화 (청크 크기만큼만)
  ├─ 네트워크 오류 시 해당 청크만 재전송
  ├─ 여러 청크 병렬 업로드 → 속도 향상
  └─ 5GB 이상 파일도 처리 가능
```

---

## S3TransferManager 의존성 추가

```kotlin
// build.gradle.kts
dependencies {
    // 기존 의존성 유지 ...

    // S3TransferManager (멀티파트 업로드/다운로드)
    implementation("software.amazon.awssdk:s3-transfer-manager")

    // 비동기 HTTP 클라이언트 (TransferManager 필수)
    implementation("software.amazon.awssdk.crt:aws-crt:0.35.0")
}
```

---

## 실습

### 1단계: S3TransferManager Bean 추가

```java
// src/main/java/com/example/demo/config/SeaweedFsConfig.java 수정
package com.example.demo.config;

import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3AsyncClient;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.transfer.s3.S3TransferManager;

import java.net.URI;

@Configuration
@RequiredArgsConstructor
public class SeaweedFsConfig {

    private final SeaweedFsProperties properties;

    @Bean
    public S3Client s3Client() {
        return S3Client.builder()
            .endpointOverride(URI.create(properties.getEndpoint()))
            .credentialsProvider(StaticCredentialsProvider.create(
                AwsBasicCredentials.create(properties.getAccessKey(), properties.getSecretKey())
            ))
            .region(Region.of(properties.getRegion()))
            .serviceConfiguration(
                S3Configuration.builder().pathStyleAccessEnabled(true).build()
            )
            .build();
    }

    @Bean
    public S3AsyncClient s3AsyncClient() {
        return S3AsyncClient.crtBuilder()
            .endpointOverride(URI.create(properties.getEndpoint()))
            .credentialsProvider(StaticCredentialsProvider.create(
                AwsBasicCredentials.create(properties.getAccessKey(), properties.getSecretKey())
            ))
            .region(Region.of(properties.getRegion()))
            .forcePathStyle(true)  // CRT 빌더는 forcePathStyle() 사용 (일반 S3Client는 serviceConfiguration 방식)
            .targetThroughputInGbps(5.0)     // 목표 처리량 (5Gbps)
            .minimumPartSizeInBytes(5L * 1024 * 1024) // 최소 파트 크기 5MB
            .build();
    }

    @Bean
    public S3TransferManager s3TransferManager(S3AsyncClient s3AsyncClient) {
        return S3TransferManager.builder()
            .s3Client(s3AsyncClient)
            .build();
    }
}
```

### 2단계: 대용량 파일 서비스

```java
// src/main/java/com/example/demo/service/LargeFileStorageService.java
package com.example.demo.service;

import com.example.demo.config.SeaweedFsProperties;
import com.example.demo.dto.FileUploadResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.transfer.s3.S3TransferManager;
import software.amazon.awssdk.transfer.s3.model.*;
import software.amazon.awssdk.transfer.s3.progress.LoggingTransferListener;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class LargeFileStorageService {

    private final S3TransferManager transferManager;
    private final SeaweedFsProperties properties;

    /**
     * 대용량 파일 업로드 (S3TransferManager 멀티파트)
     * 파일을 임시 파일로 저장 후 TransferManager로 업로드
     */
    public FileUploadResponse uploadLargeFile(MultipartFile file, String folder) throws IOException {
        String fileKey = buildFileKey(folder, file.getOriginalFilename());

        // 임시 파일로 저장 (MultipartFile → Path)
        Path tempFile = Files.createTempFile("upload_", "_" + file.getOriginalFilename());
        try {
            file.transferTo(tempFile);

            // TransferManager로 멀티파트 업로드
            FileUpload upload = transferManager.uploadFile(
                UploadFileRequest.builder()
                    .putObjectRequest(req -> req
                        .bucket(properties.getBucket())
                        .key(fileKey)
                        .contentType(file.getContentType())
                    )
                    .source(tempFile)
                    .addTransferListener(LoggingTransferListener.create()) // 진행률 로그
                    .build()
            );

            // 업로드 완료 대기 (동기)
            CompletedFileUpload result = upload.completionFuture().join();
            log.info("대용량 파일 업로드 완료: {} (ETag: {})",
                fileKey, result.response().eTag());

            return FileUploadResponse.builder()
                .fileKey(fileKey)
                .originalName(file.getOriginalFilename())
                .contentType(file.getContentType())
                .size(file.getSize())
                .url(buildFileUrl(fileKey))
                .build();

        } finally {
            // 임시 파일 삭제
            Files.deleteIfExists(tempFile);
        }
    }

    /**
     * 대용량 파일 다운로드 — 로컬 파일로 저장
     * 웹 응답에는 07편의 스트리밍 방식 사용, 여기서는 파일 저장 예시
     */
    public Path downloadToFile(String fileKey, Path destination) {
        FileDownload download = transferManager.downloadFile(
            DownloadFileRequest.builder()
                .getObjectRequest(req -> req
                    .bucket(properties.getBucket())
                    .key(fileKey)
                )
                .destination(destination)
                .addTransferListener(LoggingTransferListener.create())
                .build()
        );

        download.completionFuture().join();
        log.info("파일 다운로드 완료: {} → {}", fileKey, destination);
        return destination;
    }

    private String buildFileKey(String folder, String originalFilename) {
        String uuid = UUID.randomUUID().toString().replace("-", "");
        String safeName = originalFilename != null
            ? originalFilename.replaceAll("[^a-zA-Z0-9._-]", "_")
            : "file";
        return folder + "/" + uuid + "_" + safeName;
    }

    private String buildFileUrl(String fileKey) {
        return properties.getEndpoint() + "/" + properties.getBucket() + "/" + fileKey;
    }
}
```

### 3단계: 스트리밍 다운로드 (메모리 효율 극대화)

07편의 `download()` 메서드는 `InputStreamResource`로 스트리밍하지만, 대용량 파일에는 `StreamingResponseBody`로 **8KB 버퍼 청크 스트리밍**이 더 안정적입니다.

`FileStorageService`에 스트리밍 다운로드 메서드를 추가합니다:

```java
// FileStorageService.java에 추가
import org.springframework.http.ResponseEntity;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;
import software.amazon.awssdk.services.s3.model.HeadObjectResponse;

/**
 * 대용량 파일 스트리밍 다운로드용 StreamingResponseBody 생성
 */
public StreamingResponseBody streamDownload(String fileKey) {
    return outputStream -> {
        try (var s3Stream = s3Client.getObject(r -> r
            .bucket(properties.getBucket())
            .key(fileKey)
        )) {
            byte[] buffer = new byte[8192]; // 8KB 버퍼
            int bytesRead;
            while ((bytesRead = s3Stream.read(buffer)) != -1) {
                outputStream.write(buffer, 0, bytesRead);
            }
        }
    };
}

public HeadObjectResponse headObject(String fileKey) {
    return s3Client.headObject(r -> r
        .bucket(properties.getBucket())
        .key(fileKey)
    );
}
```

`FileController`에 스트리밍 엔드포인트 추가:

```java
// FileController.java에 추가
// import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;
// import software.amazon.awssdk.services.s3.model.HeadObjectResponse;

@GetMapping("/stream")
public ResponseEntity<StreamingResponseBody> streamDownload(
    @RequestParam("fileKey") String fileKey
) {
    HeadObjectResponse head = fileStorageService.headObject(fileKey);
    String contentType = head.contentType() != null
        ? head.contentType() : "application/octet-stream";

    return ResponseEntity.ok()
        .contentType(MediaType.parseMediaType(contentType))
        .contentLength(head.contentLength())
        .header(HttpHeaders.CONTENT_DISPOSITION,
            "attachment; filename=\"" + extractFilename(fileKey) + "\"")
        .body(fileStorageService.streamDownload(fileKey));
}
// extractFilename()은 07편에서 정의한 메서드 재사용
```

### 4단계: 파일 크기별 전략 분기

`FileController`에 `LargeFileStorageService`를 추가 주입합니다:

```java
// FileController.java 수정
// 기존 fileStorageService 외에 largeFileStorageService 추가
private final FileStorageService fileStorageService;
private final LargeFileStorageService largeFileStorageService;

@PostMapping("/upload")
public ResponseEntity<FileUploadResponse> upload(
    @RequestParam("file") MultipartFile file,
    @RequestParam(value = "folder", defaultValue = "uploads") String folder
) throws IOException {
    FileUploadResponse response;

    // 10MB 미만: 단순 업로드
    // 10MB 이상: TransferManager 멀티파트 업로드
    if (file.getSize() < 10 * 1024 * 1024) {
        response = fileStorageService.upload(file, folder);
    } else {
        response = largeFileStorageService.uploadLargeFile(file, folder);
    }

    return ResponseEntity.ok(response);
}
```

---

## 업로드 진행률 로그 확인

`LoggingTransferListener`를 추가하면 전송 시작/완료, 바이트 전송량 등이 로그에 출력됩니다.

```
DEBUG LoggingTransferListener - Transfer initiated...
DEBUG LoggingTransferListener - 5242880 bytes transferred
DEBUG LoggingTransferListener - 10485760 bytes transferred
...
DEBUG LoggingTransferListener - Transfer complete!
```

---

## 성능 비교

```
파일 크기별 권장 방법:

┌────────────────┬──────────────────────────────────────────────┐
│ 파일 크기       │ 방법                                          │
├────────────────┼──────────────────────────────────────────────┤
│ 0 ~ 10MB       │ S3Client.putObject() (단순 업로드)             │
│ 10MB ~ 1GB     │ S3TransferManager.uploadFile() (멀티파트)      │
│ 1GB 이상       │ S3TransferManager + 파일 시스템 임시 저장       │
└────────────────┴──────────────────────────────────────────────┘

다운로드:
┌────────────────┬──────────────────────────────────────────────┐
│ 일반 파일       │ InputStreamResource (07편, 스트리밍)           │
│ 대용량 파일     │ StreamingResponseBody (8KB 버퍼 청크 스트리밍)  │
└────────────────┴──────────────────────────────────────────────┘
```

---

## application.yml 설정 변경

07편에서 100MB로 설정했던 제한을 대용량 파일용으로 확대합니다.

```yaml
spring:
  servlet:
    multipart:
      max-file-size: 5GB      # 단일 파일 최대 5GB (07편의 100MB에서 확대)
      max-request-size: 5GB

# Tomcat 연결 타임아웃 (대용량 업로드 시 타임아웃 방지)
server:
  tomcat:
    connection-timeout: 300000  # 5분 (밀리초)
```

---

## 요약

- **10MB 이상**: `S3TransferManager.uploadFile()`로 자동 멀티파트 업로드
- **S3AsyncClient.crtBuilder()**: AWS CRT 기반 고성능 비동기 클라이언트 (멀티파트 필수)
- **스트리밍 다운로드**: `StreamingResponseBody` + 8KB 버퍼로 메모리 최소 사용
- **임시 파일 전략**: `MultipartFile.transferTo(Path)` → TransferManager → 임시 파일 삭제
- `LoggingTransferListener`로 업로드 진행률 모니터링

---

## 다음 편 예고

데이터 손실을 막는 복제(Replication)와 Erasure Coding 설정 방법을 배웁니다.

→ **[09편: 데이터 안정성 (복제 + EC)](09-replication-ec.md)**

---

## 참고 자료

- [AWS SDK v2 S3TransferManager](https://docs.aws.amazon.com/sdk-for-java/latest/developer-guide/transfer-manager.html) — docs.aws.amazon.com
- [S3AsyncClient CRT Builder](https://sdk.amazonaws.com/java/api/latest/software/amazon/awssdk/services/s3/S3AsyncClient.html) — sdk.amazonaws.com
- [Spring StreamingResponseBody](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/web/servlet/mvc/method/annotation/StreamingResponseBody.html) — docs.spring.io
