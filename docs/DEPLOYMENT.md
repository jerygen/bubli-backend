# 배포 가이드 (Deployment Guide)

이 문서는 bubli-backend를 **처음** 배포하는 팀원을 위한 가이드입니다. AWS 인프라를 처음부터 만들고, 첫 배포를 마쳐 HTTPS로 서비스가 뜨는 상태까지 순서대로 따라가면 됩니다.

## 아키텍처 한눈에 보기

- **EC2 1대** 위에서 `docker-compose.prod.yml`로 아래 컨테이너들이 돌아갑니다: `backend`(Spring Boot), `redis`, `frontend`(Next.js), `nginx`(리버스 프록시), `certbot`(인증서 갱신), `prometheus`, `grafana`, `loki`, `promtail`
- **RDS PostgreSQL**, **S3**는 별도 관리형 서비스 (terraform으로 생성)
- 배포 트리거: `develop` 브랜치 CI 통과 → `cd.yml`이 backend 이미지를 Docker Hub에 push하고 EC2에 SSH로 접속해 `backend` 컨테이너만 롤링 업데이트

참고 파일: `infra/terraform/terraform.tfvars.example`, `docs/SECRETS.md`, `docker-compose.prod.yml`, `infra/nginx/nginx.conf`

---

## 1. 사전 준비

- **AWS 계정**: EC2 / RDS / VPC / S3 / IAM 리소스를 생성할 수 있는 IAM 사용자와 Access Key/Secret Key
- **EC2 키페어**: AWS Console → EC2 → 키 페어 → 키 페어 생성에서 미리 만들어두고 `.pem` 파일을 안전하게 보관하세요.
  > terraform은 키 페어를 **만들지 않습니다.** `variables.tf`의 `key_name` 기본값은 `bubli-key`인데, 같은 이름의 키 페어가 AWS에 이미 존재해야 `terraform apply`가 성공합니다.
- **Docker Hub 계정**: `bubli-backend`, `bubli-frontend` 이미지를 올릴 계정과 Access Token (Docker Hub → Account Settings → Security → New Access Token)
- **도메인**: `my-bubli.kro.kr`. EC2 퍼블릭 IP가 나오기 전까지는 A 레코드를 설정할 수 없으니, 3번(terraform apply) 이후에 등록합니다.
- **Google OAuth 클라이언트** (로그인용, 필요시 Calendar 연동용 별도 클라이언트)
- **LiveKit Cloud 프로젝트** (API Key/Secret, 서버 URL)

---

## 2. terraform.tfvars 작성

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars`는 git-ignore 대상이라 커밋되지 않습니다 (팀 채널이나 시크릿 매니저로 공유하세요). 각 값 채우기:

| 변수 | 설명 |
|---|---|
| `aws_region` | 기본 `ap-northeast-2` |
| `project_name` | 리소스 이름 접두어 (`bubli`) |
| `key_name` | **1번에서 만든 EC2 키 페어 이름과 정확히 일치**해야 함 |
| `ec2_instance_type` | 기본 `t3.small` (아래 "주의사항" 참고) |
| `rds_instance_type` | 기본 `db.t3.micro` |
| `db_name` / `db_username` / `db_password` | RDS 마스터 계정. `db_password`는 강력한 값으로 |
| `s3_bucket_name` | **전 세계에서 유일해야 함.** 겹치면 apply가 실패하니 프로젝트명+용도 등으로 고유하게 지정 |

---

## 3. terraform apply로 인프라 생성

```bash
cd infra/terraform
terraform init
terraform plan
terraform apply
```

완료되면 output을 확인합니다:

```bash
terraform output ec2_public_ip
terraform output rds_endpoint
terraform output s3_bucket_name
```

이 값들은 4번(GitHub Secrets)과 도메인 A 레코드 설정에 그대로 씁니다.

> **주의**: `main.tf`에서 RDS는 `deletion_protection = true`, `skip_final_snapshot = false`로 설정되어 있습니다. 실수로 인프라를 지우는 사고를 막기 위한 안전장치이니, 나중에 `terraform destroy`가 필요하면 `deletion_protection`을 먼저 `false`로 바꾸고 apply한 뒤 destroy해야 합니다. (그냥 destroy하면 실패합니다.)

> **주의**: EC2 보안그룹은 `80`, `443`, `22`만 열려 있습니다. `docker-compose.prod.yml`은 Prometheus(`9090`), Grafana(`3001`)도 호스트 포트로 노출하지만, 보안그룹이 막고 있어 기본 상태로는 외부에서 접근이 안 됩니다 (10번 참고).

---

## 4. GitHub Secrets 등록

`docs/SECRETS.md`에 전체 목록과 획득 방법이 정리되어 있습니다. Repository → Settings → Secrets and variables → Actions에서 등록하세요.

> **중요 — 실제로 겪은 문제**: `docs/SECRETS.md`에는 SSH 사용자 시크릿 이름이 `EC2_USER`로 적혀 있지만, 실제 `.github/workflows/cd.yml`은 `secrets.EC2_USERNAME`을 참조합니다. 문서 이름 그대로 `EC2_USER`로 등록하면 CD 워크플로우의 SSH 단계(`appleboy/ssh-action`)가 조용히 빈 값을 받아 배포가 실패합니다. **반드시 `EC2_USERNAME`이라는 이름으로 등록**하세요 (값은 `ec2-user`). 두 문서가 어긋나 있으니 발견하면 둘 중 하나를 맞춰 고쳐도 좋습니다.

값 매핑 요약:
- `EC2_HOST` ← `terraform output ec2_public_ip`
- `RDS_HOSTNAME` ← `terraform output rds_endpoint`
- `RDS_USERNAME` / `RDS_PASSWORD` ← `terraform.tfvars`의 `db_username` / `db_password`
- `S3_BUCKET_NAME`은 secret이 아니라 EC2의 `.env`에서 직접 설정 (6번 참고)

---

## 5. Docker Hub 이미지 빌드 및 push

`cd.yml`은 **backend 이미지만** 자동으로 빌드/push합니다 (`develop` 브랜치 CI 통과가 트리거). `bubli-frontend` 이미지는 이 레포에서 만들지 않으므로 프론트엔드 레포 쪽에서 별도로 push해둬야 `docker-compose.prod.yml`이 정상적으로 pull됩니다.

**최초 배포 시점**에는 아직 EC2에 아무 것도 없고 CD가 한 번도 안 돌았을 수 있으니, 아래 중 하나로 이미지를 먼저 준비하세요.

- (권장) `develop` 브랜치에 PR을 머지해서 CI → CD 파이프라인이 자동으로 backend 이미지를 push하게 둔다.
- 급하면 로컬에서 수동으로 빌드/push:
  ```bash
  docker login
  docker build -t <DOCKER_USERNAME>/bubli-backend:latest .
  docker push <DOCKER_USERNAME>/bubli-backend:latest
  ```

frontend 이미지도 같은 태그(`<DOCKER_USERNAME>/bubli-frontend:latest`)로 Docker Hub에 존재하는지 미리 확인하세요.

---

## 6. EC2 접속 후 .env 작성

```bash
chmod 400 bubli-key.pem
ssh -i bubli-key.pem ec2-user@<EC2_PUBLIC_IP>
```

EC2에 레포를 clone하고, `docker-compose.prod.yml`과 같은 위치에 `.env` 파일을 만듭니다 (compose가 `${VAR}` 치환에 자동으로 읽습니다). `docs/SECRETS.md`의 전체 목록 그대로 값만 채우면 됩니다.

```bash
git clone <repo-url> ~/bubli-backend
cd ~/bubli-backend
vi .env
```

`.env` 예시 (값은 실제 것으로 교체):

```
DOCKER_USERNAME=...
RDS_HOSTNAME=...
RDS_PORT=5432
RDS_DB_NAME=bublidb
RDS_USERNAME=bubli
RDS_PASSWORD=...
JWT_SECRET=...
GOOGLE_OAUTH_CLIENT_ID=...
GOOGLE_OAUTH_CLIENT_SECRET=...
GOOGLE_OAUTH_REDIRECT_URI=...
GOOGLE_CALENDAR_CLIENT_ID=...
GOOGLE_CALENDAR_CLIENT_SECRET=...
GOOGLE_CALENDAR_REDIRECT_URI=...
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=ap-northeast-2
S3_BUCKET_NAME=...
LIVEKIT_API_KEY=...
LIVEKIT_API_SECRET=...
LIVEKIT_SERVER_URL=...
GRAFANA_ADMIN_PASSWORD=...
```

> **주의**: `docker-compose.prod.yml`은 `STORAGE_TYPE=s3`, `AWS_S3_BUCKET=${S3_BUCKET_NAME}`을 하드코딩해두고 있어서 `S3_BUCKET_NAME`만 채우면 됩니다. 예전에 이 값이 빠져서(`STORAGE_TYPE`, `AWS_S3_BUCKET` 누락) S3 업로드가 조용히 로컬 디스크 저장으로 fallback된 적이 있으니, `.env` 채운 뒤 실제로 파일 업로드가 S3로 가는지 한번 확인하세요.

Docker Hub 이미지가 private라면 EC2에서도 로그인이 필요합니다: `docker login`.

---

## 7. HTTP로 먼저 배포 (nginx http-only 설정)

`infra/nginx/nginx.conf`(레포 기본값)는 **이미 HTTPS 설정**이라 `fullchain.pem` / `privkey.pem`을 요구합니다. 인증서를 아직 발급받지 않은 새 서버에서 그대로 `docker compose up`을 하면 nginx 컨테이너가 인증서 파일을 못 찾아 계속 재시작(crash loop)됩니다.

그래서 인증서 발급 전에는 http-only 버전으로 바꿔서 먼저 띄웁니다. (레포에 이미 `nginx.http-only.conf`, `nginx.https.conf.bak`이 만들어져 있는 이유가 이것입니다.)

```bash
cd ~/bubli-backend
cp infra/nginx/nginx.conf infra/nginx/nginx.https.conf.bak   # 이미 있으면 생략
cp infra/nginx/nginx.http-only.conf infra/nginx/nginx.conf

docker compose -f docker-compose.prod.yml up -d
```

도메인 A 레코드를 EC2 퍼블릭 IP로 미리 걸어두고, DNS 전파가 끝났는지 확인하세요 (`dig my-bubli.kro.kr` 또는 `nslookup`). 전파가 안 끝난 상태로 다음 단계(certbot)를 진행하면 ACME 챌린지가 실패합니다.

`http://<도메인>`으로 접속해 frontend/backend가 정상 응답하는지 확인한 뒤 8번으로 넘어갑니다.

---

## 8. SSL 인증서 발급 (certbot)

```bash
docker compose -f docker-compose.prod.yml run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  -d my-bubli.kro.kr \
  --email <담당자 이메일> --agree-tos --no-eff-email
```

성공하면 `/etc/letsencrypt/live/my-bubli.kro.kr/`에 인증서가 생깁니다 (compose의 `certbot-etc` 볼륨에 저장되어 nginx 컨테이너와 공유됨).

> `docker-compose.prod.yml`의 `certbot` 서비스 자체 entrypoint(`certbot renew` 반복)는 **갱신 전용**입니다. 최초 발급은 반드시 위처럼 `certonly`를 직접 실행해야 합니다.

---

## 9. HTTPS 최종 설정으로 교체

```bash
cp infra/nginx/nginx.https.conf.bak infra/nginx/nginx.conf
docker compose -f docker-compose.prod.yml restart nginx
```

`https://<도메인>`으로 접속해 정상적으로 뜨는지, `http://` 접속 시 301로 https로 리다이렉트되는지 확인합니다. 이후 `certbot` 컨테이너가 12시간마다 자동으로 갱신을 시도하므로 별도 크론 설정은 필요 없습니다.

---

## 10. 모니터링 확인 (Grafana, Prometheus)

보안그룹이 `9090`(Prometheus), `3001`(Grafana)을 막고 있으므로, 대시보드는 SSH 포트포워딩으로 접속하는 것을 권장합니다 (보안그룹에 직접 열면 관리자 로그인 화면이 인터넷에 그대로 노출됩니다).

```bash
ssh -i bubli-key.pem -L 3001:localhost:3001 -L 9090:localhost:9090 ec2-user@<EC2_PUBLIC_IP>
```

이후 로컬 브라우저에서:
- Grafana: `http://localhost:3001` (계정: `GRAFANA_ADMIN_USER`(기본 `admin`) / `GRAFANA_ADMIN_PASSWORD`)
- Prometheus: `http://localhost:9090` → Status → Targets에서 `bubli-backend` job이 `UP`인지 확인

> **주의**: `infra/grafana/provisioning/datasources/`에는 **Loki 데이터소스만** 자동 등록되어 있고, Prometheus 데이터소스는 provisioning 되어 있지 않습니다. 로그인 후 Grafana에서 Connections → Data sources → Add data source로 Prometheus를 직접 추가해야 합니다 (URL: `http://prometheus:9090`).

정상 배포되었다면 Grafana에서 Loki 로그(backend 컨테이너 로그가 promtail을 통해 수집됨)와 Prometheus 메트릭(`/actuator/prometheus`)을 모두 확인할 수 있어야 합니다.

---

## 기타 실전 주의사항

- **EC2 메모리 부족**: `t3.small`은 RAM 2GB인데, `docker-compose.prod.yml`의 컨테이너별 메모리 limit 합계가 2.5GB에 근접합니다(backend 512m + redis 768m + frontend 256m + nginx 64m + certbot 64m + prometheus 256m + grafana 256m + loki 256m + promtail 128m). 실제로 redis가 초기 128m 제한에서 OOM killed 되어 768m으로 올린 이력이 있습니다(`docker-compose.prod.yml` 히스토리 참고). 배포 후 `docker stats`로 메모리 사용량을 한 번 확인하고, 여유가 없으면 인스턴스 타입을 올리거나 모니터링 스택(prometheus/grafana/loki/promtail) 중 일부를 별도 서버로 분리하는 것을 고려하세요.
- **CORS 허용 도메인**: `docker-compose.prod.yml`의 `CORS_ALLOWED_ORIGIN_PATTERNS`에 실제 서비스 도메인이 빠지면 프론트에서 로그인/API 호출이 CORS로 막힙니다. 도메인을 바꾸거나 새 클라이언트(Tauri 등)를 추가하면 이 값도 같이 업데이트해야 합니다.
- **git reset --hard 배포 방식**: `cd.yml`은 EC2에서 `git fetch && git reset --hard origin/develop`으로 코드를 갱신합니다. EC2 로컬에서 임시로 파일을 고쳐놓고 커밋하지 않으면 다음 자동 배포 때 그대로 날아가니, 서버에서 직접 설정을 바꿀 일이 있으면 레포에도 반영해두세요.
