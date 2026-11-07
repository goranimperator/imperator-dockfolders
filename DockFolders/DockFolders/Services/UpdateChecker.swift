import AppKit
import Observation
import UserNotifications

/// Tells the user when a newer release is out.
///
/// Once a day, it asks GitHub for the latest published release of this repo
/// and compares its tag with the running version. That one request is the
/// app's only network traffic, and nothing goes with it but the app's name and
/// version as the User-Agent GitHub requires. A newer version shows as a row in
/// the sidebar and as one macOS notification per version; clicking either opens
/// the release page. Installing stays manual, as the README's Install section
/// describes: this app is not notarized, so it does not replace itself.
///
/// The notification permission is asked for the first time there is an update
/// to report, not at first launch. Settings → Updates turns the check off.
@MainActor
@Observable
final class UpdateChecker: NSObject {
    static let shared = UpdateChecker()

    struct Release: Equatable {
        let version: String
        let page: URL
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case failed
        case available(Release)
    }

    private(set) var status: Status = .idle

    /// The newer release, if there is one. Drives the row in the sidebar.
    var available: Release? {
        if case .available(let release) = status { return release }
        return nil
    }

    static let enabledKey = "checkForUpdates"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let notifiedKey = "notifiedUpdateVersion"
    private static let interval: TimeInterval = 24 * 60 * 60
    private static let latestURL = URL(string: "https://api.github.com/repos/goranimperator/imperator-dockfolders/releases/latest")!

    @ObservationIgnored private var timer: Timer?

    /// On by default; read through `object(forKey:)` because `bool(forKey:)`
    /// reports an unset key as false.
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        // An hourly tick that only checks once a day has passed, so a Mac that
        // slept through the 24-hour mark still checks soon after it wakes, and
        // a failed check is retried within the hour.
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            Task { @MainActor in UpdateChecker.shared.checkIfDue() }
        }
        checkIfDue()
    }

    func checkIfDue() {
        guard isEnabled else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last >= Self.interval else { return }
        Task { await check() }
    }

    /// Checks now. Settings' Check Now calls this directly, which is an
    /// explicit request and so runs even with the daily check switched off.
    func check() async {
        guard status != .checking else { return }
        status = .checking

        var request = URLRequest(url: Self.latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Imperator-DockFolders/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                status = .failed
                return
            }
            let latest = try JSONDecoder().decode(LatestRelease.self, from: data)
            // Only a successful check counts toward the daily interval, so a
            // failure is retried on the next hourly tick.
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)

            let version = latest.tagName.hasPrefix("v") ? String(latest.tagName.dropFirst()) : latest.tagName
            guard Self.isNewer(version, than: Self.currentVersion) else {
                status = .upToDate
                return
            }
            let release = Release(version: version, page: latest.htmlURL)
            status = .available(release)
            await notifyOnce(release)
        } catch {
            status = .failed
        }
    }

    /// Opens a release page, and only a GitHub page over HTTPS: the link comes
    /// from a network response, and nothing else should be opened from it.
    static func open(_ url: URL) {
        guard url.scheme == "https", url.host == "github.com" else { return }
        NSWorkspace.shared.open(url)
    }

    /// Numeric comparison, component by component, so 1.0.10 is newer than
    /// 1.0.9. A missing component counts as 0.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// One notification per version, and the permission question only once
    /// there is something to say.
    private func notifyOnce(_ release: Release) async {
        guard UserDefaults.standard.string(forKey: Self.notifiedKey) != release.version else { return }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Imperator DockFolders \(release.version) is available"
        content.body = "You have \(Self.currentVersion). Click to open the release page."
        content.userInfo = ["url": release.page.absoluteString]
        let request = UNNotificationRequest(identifier: "update-\(release.version)", content: content, trigger: nil)
        try? await center.add(request)
        UserDefaults.standard.set(release.version, forKey: Self.notifiedKey)
    }
}

extension UpdateChecker: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let string = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: string) else { return }
        await MainActor.run { UpdateChecker.open(url) }
    }

    /// Show the banner even when the app is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// The two fields of GitHub's "latest release" response the check uses.
private nonisolated struct LatestRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
