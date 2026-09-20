FROM node:22-alpine
RUN npm install -g pnpm@10.32.1
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/server/package.json apps/server/package.json
COPY packages/contracts/package.json packages/contracts/package.json
RUN pnpm install --prod --frozen-lockfile
COPY apps/server/dist apps/server/dist
COPY packages/contracts/dist packages/contracts/dist
COPY database database
USER node
ENV NODE_ENV=production NODE_OPTIONS=--max-old-space-size=192
CMD ["node","apps/server/dist/index.js"]
