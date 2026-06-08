# Build Environment (important)

This machine's default Swift toolchains do not work for this package:

- **CLT Swift 6.1.2** (`/usr/bin/swift`) crashes in `swift build` due to an llbuild
  symbol mismatch (`depedencyDataFormat` vs `dependencyDataFormat`). Unusable.
- **Xcode 14.2** ships Swift 5.7.1, older than this package's `swift-tools-version: 5.9`. Too old.

**Use Homebrew Swift 6.2.4 for everything:**

```bash
SW=/opt/homebrew/opt/swift/bin/swift
$SW build
$SW test
$SW build -c release   # for bundling
```

A harmless `warning: Unable to locate libSwiftScan` may print; ignore it.

## Tests use Swift Testing, NOT XCTest

Homebrew Swift cannot run XCTest here (no usable Xcode platform). All tests use the
**Swift Testing** framework. The implementation plan's test snippets are written in
XCTest — translate them mechanically:

| XCTest | Swift Testing |
|---|---|
| `import XCTest` | `import Testing` |
| `final class FooTests: XCTestCase { func testBar() {...} }` | `@Suite struct FooTests { @Test func bar() {...} }` (or free `@Test func`) |
| `func testBar() throws` | `@Test func bar() throws` |
| `XCTAssertEqual(a, b)` | `#expect(a == b)` |
| `XCTAssertNil(x)` | `#expect(x == nil)` |
| `XCTAssertNotNil(x)` | `#expect(x != nil)` |
| `XCTAssertTrue(c)` | `#expect(c)` |
| `XCTAssertFalse(c)` | `#expect(!c)` |
| `try XCTUnwrap(x)` | `try #require(x)` |

Keep test names descriptive and the assertions semantically identical to the plan.
Helper methods inside an `@Suite struct` are allowed (instance methods).
