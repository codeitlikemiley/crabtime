import SwiftUI

struct EditorWorkbenchView: View {
    var body: some View {
        VSplitView {
            CodeEditorPaneView()
                .frame(minHeight: 420)

            ConsolePanelView()
                .frame(minHeight: 220)
        }
    }
}
