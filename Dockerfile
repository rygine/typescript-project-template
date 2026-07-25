FROM node:26-slim AS base
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
WORKDIR /app
RUN npm i -g corepack && corepack enable
COPY package.json yarn.lock .yarnrc.yml ./

FROM base AS build
RUN yarn install --immutable
COPY tsconfig.json tsdown.config.ts ./
COPY src ./src
RUN yarn build

FROM base AS prod-deps
# Not immutable, and it cannot be: `yarn workspaces focus` takes no
# --immutable flag and ignores YARN_ENABLE_IMMUTABLE_INSTALLS (verified — it
# exits 0 on a lockfile that plain `yarn install` rejects). The gate is the
# build stage above: it installs immutably from the same manifests, so a stale
# lockfile fails the image build before this stage's output is ever used.
RUN yarn workspaces focus --production

FROM node:26-slim AS runtime
ARG DATA_DIR=/data
ENV NODE_ENV=production \
    PORT=3000 \
    DATA_DIR=${DATA_DIR}
WORKDIR /app
RUN mkdir -p "$DATA_DIR" && chown node:node "$DATA_DIR"
COPY package.json ./
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=build     /app/dist         ./dist

EXPOSE 3000
# node:26-slim ships no curl or wget, so the probe is Node itself. Upgrades
# `docker compose up --wait` from waiting for "running" to waiting for
# "healthy", which a crash loop can never reach.
HEALTHCHECK --start-period=15s --start-interval=2s --interval=10s \
  --timeout=3s --retries=3 CMD \
  node -e "fetch('http://127.0.0.1:' + (process.env.PORT || 3000)).then((r) => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"
USER node
CMD ["node", "dist/index.js"]
