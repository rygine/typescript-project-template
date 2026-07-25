import { writeFile } from "node:fs/promises";
import { createServer } from "node:http";

// Unset or blank PORT means "use the default", matching compose's
// ${PORT:-3000}, which also treats empty as unset. Anything else must be
// digits and nothing else: Number() would otherwise quietly accept "1e3" as
// 1000, "0x10" as 16, and — worst — whitespace as 0, which Node reads as "any
// free port". A typo'd PORT would then bind a random port and surface only
// much later as a confusing healthcheck failure.
//
// PORT=0 is still allowed, deliberately: it is useful on the host for
// grabbing a free port. Inside the container it guarantees a healthcheck
// failure, since the probe uses $PORT.
const parsePort = (value: string | undefined) => {
  const trimmed = value?.trim();
  if (!trimmed) {
    return 3000;
  }
  if (!/^\d+$/.test(trimmed)) {
    console.error(`invalid PORT: ${value}`);
    process.exit(1);
  }
  const parsed = Number(trimmed);
  if (parsed > 65535) {
    console.error(`invalid PORT: ${value} is above 65535`);
    process.exit(1);
  }
  return parsed;
};

const port = parsePort(process.env.PORT);
const host = process.env.HOST || "0.0.0.0";
const dataDir = process.env.DATA_DIR;
const startedAt = new Date().toISOString();

// Proves the volume is writable under the non-root user and read-only root.
// Unset means the host (`yarn start`), where /data need not exist; set means
// the container, where the image's ENV always provides it. So a failure here
// is fatal on purpose — warning and carrying on would report a healthy
// container with an unusable volume, which is the failure this check exists
// to catch (a bad mount, a lost chown, a `user:` override in compose.yaml).
if (dataDir) {
  try {
    await writeFile(`${dataDir}/started-at`, startedAt);
  } catch (error) {
    console.error(`could not write to ${dataDir}:`, error);
    process.exit(1);
  }
}

const server = createServer((req, res) => {
  res.writeHead(200, { "content-type": "application/json" });
  res.end(JSON.stringify({ ok: true, startedAt, path: req.url }));
});

// Without this, a listen failure — EADDRINUSE being the usual one — surfaces
// as an unhandled 'error' event: a raw stack trace, and an unbounded crash
// loop under compose's `restart: on-failure`.
server.on("error", (error) => {
  console.error("server error:", error);
  process.exit(1);
});

const shutdown = (signal: string) => {
  console.log(`${signal} received, closing`);
  server.close(() => process.exit(0));
};

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

server.listen(port, host, () => {
  // Report the port actually bound, which differs from `port` when PORT is 0
  // and the OS picks one.
  const address = server.address();
  const bound =
    address !== null && typeof address !== "string" ? address.port : port;
  console.log(`listening on http://${host}:${bound}`);
});
