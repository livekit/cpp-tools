# AGENTS.md — Shared C++ Engineering Baseline

## Scope

These rules apply to LiveKit C++ projects that consume `cpp-tools`. If a consuming
repository has an `AGENTS.md` with conflicting rules they should take priority.

## Safety and Determinism

- Design for predictable memory use, execution time, and failure behavior.
- Avoid heap allocation when practical. In real-time, callback, and steady-state
  paths, allocate resources during initialization and reuse them.
- Prefer stack storage, RAII, fixed-capacity storage, and bounded pools or
  queues. Document unavoidable dynamic allocation in time-sensitive code.
- Put explicit bounds on queues, retries, buffers, worker counts, and waits.
  Define observable behavior for exhaustion and overload.
- Do not block real-time or callback threads with file/network I/O, sleeps,
  unbounded work, allocation, or contended locks. Offload work through bounded
  mechanisms with clear back-pressure.
- Avoid unbounded recursion and large stack objects. Account for stack limits on
  embedded targets.

## Errors and Failure Modes

- Use return values for expected failures instead of exceptions:
  - `std::optional<T>` when absence is expected and needs no diagnostic.
  - `bool` for a simple success/failure result.
  - `Result<T, E>`, `expected` (C++23 or higher), or equivalent when callers need a typed error.
- Callers must inspect status-bearing return values. Mark important results
  `[[nodiscard]]` where practical.
- Do not throw through C, FFI, callback, destructor, real-time, or
  resource-constrained boundaries.
- Reserve exceptions for genuinely exceptional failures when the consuming
  project permits them. Catch them at a well-defined boundary and convert them
  to the project's error model.
- Validate external inputs and cross-boundary data. Keep state valid on failure
  and prefer fail-safe behavior over partial updates.

## Memory, Ownership, and Lifetime

- Make ownership explicit. Prefer values and RAII types; do not use raw owning
  pointers.
- Use `std::unique_ptr` for exclusive dynamic ownership and `std::shared_ptr`
  only when ownership is genuinely shared.
- Avoid heap allocations as much as possible. If code is heap allocating in a loop
  or a high-frequency path, second guess the design and consider alternatives.
- Keep object lifetimes and teardown order deterministic. Destructors must not
  throw.
- Avoid hidden copies of large buffers. Make copy and move behavior intentional,
  especially for media, sensor, and message data.
- Declare data at the smallest useful scope and initialize it before use.

## Types, Arithmetic, and Units

- Prefer STL types over third-party dependencies when possible.
- Prefer fixed-width integers from `<cstdint>` when width or signedness matters,
  including serialization, FFI, hardware, timestamps, IDs, and public APIs.
- Use platform-sized primitive integers only when the value is intentionally
  platform-sized or compatibility requires it.
- Avoid implicit narrowing and mixed signed/unsigned arithmetic. Validate ranges
  before conversions and arithmetic that can overflow.
- Represent durations and time points with `std::chrono`; use a monotonic clock
  for elapsed time, deadlines, and timeouts.
- Make physical units explicit with strong or clearly named types, such as `_us`
  for microseconds. Do not pass ambiguous raw numeric values across interfaces.

## Concurrency

- Document which threads call an API and whether each type is thread-safe.
- Minimize shared mutable state. Protect it with clear synchronization and keep
  critical sections short.
- Never call user code while holding an internal lock.
- Use bounded waits and define cancellation and shutdown behavior. Join worker
  threads outside locks.
- Treat atomics and lock-free code as specialized tools; document memory-order
  reasoning and test concurrency paths under stress.

## Design and Readability

- Keep functions focused and short, roughly 60 lines or fewer when practical.
- Prefer straightforward control flow over clever abstractions. Document any
  deliberate tradeoff between readability, determinism, and performance.
- Use `enum class`, `nullptr`, explicit conversions, and const-correct
  interfaces.
- Check non-void return values and make ignored results explicit.
- Use `git mv` when moving or renaming tracked files.

## Portability

- Avoid undefined behavior, compiler-specific assumptions, and dependence on
  host endianness, alignment, or primitive widths.
- Keep cross-platform and cross-architecture boundaries explicit. Test all
  supported targets defined by the consuming repository.
- Keep third-party implementation details out of public headers and ABI
  boundaries.

## Style

- Add the LiveKit copyright header with the correct year to new code files.
- Prefer the constructor initializer list rather than variable declaration
  and assignment in the constructor body.
- For Doxygen/doc comments, prefer `///` comment style and use @brief,
  @param, @return, @throw, @ref, @note, @warning as applicable.

## Project-Owned clangd Configuration

- Each consuming project must provide its own `.clangd`; compilation database
  locations and flags are project-specific and are not shared by `cpp-tools`.
- Verify `.clangd` points clangd at the project's generated compilation database
  before relying on IDE diagnostics.
- clang-tidy does not read `.clangd`. Before running clang-tidy, generate a valid
  `compile_commands.json` and pass its build directory to `clang-tidy.sh`.

## Verification

- Adhere to the shared `.clang-format` and `.clang-tidy` configurations.
- After C++ changes, run `./cpp-tools/clang-format.sh` with the consuming
  project's paths. Use `--fix` when needed, then rerun the check.
- Generate the consuming project's compilation database and run
  `./cpp-tools/clang-tidy.sh` with its documented build directory and filters.
- Do not bypass formatter or static-analysis failures. Keep suppressions narrow,
  local, and justified in code.
- Add deterministic tests for normal, boundary, overload, timeout, cancellation,
  and failure behavior. Avoid timing-only sleeps when a condition or simulated
  clock can be used.
- Benchmark or stress-test new time-sensitive or resource-sensitive behavior and
  verify that configured limits are enforced.
