import SwiftUI

struct SetupWizardView: View {
    let status: DependencyManager.Status
    let onInstall: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 64))
                .foregroundStyle(RustGoblinTheme.Palette.panelTint)
            
            VStack(spacing: 8) {
                Text("Setup Required")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(RustGoblinTheme.Palette.ink)
                
                Text("RustGoblin needs some system tools to function properly.")
                    .font(.body)
                    .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                switch status {
                case .unknown, .checking:
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking dependencies...")
                            .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                case .missing(let needsRust, let needsExercism):
                    VStack(alignment: .leading, spacing: 12) {
                        if needsRust {
                            MissingDependencyRow(name: "Rust & Cargo", icon: "cube.box.fill")
                        }
                        if needsExercism {
                            MissingDependencyRow(name: "Exercism CLI", icon: "paperplane.fill")
                        }
                    }
                    .padding()
                    .background(RustGoblinTheme.Palette.panelTint.opacity(0.1))
                    .cornerRadius(RustGoblinTheme.Layout.subpanelRadius)
                    
                    Button(action: onInstall) {
                        Text("Install Missing Tools")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RustGoblinTheme.Palette.panelTint)
                            .cornerRadius(RustGoblinTheme.Layout.cornerRadius)
                    }
                    .buttonStyle(.plain)
                    .interactivePointer()
                    
                case .installing(let component, let progress, let message):
                    VStack(spacing: 12) {
                        Text("Installing \(component)...")
                            .font(.headline)
                            .foregroundStyle(RustGoblinTheme.Palette.ink)
                        
                        ProgressView(value: progress)
                            .tint(RustGoblinTheme.Palette.panelTint)
                        
                        Text(message)
                            .font(.caption.monospaced())
                            .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    
                case .failed(let error):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.largeTitle)
                        
                        Text("Installation Failed")
                            .font(.headline)
                        
                        ScrollView {
                            Text(error)
                                .font(.caption.monospaced())
                                .foregroundStyle(RustGoblinTheme.Palette.ember)
                        }
                        .frame(maxHeight: 100)
                        
                        Button("Retry") {
                            onInstall()
                        }
                        .padding(.top)
                    }
                    
                case .ready:
                    Text("All dependencies installed!")
                        .font(.headline)
                        .foregroundStyle(RustGoblinTheme.Palette.moss)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: 400)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RustGoblinTheme.Palette.panelFill)
    }
}

private struct MissingDependencyRow: View {
    let name: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(RustGoblinTheme.Palette.panelTint)
                .frame(width: 24)
            Text(name)
                .font(.body.weight(.medium))
                .foregroundStyle(RustGoblinTheme.Palette.ink)
            Spacer()
            Text("Missing")
                .font(.caption.bold())
                .foregroundStyle(RustGoblinTheme.Palette.ember)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RustGoblinTheme.Palette.ember.opacity(0.12))
                .cornerRadius(4)
        }
    }
}
