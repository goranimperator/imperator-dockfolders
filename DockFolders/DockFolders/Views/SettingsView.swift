import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra: Bool = true
    @AppStorage("showMainWindow") private var showMainWindow: Bool = true
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: $openAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: openAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Window") {
                Toggle("Show in menu bar", isOn: $showMenuBarExtra)
                    .toggleStyle(.switch)
                Toggle("Show main window on launch", isOn: $showMainWindow)
                    .toggleStyle(.switch)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
        .tint(AppColors.brand)
    }
}

/// Footer launch-at-login row. Same structure as the one in Imperator
/// MenuBarFolders so the two apps read identically: caption label, the stock
/// switch tinted brand, and the whole row fading in on hover.
///
/// No frame on the switch here: this row is left-aligned with nothing to line
/// its right edge up against, so the layout size the switch claims does not
/// matter. The sidebar settings rows in ContentView do need it, because their
/// controls share a right edge.
struct LaunchAtLoginToggle: View {
    @State private var isEnabled = SMAppService.mainApp.status == .enabled
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text("Open at Login")
                .font(.caption)
            Toggle("Open at Login", isOn: $isEnabled)
                .toggleStyle(.switch)
                .scaleEffect(0.55)
                .tint(AppColors.brand)
                .labelsHidden()
                .onChange(of: isEnabled) { _, newValue in
                    do {
                        if newValue { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        isEnabled = SMAppService.mainApp.status == .enabled
                    }
                }
        }
        .opacity(isHovered ? 1.0 : 0.45)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
