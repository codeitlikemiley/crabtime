import SwiftUI

struct MarkdownDocumentView: View {
    enum SizingMode {
        case intrinsicHeight
        case fill
    }

    let markdown: String
    var sourceURL: URL? = nil
    var sizingMode: SizingMode = .intrinsicHeight
    @State private var contentHeight: CGFloat = 140

    var body: some View {
        MarkdownPreviewView(
            markdown: markdown,
            sourceURL: sourceURL,
            sizingMode: sizingMode,
            contentHeight: $contentHeight
        )
        .frame(
            minHeight: sizingMode == .intrinsicHeight ? max(140, contentHeight) : 0,
            idealHeight: sizingMode == .intrinsicHeight ? contentHeight : nil,
            maxHeight: sizingMode == .fill ? .infinity : nil
        )
    }
}
