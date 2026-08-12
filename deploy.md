cd /home/deploy/apps/ahadi

git pull
pnpm install --frozen-lockfile

VITE_BUILD_COMMIT="$(git rev-parse --short HEAD)" pnpm --filter web build
pnpm --filter @ahadi/api build
pnpm --filter @ahadi/worker build

rsync -av --delete apps/web/dist/ /var/www/ahadi/

pm2 restart ahadi-api
pm2 restart ahadi-worker

pm2 save
