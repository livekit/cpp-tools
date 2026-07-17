# cpp-tools

Standardized formatting, static-analysis, and documentation checks for LiveKit
C++ projects.

This repository is intended to be consumed as a git submodule by LiveKit C++
repositories.

## Quick start

Add `cpp-tools` to the consuming repository:

```bash
git submodule add https://github.com/livekit/cpp-tools.git cpp-tools
```

From the consuming repository root, install the shared configuration symlinks:

```bash
./cpp-tools/install.sh  # Installs .clang-format and .clang-tidy symlinks to repo root
```

Optionally pass `precommit-hook` to install a precommit hook that automatically runs `clang-format`
before commits.

> Note: Only one precommit hook is allowed in Git

```bash
./cpp-tools/install.sh precommit-hook   # Installs precommit hook
```

The installer refuses to replace existing configuration files unless `--force`
is passed. Use `--repo-root PATH` when the consumer root cannot be detected
automatically.

Run the tools from the repository root:

```bash
# Check formatting or rewrite files in place.
./cpp-tools/clang-format.sh --path path/to/sources
./cpp-tools/clang-format.sh --path path/to/sources --fix

# Run static analysis after generating compile_commands.json.
./cpp-tools/clang-tidy.sh --file-regex '.*\.(c|cpp|cc|cxx)$'
./cpp-tools/clang-tidy.sh --file-regex '.*\.(c|cpp|cc|cxx)$' --fail-on-warning
```

## What this repository provides

The shared source of truth includes:

- `clang-format` style (`.clang-format`)
- `clang-tidy` checks (`.clang-tidy`)
- shared C++ engineering guidance (`AGENTS.md`)
- local and CI wrapper scripts at the repository root

Consumer repositories should expose root-level symlinks for `.clang-format` and
`.clang-tidy` so editor integrations can find them, and should pass
project-specific paths/build filters to the shared scripts.

Their root `AGENTS.md` should reference `cpp-tools/AGENTS.md` as the shared C++
baseline and add only repository-specific architecture and workflow guidance.

## Consumer wrappers

Consumer repositories should provide thin project-owned entrypoints such as
`scripts/clang-format.sh` and `scripts/clang-tidy.sh`. The wrappers encode the
repository's paths, filters, and build directory, then `exec` the shared script.
This gives developers a zero-argument command without copying the formatting,
diagnostic, or GitHub summary implementation.

For example:

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export CLANG_FORMAT_FIX_COMMAND="./scripts/clang-format.sh --fix"
exec "${repo_root}/cpp-tools/clang-format.sh" \
  --repo-root "${repo_root}" \
  --path src \
  --path include \
  "$@"
```

Repository-owned CI workflows should invoke the same project entrypoints so
local and CI file selection cannot drift. Repositories that do not use wrappers
can call the shared scripts with explicit arguments.

## clang-format

Each consumer supplies the tracked paths that `clang-format.sh` should check.
Pass `--path` repeatedly for repositories with multiple source trees:

```bash
./cpp-tools/clang-format.sh \
  --path path/to/sources \
  --path path/to/headers
```

The `CLANG_FORMAT_PATHS` environment variable provides the same configuration
as a colon-separated list. Positional file paths restrict the check to those
files.

## clang-tidy

See [docs/clang-tidy.md](docs/clang-tidy.md) for the enabled checks,
exclusions, and the reasoning behind them.

The consuming repository must generate `compile_commands.json` before running
`clang-tidy.sh`. Project-specific behavior is configured with command-line
flags or their corresponding environment variables:

```bash
./cpp-tools/clang-tidy.sh \
  --build-dir build-release \
  --file-regex '.*\.(c|cpp|cc|cxx)$'
```

Additional `run-clang-tidy` arguments can be passed after `--`.

## Pre-commit hook

The hook is not installed by default. `install.sh precommit-hook` explicitly
installs `.git/hooks/pre-commit`. The hook formats staged C and C++ files and
re-stages files rewritten by `clang-format`. Re-run the installer after cloning
a fresh checkout.

## GitHub Actions

The scripts automatically enable GitHub annotations and step summaries when
`GITHUB_ACTIONS=true`. Consumer repositories own checkout, tool installation,
and project-specific build preparation, then call their project wrappers:

```yaml
- name: Run clang-format
  env:
    FORMAT_BLOB_SHA: ${{ github.event.pull_request.head.sha || github.sha }}
  run: ./scripts/clang-format.sh

- name: Run clang-tidy
  env:
    TIDY_BLOB_SHA: ${{ github.event.pull_request.head.sha || github.sha }}
  run: ./scripts/clang-tidy.sh --fail-on-warning
```

`FORMAT_BLOB_SHA` and `TIDY_BLOB_SHA` make source links target the pull
request's head commit such that links to violating files render correctly.
The scripts fall back to `GITHUB_SHA` when these values are not supplied.
