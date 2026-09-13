#!/usr/bin/env bash

# Creates the EC2-local .env.aws file on every deployment.
# RDS connection data comes from AWS Secrets Manager through the EC2 instance role.
# Third-party credentials are passed by GitHub Actions as process environment variables.
set -Eeuo pipefail

runtime_file="${BUBLI_RUNTIME_CONFIG_FILE:-$HOME/.bubli-runtime.env}"

if [[ ! -r "$runtime_file" ]]; then
  echo "Missing runtime configuration: $runtime_file" >&2
  exit 1
fi

# This file is written by Terraform user_data and contains no secret values.
# shellcheck disable=SC1090
source "$runtime_file"

for command in aws jq mktemp; do
  command -v "$command" >/dev/null || {
    echo "Required command is unavailable: $command" >&2
    exit 1
  }
done

require_value() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" || "$value" == CHANGE_ME* ]]; then
    echo "Required deployment secret is missing: $name" >&2
    exit 1
  fi
}

write_value() {
  local name="$1"
  local value="$2"
  # JSON quoting also produces a Docker Compose-compatible quoted .env value.
  printf '%s=%s\n' "$name" "$(printf '%s' "$value" | jq -Rs .)" >> "$output_file"
}

require_value DOCKER_USERNAME

rds_secret="$(aws secretsmanager get-secret-value \
  --secret-id "$BUBLI_RDS_SECRET_ARN" \
  --region "$BUBLI_AWS_REGION" \
  --query SecretString \
  --output text)"

rds_host="$(jq -er '.host' <<<"$rds_secret")"
rds_port="$(jq -er '.port | tostring' <<<"$rds_secret")"
rds_username="$(jq -er '.username' <<<"$rds_secret")"
rds_password="$(jq -er '.password' <<<"$rds_secret")"

if app_secret="$(aws secretsmanager get-secret-value \
  --secret-id "$BUBLI_APP_RUNTIME_SECRET_ARN" \
  --region "$BUBLI_AWS_REGION" \
  --query SecretString \
  --output text 2>/dev/null)"; then
  :
else
  app_secret="$(jq -n \
    --arg jwt_secret "$(openssl rand -base64 48)" \
    --arg grafana_admin_password "$(openssl rand -base64 36)" \
    '{JWT_SECRET: $jwt_secret, GRAFANA_ADMIN_PASSWORD: $grafana_admin_password}')"
  aws secretsmanager put-secret-value \
    --secret-id "$BUBLI_APP_RUNTIME_SECRET_ARN" \
    --region "$BUBLI_AWS_REGION" \
    --secret-string "$app_secret" >/dev/null
fi

jwt_secret="$(jq -er '.JWT_SECRET' <<<"$app_secret")"
grafana_admin_password="$(jq -er '.GRAFANA_ADMIN_PASSWORD' <<<"$app_secret")"

# Certificates live in Docker's named volume. The certbot container is the
# reliable place to check it after the first successful issuance.
if docker exec bubli-certbot test -f /etc/letsencrypt/live/my-bubli.kro.kr/fullchain.pem >/dev/null 2>&1; then
  nginx_config_path="./infra/nginx/nginx.conf"
else
  nginx_config_path="./infra/nginx/nginx.http-only.conf"
fi

output_file="$(mktemp .env.aws.XXXXXX)"
trap 'rm -f "$output_file"' EXIT
umask 077

write_value DOCKER_USERNAME "$DOCKER_USERNAME"
write_value IMAGE_TAG "${DEPLOY_IMAGE_TAG:-latest}"
write_value FRONTEND_IMAGE_TAG "${FRONTEND_IMAGE_TAG:-latest}"

write_value RDS_HOSTNAME "$rds_host"
write_value RDS_PORT "$rds_port"
write_value RDS_DB_NAME "$BUBLI_DB_NAME"
write_value RDS_USERNAME "$rds_username"
write_value RDS_PASSWORD "$rds_password"

write_value STORAGE_TYPE s3
write_value S3_BUCKET_NAME "$BUBLI_S3_BUCKET_NAME"
write_value AI_CHAT_PROVIDER bedrock-converse
write_value AI_EMBEDDING_PROVIDER bedrock-titan
write_value AI_EMBEDDING_DIMENSIONS 1024
write_value AWS_REGION "$BUBLI_AWS_REGION"
write_value BEDROCK_CHAT_MODEL_ID apac.anthropic.claude-3-haiku-20240307-v1:0
write_value BEDROCK_EMBEDDING_MODEL_ID amazon.titan-embed-text-v2:0

write_value JWT_SECRET "$jwt_secret"
write_value GOOGLE_OAUTH_CLIENT_ID "${GOOGLE_OAUTH_CLIENT_ID:-}"
write_value GOOGLE_OAUTH_CLIENT_SECRET "${GOOGLE_OAUTH_CLIENT_SECRET:-}"
write_value GOOGLE_OAUTH_REDIRECT_URI https://my-bubli.kro.kr/login/oauth2/code/google
# Login and Calendar use one Google OAuth Web client.
write_value GOOGLE_CALENDAR_CLIENT_ID "${GOOGLE_OAUTH_CLIENT_ID:-}"
write_value GOOGLE_CALENDAR_CLIENT_SECRET "${GOOGLE_OAUTH_CLIENT_SECRET:-}"
write_value GOOGLE_CALENDAR_REDIRECT_URI https://my-bubli.kro.kr/api/calendar/google/callback
write_value LIVEKIT_API_KEY "${LIVEKIT_API_KEY:-}"
write_value LIVEKIT_API_SECRET "${LIVEKIT_API_SECRET:-}"
write_value LIVEKIT_SERVER_URL "${LIVEKIT_SERVER_URL:-}"
write_value CORS_ALLOWED_ORIGIN_PATTERNS https://my-bubli.kro.kr,tauri://localhost,http://tauri.localhost,http://localhost:3000,http://localhost:5173,http://localhost:1420
write_value SENTRY_DSN "${SENTRY_DSN:-}"
write_value SENTRY_SEND_DEFAULT_PII false
write_value GRAFANA_ADMIN_USER admin
write_value GRAFANA_ADMIN_PASSWORD "$grafana_admin_password"
write_value LETSENCRYPT_EMAIL "${LETSENCRYPT_EMAIL:-myksphone2001@gmail.com}"
write_value NGINX_CONFIG_PATH "$nginx_config_path"

chmod 600 "$output_file"
mv "$output_file" .env.aws
trap - EXIT
