import SwiftUI

struct EditorWorkbenchView: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        GeometryReader { proxy in
            switch store.terminalDisplayMode {
            case .hidden:
                CodeEditorPaneView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .maximized:
                ConsolePanelView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .split:
                VStack(spacing: CrabTimeTheme.Layout.columnSpacing) {
                    CodeEditorPaneView()
                        .frame(height: editorHeight(in: proxy.size.height))

                    ConsolePanelView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                store.setExplorerKeyboardFocus(active: false)
            }
        )
    }

    private func editorHeight(in totalHeight: CGFloat) -> CGFloat {
        min(max(360, totalHeight * 0.58), max(360, totalHeight - 240))
    }
}
