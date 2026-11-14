import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("showMainWindow") private var showMainWindow: Bool = true
    @AppStorage(VolumeScanSettings.scanEnabledKey) private var scanExternalDrives: Bool = true
    @AppStorage(UpdateChecker.enabledKey) private var checkForUpdates: Bool = true
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var externalVolumeNames: [String] = []
    @State private var excludedVolumeNames = VolumeScanSettings.excludedVolumeNames

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: $openAtLogin)
                    .toggleStyle(.switch)
                    .tint(AppColors.brand)
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
                Toggle("Show main window on launch", isOn: $showMainWindow)
                    .toggleStyle(.switch)
                    .tint(AppColors.brand)
            }

            Section {
                Toggle("Scan external drives", isOn: $scanExternalDrives)
                    .toggleStyle(.switch)
                    .tint(AppColors.brand)

                if scanExternalDrives {
                    if externalVolumeNames.isEmpty {
                        Text("No external drives connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(externalVolumeNames, id: \.self) { name in
                            Toggle(name, isOn: scanBinding(for: name))
                                .toggleStyle(.switch)
                                .tint(AppColors.brand)
                        }
                    }
                }
            } header: {
                Text("External Drives")
            } footer: {
                Text("Apps are found on the drive itself and up to three folders down. Anything deeper is added with Choose Apps in the app picker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Check for updates", isOn: $checkForUpdates)
                    .toggleStyle(.switch)
                    .tint(AppColors.brand)
                    .onChange(of: checkForUpdates) { _, on in
                        if on { UpdateChecker.shared.checkIfDue() }
                    }

                HStack {
                    Text(settingsStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let update = UpdateChecker.shared.available {
                        Button("Download") { UpdateChecker.open(update.page) }
                    }
                    HoverButton(action: { Task { await UpdateChecker.shared.check() } }) {
                        Text("Check Now")
                            .font(.caption)
                    }
                    .disabled(UpdateChecker.shared.status == .checking)
                }
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
        .tint(AppColors.brand)
        .onAppear { reloadVolumes() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            reloadVolumes()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            reloadVolumes()
        }
    }

    /// The shared status text, plus the running version when an update is
    /// out, which the sidebar has no room for.
    private var settingsStatus: String {
        let text = UpdateChecker.shared.statusText
        return UpdateChecker.shared.available == nil ? text : "\(text), you have \(UpdateChecker.currentVersion)"
    }

    private func reloadVolumes() {
        externalVolumeNames = AppDiscovery.externalVolumes()
            .map { AppDiscovery.volumeName(for: $0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The switch reads as "scan this drive", so it is the inverse of the
    /// stored exclusion. Excluding by name keeps the choice when the drive is
    /// unplugged, which is the only time its row disappears from the list.
    private func scanBinding(for volumeName: String) -> Binding<Bool> {
        Binding(
            get: { !excludedVolumeNames.contains(volumeName) },
            set: { include in
                VolumeScanSettings.setExcluded(!include, for: volumeName)
                excludedVolumeNames = VolumeScanSettings.excludedVolumeNames
            }
        )
    }
}
