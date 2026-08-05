import AppKit
import Combine
import Foundation

enum ShortcutAssignmentResult: Equatable {
    case saved
    case duplicate
    case reserved
}

@MainActor
final class KeyboardShortcutSettings: ObservableObject {
    @Published private(set) var shortcuts: [AppShortcutAction: KeyboardShortcut]
    @Published private(set) var recordingAction: AppShortcutAction?

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcuts = Dictionary(uniqueKeysWithValues: AppShortcutAction.allCases.map { action in
            let shortcut = Self.load(action: action, defaults: defaults, decoder: JSONDecoder())
                ?? action.defaultShortcut
            return (action, shortcut)
        })
    }

    var isRecording: Bool { recordingAction != nil }

    func shortcut(for action: AppShortcutAction) -> KeyboardShortcut {
        shortcuts[action] ?? action.defaultShortcut
    }

    func action(for event: NSEvent) -> AppShortcutAction? {
        AppShortcutAction.allCases.first { shortcut(for: $0).matches(event) }
    }

    @discardableResult
    func set(
        _ shortcut: KeyboardShortcut,
        for action: AppShortcutAction
    ) -> ShortcutAssignmentResult {
        guard !shortcut.conflictsWithFixedAppCommand else { return .reserved }
        guard !AppShortcutAction.allCases.contains(where: {
            $0 != action && self.shortcut(for: $0) == shortcut
        }) else { return .duplicate }

        shortcuts[action] = shortcut
        persist(shortcut, for: action)
        return .saved
    }

    func beginRecording(_ action: AppShortcutAction) {
        recordingAction = action
    }

    func endRecording(_ action: AppShortcutAction) {
        if recordingAction == action {
            recordingAction = nil
        }
    }

    func reset() {
        for action in AppShortcutAction.allCases {
            let shortcut = action.defaultShortcut
            shortcuts[action] = shortcut
            persist(shortcut, for: action)
        }
    }

    private func persist(_ shortcut: KeyboardShortcut, for action: AppShortcutAction) {
        guard let data = try? encoder.encode(shortcut) else { return }
        defaults.set(data, forKey: Self.storageKey(for: action))
    }

    private static func load(
        action: AppShortcutAction,
        defaults: UserDefaults,
        decoder: JSONDecoder
    ) -> KeyboardShortcut? {
        guard let data = defaults.data(forKey: storageKey(for: action)) else { return nil }
        return try? decoder.decode(KeyboardShortcut.self, from: data)
    }

    private static func storageKey(for action: AppShortcutAction) -> String {
        "keyboardShortcut.\(action.rawValue)"
    }
}
