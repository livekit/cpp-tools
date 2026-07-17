# cpp-tools

Standardized tools for LiveKit C++ projects. This repository provides:

- [clang-format](https://clang.llvm.org/docs/ClangFormat.html): Code styling consistency across projects
- [clang-tidy](https://clang.llvm.org/extra/clang-tidy/): Static analysis and bug catching
- Base [AGENTS.md](./AGENTS.md) with C++ best practices
- Helper scripts and GitHub actions reporting support

This repository is intended to be consumed as a git submodule.

## Quick start

Add this repository as a submodule from the consuming repository root:

```bash
git submodule add https://github.com/livekit/cpp-tools.git cpp-tools
```

Install the shared configuration symlinks:

```bash
./cpp-tools/install.sh  # Installs .clang-format and .clang-tidy symlinks to repo root
```

Optionally install a precommit hook that automatically runs `clang-format` before commits:

```bash
./cpp-tools/install.sh precommit-hook   # Installs precommit hook
```

Run the tools from the repository root:

```bash
# Check formatting or rewrite files in place.
./cpp-tools/clang-format.sh --path path/to/sources
./cpp-tools/clang-format.sh --path path/to/sources --fix

# Run static analysis after generating compile_commands.json.
./cpp-tools/clang-tidy.sh --file-regex '.*\.(c|cpp|cc|cxx)$'
./cpp-tools/clang-tidy.sh --file-regex '.*\.(c|cpp|cc|cxx)$' --fail-on-warning
```

Update existing `AGENTS.md` file to reference this one:

```markdown
## Shared C++ baseline
Follow `cpp-tools/AGENTS.md` for shared LiveKit C++ engineering guidance.
Instructions in this file are project-specific and take precedence if they
conflict with the shared baseline.
```

## Tool wrappers

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
