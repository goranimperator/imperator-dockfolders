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
                Toggle("Show main window on launch", isOn: $showMainWindow)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
        .tint(AppColors.brand)
    }
}
