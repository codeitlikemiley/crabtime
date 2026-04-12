import SwiftUI

enum CrabTimeTheme {
    enum Layout {
        static let outerPadding: CGFloat = 14
        static let shellPadding: CGFloat = 0
        static let columnSpacing: CGFloat = 14
        static let sidebarWidth: CGFloat = 60
        static let problemWidth: CGFloat = 348
        static let inspectorWidth: CGFloat = 400
        static let cornerRadius: CGFloat = 22
        static let cardPadding: CGFloat = 16
        static let iconButtonSize: CGFloat = 34
        static let shellHeaderHeight: CGFloat = 36
        static let subpanelRadius: CGFloat = 18
        static let compactSpacing: CGFloat = 10
    }

    enum Palette {
        static let backgroundTop = Color(red: 0.05, green: 0.06, blue: 0.09)
        static let backgroundBottom = Color(red: 0.02, green: 0.03, blue: 0.05)
        static let glowTop = Color(red: 0.82, green: 0.29, blue: 0.06)
        static let glowBottom = Color(red: 0.28, green: 0.60, blue: 0.77)
        static let panelTint = Color(red: 1.0, green: 0.74, blue: 0.66)
        static let cyan = Color(red: 0.56, green: 0.82, blue: 1.0)
        static let ember = Color(red: 0.82, green: 0.29, blue: 0.06)
        static let moss = Color(red: 0.47, green: 0.84, blue: 0.63)
        static let ink = Color(red: 0.96, green: 0.96, blue: 0.98)
        static let textMuted = Color.white.opacity(0.64)
        static let glassTint = Color.white.opacity(0.015)
        static let divider = Color.white.opacity(0.07)
        static let strongDivider = Color.white.opacity(0.16)
        static let selectionFill = Color(red: 0.82, green: 0.29, blue: 0.06).opacity(0.16)
        static let editorBackground = Color(red: 0.06, green: 0.07, blue: 0.10)
        static let editorChrome = Color(red: 0.10, green: 0.11, blue: 0.15)
        static let shellFill = Color.clear
        static let panelFill = Color(red: 0.09, green: 0.10, blue: 0.14).opacity(0.94)
        static let raisedFill = Color(red: 0.12, green: 0.13, blue: 0.18).opacity(0.97)
        static let subtleFill = Color.white.opacity(0.035)
        static let buttonFill = Color.white.opacity(0.06)
        static let buttonActiveFill = Color(red: 0.82, green: 0.29, blue: 0.06).opacity(0.22)
        static let terminalFill = Color(red: 0.04, green: 0.05, blue: 0.07).opacity(0.96)
    }
}
