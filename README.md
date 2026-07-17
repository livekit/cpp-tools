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
./cpp-tools/clang-format.sh
./cpp-tools/clang-format.sh --fix

# Run static analysis after generating compile_commands.json.
./cpp-tools/clang-tidy.sh
./cpp-tools/clang-tidy.sh --fail-on-warning
```

## What this repository provides

The shared source of truth includes:

- `clang-format` style (`.clang-format`)
- `clang-tidy` checks (`.clang-tidy`)
- shared C++ engineering guidance (`AGENTS.md`)
- local and CI wrapper scripts at the repository root
- reusable GitHub Actions workflow under `.github/workflows/cpp-tools.yml`

Consumer repositories should expose root-level symlinks for `.clang-format` and
`.clang-tidy` so editor integrations can find them, and should pass
project-specific paths/build filters to the shared scripts.

Their root `AGENTS.md` should reference `cpp-tools/AGENTS.md` as the shared C++
baseline and add only repository-specific architecture and workflow guidance.

## clang-format

By default, `clang-format.sh` checks tracked C and C++ files in existing
`src/`, `include/`, and `benchmarks/` trees. Repositories with different
layouts can pass `--path` repeatedly:

```bash
./cpp-tools/clang-format.sh \
  --path src/first_package \
  --path src/second_package
```

The `CLANG_FORMAT_PATHS` environment variable provides the same configuration
as a colon-separated list. Positional file paths restrict the check to those
files.

## clang-tidy

The consuming repository must generate `compile_commands.json` before running
`clang-tidy.sh`. Project-specific behavior is configured with command-line
flags or their corresponding environment variables:

```bash
./cpp-tools/clang-tidy.sh \
  --build-dir build-release \
  --file-regex '.*src/.*\.(c|cpp|cc|cxx)$' \
  --header-filter '.*/(include|src)/.*\.(h|hpp)$' \
  --exclude-header-filter '(.*/tests/.*)|(.*/build-[^/]*/.*)'
```

Use `--require-generated-protobuf PATH` when generated protobuf headers must
exist before analysis. Additional `run-clang-tidy` arguments can be passed
after `--`.

## Pre-commit hook

The hook is not installed by default. `install.sh precommit-hook` explicitly
installs `.git/hooks/pre-commit`. The hook formats staged C and C++ files and
re-stages files rewritten by `clang-format`. Re-run the installer after cloning
a fresh checkout.

## GitHub Actions

Consumer repositories can delegate checks to the reusable workflow:

```yaml
jobs:
  cpp-tools:
    uses: livekit/cpp-tools/.github/workflows/cpp-tools.yml@main
    with:
      clang_format: true
      clang_tidy: true
      clang_tidy_fail_on_warning: true
      clang_tidy_file_regex: '.*\.(c|cpp|cc|cxx)$'
```

The workflow documents each supported input alongside its default.
`clang_tidy_file_regex` is required because source layouts and exclusions are
consumer-specific. Other repository-specific commands and filters are supplied
with inputs such as `clang_tidy_configure_command`,
`clang_tidy_generate_command`, and `clang_format_paths`.
