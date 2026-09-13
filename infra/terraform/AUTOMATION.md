# AWS deployment secret flow

`terraform apply` creates the RDS instance with an AWS-managed master password.
Terraform does not receive, output, or store that password. AWS Secrets Manager stores
the credential, and only the EC2 instance role can read that one secret. Terraform also
creates an empty application-secret container. On the first deployment, EC2 generates
and stores the JWT secret and Grafana administrator password there.

On every AWS CD deployment, GitHub Actions runs `scripts/render-aws-env.sh` on EC2.
The script combines the RDS credential with the following GitHub Actions secrets and
writes an EC2-local `.env.aws` with mode `0600`:

- `DOCKER_USERNAME`
- `GOOGLE_OAUTH_CLIENT_ID`
- `GOOGLE_OAUTH_CLIENT_SECRET`
- `LIVEKIT_API_KEY`
- `LIVEKIT_API_SECRET`
- `LIVEKIT_SERVER_URL`
- `SENTRY_DSN` (optional)

Google login and Calendar share the same OAuth Web client. The Google and LiveKit secrets
must be entered once in GitHub. They are never committed to this repository or copied
manually to EC2.
