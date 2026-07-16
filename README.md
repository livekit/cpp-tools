# cpp-tools

Standardized formatting, static-analysis, and documentation checks for LiveKit
C++ projects.

This repository is intended to be consumed as a git submodule by LiveKit C++
repositories.

## Quick start

From the consuming repository root, install the shared configuration symlinks:

```bash
./cpp-tools/install.sh
```

The installer creates `.clang-format` and `.clang-tidy` links at the consumer
root. It refuses to replace existing files unless `--force` is passed. Use
`--repo-root PATH` when the consumer root cannot be detected automatically.

Run the tools from the same directory:

```bash
# Check formatting or rewrite files in place.
./cpp-tools/clang-format.sh
./cpp-tools/clang-format.sh --fix

# Run static analysis after generating compile_commands.json.
./cpp-tools/clang-tidy.sh
./cpp-tools/clang-tidy.sh --fail-on-warning
```

Optionally install the optional auto-format pre-commit hook, which runs the above tools automatically on commit to save CI iterations:

```bash
./cpp-tools/install-pre-commit.sh
```

## What this repository provides

The shared source of truth includes:

- `clang-format` style (`.clang-format`)
- `clang-tidy` checks (`.clang-tidy`)
- local and CI wrapper scripts at the repository root
- reusable GitHub Actions workflow under `.github/workflows/cpp-tools.yml`

Consumer repositories should expose root-level symlinks for `.clang-format` and
`.clang-tidy` so editor integrations can find them, and should pass
project-specific paths/build filters to the shared scripts.

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

`install-pre-commit.sh` installs `.git/hooks/pre-commit`. The hook formats
staged C and C++ files and re-stages files rewritten by `clang-format`.
Re-run the installer after cloning a fresh checkout.

## GitHub Actions

Consumer repositories can delegate checks to the reusable workflow:

```yaml
jobs:
  cpp-tools:
    uses: livekit/cpp-tools/.github/workflows/cpp-tools.yml@main
    with:
      clang_format: true
      clang_tidy: true
```

The boolean inputs enable the corresponding jobs. Repository-specific commands
and filters are supplied with string inputs such as
`clang_tidy_configure_command`, `clang_tidy_generate_command`,
`clang_tidy_file_regex`, and `clang_format_paths`.
