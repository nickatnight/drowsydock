# drowsydock

DrowsyDock: a macOS menu-bar app (Swift 6, macOS 14+, Apple frameworks only). An original cat perches on the Dock and gets drowsier as the battery drains. It is drawn in a click-through overlay window and tracks the Dock through the Accessibility API.

Read CONSTRAINTS.md before writing code. Do not weaken it to make a change pass.

## Layout

- `Sources/DockOverlayKit/`: Dock geometry (AX), overlay window, Accessibility permission, and `MirroredLogger`, which every log line goes through (ADR 0020). Every message is public in the unified log and the QA log, so log no user data. Shared with future Dock apps, so keep it free of battery or mascot knowledge.
- `Sources/DrowsyDockCore/`: pure logic and value types. No AppKit, SpriteKit, IOKit or AX imports. Everything here is unit-tested.
- `Sources/DrowsyDock/`: the executable. SwiftUI menu bar and settings, the IOKit adapter, the SpriteKit scene, wiring.
- `Tests/`: XCTest, one target per library, plus `DrowsyDockTests` for the app (`@testable import DrowsyDock`, snapshot references under `Snapshots/`, ADR 0016) and `LiveQAKitTests` for the live QA helper. `DockOverlayKitTestSupport` is a library both overlay test targets import: `FadeRecorder`, through `OverlayWindow`'s `package` fade seam.
- `scripts/qa/`: the live QA helper (`qa-helper`, its pure checks in `LiveQAKit`), `dock-preferences.sh` (the Dock backup and restore that `qa-live.sh` sources), `live-functions.sh` (every function `qa-live.sh` runs, sourced so the checks can call them; it names every app log line it waits for as a `log_…` pattern, which `QALogMessageTests` checks against the app's messages, so a scenario reads the log only through those names), and the checks `check.sh fast` runs on them: `check-dry-run.sh`, `check-dock-restore.sh` (the restore against a scratch defaults domain, never `com.apple.dock`), `check-restore-selftest.sh` (`qa-live.sh`'s restore self-test and exit cleanup on a scratch domain, needs the built `qa-helper`), `check-app-log.sh` (`qa-live.sh`'s log reads over `Tests/LiveQAKitTests/Fixtures/qa.log`, needs the built `qa-helper`), `check-qa-mapping.sh` and its `check-qa-mapping-selftest.sh`. The app bundle never includes any of it.
- `docs/manual-qa.md`: every QA row, mapped to the test or `scripts/qa-live.sh` scenario that covers it, with a short manual checklist for what needs hardware, a permission dialog or an eye.
- `docs/adr/`: architecture decision records, kept only on the owner's machine: git ignores `docs/` except `docs/manual-qa.md` and `docs/qa-rows.txt`, so a fresh clone has no ADRs. The "ADR NNNN" citations in code and docs name these files. Where they exist, read them before changing the build setup (0001), the target split (0002), the drowsiness tracker's phases (0003), the Dock tracker's phases and triggers (0004), signing (0005, 0007), the Accessibility coordinate handling (0006) the mascot's windows and renderer (0008), how it animates within the CPU budget (0009, 0011, 0015, 0017), how `waking` ends (0010), where animation timing lives (0012, 0014) how the veil and the perch fit the Dock's drawn background (0013) how the app is tested (0016), how the live QA script drives the app and the Dock (0018) and reads the app's QA log (0020), or how test helpers reach a module's seams (0019). Supersede an ADR with a new one; don't edit its decision.

## Commands

```
Build:   swift build -Xswiftc -warnings-as-errors
Test:    swift test
Cover:   swift test --enable-code-coverage
Record:  RECORD_SNAPSHOTS=1 swift test      # rewrites the snapshot references, then fails on purpose
Format:  swift format lint --strict --recursive Sources scripts/qa/Sources Tests
Bundle:  scripts/bundle.sh                 # → build/DrowsyDock.app, universal, ad-hoc signed
Run:     open build/DrowsyDock.app
Quit:    pkill -x DrowsyDock
Logs:    open build/DrowsyDock.app --args --qa-log && tail -F ~/Library/Logs/DrowsyDock/qa.log
         log stream --level debug --predicate 'subsystem == "com.drowsydock.DrowsyDock"'   # admin only
Checks:  scripts/check.sh fast | task
Live QA: scripts/qa-live.sh [--only a,b] [--dry-run] [--list] [--keep-captures]   # the owner runs it; agents only --dry-run
Restore: scripts/qa-live.sh --restore [--yes]   # puts back the Dock preferences a killed run left changed
```

- `scripts/check.sh fast` runs after every edit. It compiles with warnings as errors and runs the format lint. It checks `scripts/qa-live.sh` with `bash -n`, a dry run that must call no Dock, app, pointer, screen or log command and write nothing (`scripts/qa/check-dry-run.sh`), the Dock restore and the restore self-test on a scratch domain (`scripts/qa/check-dock-restore.sh`, `scripts/qa/check-restore-selftest.sh`), and the script's log reads over a fixture QA log (`scripts/qa/check-app-log.sh`). It checks the CONSTRAINTS floor rules, keeps `DrowsyDockCore` free of UI and hardware imports, and lets only `MirroredLogger` import `os` (ADR 0020). It requires every coverage-exempt file under `Sources` and `scripts/qa/Sources` to be named in `docs/manual-qa.md`, and every test and live scenario that file cites to exist and each cited scenario to list the row, with each automated row citing at least one and the row numbers equal to `docs/qa-rows.txt` (`scripts/qa/check-qa-mapping.sh`, which `check-qa-mapping-selftest.sh` checks with planted errors). A new QA row goes into both files. Last comes the secret scan (commits, uncommitted files and signing-material file types).
- `scripts/check.sh task` runs before every commit. It runs `fast`, then the tests with coverage, the changed-line coverage gate and the signed bundle. The bundle must carry the hardened runtime (ADR 0005) and no entitlements (ADR 0007). The gate diffs against the merge base with `$CHECK_BASE` (default `main`).
- `scripts/bundle.sh` signs with `$SIGN_IDENTITY`, default `-` (ad hoc), always with `--options runtime`. No signing identity exists yet. Scripts never create certificates or touch the keychain.
- `swift format --in-place --recursive Sources scripts/qa/Sources Tests` fixes most format findings.
- A snapshot mismatch writes the actual and a diff image under `.build/snapshot-failures/` and names them in the failure. The references were recorded on Apple silicon; elsewhere the snapshot tests skip. `DROWSYDOCK_SKIP_SNAPSHOTS=1` (exactly `1`) also skips them, naming the Mac in `RECORDED_ON`; CI sets it, because its runner draws on another GPU and macOS. Local runs leave it unset. Record new references only for a deliberate visual change, and look at the diff.
- `scripts/qa-live.sh` drives the real app and the real Dock. It changes the Dock's preferences through System Events and restores them from `build/qa/dock-backup.plist` on exit, deleting the backup only once the restore verifies; after a kill -9, run the restore command it printed or `--restore`, which shows what it would change and asks first (`--yes` skips the question, and it refuses while a run still owns the backup). Screenshots and samples are deleted when their checks pass; `--keep-captures` keeps them. Never run it for real as an agent: no Dock settings changes, synthetic events or menu driving.

## Git

- Name branches `nickatnight/<short_description>`, e.g. `nickatnight/untrack-docs`.

## Swift style

Follow the [Google Swift Style Guide](https://google.github.io/swift/). It includes Apple's [API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) by reference. `swift format` implements the formatting rules and is the arbiter: run `swift format lint --strict --recursive Sources scripts/qa/Sources Tests`. Where CONSTRAINTS.md is stricter, CONSTRAINTS.md wins.

### Files and imports

- One primary type per file, with the file named after it. Extensions adding a conformance go in `Type+Protocol.swift`, and grab-bag extensions in `Type+Additions.swift`. A type may share a file with its delegate protocol or small helper types.
- Encoding is UTF-8. Indent with spaces only (no tabs). Use `\n`, `\t` and similar escapes rather than `\u{…}`; use `\u{…}` for invisible characters. Never mix literal non-ASCII and `\u{…}` in one string literal.
- Import exactly the modules you use, with no transitive reliance. Use whole-module imports. Imports are never wrapped. Put them in three groups separated by one blank line, each sorted: modules, then individual declarations, then `@testable` (tests only).
- Order members logically (not "append to the end"). Use `// MARK: -` for groups. Overloads (inits, subscripts, same-name functions) must be contiguous.

### Formatting

- **100-column limit.** Allowed exceptions: unbreakable units such as URLs, imports, and generated code. **2-space indent**; continuation lines are +2.
- **K&R braces.** No newline before `{`. Write `} else {` on one line. Empty blocks may be `{}`.
- **No semicolons.** One statement per line. One-liners are OK only for a block of zero or one statements, e.g. `guard x else { return }` or `defer { close() }`.
- **Wrapping:**
  - If it fits on one line, keep it on one line.
  - Lay out comma lists either all horizontal or all vertical. Vertical means a break before the first element and after each element, at +2.
  - Never align to the opening paren.
  - Wrapped function declarations put each parameter at +2, with `)` on its own line followed by `-> Result`.
  - Wrapped calls put each argument at +2.
  - In wrapped `if`/`guard`, continuation lines align after the keyword.
  - If the last continuation line sits at +2, `{` goes on its own line.
- **Spaces:**
  - Write `if (a || b) && c`, never `if(`.
  - Put spaces around binary and ternary operators, `=`, `->` and `&` in compositions.
  - No spaces around `.`, `...` or `..<`.
  - Space after `,` and `:`, never before.
  - Two spaces before an end-of-line `//`.
  - No spaces inside `[ ]` or `( )`.
- **No horizontal alignment** of declarations or comments. The only exception is truly tabular data.
- One blank line between type members. It may be omitted between related one-line stored properties or enum cases. Blank lines inside functions only to separate logical steps.
- No parentheses around `if`/`guard`/`while`/`switch` conditions. Add grouping parens when precedence might be misread.

### Constructs

- Comments use `//` only, never `/* */`. Doc comments use `///` only.
- Declare one variable per `let` or `var`. Tuple destructuring is the exception. Declare locals near first use.
- `case` labels sit at the same indent as `switch`.
- One enum case per line. The comma form is OK only for simple cases with no values that fit on one line.
  - Never write `case foo()`.
  - Mark the whole enum `indirect` when every case is.
  - Order cases logically, or alphabetically when no order is obvious.
- **Trailing closures:**
  - Pass a single final closure argument as a trailing closure, and drop `()` when it is the only argument: `map { $0 * 2 }`.
  - When there are several closure arguments, label all of them and use no trailing closure.
  - Inside `if`/`guard` conditions, use a labeled closure.
  - Don't overload functions that differ only by closure label.
- Use trailing commas in multi-line array and dictionary literals.
- Long numeric literals may use `_` grouping: 3 digits for decimal, 4 for hex.
- Parameterized attributes (`@available(…)`) go on their own line above the declaration, sorted. Bare attributes may share the line if it fits.

### Naming

- Follow the API Design Guidelines: clarity at the point of use, lowerCamelCase for values, UpperCamelCase for types.
- Use access control, not underscores, to hide things.
- Identifiers are ASCII. No emoji identifiers.
- Global constants are lowerCamelCase (`let secondsPerMinute = 60`). No `k` prefix and no SCREAMING_CASE.
- Static members returning their own type have no type suffix: `.default`, `.shared`, `.red`.
- Initializer parameters keep the property name: `self.name = name`.
- **Delegate methods** take the source object first, unlabeled:
  - With no other arguments: `scrollViewDidScroll(_:)`, `scrollViewShouldScrollToTop(_:) -> Bool`, `numberOfSections(in:)`.
  - With more arguments, the base name is the source type: `tableView(_:didSelectRowAt:)`.

### Practices

- **No compiler warnings.** CONSTRAINTS.md enforces this with `-warnings-as-errors`.
- **Initializers:**
  - Rely on the synthesized memberwise init.
  - Never call `ExpressibleBy…Literal` inits directly: write `let x: Kilometers = 10` or `10 as Kilometers`.
  - Call `MyType(…)`, not `MyType.init(…)`. The only exception is a metatype variable: `type.init(…)`.
- Read-only computed properties omit `get {}`.
- **Type spelling:**
  - Use shorthand types: `[T]`, `[K: V]`, `T?`.
  - Function types return `Void`, as in `() -> Void`. Empty parameter lists are `()`.
  - Functions with no return value omit `-> Void`.
- **Optionals and errors:**
  - Use optionals instead of sentinel values such as `-1`.
  - A failable `init?` is OK for a single obvious failure.
  - Use `throws` with a nested `enum …Error: Error` when there are several failure modes.
  - Test presence with `x != nil`, not `if let _ = x`.
- **Forced operations:**
  - No `try!`. This project is stricter than Google here (see CONSTRAINTS.md); tests are exempt.
  - Avoid force-unwraps and force-casts. When one is unavoidable, add a comment stating the invariant that makes it safe. Tests are exempt.
  - Avoid implicitly unwrapped optionals, except for lifecycle-set UI properties, unannotated Objective-C APIs and test fixtures set in `setUp()`.
- **Access and nesting:**
  - Access modifiers go on members, never on the `extension` itself.
  - Nest types that belong to another type (`Parser.Error`).
  - Use a caseless `enum` as a namespace for constants and helpers.
- **Control flow:**
  - Use `guard` for early exits and keep the main path flush left.
  - Write `for x in xs where cond` instead of a body that is a single `if`.
  - No case whose only body is `fallthrough`: combine the patterns instead.
- **Patterns:**
  - Write `let` per binding: `case .pair(let a, let b)`, not `case let .pair(a, b)`. Omit labels that match the binding name.
  - Destructured tuples are unlabeled on the left: `let (a, b) = …`.
- **Literals:**
  - Give a literal a non-default type by annotation or `as` (`let x: Int32 = 5`, `"a" as Character`), not by `Int32(5)` or `Character("a")`.
  - No playground literals (`#colorLiteral`).
- **Arithmetic and operators:**
  - Use trapping arithmetic. `&+` and friends are only for hashing or crypto, or for proven hot paths with a comment explaining why.
  - No custom operators unless the domain meaning is unmistakable.
  - Overload existing operators only with their standard meaning.

### Documentation comments

- Every `public`/`open` declaration gets a `///` comment. Not needed for: self-evident enum cases, overrides and protocol implementations, test code, and extension declarations themselves.
- Start with a one-sentence summary ending in a period. Methods take a verb phrase ("Returns the…", not "This method…"); properties take a noun phrase. Put details in further paragraphs after a blank `///` line.
- Tags go in order: `- Parameter x:` for a single parameter, or `- Parameters:` with a nested list for several; then `- Returns:`; then `- Throws:`. Never leave a tag empty. End each with a period. Indent wrapped lines 2 spaces past the hyphen. Omit tags the summary already covers.
- Don't restate the code ("A representation of…"). Do define terms a reader needs.
