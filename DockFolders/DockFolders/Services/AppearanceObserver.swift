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
        isDark = currentIsDark()
        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                let newValue = self.currentIsDark()
                if self.isDark != newValue {
                    self.isDark = newValue
                    self.regenerateIcons()
                }
            }
        }
    }

    private func currentIsDark() -> Bool {
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
