# GitHub Secrets 설정 가이드

`cd.yml` 및 `docker-compose.prod.yml`에서 참조하는 GitHub Secrets 전체 목록입니다.

> **설정 경로**: GitHub Repository → Settings → Secrets and variables → Actions → New repository secret

---

## Docker Hub

| Secret 이름 | 설명 | 예시값 / 획득 방법 |
|---|---|---|
| `DOCKER_USERNAME` | Docker Hub 계정명 | `myusername` |
| `DOCKER_PASSWORD` | Docker Hub Access Token (비밀번호 대신 토큰 권장) | Docker Hub → Account Settings → Security → **New Access Token** |

---

## EC2 접속

| Secret 이름 | 설명 | 예시값 / 획득 방법 |
|---|---|---|
| `EC2_HOST` | EC2 퍼블릭 IP 또는 도메인 | `terraform output ec2_public_ip` 결과값 |
| `EC2_USER` | SSH 접속 사용자명 | `ec2-user` (Amazon Linux 2023 기본값) |
| `EC2_SSH_KEY` | SSH 프라이빗 키 전체 내용 (PEM) | `cat bubli-key.pem` 출력값을 그대로 붙여넣기 |

---

## 데이터베이스 (RDS)

| Secret 이름 | 설명 | 예시값 / 획득 방법 |
|---|---|---|
| `RDS_HOSTNAME` | RDS 엔드포인트 호스트명 | `terraform output rds_endpoint` 결과값 |
| `RDS_PORT` | PostgreSQL 포트 | `5432` |
| `RDS_DB_NAME` | 데이터베이스 이름 | `bublidb` |
| `RDS_USERNAME` | DB 마스터 사용자명 | `bubli` |
| `RDS_PASSWORD` | DB 마스터 비밀번호 | `terraform.tfvars`의 `db_password` 값 |

---

## JWT

| Secret 이름 | 설명 | 예시값 / 획득 방법 |
|---|---|---|
| `JWT_SECRET` | JWT 서명 시크릿 키 (32바이트 이상) | `openssl rand -base64 64` 로 생성 |

---

## Google OAuth

| Secret 이름 | 설명 | 예시값 / 획득 방법 |
|---|---|---|
| `GOOGLE_OAUTH_CLIENT_ID` | Google 로그인 OAuth 클라이언트 ID | Google Cloud Console → OAuth 2.0 Client |
| `GOOGLE_OAUTH_CLIENT_SECRET` | Google 로그인 OAuth 클라이언트 보안 비밀번호 | 위 클라이언트 상세 화면 |
| `GOOGLE_OAUTH_REDIRECT_URI` | 로그인 후 프론트 콜백 주소 | `https://my-bubli.kro.kr/auth/callback` |
| `GOOGLE_CALENDAR_CLIENT_ID` | Google Calendar 연동 클라이언트 ID, 로그인과 같으면 같은 값을 등록 | Google OAuth와 같은 클라이언트 사용 가능 |
| `GOOGLE_CALENDAR_CLIENT_SECRET` | Google Calendar 연동 클라이언트 보안 비밀번호, 로그인과 같으면 같은 값을 등록 | Google OAuth와 같은 클라이언트 사용 가능 |
| `GOOGLE_CALENDAR_REDIRECT_URI` | Calendar 연결 후 프론트 콜백 주소 | `https://my-bubli.kro.kr/calendar/google/callback` |

---

## AWS

| Secret 이름 | 설명 | 예시값 / 획득 방법 |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | IAM 사용자 액세스 키 ID | AWS Console → IAM → 사용자 → 보안 자격 증명 → **액세스 키 만들기** |
| `AWS_SECRET_ACCESS_KEY` | IAM 사용자 시크릿 액세스 키 | 위 액세스 키 생성 시 함께 발급 (재조회 불가, 생성 시 저장 필수) |
| `AWS_REGION` | AWS 리전 | `ap-northeast-2` |

---

## LiveKit

| Secret 이름 | 설명 | 예시값 / 획득 방법 |
|---|---|---|
| `LIVEKIT_API_KEY` | LiveKit 서버 API 키 | LiveKit Cloud 대시보드 → 프로젝트 → **Keys** |
| `LIVEKIT_API_SECRET` | LiveKit 서버 API 시크릿 | 위 Keys 페이지에서 함께 발급 |
| `LIVEKIT_SERVER_URL` | 클라이언트가 접속할 LiveKit 서버 URL | LiveKit Cloud 프로젝트의 `wss://...livekit.cloud` 주소 |

---

## Grafana

| Secret 이름 | 설명 | 예시값 / 획득 방법 |
|---|---|---|
| `GRAFANA_ADMIN_USER` | Grafana 관리자 계정명 (선택, 기본값: `admin`) | `admin` |
| `GRAFANA_ADMIN_PASSWORD` | Grafana 관리자 비밀번호 | `openssl rand -base64 32` 로 생성 |

---

## 전체 목록 요약

| 카테고리 | Secret 이름 | 필수 여부 |
|---|---|---|
| Docker Hub | `DOCKER_USERNAME` | 필수 |
| Docker Hub | `DOCKER_PASSWORD` | 필수 |
| EC2 접속 | `EC2_HOST` | 필수 |
| EC2 접속 | `EC2_USER` | 필수 |
| EC2 접속 | `EC2_SSH_KEY` | 필수 |
| RDS | `RDS_HOSTNAME` | 필수 |
| RDS | `RDS_PORT` | 필수 |
| RDS | `RDS_DB_NAME` | 필수 |
| RDS | `RDS_USERNAME` | 필수 |
| RDS | `RDS_PASSWORD` | 필수 |
| JWT | `JWT_SECRET` | 필수 |
| Google OAuth | `GOOGLE_OAUTH_CLIENT_ID` | 필수 |
| Google OAuth | `GOOGLE_OAUTH_CLIENT_SECRET` | 필수 |
| Google OAuth | `GOOGLE_OAUTH_REDIRECT_URI` | 필수 |
| Google Calendar | `GOOGLE_CALENDAR_CLIENT_ID` | 필수, 로그인과 같으면 같은 값 등록 |
| Google Calendar | `GOOGLE_CALENDAR_CLIENT_SECRET` | 필수, 로그인과 같으면 같은 값 등록 |
| Google Calendar | `GOOGLE_CALENDAR_REDIRECT_URI` | 필수 |
| AWS | `AWS_ACCESS_KEY_ID` | 필수 |
| AWS | `AWS_SECRET_ACCESS_KEY` | 필수 |
| AWS | `AWS_REGION` | 필수 |
| LiveKit | `LIVEKIT_API_KEY` | 필수 |
| LiveKit | `LIVEKIT_API_SECRET` | 필수 |
| LiveKit | `LIVEKIT_SERVER_URL` | 필수 |
| Grafana | `GRAFANA_ADMIN_USER` | 선택 |
| Grafana | `GRAFANA_ADMIN_PASSWORD` | 필수 |
