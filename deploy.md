cd /home/deploy/apps/ahadi

git pull
git log -1 --oneline
git rev-parse --short HEAD

pnpm install --frozen-lockfile

rm -rf apps/web/dist
rm -rf apps/web/node_modules/.vite

pnpm --filter @ahadi/config build
pnpm --filter @ahadi/types build
pnpm --filter @ahadi/validation build
pnpm --filter @ahadi/database build
pnpm --filter @ahadi/sms build
pnpm --filter @ahadi/ui build

pnpm --filter @ahadi/api build
pnpm --filter @ahadi/worker build
VITE_BUILD_SHA="$(git rev-parse --short HEAD)" pnpm --filter web build

sudo rsync -av --delete apps/web/dist/ /var/www/ahadi/

pm2 restart ahadi-api
pm2 restart ahadi-worker
pm2 save

Verify the deployed bundle:

grep -o 'assets/index-[^"]*\.js' apps/web/dist/index.html
grep -o 'assets/index-[^"]*\.js' /var/www/ahadi/index.html
curl -s https://ahadi.yuiop.work | grep -o 'assets/index-[^"]*\.js'

All three asset names must match. Open the browser console and confirm the Ahadi web build SHA matches `git rev-parse --short HEAD`.

Recommended Nginx cache policy:

location = /index.html {
    add_header Cache-Control "no-cache, no-store, must-revalidate";
}

location = /sw.js {
    add_header Cache-Control "no-cache, no-store, must-revalidate";
}

location = /registerSW.js {
    add_header Cache-Control "no-cache, no-store, must-revalidate";
}

location /assets/ {
    try_files $uri =404;
    expires 1y;
    add_header Cache-Control "public, immutable";
}

location / {
    try_files $uri $uri/ /index.html;
}
