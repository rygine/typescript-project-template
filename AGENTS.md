# AGENTS.md

Instructions for agents working in this project.

## Stack

| Concern         | Tool                                            |
| --------------- | ----------------------------------------------- |
| Runtime         | Node >= 26 (pinned to 26.5.0)                   |
| Package manager | Yarn 4 (Corepack, `nodeLinker: node-modules`)   |
| Language        | TypeScript 7, `strict`, ESM only                |
| Bundler         | tsdown (esm + sourcemaps)                       |
| Dev runner      | tsx                                             |
| Lint            | oxlint                                          |
| Format          | oxfmt                                           |
| CI              | GitHub Actions (`.github/workflows/checks.yml`) |
| Container       | Docker (`Dockerfile` + `compose.yaml`)          |

There is no framework and no test runner. `src/index.ts` is the sole entry
point — tsdown bundles it and nothing else.

<!-- init:start -->

## Initialize

Run once, before the first commit. `scripts/init.sh` sets the package name,
retitles `README.md`, refreshes the `LICENSE` year, strips this section from
`AGENTS.md`, and deletes itself:

```bash
./scripts/init.sh my-project-name
```

The name is validated against npm's rules, so scoped names work
(`@scope/my-project`). Nothing is written until every check passes, and the
script only deletes itself on success — a failed run leaves it in place, and
every step is idempotent, so re-running after a fix is safe.

It does not set `"description"`, or `"repository"` — edit those in
`package.json` by hand.

The template is an application, not a library: `package.json` has no `"main"`
and tsdown emits no declarations. To publish it to npm instead, drop
`"private": true`, confirm `"license"` matches your `LICENSE`, set `dts: true`
in `tsdown.config.ts`, and add `"types"`, `"exports"`, and `"files"` — without
those a consumer cannot resolve anything in `dist/`.

Then confirm nothing named `placeholder` survives:

```bash
grep -ri placeholder . --exclude-dir={node_modules,.git,.yarn,dist}
```

<!-- init:end -->

## Setup

```bash
npm i -g corepack
corepack enable
yarn install
```

Node 25 dropped Corepack from the official distributions, so on the pinned Node
26 it has to be installed from npm first. Some version managers still bundle it
— if `corepack --version` already answers, skip the install step.

Do not run `npm install` or `pnpm install`. The repo is pinned to `yarn@4.17.1`
via `packageManager`, and `yarn.lock` is the only lockfile that should exist.

Then confirm the toolchain is green:

```bash
yarn lint && yarn format:check && yarn typecheck && yarn build
```

These are exactly the steps CI runs, and all four pass on a clean checkout —
tsdown emits `dist/index.js` and `dist/index.js.map`. `yarn build` prints a
`TypeScript 7.0 does not yet have a stable API and is experimental` warning;
that is expected and not a failure.

## Dependencies

**Always add new dependencies at the latest available version unless told
otherwise.** Let the package manager resolve it — `yarn add <pkg>` and
`yarn add -D <pkg>` already pick the newest release:

```bash
yarn add some-package
yarn add -D some-dev-package
```

Do not hand-write a version range into `package.json`, and do not copy a version
from memory or from another project — both routinely pin something stale.
Pin an explicit version only when the user asks for one or a documented
incompatibility forces it, and leave a comment or commit message saying why.

## Commands

| Script              | What it does                            |
| ------------------- | --------------------------------------- |
| `yarn start`        | Run `src/index.ts` directly through tsx |
| `yarn build`        | Bundle to `dist/` (esm, sourcemaps)     |
| `yarn typecheck`    | `tsc` with `noEmit`                     |
| `yarn lint`         | oxlint                                  |
| `yarn fix`          | oxlint with `--fix`                     |
| `yarn format`       | oxfmt, writes in place                  |
| `yarn format:check` | oxfmt, fails on unformatted files       |
| `yarn clean`        | Remove `node_modules` and `dist`        |

Run `yarn format` before `yarn format:check` in CI-shaped verification — oxfmt
also sorts imports and `package.json` keys, and formats Markdown, so
hand-written files frequently fail the check on first pass.

## Conventions

Formatting is enforced by `.oxfmtrc.json`, so match it rather than reformatting
by taste: 80 columns, 2 spaces, double quotes, semicolons, trailing commas
everywhere, `bracketSameLine: true`, LF endings. Imports are sorted, with `@/`
treated as the internal prefix.

`.oxlintrc.json` enables the `eslint`, `import`, `node`, `oxc`, `promise`,
`react`, `typescript`, and `unicorn` plugins, with `correctness` and
`suspicious` categories set to error and `options.typeAware` on — so a lot
more is enforced than just the rules spelled out under `"rules"`, including
type-aware checks that need real project types, not just syntax. Don't
assume a rule is inactive just because it's absent from that list; `yarn
lint` (or `yarn fix` for autofixable ones) is the source of truth. The one
structural override: `*.test.ts` files may use non-null assertions, other
files may not.

Other things to keep in mind:

- ESM only (`"type": "module"`). Use `import`/`export`, never `require`.
- Define functions as `const fn = () => {}`, not `function fn() {}` or
  `const fn = function () {}`. `func-style` catches the `function fn() {}`
  form; the `const fn = function () {}` form is convention only.
- `moduleResolution: "bundler"`, so extensionless relative imports are fine.
- `tsconfig.json` includes `src`, `scripts`, and `tsdown.config.ts`. New
  top-level source directories must be added to `include` or they will not be
  typechecked.
- `dist/` is gitignored. Do not commit build output.

### React

React is not a dependency yet, but the lint rules for it are already in place
and apply the moment it is added.

**Never use `useEffect`.** This is a hard rule, not a preference.
`no-restricted-imports` and `no-restricted-properties` both fail the build on
it — the first catches `import { useEffect } from "react"` (including aliased
imports), the second catches `React.useEffect`. Do not reach for
`// oxlint-disable` to get around either one; if you believe a case genuinely
requires an effect, stop and ask rather than disabling the rule.

Almost everything effects get used for has a better answer:

- Data that can be computed from props or state — derive it during render.
- Responding to a user action — do the work in the event handler.
- Resetting state when a prop changes — give the component a `key`.
- Reading from an external store — `useSyncExternalStore`.
- Fetching — a data-fetching library, or a framework loader.

Two other React conventions, both lint-enforced:

- Components are arrow functions, named and unnamed alike
  (`react/function-component-definition`). This matches the general function
  convention above, and unlike `func-style` it also rejects
  `const C = function () {}`.
- Component names are PascalCase, with a leading underscore permitted
  (`react/jsx-pascal-case` with `allowLeadingUnderscore`).

### Docker

The image is production-only. There is no dev target and no `tsx` in any
image — development runs on the host.

`Dockerfile` has four stages: `base` (Corepack + manifests), `build`
(`yarn install --immutable` then `yarn build`), `prod-deps`
(`yarn workspaces focus --production`), and `runtime`, which starts clean from
`node:26-slim` and copies in only `package.json`, `node_modules`, and `dist`.

`scripts/up.sh` builds and starts the stack detached; `scripts/down.sh` stops
it and keeps the data volume unless you pass `-v`. Both cd to the repo root
first and forward arguments to `docker compose`.

`up.sh` passes `--wait`, which is only meaningful because the Dockerfile has a
`HEALTHCHECK`. Without one, `--wait` waits for "running", and a container
restarting under `restart: on-failure` passes through "running" — so a crash
loop would report success. Keep the healthcheck if you keep `--wait`.

The healthcheck intervals and `--wait-timeout 60` are a matched pair, and
nothing enforces it. A container that never listens is marked unhealthy at
~38s, inside the window, so `--wait` reports the real verdict; widen
`--interval`/`--retries` or shorten the timeout and `up.sh` starts failing
with a timeout instead, which reads the same for a broken image as for a slow
one.

Things that are easy to break:

- `package.json` must be copied into the runtime stage. Without it Node has no
  `"type": "module"` and treats `dist/index.js` as CommonJS, so the first
  `import` fails at runtime.
- `mkdir -p "$DATA_DIR" && chown node:node "$DATA_DIR"` must stay before
  `USER node` — `chown` needs root. It exists so Docker seeds the named volume
  with `node` ownership; without it the unprivileged process cannot write.
- `DATA_DIR` is a build arg as well as an env var, for the same reason. It is
  not a pure runtime knob; changing it needs `--build`.
- Yarn's version comes from `packageManager`. Never hardcode it in the
  Dockerfile. `node:26-slim` ships neither Corepack nor Yarn, which is why the
  base stage runs `npm i -g corepack`.
- Do not add `user:` to `compose.yaml`. The image sets `USER node`, and any
  other uid loses write access to the chowned `$DATA_DIR`.
- Never put `NODE_ENV` in `.env`. `env_file` is applied at container start, so
  it silently overrides the image's `ENV NODE_ENV=production` — a development
  build ships with no error and nothing in `git status`.
- The Dockerfile enumerates its inputs explicitly. `yarn set version` or
  `yarn patch` write to `.yarn/`, which is never copied, so the image breaks
  while host builds and CI keep passing. New top-level source directories and
  native dependencies (which need `python3`/`make`/`g++`, absent from
  `node:26-slim`) need Dockerfile changes too. CI does not build the image, so
  nothing catches this.

## Adding a test runner

There is none. `.oxlintrc.json` already has a `**/*.test.ts` override, which
implies colocated `*.test.ts` files as the intended layout. After adding a
runner, wire a `test` script into `package.json` **and** add a step to
`.github/workflows/checks.yml` — CI does not run tests today.

## Verification

Before claiming work is complete, run the full CI sequence and report the actual
output:

```bash
yarn lint && yarn format:check && yarn typecheck && yarn build
```

## Docs

Generated documents — specs, design notes, plans, research, scratch write-ups —
belong in `docs/`, which is gitignored. **This is expected, not a mistake.** Do
not "fix" it by removing `docs/` from `.gitignore`, force-adding files with
`git add -f`, or relocating them into a tracked directory.

Do not attempt to commit anything under `docs/` unless the user asks. Because
the directory is ignored, a plain `git status` will not show that work — say
explicitly which files you wrote there so the user knows they exist.

Documentation that is genuinely part of the project — `README.md`, `AGENTS.md`,
and anything a consumer needs — is tracked and lives at the root, not in
`docs/`.

## Commits

**Do not make commits unless the user specifically asks.** Finish the work,
report what changed, and leave it staged or unstaged for the user to review.
The same goes for anything downstream of a commit — no `git push`, no branches,
no PRs, no tags — unless asked.

Being done with a task is not a reason to commit. Neither is a green
verification run, a long stretch of work, or wanting to checkpoint before
continuing. Wait to be asked.
