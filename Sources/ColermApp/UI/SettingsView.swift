import SwiftUI

struct SettingsView: View {
    @ObservedObject var shortcutSettings: KeyboardShortcutSettings
    @ObservedObject var workspaceLayoutSettings: WorkspaceLayoutSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspace")
                    .font(.title2.weight(.semibold))
                Text("Choose how terminal tabs are arranged.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                Toggle(
                    "Vertical Tabs",
                    isOn: Binding(
                        get: { workspaceLayoutSettings.isVerticalTabsEnabled },
                        set: { workspaceLayoutSettings.setVerticalTabsEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .accessibilityHint("Places terminal tabs in a sidebar")
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text("Keyboard Shortcuts")
                    .font(.title2.weight(.semibold))
                Text("Click a shortcut, then press the new key combination.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(AppShortcutAction.allCases.enumerated()), id: \.element) { index, action in
                    ShortcutSettingsRow(settings: shortcutSettings, action: action)
                    if index < AppShortcutAction.allCases.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Spacer()
                Button("Restore Defaults") {
                    shortcutSettings.reset()
                    workspaceLayoutSettings.reset()
                }
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}

private struct ShortcutSettingsRow: View {
    @ObservedObject var settings: KeyboardShortcutSettings
    let action: AppShortcutAction
    @State private var validationMessage: String?
    @State private var focusID = UUID()

    var body: some View {
        Button(action: beginRecording) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(.body.weight(.medium))
                    if isRecording {
                        Text(validationMessage ?? "Press a shortcut · Esc to cancel")
                            .font(.caption)
                            .foregroundStyle(validationMessage == nil ? Color.secondary : Color.orange)
                    }
                }

                Spacer()

                HStack(spacing: 3) {
                    ForEach(Array(settings.shortcut(for: action).displayComponents.enumerated()), id: \.offset) { _, component in
                        Text(component)
                            .font(.system(size: 12, weight: .medium))
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                .opacity(isRecording ? 0.45 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay {
            if isRecording {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 1)
                    .padding(2)
            }
        }
        .overlay {
            if isRecording {
                ShortcutRecorderView(
                    focusID: focusID,
                    onShortcut: save,
                    onCancel: cancel,
                    onInvalid: { validationMessage = "Include ⌘, ⌥, or ⌃" }
                )
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("\(action.title) shortcut")
        .accessibilityValue(settings.shortcut(for: action).displayComponents.joined(separator: " "))
        .onDisappear(perform: cancel)
    }

    private var isRecording: Bool {
        settings.recordingAction == action
    }

    private func beginRecording() {
        settings.beginRecording(action)
        validationMessage = nil
        focusID = UUID()
    }

    private func save(_ shortcut: KeyboardShortcut) -> Bool {
        switch settings.set(shortcut, for: action) {
        case .saved:
            cancel()
            return true
        case .duplicate:
            validationMessage = "Already used by another shortcut"
            focusID = UUID()
            return false
        case .reserved:
            validationMessage = "Reserved by an app command"
            focusID = UUID()
            return false
        }
    }

    private func cancel() {
        settings.endRecording(action)
        validationMessage = nil
    }
}
