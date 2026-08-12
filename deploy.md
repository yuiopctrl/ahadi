<!-- nano /home/deploy/apps/ahadi/scripts/deploy-production.sh -->
<!-- chmod +x /home/deploy/apps/ahadi/scripts/deploy-production.sh -->
#!/usr/bin/env bash
set -euo pipefail

cd /home/deploy/apps/ahadi

echo "=== Pull latest code ==="
git pull
git log -1 --oneline

BUILD_SHA="$(git rev-parse --short HEAD)"
echo "Deploying build: $BUILD_SHA"

echo "=== Install dependencies ==="
pnpm install --frozen-lockfile

echo "=== Clean frontend build ==="
rm -rf apps/web/dist
rm -rf apps/web/node_modules/.vite

echo "=== Build shared packages ==="
pnpm --filter @ahadi/config build
pnpm --filter @ahadi/types build
pnpm --filter @ahadi/validation build
pnpm --filter @ahadi/database build
pnpm --filter @ahadi/sms build
pnpm --filter @ahadi/ui build

echo "=== Build API and worker ==="
pnpm --filter @ahadi/api build
pnpm --filter @ahadi/worker build

echo "=== Build frontend ==="
VITE_BUILD_SHA="$BUILD_SHA" pnpm --filter web build

echo "=== Publish frontend ==="
sudo rsync -av --delete \
  apps/web/dist/ \
  /var/www/ahadi/

echo "=== Restart backend services ==="
pm2 restart ahadi-api
pm2 restart ahadi-worker
pm2 save

echo "=== PM2 status ==="
pm2 status

echo "=== Verify frontend bundles ==="

DIST_BUNDLE="$(grep -o 'assets/index-[^"]*\.js' apps/web/dist/index.html | head -1)"
LIVE_BUNDLE="$(grep -o 'assets/index-[^"]*\.js' /var/www/ahadi/index.html | head -1)"
PUBLIC_BUNDLE="$(curl -fsS https://ahadi.yuiop.work | grep -o 'assets/index-[^"]*\.js' | head -1)"

echo "Build dist : $DIST_BUNDLE"
echo "Nginx root : $LIVE_BUNDLE"
echo "Public site: $PUBLIC_BUNDLE"

if [[ -z "$DIST_BUNDLE" || -z "$LIVE_BUNDLE" || -z "$PUBLIC_BUNDLE" ]]; then
  echo "ERROR: Could not determine one or more frontend bundle names."
  exit 1
fi

if [[ "$DIST_BUNDLE" != "$LIVE_BUNDLE" || "$DIST_BUNDLE" != "$PUBLIC_BUNDLE" ]]; then
  echo "ERROR: Frontend bundle mismatch."
  exit 1
fi

echo "Frontend bundle verified."

echo "=== API health ==="

API_HEALTH_URL="https://api.yuiop.work/api/v1/health"
API_HEALTH_OK=false

for attempt in {1..15}; do
  if curl -fsS "$API_HEALTH_URL" >/dev/null; then
    API_HEALTH_OK=true
    echo "API health check passed."
    break
  fi

  echo "API not ready yet. Retry $attempt/15..."
  sleep 2
done

if [[ "$API_HEALTH_OK" != "true" ]]; then
  echo "ERROR: API health check failed after retries."
  echo
  echo "=== Ahadi API logs ==="
  pm2 logs ahadi-api --lines 50 --nostream
  exit 1
fi

echo "=== Final PM2 status ==="
pm2 status

echo
echo "=== Deployment completed successfully ==="
echo "Build SHA: $BUILD_SHA"
echo "Frontend: https://ahadi.yuiop.work"
echo "API:      https://api.yuiop.work"

cd /home/deploy/apps/ahadi
./scripts/deploy-production.sh