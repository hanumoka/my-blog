# 파일 업로드/다운로드 구현 — Spring Boot REST API 완성

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [06편: Spring Boot 프로젝트 설정](06-spring-boot-setup.md)
> **시리즈**: Spring Boot + SeaweedFS 학습 가이드 7/10

---

## 개요

06편에서 설정한 S3Client를 활용해 파일 업로드/다운로드 기능을 구현합니다.
MultipartFile을 받아 SeaweedFS에 저장하고, 파일 URL 반환, 다운로드 스트리밍, 삭제 API를 만듭니다.
실무에서 그대로 사용할 수 있는 수준으로 작성됩니다.

---

## 구현할 API 목록

```
파일 관리 REST API:

  POST   /api/files/upload               단일 파일 업로드
  POST   /api/files/upload/multiple      다중 파일 업로드
  GET    /api/files/download?fileKey=...  파일 다운로드 (스트리밍)
  GET    /api/files/metadata?fileKey=...  파일 메타데이터 및 URL 조회
  DELETE /api/files?fileKey=...           파일 삭제
  GET    /api/files/list?folder=...       파일 목록 조회

  ※ fileKey에 슬래시(/)가 포함되므로 @RequestParam으로 전달합니다.
```

---

## 실습

### 1단계: DTO 클래스

```java
// src/main/java/com/example/demo/dto/FileUploadResponse.java
package com.example.demo.dto;

import lombok.Builder;
import lombok.Getter;

@Getter
@Builder
public class FileUploadResponse {
    private String fileKey;       // SeaweedFS에서의 파일 키 (경로)
    private String originalName;  // 원본 파일명
    private String contentType;   // MIME 타입
    private long size;            // 파일 크기 (bytes)
    private String url;           // 접근 URL
}
```

```java
// src/main/java/com/example/demo/dto/FileMetadataResponse.java
package com.example.demo.dto;

import lombok.Builder;
import lombok.Getter;
import java.time.Instant;

@Getter
@Builder
public class FileMetadataResponse {
    private String fileKey;
    private String contentType;
    private long size;
    private Instant lastModified;
    private String url;
}
```

### 2단계: FileStorageService

```java
// src/main/java/com/example/demo/service/FileStorageService.java
package com.example.demo.service;

import com.example.demo.config.SeaweedFsProperties;
import com.example.demo.dto.FileMetadataResponse;
import com.example.demo.dto.FileUploadResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

import java.io.IOException;
import java.io.InputStream;
import java.util.List;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class FileStorageService {

    private final S3Client s3Client;
    private final SeaweedFsProperties properties;

    /**
     * 단일 파일 업로드
     * @param file     업로드할 파일 (MultipartFile)
     * @param folder   저장 폴더 경로 (예: "images/users")
     * @return 업로드 결과 (파일 키, URL 포함)
     */
    public FileUploadResponse upload(MultipartFile file, String folder) throws IOException {
        // 고유한 파일 키 생성: folder/uuid_originalName
        String originalFilename = file.getOriginalFilename();
        String fileKey = buildFileKey(folder, originalFilename);
        String contentType = file.getContentType() != null
            ? file.getContentType()
            : "application/octet-stream";

        // S3에 업로드
        PutObjectRequest request = PutObjectRequest.builder()
            .bucket(properties.getBucket())
            .key(fileKey)
            .contentType(contentType)
            .contentLength(file.getSize())
            .build();

        s3Client.putObject(request, RequestBody.fromInputStream(
            file.getInputStream(), file.getSize()
        ));

        log.info("파일 업로드 완료: {}", fileKey);

        return FileUploadResponse.builder()
            .fileKey(fileKey)
            .originalName(originalFilename)
            .contentType(contentType)
            .size(file.getSize())
            .url(buildFileUrl(fileKey))
            .build();
    }

    /**
     * 파일 다운로드 스트림 반환
     * @param fileKey  파일 키
     * @return S3 응답 스트림 (InputStream)
     */
    public ResponseInputStream<GetObjectResponse> download(String fileKey) {
        GetObjectRequest request = GetObjectRequest.builder()
            .bucket(properties.getBucket())
            .key(fileKey)
            .build();

        return s3Client.getObject(request);
    }

    /**
     * 파일 메타데이터 조회
     */
    public FileMetadataResponse getMetadata(String fileKey) {
        HeadObjectRequest request = HeadObjectRequest.builder()
            .bucket(properties.getBucket())
            .key(fileKey)
            .build();

        HeadObjectResponse response = s3Client.headObject(request);

        return FileMetadataResponse.builder()
            .fileKey(fileKey)
            .contentType(response.contentType())
            .size(response.contentLength())
            .lastModified(response.lastModified())
            .url(buildFileUrl(fileKey))
            .build();
    }

    /**
     * 파일 삭제
     */
    public void delete(String fileKey) {
        DeleteObjectRequest request = DeleteObjectRequest.builder()
            .bucket(properties.getBucket())
            .key(fileKey)
            .build();

        s3Client.deleteObject(request);
        log.info("파일 삭제 완료: {}", fileKey);
    }

    /**
     * 파일 목록 조회 (특정 폴더 내)
     */
    public List<String> listFiles(String folder) {
        ListObjectsV2Request request = ListObjectsV2Request.builder()
            .bucket(properties.getBucket())
            .prefix(folder.endsWith("/") ? folder : folder + "/")
            .maxKeys(100)
            .build();

        ListObjectsV2Response response = s3Client.listObjectsV2(request);

        return response.contents().stream()
            .map(S3Object::key)
            .toList();
    }

    // --- 내부 헬퍼 ---

    private String buildFileKey(String folder, String originalFilename) {
        String uuid = UUID.randomUUID().toString().replace("-", "");
        String safeName = originalFilename != null
            ? originalFilename.replaceAll("[^a-zA-Z0-9._-]", "_")
            : "unknown";
        return folder + "/" + uuid + "_" + safeName;
    }

    private String buildFileUrl(String fileKey) {
        return properties.getEndpoint() + "/" + properties.getBucket() + "/" + fileKey;
    }
}
```

### 3단계: FileController

```java
// src/main/java/com/example/demo/controller/FileController.java
package com.example.demo.controller;

import com.example.demo.dto.FileMetadataResponse;
import com.example.demo.dto.FileUploadResponse;
import com.example.demo.service.FileStorageService;
import lombok.RequiredArgsConstructor;
import org.springframework.core.io.InputStreamResource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/files")
@RequiredArgsConstructor
public class FileController {

    private final FileStorageService fileStorageService;

    /**
     * 단일 파일 업로드
     * POST /api/files/upload?folder=images
     */
    @PostMapping("/upload")
    public ResponseEntity<FileUploadResponse> upload(
        @RequestParam("file") MultipartFile file,
        @RequestParam(value = "folder", defaultValue = "uploads") String folder
    ) throws IOException {
        FileUploadResponse response = fileStorageService.upload(file, folder);
        return ResponseEntity.ok(response);
    }

    /**
     * 다중 파일 업로드
     * POST /api/files/upload/multiple?folder=images
     */
    @PostMapping("/upload/multiple")
    public ResponseEntity<List<FileUploadResponse>> uploadMultiple(
        @RequestParam("files") List<MultipartFile> files,
        @RequestParam(value = "folder", defaultValue = "uploads") String folder
    ) throws IOException {
        List<FileUploadResponse> responses = new ArrayList<>();
        for (MultipartFile file : files) {
            responses.add(fileStorageService.upload(file, folder));
        }
        return ResponseEntity.ok(responses);
    }

    /**
     * 파일 다운로드
     * GET /api/files/download?fileKey=images/users/abc123_photo.jpg
     *
     * fileKey에 슬래시(/)가 포함되므로 @RequestParam으로 전달
     */
    @GetMapping("/download")
    public ResponseEntity<InputStreamResource> download(
        @RequestParam("fileKey") String fileKey
    ) {
        ResponseInputStream<GetObjectResponse> s3Response = fileStorageService.download(fileKey);
        GetObjectResponse metadata = s3Response.response();

        String contentType = metadata.contentType() != null
            ? metadata.contentType()
            : "application/octet-stream";

        return ResponseEntity.ok()
            .contentType(MediaType.parseMediaType(contentType))
            .contentLength(metadata.contentLength())
            .header(HttpHeaders.CONTENT_DISPOSITION,
                "inline; filename=\"" + extractFilename(fileKey) + "\"")
            .body(new InputStreamResource(s3Response));
    }

    /**
     * 파일 메타데이터 및 URL 조회
     * GET /api/files/metadata?fileKey=images/users/abc123_photo.jpg
     */
    @GetMapping("/metadata")
    public ResponseEntity<FileMetadataResponse> getMetadata(
        @RequestParam("fileKey") String fileKey
    ) {
        return ResponseEntity.ok(fileStorageService.getMetadata(fileKey));
    }

    /**
     * 파일 삭제
     * DELETE /api/files?fileKey=images/users/abc123_photo.jpg
     */
    @DeleteMapping
    public ResponseEntity<Map<String, String>> delete(
        @RequestParam("fileKey") String fileKey
    ) {
        fileStorageService.delete(fileKey);
        return ResponseEntity.ok(Map.of("message", "파일이 삭제되었습니다.", "fileKey", fileKey));
    }

    /**
     * 파일 목록 조회
     * GET /api/files/list?folder=images
     */
    @GetMapping("/list")
    public ResponseEntity<List<String>> list(
        @RequestParam(value = "folder", defaultValue = "") String folder
    ) {
        return ResponseEntity.ok(fileStorageService.listFiles(folder));
    }

    private String extractFilename(String fileKey) {
        // "images/users/a1b2c3d4_photo.jpg" → "photo.jpg"
        String[] parts = fileKey.split("/");
        String last = parts[parts.length - 1];
        int underscoreIdx = last.indexOf('_');
        return underscoreIdx >= 0 ? last.substring(underscoreIdx + 1) : last;
    }
}
```

### 4단계: 파일 크기 제한 설정

```yaml
# application.yml에 추가
spring:
  servlet:
    multipart:
      enabled: true
      max-file-size: 100MB    # 단일 파일 최대 크기
      max-request-size: 500MB # 요청 전체 최대 크기
```

---

## 실습: curl로 API 테스트

```bash
# 1. 파일 업로드
curl -X POST \
  -F "file=@/path/to/photo.jpg" \
  "http://localhost:8080/api/files/upload?folder=images/users"
```

응답:

```json
{
  "fileKey": "images/users/a1b2c3d4_photo.jpg",
  "originalName": "photo.jpg",
  "contentType": "image/jpeg",
  "size": 204800,
  "url": "http://localhost:8333/my-bucket/images/users/a1b2c3d4_photo.jpg"
}
```

```bash
# 2. 파일 다운로드
curl "http://localhost:8080/api/files/download?fileKey=images/users/a1b2c3d4_photo.jpg" \
  -o downloaded.jpg

# 3. 메타데이터 조회
curl "http://localhost:8080/api/files/metadata?fileKey=images/users/a1b2c3d4_photo.jpg"

# 4. 파일 목록
curl "http://localhost:8080/api/files/list?folder=images/users"

# 5. 파일 삭제
curl -X DELETE \
  "http://localhost:8080/api/files?fileKey=images/users/a1b2c3d4_photo.jpg"
```

---

## 파일 업로드 흐름 정리

```
클라이언트
    │
    │  POST /api/files/upload (multipart/form-data)
    ▼
FileController
    │
    │  upload(MultipartFile, folder)
    ▼
FileStorageService
    │
    │  UUID로 파일 키 생성
    │  S3Client.putObject(bucket, key, inputStream)
    ▼
SeaweedFS S3 Gateway (포트 8333)
    │
    │  Filer에 파일 저장 요청
    ▼
SeaweedFS Filer
    │
    │  Master에 File ID 요청
    ▼
SeaweedFS Volume
    │  실제 파일 데이터 저장
    │
    ← 응답: 저장 완료
    ← 파일 URL 반환
```

---

## 요약

- `FileStorageService`: S3Client로 업로드/다운로드/삭제/목록 조회 캡슐화
- `UUID + 원본파일명` 조합으로 고유한 파일 키 생성 (충돌 방지)
- 다운로드는 `InputStreamResource`로 스트리밍 처리 (메모리 효율)
- fileKey에 `/`가 포함되므로 `@RequestParam`으로 전달 (PathVariable은 `/` 미지원)
- `multipart.max-file-size`와 `multipart.max-request-size`로 크기 제한 설정

---

## 다음 편 예고

100MB 이상의 대용량 파일을 효율적으로 처리하는 멀티파트 업로드와 스트리밍 다운로드를 구현합니다.

→ **[08편: 대용량 파일 처리](08-large-file-handling.md)**

---

## 참고 자료

- [AWS SDK v2 S3 PutObject](https://sdk.amazonaws.com/java/api/latest/software/amazon/awssdk/services/s3/S3Client.html#putObject) — sdk.amazonaws.com
- [Spring MultipartFile](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/web/multipart/MultipartFile.html) — docs.spring.io
- [AWS SDK v2 S3 TransferManager](https://docs.aws.amazon.com/sdk-for-java/latest/developer-guide/transfer-manager.html) — docs.aws.amazon.com
