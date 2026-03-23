import XCTest
@testable import MarkdownViewer

final class MarkdownRendererTests: XCTestCase {
    func testRendersHeadingsParagraphsAndListsAsSeparateBlocks() throws {
        let markdown = """
        # Title

        Intro paragraph.

        - One
        - Two

        ## Next

        More text.
        """

        let html = try MarkdownRenderer.render(markdown)

        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<p>Intro paragraph.</p>"))
        XCTAssertTrue(html.contains("<ul><li>One</li><li>Two</li></ul>"))
        XCTAssertTrue(html.contains("<h2>Next</h2>"))
        XCTAssertTrue(html.contains("<p>More text.</p>"))
    }

    func testRendersBlockquoteAndInlineCode() throws {
        let markdown = """
        > Quote line

        Use `code` here.
        """

        let html = try MarkdownRenderer.render(markdown)

        XCTAssertTrue(html.contains("<blockquote>"))
        XCTAssertTrue(html.contains("<p>Quote line</p>"))
        XCTAssertTrue(html.contains("<p>Use <code>code</code> here.</p>"))
    }
}
