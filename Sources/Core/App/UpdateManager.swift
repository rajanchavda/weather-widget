import Cocoa

@MainActor
class UpdateManager {
    unowned let appDelegate: AppDelegate

    /// Development builds (`swift run`) have no bundle version, so they would always look outdated.
    var isAppBundle = Bundle.main.bundlePath.hasSuffix(".app")
    /// Version found by the last check when it is newer than the running one.
    private(set) var availableVersion: String?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    nonisolated static func latestVersion(fromReleaseJSON data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, !tag.isEmpty else {
            return nil
        }
        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    nonisolated static func isVersion(_ latest: String, newerThan current: String) -> Bool {
        latest.compare(current, options: .numeric) == .orderedDescending
    }

    /// A background check only flags the update in the menu; installing always needs a click.
    func performUpdateCheck(isUserInitiated: Bool) {
        guard isUserInitiated || isAppBundle else {
            print("[Update] Not running from an app bundle. Skipping background update check.")
            return
        }
        guard let url = URL(string: "https://api.github.com/repos/rajanchavda/weather-widget/releases/latest") else {
            return
        }
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            let latestVersion = data.flatMap { error == nil ? Self.latestVersion(fromReleaseJSON: $0) : nil }
            DispatchQueue.main.async {
                self?.handleCheckResult(latestVersion: latestVersion, isUserInitiated: isUserInitiated)
            }
        }
        task.resume()
    }

    func handleCheckResult(latestVersion: String?, isUserInitiated: Bool) {
        guard let latestVersion else {
            if isUserInitiated {
                showAlert(
                    "Update Check Failed",
                    "Could not check for updates. Please check your network connection.",
                    style: .warning
                )
            }
            return
        }

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        guard Self.isVersion(latestVersion, newerThan: currentVersion) else {
            if isUserInitiated {
                showAlert("Up to Date", "You are running the latest version (\(currentVersion)).")
            }
            return
        }

        markUpdateAvailable(latestVersion)
        guard isUserInitiated else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "A new version (\(latestVersion)) is available. You are running version \(currentVersion).\n\nWould you like to automatically update and restart the app?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update & Restart")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            performUpdateAndRestart()
        }
    }

    private func markUpdateAvailable(_ version: String) {
        availableVersion = version
        appDelegate.isUpdateReady = true
        appDelegate.menuBarManager.updateStatusItem()
        appDelegate.menuBarManager.showUpdateAvailable(version: version)
    }

    func performUpdateAndRestart() {
        guard let button = appDelegate.statusItem?.button else { return }

        let oldVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let bundlePath = Bundle.main.bundlePath

        button.title = "🌤️ Updating..."
        if let menu = appDelegate.statusItem?.menu, menu.items.count > 1 {
            menu.items[1].title = "Status: Downloading update via Homebrew..."
        }

        showAlert(
            "Updating Weather Overlay",
            "The update is downloading and installing via Homebrew in the background.\n\nThe app will automatically restart once finished. This may take a few moments."
        )

        Task.detached { [weak self] in
            let task = Process()
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            var env = ProcessInfo.processInfo.environment
            let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            if let currentPath = env["PATH"] {
                env["PATH"] = "\(extraPaths):\(currentPath)"
            } else {
                env["PATH"] = extraPaths
            }
            task.environment = env

            let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            if let brewPath = brewPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                task.executableURL = URL(fileURLWithPath: brewPath)
                task.arguments = ["upgrade", "rajanchavda/tap/weatheroverlay"]
            } else {
                task.executableURL = URL(fileURLWithPath: "/bin/sh")
                task.arguments = ["-c", "brew upgrade rajanchavda/tap/weatheroverlay"]
            }

            let failure: String?
            do {
                try task.run()
                // Drain before waiting: brew blocks once the pipe buffer fills.
                let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()

                if task.terminationStatus == 0 {
                    failure = nil
                } else {
                    let output = String(data: outputData, encoding: .utf8) ?? "Unknown error"
                    failure = "Could not update via Homebrew. Please run 'brew upgrade rajanchavda/tap/weatheroverlay' manually in Terminal.\n\nError:\n\(output.suffix(200))"
                }
            } catch {
                failure = "Failed to launch update process: \(error.localizedDescription)"
            }

            let infoPlistPath = "\(bundlePath)/Contents/Info.plist"
            let newVersion = (NSDictionary(contentsOfFile: infoPlistPath)?["CFBundleShortVersionString"] as? String) ?? oldVersion

            DispatchQueue.main.async {
                guard let self = self else { return }
                if let failure {
                    self.showAlert("Update Failed", failure, style: .warning)
                    self.appDelegate.weatherManager.fetchWeather()
                } else if newVersion != oldVersion {
                    self.relaunchApp()
                } else {
                    print("[Update] brew exited 0 but version unchanged (\(oldVersion)). No update applied.")
                    self.showAlert("Already Up to Date", "You are already running version \(oldVersion).")
                    self.appDelegate.weatherManager.fetchWeather()
                }
            }
        }
    }

    private func showAlert(_ title: String, _ message: String, style: NSAlert.Style = .informational) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let executablePath = Bundle.main.executablePath ?? bundlePath
        let launchCmd = bundlePath.hasSuffix(".app") ? "open '\(bundlePath)'" : "'\(executablePath)' &"

        let relaunchTask = Process()
        relaunchTask.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        let relaunchScript = "while pgrep 'WeatherOverlay' > /dev/null; do sleep 0.1; done; \(launchCmd)"
        relaunchTask.arguments = ["/bin/sh", "-c", relaunchScript]

        do {
            try relaunchTask.run()
        } catch {
            print("Failed to execute relaunch: \(error.localizedDescription)")
        }

        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
}
