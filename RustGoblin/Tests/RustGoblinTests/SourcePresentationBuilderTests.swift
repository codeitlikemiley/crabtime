import XCTest
@testable import RustGoblin

final class SourcePresentationBuilderTests: XCTestCase {
    func testBuildHidesShebangManifestAndTests() {
        let source = """
        #!/usr/bin/env -S cargo +nightly -Zscript
        ---
        [dependencies]
        anyhow = "1"
        ---

        fn main() {
            println!("hello");
        }

        #[cfg(test)]
        mod tests {
            #[test]
            fn example_case() {
                assert_eq!(2 + 2, 4);
            }
        }
        """

        let presentation = SourcePresentationBuilder().build(from: source)

        XCTAssertEqual(
            presentation.visibleSource,
            """
            fn main() {
                println!("hello");
            }

            """
        )
        XCTAssertEqual(presentation.hiddenChecks.map(\.id), ["example_case"])
        XCTAssertTrue(presentation.prefix.contains("#!/usr/bin/env"))
        XCTAssertTrue(presentation.suffix.contains("mod tests"))
    }

    func testRebuildPreservesHiddenSections() {
        let source = """
        #!/usr/bin/env bash

        fn main() {
            println!("old");
        }

        #[cfg(test)]
        mod tests {
            #[test]
            fn smoke() {
                assert!(true);
            }
        }
        """

        let presentation = SourcePresentationBuilder().build(from: source)
        let rebuilt = presentation.rebuild(
            with: """
            fn main() {
                println!("new");
            }
            """
        )

        XCTAssertTrue(rebuilt.contains("#!/usr/bin/env bash"))
        XCTAssertTrue(rebuilt.contains("mod tests"))
        XCTAssertTrue(rebuilt.contains("println!(\"new\")"))
        XCTAssertFalse(rebuilt.contains("println!(\"old\")"))
    }

    func testBuildIgnoresIgnoredHiddenTests() {
        let source = """
        fn main() {}

        #[cfg(test)]
        mod tests {
            #[test]
            fn active_case() {}

            #[test]
            #[ignore]
            fn skipped_case() {}
        }
        """

        let presentation = SourcePresentationBuilder().build(from: source)

        XCTAssertEqual(presentation.hiddenChecks.map(\.id), ["active_case"])
    }
}
