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
                    Button("Check Now") { Task { await UpdateChecker.shared.check() } }
                        .disabled(UpdateChecker.shared.status == .checking)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Once a day the app asks GitHub for the latest release and compares it with this version. Check Now sends the same request on demand, even with the daily check off. Nothing is sent but the app's name and version. A newer version shows in the sidebar and as one notification; installing it is up to you.")
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

/// Sidebar rows just above Open at Login: the daily check's switch on one
/// row, its last result and Check Now on the next. Check Now runs even with
/// the switch off, because it is asked for. Same layout as the update rows in
/// the other Imperator apps; the switch takes the footer's right edge.
struct UpdateCheckRow: View {
    @AppStorage(UpdateChecker.enabledKey) private var checkForUpdates = true
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("Check for updates")
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Toggle("Check for updates", isOn: $checkForUpdates)
                    .toggleStyle(.switch)
                    .scaleEffect(0.55)
                    .tint(AppColors.brand)
                    .labelsHidden()
                    .frame(width: SwitchMetrics.size.width, height: SwitchMetrics.size.height)
                    .onChange(of: checkForUpdates) { _, on in
                        if on { UpdateChecker.shared.checkIfDue() }
                    }
            }
            .opacity(isHovered ? 1.0 : 0.45)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { isHovered = $0 }

            HStack {
                Text(UpdateChecker.shared.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                HoverButton(action: { Task { await UpdateChecker.shared.check() } }) {
                    Text("Check Now")
                        .font(.caption)
                }
                .fixedSize()
                .disabled(UpdateChecker.shared.status == .checking)
            }
        }
    }
}

/// Footer launch-at-login row: caption label on the left, the stock switch
/// tinted brand on the right, and the whole row fading in on hover.
///
/// The switch sits on the same right edge as the Folder options switches
/// above it, so it gets the same frame: scaleEffect only scales the
/// rendering, and without the frame the drawn capsule would sit ~12pt short
/// of that edge.
struct LaunchAtLoginToggle: View {
    @State private var isEnabled = SMAppService.mainApp.status == .enabled
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text("Open at Login")
                .font(.caption)
            Spacer(minLength: 0)
            Toggle("Open at Login", isOn: $isEnabled)
                .toggleStyle(.switch)
                .scaleEffect(0.55)
                .tint(AppColors.brand)
                .labelsHidden()
                .frame(width: SwitchMetrics.size.width, height: SwitchMetrics.size.height)
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
