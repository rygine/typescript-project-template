# Placeholder

## Requirements

- Node >= 26 (pinned in `.node-version`)
- Yarn 4, enabled through Corepack

## Getting started

```bash
# install corepack (node > 24)
npm i -g corepack

# enable corepack
corepack enable

# install dependencies
yarn

# run project locally
yarn start
```

## Docker

Production image only — local development runs on the host.

```bash
# build and start (detached)
./scripts/up.sh

# stop — keeps the data volume; pass -v to delete it
./scripts/down.sh

# run without compose
docker build -t app:local .
docker run --rm --init -p 127.0.0.1:3000:3000 app:local
```

Both scripts resolve the repo root from their own location, so they work from
any directory, and pass extra arguments through to `docker compose`.

Configuration comes from `.env` (copy `.env.example`). `PORT` drives the
published port and the container's `PORT`; `HOST` drives the bind address
inside the container; `BIND_ADDR` drives which host interface the port is
published on. Compose supplies defaults for all three, so a missing `.env`
still works.

The port is published on loopback by default. Docker's iptables rules bypass
`ufw`, so `BIND_ADDR=0.0.0.0` exposes the service on every interface no matter
what the host firewall says — set it deliberately, not by habit.

`DATA_DIR` is different: it is baked into the image at build time, because the
directory has to exist and be owned by the `node` user before Docker can seed
the volume with the right ownership. Changing it requires
`docker compose up --build`.

The image itself runs as the non-root `node` user. The rest of the hardening
lives in `compose.yaml`: a read-only root filesystem, all Linux capabilities
dropped, `no-new-privileges`, tini as PID 1, and caps on memory, process count,
and log size. Only `$DATA_DIR` (a named volume) and `/tmp` are writable, and
`/tmp` is a 64MB non-executable tmpfs. A plain `docker run` gets none of that
beyond the non-root user — pass the equivalent flags yourself, or use compose.

The service writes to `$DATA_DIR` on startup and exits non-zero if it cannot,
so a broken mount fails the healthcheck instead of coming up healthy with an
unusable volume. On the host, where `DATA_DIR` is unset, the write is skipped.

## Scripts

| Script              | What it does                        |
| ------------------- | ----------------------------------- |
| `yarn start`        | Run `src/index.ts` through tsx      |
| `yarn build`        | Bundle to `dist/` (esm, sourcemaps) |
| `yarn typecheck`    | Type-check with `tsc`               |
| `yarn lint`         | Lint with oxlint                    |
| `yarn fix`          | Lint and apply fixes                |
| `yarn format`       | Format with oxfmt                   |
| `yarn format:check` | Check formatting without writing    |
| `yarn clean`        | Remove `node_modules` and `dist`    |
