#!/usr/bin/env bash
set -euo pipefail

echo "==> Deploy: start"

OWNER_LC="$(echo "${GITHUB_REPOSITORY_OWNER:-}" | tr '[:upper:]' '[:lower:]')"
IMAGE_TAG="${GITHUB_SHA:?GITHUB_SHA is required}"

echo "==> GHCR owner: $OWNER_LC"
echo "==> Image tag:  $IMAGE_TAG"

echo "==> Stopping blue/green stack"
docker rm -f reverse-proxy app-back-blue app-back-green 2>/dev/null || true

echo "==> Stopping stack (keep volumes)"
docker compose down || true

echo "==> Pulling images"
docker pull "ghcr.io/${OWNER_LC}/cloudnative-backend:${IMAGE_TAG}"
docker pull "ghcr.io/${OWNER_LC}/cloudnative-frontend:${IMAGE_TAG}"

echo "==> Writing backend/.env"
cat > backend/.env <<EOF
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
DATABASE_URL=${DATABASE_URL}
EOF

echo "==> Starting stack"
IMAGE_TAG="${IMAGE_TAG}" docker compose up -d --remove-orphans

echo "==> Deploy: done ✅"