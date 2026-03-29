# 데이터 안정성 — 복제(Replication)와 Erasure Coding

> **난이도**: 중급
> **소요 시간**: 약 3분
> **사전 지식**: [08편: 대용량 파일 처리](08-large-file-handling.md)
> **시리즈**: Spring Boot + SeaweedFS 학습 가이드 9/10

---

## 개요

파일 저장 시스템에서 가장 중요한 것은 **데이터가 사라지지 않는 것**입니다.
SeaweedFS는 두 가지 방식으로 데이터를 보호합니다:
- **Replication (복제)**: 동일한 파일을 여러 Volume에 복사
- **Erasure Coding (EC)**: 파일을 수학적으로 분산해 원본 없이도 복구 가능

이번 편에서는 각 방식의 원리와 설정 방법을 배웁니다.

---

## Replication — 복제

### 복제 방식 이해

SeaweedFS는 `ZYX` 형식의 복제 코드로 복제 전략을 지정합니다.

```
복제 코드 ZYX 의미:

  Z = 다른 데이터 센터(DataCenter)에 복제 수
  Y = 같은 데이터 센터, 다른 랙(Rack)에 복제 수
  X = 같은 랙, 다른 서버에 복제 수

예시:
  000 = 복제 없음 (총 1개 보관) ← 기본값
  001 = 같은 랙, 다른 서버 1개 복제 (총 2개)
  010 = 다른 랙 1개 복제 (총 2개)
  100 = 다른 데이터 센터 1개 복제 (총 2개)
  011 = 다른 랙 + 같은 랙 다른 서버 각 1개 (총 3개)
  111 = 다른 데이터 센터, 다른 랙, 다른 서버 각 1개 (총 4개)
  200 = 다른 데이터 센터 2개 복제 (총 3개)
```

### 복제 설정 방법

**방법 1: Master 기본 복제 설정**

```yaml
# docker-compose.yml 수정
seaweedfs-master:
  command: "master -ip=seaweedfs-master -port=9333 -mdir=/data -defaultReplication=001"
```

이제 새로 생성되는 모든 볼륨이 복제 `001` 규칙을 따릅니다.

**방법 2: 파일 업로드 시 복제 지정**

Spring Boot 코드에서 특정 파일만 복제 설정:

```java
// S3 API는 복제 설정을 직접 지원하지 않음 → Filer REST API 사용
// FileStorageService.java에 Filer 직접 업로드 메서드 추가

import org.springframework.web.client.RestClient;

@Value("${seaweedfs.filer.endpoint:http://localhost:8888}")
private String filerEndpoint;

private final RestClient restClient = RestClient.create();

/**
 * 복제 설정과 함께 Filer에 직접 업로드
 * S3 API 대신 Filer REST API를 사용해야 복제/TTL 등 고급 기능 가능
 */
public FileUploadResponse uploadWithReplication(
    MultipartFile file,
    String filePath,
    String replication  // 예: "001"
) throws IOException {
    // 복제 설정은 쿼리 파라미터로 전달
    String url = filerEndpoint + filePath + "?replication=" + replication;

    restClient.put()
        .uri(url)
        .contentType(MediaType.parseMediaType(
            file.getContentType() != null ? file.getContentType() : "application/octet-stream"))
        .body(file.getInputStream().readAllBytes())
        .retrieve()
        .body(String.class);

    return FileUploadResponse.builder()
        .fileKey(filePath)
        .originalName(file.getOriginalFilename())
        .contentType(file.getContentType())
        .size(file.getSize())
        .url(filerEndpoint + filePath)
        .build();
}
```

> 💡 대용량 파일에 복제를 적용하려면 `readAllBytes()` 대신 08편의 스트리밍 방식을 사용하세요.

---

## 복제 환경 Docker Compose 구성

복제를 테스트하려면 Volume 서버가 여러 대 필요합니다.

```yaml
# docker-compose.yml — 복제 환경
services:
  seaweedfs-master:
    image: chrislusf/seaweedfs:3.73
    ports:
      - "9333:9333"
    volumes:
      - ./data/master:/data
    command: "master -ip=seaweedfs-master -port=9333 -mdir=/data -defaultReplication=001"
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:9333/cluster/status"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Volume 서버 1 (랙 1)
  seaweedfs-volume1:
    image: chrislusf/seaweedfs:3.73
    ports:
      - "8080:8080"
    volumes:
      - ./data/volume1:/data
    command: >
      volume
      -mserver=seaweedfs-master:9333
      -port=8080
      -dir=/data
      -dataCenter=dc1
      -rack=rack1
    depends_on:
      seaweedfs-master:
        condition: service_healthy

  # Volume 서버 2 (랙 2 — 다른 랙)
  seaweedfs-volume2:
    image: chrislusf/seaweedfs:3.73
    ports:
      - "8081:8080"
    volumes:
      - ./data/volume2:/data
    command: >
      volume
      -mserver=seaweedfs-master:9333
      -port=8080
      -dir=/data
      -dataCenter=dc1
      -rack=rack2
    depends_on:
      seaweedfs-master:
        condition: service_healthy

  seaweedfs-filer:
    image: chrislusf/seaweedfs:3.73
    ports:
      - "8888:8888"
    volumes:
      - ./data/filer:/data
    command: "filer -master=seaweedfs-master:9333 -port=8888"
    depends_on:
      seaweedfs-master:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8888/"]
      interval: 10s
      timeout: 5s
      retries: 5

  seaweedfs-s3:
    image: chrislusf/seaweedfs:3.73
    ports:
      - "8333:8333"
    command: "s3 -filer=seaweedfs-filer:8888 -port=8333"
    depends_on:
      seaweedfs-filer:
        condition: service_healthy
```

복제 확인:

```bash
# Volume 상태 확인 (볼륨별 복제 설정 확인)
curl http://localhost:9333/vol/status | python3 -m json.tool
```

복제가 적용된 볼륨의 응답:

```json
{
  "Volumes": [
    {
      "Id": 1,
      "ReplicaPlacement": { "SameRackCount": 1 },
      "Locations": [
        { "Url": "seaweedfs-volume1:8080" },
        { "Url": "seaweedfs-volume2:8080" }
      ]
    }
  ]
}
```

---

## Erasure Coding (EC)

### EC 원리

Erasure Coding은 RAID-6를 발전시킨 방식입니다.
SeaweedFS는 `RS(10, 4)` 방식을 사용합니다.

```
RS(10, 4) Erasure Coding:

원본 파일 → 10개 데이터 샤드 + 4개 패리티 샤드 = 총 14개 샤드

┌──────────────────────────────────────────────────────────┐
│  원본 1GB 파일                                             │
│                                                          │
│  데이터 샤드:                    패리티 샤드:               │
│  shard_01 (100MB) ───────────── parity_01 (100MB)        │
│  shard_02 (100MB)               parity_02 (100MB)        │
│  ...                            parity_03 (100MB)        │
│  shard_10 (100MB) ───────────── parity_04 (100MB)        │
│                                                          │
│  14개 중 4개까지 손실되어도 원본 복구 가능!                  │
└──────────────────────────────────────────────────────────┘

저장 효율:
  복제(1개→3개): 200% 추가 공간 필요
  EC(10+4): 40% 추가 공간만 필요 (훨씬 효율적!)
```

### EC 적용 시기

EC는 **콜드 데이터(잘 변경되지 않는 오래된 파일)**에 적합합니다.
핫 데이터(자주 변경)에는 복제를 사용하고, 일정 시간이 지나면 EC로 전환합니다.

EC 인코딩은 `weed shell` 명령으로 수행합니다:

```bash
# weed shell 접속
docker exec -it seaweedfs-master weed shell -master=localhost:9333

# EC 인코딩 실행 (특정 컬렉션의 볼륨을 EC로 변환)
> ec.encode -collection=my-bucket -fullPercent=95

# EC 상태 확인
> ec.balance -collection=my-bucket

# 볼륨 컴팩션 (삭제된 데이터 공간 회수 — EC와 별개)
> volume.vacuum -garbageThreshold=0.3
```

> ⚠️ EC 변환은 자동이 아닌 **수동 명령**입니다.
> 운영 환경에서는 cron 작업으로 주기적으로 실행하는 패턴을 사용합니다.

```bash
# 예: cron으로 매일 새벽 EC 인코딩 실행
0 3 * * * docker exec seaweedfs-master weed shell \
  -master=localhost:9333 \
  -cmd="ec.encode -collection=my-bucket -fullPercent=95"
```

---

## 복제 vs EC 선택 가이드

```
┌──────────────────┬──────────────────────────┬────────────────────────────┐
│ 항목              │ 복제 (Replication)        │ Erasure Coding (EC)        │
├──────────────────┼──────────────────────────┼────────────────────────────┤
│ 데이터 보호       │ 완전한 복사본             │ 수학적 패리티 (샤드)         │
│ 최대 장애 허용    │ (n-1)대 서버 장애         │ 14개 중 4개 장애             │
│ 저장 오버헤드     │ n배 (2복제 → 200%)        │ 40% (RS 10+4)              │
│ 읽기 성능         │ 복사본에서 병렬 읽기       │ 복원 후 읽기 (약간 느림)     │
│ 쓰기 성능         │ n개 서버에 동시 쓰기       │ 인코딩 연산 필요             │
│ 적합한 데이터     │ 핫 데이터, 소형 파일       │ 콜드 데이터, 대형 파일       │
│ 최소 서버 수      │ n대 (복제 수만큼)          │ 4대 이상 권장 (샤드 분산)     │
└──────────────────┴──────────────────────────┴────────────────────────────┘

실무 권장 전략:
  소규모 서비스: 복제 001 (2개 Volume 서버)
  중규모 서비스: 복제 010 또는 011
  대규모 서비스: 복제(핫) + EC(콜드) 혼합
```

---

## 장애 복구 시나리오

```bash
# Volume 서버 1이 다운된 경우 시뮬레이션
docker compose stop seaweedfs-volume1

# 파일이 여전히 접근 가능한지 확인 (복제 덕분에)
curl "http://localhost:8888/test/hello.txt"
# 정상 응답!

# Volume 서버 1 복구
docker compose start seaweedfs-volume1

# 복구 후 자동으로 데이터 동기화 (백그라운드)
# Master가 복제본 상태 모니터링 후 필요 시 재복제
```

---

## 요약

- **Replication ZYX**: Z=다른DC, Y=다른랙, X=같은랙다른서버 복제 수. `001`=같은랙 1복제(권장 최소)
- **Erasure Coding RS(10,4)**: 14개 샤드 중 4개 손실까지 복구 가능. 40% 오버헤드
- **복제**: 핫 데이터, 즉각적인 가용성 필요 시
- **EC**: 콜드 데이터, 저장 비용 최적화 시
- 프로덕션 최소 권장: `defaultReplication=001` + Volume 서버 2대 이상

---

## 다음 편 예고

로드밸런서, 모니터링, 보안, 스케일링 등 실제 운영에 필요한 모든 것을 정리합니다.

→ **[10편: 프로덕션 운영 가이드](10-production-guide.md)**

---

## 참고 자료

- [SeaweedFS Replication](https://github.com/seaweedfs/seaweedfs/wiki/Replication) — github.com
- [SeaweedFS Erasure Coding](https://github.com/seaweedfs/seaweedfs/wiki/Erasure-Coding-for-warm-storage) — github.com
- [Reed-Solomon Erasure Coding](https://en.wikipedia.org/wiki/Reed%E2%80%93Solomon_error_correction) — wikipedia.org
