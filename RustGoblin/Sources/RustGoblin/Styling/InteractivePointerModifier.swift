import AppKit
import SwiftUI

struct InteractivePointerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

extension View {
    func interactivePointer() -> some View {
        modifier(InteractivePointerModifier())
    }
}
