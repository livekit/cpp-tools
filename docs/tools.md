# LiveKit C++ Tools

This repository owns shared C++ formatting and static-analysis policy for
LiveKit C++ projects.

## Configs

Consumer repositories should expose root-level symlinks so editor extensions
and local command-line tools can discover the standard config files:

```bash
ln -s cpp-tools/configs/.clang-format .clang-format
ln -s cpp-tools/configs/.clang-tidy .clang-tidy
```

## clang-format

Run from a consuming repository root:

```bash
./cpp-tools/scripts/clang-format.sh
./cpp-tools/scripts/clang-format.sh --fix
```

By default the script scans existing `src/`, `include/`, and `benchmarks/`
trees. Repos with different layouts can pass `--path` repeatedly or set
`CLANG_FORMAT_PATHS` to a colon-separated list.

## clang-tidy

Run after the consuming repository has generated `compile_commands.json`:

```bash
./cpp-tools/scripts/clang-tidy.sh
./cpp-tools/scripts/clang-tidy.sh --fail-on-warning
```

Project-specific behavior is configured with command-line flags or environment
variables:

```bash
./cpp-tools/scripts/clang-tidy.sh \
  --build-dir build-release \
  --file-regex '.*src/.*\.(c|cpp|cc|cxx)$' \
  --header-filter '.*/(include|src)/.*\.(h|hpp)$' \
  --exclude-header-filter '(.*/tests/.*)|(.*/build-[^/]*/.*)'
```

## Pre-commit Hook

Install the shared auto-format hook from a consuming repository:

```bash
./cpp-tools/scripts/install-pre-commit.sh
```

The hook formats staged C/C++ files and re-stages any files rewritten by
`clang-format`.
