# cpp-tools

Standardized tools for LiveKit C++ projects.

This repository is intended to be consumed as a git submodule by LiveKit C++
repositories. It provides the shared source of truth for:

- `clang-format` style (`configs/.clang-format`)
- `clang-tidy` checks (`configs/.clang-tidy`)
- local and CI wrapper scripts under `scripts/`
- documentation for the shared tooling under `docs/`

Consumer repositories should expose root-level symlinks for `.clang-format` and
`.clang-tidy` so editor integrations can find them, and should pass
project-specific paths/build filters to the shared scripts.

See [docs/tools.md](docs/tools.md) for usage.
