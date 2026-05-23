import AppKit
import Combine

@MainActor
class AppearanceObserver: ObservableObject {
    @Published var isDark: Bool = false

    private var observation: NSKeyValueObservation?
    private var started = false

    func startObserving() {
        guard !started else { return }
        started = true
        isDark = effectiveIsDark()
        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                let newValue = self.effectiveIsDark()
                if self.isDark != newValue {
                    self.isDark = newValue
                    self.regenerateIcons()
                }
            }
        }
    }

    /// Recalculate isDark based on current appearanceMode setting and regenerate icons if changed.
    func reapply() {
        let newValue = effectiveIsDark()
        if isDark != newValue {
            isDark = newValue
            regenerateIcons()
        }
    }

    private func effectiveIsDark() -> Bool {
        let mode = UserDefaults.standard.string(forKey: "appearanceMode") ?? AppearanceMode.system.rawValue
        if mode == AppearanceMode.dark.rawValue {
            return true
        }
        // system mode — follow actual system appearance
        guard NSApp != nil else { return false }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func regenerateIcons() {
        DispatchQueue.global(qos: .userInitiated).async {
            IconGenerator.regenerateAllIcons()
            DispatchQueue.main.async {
                DockController.shared.refreshDock()
            }
        }
    }
}
