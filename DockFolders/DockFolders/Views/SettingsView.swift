import SwiftUI

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra: Bool = true
    @AppStorage("showMainWindow") private var showMainWindow: Bool = true
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appearanceMode) {
                    guard let delegate = NSApp.delegate as? AppDelegate else { return }
                    delegate.appearanceObserver.reapply()
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
    }
}
