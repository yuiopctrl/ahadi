cd /home/deploy/apps/ahadi

git pull
pnpm install --frozen-lockfile

pnpm --filter @ahadi/web build
pnpm --filter @ahadi/api build
pnpm --filter @ahadi/worker build

rsync -av --delete apps/web/dist/ /var/www/ahadi/

pm2 restart ahadi-api
pm2 restart ahadi-worker

pm2 save