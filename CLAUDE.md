# drowsydock

Sleepy Battery: a macOS menu-bar app (Swift 6, macOS 14+, Apple frameworks only). An original cat perches on the Dock and gets drowsier as the battery drains. It is drawn in a click-through overlay window and tracks the Dock through the Accessibility API.

Read CONSTRAINTS.md before writing code. Do not weaken it to make a change pass.

## Layout

- `Sources/DockOverlayKit/`: Dock geometry (AX), overlay window, Accessibility permission. Shared with future Dock apps, so keep it free of battery or mascot knowledge.
- `Sources/SleepyBatteryCore/`: pure logic and value types. No AppKit, SpriteKit, IOKit or AX imports. Everything here is unit-tested.
- `Sources/SleepyBattery/`: the executable. SwiftUI menu bar and settings, the IOKit adapter, the SpriteKit scene, wiring.
- `Tests/`: XCTest, one target per library.
- `docs/manual-qa.md`: checks that need a real Dock, a real charger or an Accessibility grant.

## Commands

(Filled in by the foundation job once the package exists.)

## Swift style

Follow the [Google Swift Style Guide](https://google.github.io/swift/). It includes Apple's [API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) by reference. `swift format` implements the formatting rules and is the arbiter: run `swift format lint --strict --recursive Sources Tests`. Where CONSTRAINTS.md is stricter, CONSTRAINTS.md wins.

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
