# clang-tidy checks

LiveKit C++ projects use `clang-tidy` to detect correctness, safety,
maintainability, and performance issues that ordinary compiler diagnostics may
not catch. These checks are particularly valuable at FFI boundaries and in
media, robotics, and embedded code, where undefined behavior, unsafe
conversions, and lifetime mistakes can be difficult to diagnose.

The configuration is defined at [`.clang-tidy`](../.clang-tidy). This page explains
which checks are enabled, which checks are explicitly excluded, and the reasoning.

A pattern ending in `-*` enables every check in that category unless a later
entry excludes it. A leading `-` disables a check. See the
[complete clang-tidy check list](https://clang.llvm.org/extra/clang-tidy/checks/list.html)
for all available checks.

## Enabled Checks

| Check | Reasoning |
| --- | --- |
| `clang-analyzer-*` | Enables Clang static analyzer checks for issues such as null dereferences, memory leaks, and dead stores. |
| `bugprone-*` | Catches common C++ bugs: use-after-move, dangling references, implicit conversions, incorrect loop logic, etc. |
| `performance-*` | Flags unnecessary copies, inefficient container operations, and missed move opportunities. |
| `modernize-*` | Encourages modern C++17 idioms: `auto`, range-for, `override`, `nullptr`, smart pointers. |
| `readability-misleading-indentation` | Catches indentation that suggests a different control flow than what actually executes. |
| `readability-redundant-smartptr-get` | Flags `ptr.get()` calls where `*ptr` or `ptr->` would suffice – reduces noise and makes smart pointer usage idiomatic. |
| `readability-identifier-naming` | Enforces consistent class and method naming conventions across LiveKit C++ projects. |
| `misc-const-correctness` | Similar to Rust, ensures variables are immutable by default unless intended to be changed. |

## Excluded Checks

| Check | Reasoning |
| --- | --- |
| `-*` (base) | Start from a clean slate rather than enabling all checks (explicitly opt-in to desired checks) |
| `-readability-braces-around-statements` | Style preference (enforces `{ }` around statements. Arguably a good thing but open to debate. |
| `-modernize-use-trailing-return-type` | Would rewrite every function to `auto foo() -> int` style. Opinionated. |
| `-modernize-avoid-c-arrays` | C-style arrays are sometimes necessary for FFI boundaries (interfacing with the Rust bridge and C APIs like `livekit_ffi`). Flagging them all would create false positives at interop boundaries. |
| `-modernize-use-auto` | Flags every case that could use `auto`. This is opinionated and does not add enough value to justify the resulting noise. |
| `-modernize-use-nodiscard` | Adding `[[nodiscard]]` everywhere is noisy and better done intentionally by the developer on APIs where ignoring the return value is genuinely a bug. Not clear but may be a breaking API change for downstream users that are discarding return results today. |
| `-bugprone-easily-swappable-parameters` | Fires on any function with consecutive parameters of the same type (e.g., `(int width, int height)`). Extremely noisy for a codebase with many similarly-typed parameters in media/audio APIs. |
| `-performance-enum-size` | Fairly noisy and low impact performance-wise. Possibly good to turn on in the future. |
| `-modernize-return-braced-init-list` | Decided against it during review. |
| `-modernize-type-traits` | Lots of existing type traits code not using this style, could be breaking change. |

## Warnings Treated as Errors

The following findings are promoted to errors because they generally indicate
correctness or safety defects. In GitHub Actions, the shared scripts surface
findings as annotations and in the step summary. Consumer workflows may also
use `--fail-on-warning` to reject any remaining warning.

| Check | Reasoning |
| --- | --- |
| `clang-analyzer-*` | Static analyzer findings (null dereference, memory leaks, dead stores) are almost always real bugs. Failing the build on these prevents them from merging. |
| `bugprone-use-after-move` | Accessing an object after `std::move` is undefined behavior. Critical in a codebase that passes ownership of SDK handles and shared pointers. |
| `bugprone-dangling-handle` | Detects references/views to temporaries that go out of scope. Especially relevant with `std::string_view` and callback patterns used throughout the SDK. |
| `bugprone-infinite-loop` | Catches loops whose condition can never become false. A hard hang in a real-time media SDK is worse than a crash. |
| `bugprone-narrowing-conversions` | Implicit narrowing (e.g., `int64_t` to `int32_t`) can silently corrupt audio frame sizes, sample rates, or timestamps. |
| `bugprone-undefined-memory-manipulation` | Flags `memset`/`memcpy` on non-trivially-copyable types. The SDK copies raw audio/video frame buffers and this ensures those operations are safe. |
| `bugprone-move-forwarding-reference` | Calling `std::move` on a forwarding reference instead of `std::forward` breaks perfect forwarding. Subtle and hard to catch in review. |
| `bugprone-incorrect-roundings` | Detects `(x + 0.5)` cast-to-int patterns that fail for negative numbers. Relevant for audio sample math and timestamp calculations. |
| `bugprone-sizeof-expression` | Catches `sizeof(ptr)` when `sizeof(*ptr)` was intended – common source of buffer size bugs in code that handles raw media buffers. |
| `bugprone-string-literal-with-embedded-nul` | A `\0` inside a string literal silently truncates it. Would cause hard-to-debug issues in protocol payloads or RPC method names. |
| `bugprone-suspicious-memset-usage` | Catches `memset(ptr, size, 0)` where arguments are swapped. Would silently corrupt audio frame buffers. |

## Formatting

These settings keep `clang-tidy` fixes and identifier naming consistent with the
shared LiveKit C++ style.

| Setting | Reasoning |
| --- | --- |
| `FormatStyle: file` | Uses the project’s `.clang-format` for any auto-fix formatting, keeping fixes consistent with the existing code style. |
| `readability-identifier-naming.ClassCase: CamelCase` | Requires class names to use `CamelCase`. |
| `readability-identifier-naming.MethodCase: camelBack` | Requires method names to use `camelBack`. |

## Other Settings

These options control tool-wide behavior or individual checks.

| Setting | Reasoning |
| --- | --- |
| `modernize-use-nullptr.NullMacros: NULL` | Tells the nullptr modernizer to also replace `NULL` macros (common in C-interop code from the FFI bridge). |
