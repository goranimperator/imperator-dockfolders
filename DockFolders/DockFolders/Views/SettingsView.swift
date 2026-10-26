import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("showMainWindow") private var showMainWindow: Bool = true
    @AppStorage(VolumeScanSettings.scanEnabledKey) private var scanExternalDrives: Bool = true
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
