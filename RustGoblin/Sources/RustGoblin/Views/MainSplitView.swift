import SwiftUI

struct MainSplitView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var store = store

        GeometryReader { proxy in
            HStack(alignment: .top, spacing: RustGoblinTheme.Layout.columnSpacing) {
                WorkspaceRailView()
                    .frame(width: RustGoblinTheme.Layout.sidebarWidth)

                ProblemBrowserView()
                    .frame(width: store.showsProblemPane ? problemWidth(in: proxy.size.width) : 0)
                    .opacity(store.showsProblemPane ? 1 : 0)
                    .allowsHitTesting(store.showsProblemPane)
                    .clipped()

                EditorWorkbenchView()
                    .frame(maxWidth: store.showsEditorPane ? .infinity : 0, maxHeight: .infinity)
                    .opacity(store.showsEditorPane ? 1 : 0)
                    .allowsHitTesting(store.showsEditorPane)
                    .clipped()

                InspectorSidebarView()
                    .frame(width: store.showsInspector ? inspectorWidth(in: proxy.size.width) : 0)
                    .opacity(store.showsInspector ? 1 : 0)
                    .allowsHitTesting(store.showsInspector)
                    .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(layoutAnimation, value: store.contentDisplayMode)
            .animation(layoutAnimation, value: store.isInspectorVisible)
            .padding(RustGoblinTheme.Layout.outerPadding)
            .background(WorkbenchBackgroundView())
        }
    }

    private var layoutAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.16)
    }

    private func problemWidth(in totalWidth: CGFloat) -> CGFloat {
        min(RustGoblinTheme.Layout.problemWidth, max(312, totalWidth * 0.24))
    }

    private func inspectorWidth(in totalWidth: CGFloat) -> CGFloat {
        min(RustGoblinTheme.Layout.inspectorWidth, max(280, totalWidth * 0.20))
    }
}
