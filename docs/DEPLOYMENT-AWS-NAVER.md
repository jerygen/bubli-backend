# AWS / Naver Cloud 선택 배포

운영 Compose는 공통 파일과 환경별 오버레이를 함께 사용한다.

| 대상 | Compose 명령 |
|---|---|
| AWS EC2 + RDS/S3/Bedrock | `docker compose --env-file .env.aws -f docker-compose.prod.yml -f docker-compose.aws.yml --profile observability up -d` |
| Naver Cloud + 로컬 PostgreSQL/Storage/Ollama | `docker compose --env-file .env.naver -f docker-compose.prod.yml -f docker-compose.naver.yml up -d` |

Naver 기본 구성은 vCPU 2개, RAM 4GB에 맞춰 모니터링 스택을 실행하지 않는다. Prometheus, Grafana, Loki, Promtail은 `observability` 프로필이므로 메모리 증설 후 명시적으로 활성화한다. 프론트엔드의 3000 포트와 Ollama의 11434 포트는 Docker 내부에서만 사용하며 호스트에 공개하지 않는다.

## 1. GitHub 설정

GitHub Actions의 Repository variable `DEPLOY_TARGET`을 사용한다.

- `aws`: CI 성공 후 AWS에 자동 배포한다. 변수가 없을 때도 기존 동작 보존을 위해 AWS가 기본값이다.
- `naver`: CI 성공 후 Naver Cloud에 자동 배포한다.
- `both`: 두 서버 모두 배포한다.

수동 실행에서는 CD 워크플로의 `target` 입력으로 대상을 선택할 수 있다.

필요한 GitHub secrets:

- 공통: `DOCKER_USERNAME`, `DOCKER_PASSWORD`
- AWS: `EC2_HOST`, `EC2_USERNAME`, `EC2_SSH_KEY`
- Naver: `NAVER_SSH_KEY` (PEM 개인키 전체 내용)

Naver 호스트 기본값은 `101.79.29.236`, SSH 사용자는 `deploy`, 저장소 경로는 `/home/deploy/bubli-backend`이다. 필요하면 Repository variable `NAVER_HOST`, `NAVER_SSH_USERNAME`, `NAVER_DEPLOY_PATH`로 변경한다.

## 2. 서버별 환경 파일

실제 환경 파일은 Git에 커밋하지 않는다.

```bash
cp config/deploy/aws.env.example .env.aws
cp config/deploy/naver.env.example .env.naver
chmod 600 .env.aws .env.naver
```

기존 AWS 서버에 `.env`가 있다면 내용을 검토한 뒤 `.env.aws`로 복사해 기존 secret을 옮긴다. 각 서버에는 해당 환경 파일 하나만 만들고 `CHANGE_ME` 값을 실제 secret으로 바꾼다. Naver에서 Bedrock 채팅을 계속 사용하려면 AWS 자격 증명을 유지한다. Bedrock을 사용하지 않으면 `AI_CHAT_PROVIDER=none`, `AGENT_EXECUTION_MODE=noop`으로 설정한다.

## 3. Rocky Linux 8.10 준비

Docker Engine과 Compose plugin을 설치한 뒤 서비스를 활성화하고 저장소를 준비한다.

```bash
dnf -y install dnf-plugins-core git
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
usermod -aG docker deploy
sudo -u deploy git clone https://github.com/kosta-dev-sjh/bubli-backend.git /home/deploy/bubli-backend
sudo -u deploy sh -c 'cd /home/deploy/bubli-backend && cp config/deploy/naver.env.example .env.naver && chmod 600 .env.naver'
```

`deploy` 계정은 Docker 그룹 적용을 위해 다시 로그인한 뒤 배포해야 한다.

Naver Cloud 방화벽/ACG는 80과 443을 전체 공개하고, 22는 관리자 IP만 허용한다. 3000은 Nginx가 내부 프론트엔드로 전달하므로 외부 공개가 필요하지 않다.

## 4. Naver 최초 HTTPS 발급

처음에는 `.env.naver`의 `NGINX_CONFIG_PATH`를 `./infra/nginx/nginx.http-only.conf`로 둔다.

```bash
docker compose --env-file .env.naver -f docker-compose.prod.yml -f docker-compose.naver.yml up -d
```

DNS A 레코드가 `101.79.29.236`을 가리키는 것을 확인한 다음 인증서를 발급한다.

```bash
docker compose --env-file .env.naver -f docker-compose.prod.yml -f docker-compose.naver.yml run --rm --entrypoint certbot certbot certonly --webroot -w /var/www/certbot -d my-bubli.kro.kr --email CHANGE_ME --agree-tos --no-eff-email
```

발급 후 `.env.naver`를 다음과 같이 변경하고 Nginx를 재생성한다.

```dotenv
NGINX_CONFIG_PATH=./infra/nginx/nginx.conf
```

```bash
docker compose --env-file .env.naver -f docker-compose.prod.yml -f docker-compose.naver.yml up -d --force-recreate nginx certbot
```

## 5. Ollama 임베딩

Naver 오버레이는 `qwen3-embedding:0.6b`을 최초 실행 시 한 번 내려받는다. Ollama는 동시 모델 1개, 병렬 요청 1개, CPU thread 2개로 제한하며 호스트 포트를 열지 않는다.

기본 AI 조합은 다음과 같다.

```dotenv
AI_CHAT_PROVIDER=bedrock-converse
AI_EMBEDDING_PROVIDER=ollama
AI_EMBEDDING_DIMENSIONS=1024
OLLAMA_EMBEDDING_MODEL=qwen3-embedding:0.6b
```

AWS 방식으로 되돌리려면 다음 값을 사용한다.

```dotenv
AI_CHAT_PROVIDER=bedrock-converse
AI_EMBEDDING_PROVIDER=bedrock-titan
AI_EMBEDDING_DIMENSIONS=1024
```

같은 1024차원이라도 Titan과 Qwen 임베딩은 서로 호환되지 않는다. 기존 RDS 데이터를 Naver PostgreSQL로 옮길 경우 기존 `vector_store` 행을 백업 후 비우고 모든 자료를 Qwen으로 다시 임베딩해야 한다. 현재 프로젝트에는 전체 자료 자동 재임베딩 명령이 없으므로 데이터 이전 전에 별도 재색인 절차를 마련해야 한다.

## 6. 점검

```bash
docker compose --env-file .env.naver -f docker-compose.prod.yml -f docker-compose.naver.yml ps
docker stats --no-stream
docker exec bubli-ollama ollama list
docker exec bubli-backend wget -qO- http://localhost:8080/actuator/health
```

RAM 4GB에서는 `observability` 프로필을 켜지 않는다. OOM이나 API 지연이 발생하면 먼저 Ollama의 `num-ctx`, 배치 크기, 동시 처리량을 확인한다.
