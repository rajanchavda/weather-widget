import Cocoa

@MainActor
class UpdateManager {
    unowned let appDelegate: AppDelegate

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    func performUpdateCheck(isUserInitiated: Bool) {
        guard let url = URL(string: "https://api.github.com/repos/rajanchavda/weather-widget/releases/latest") else {
            return
        }
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                if isUserInitiated {
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        let alert = NSAlert()
                        alert.messageText = "Update Check Failed"
                        alert.informativeText = "Could not check for updates. Please check your network connection."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let latestVersionTag = json["tag_name"] as? String {

                    let latestVersion = latestVersionTag.replacingOccurrences(of: "v", with: "")
                    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

                    if latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                        if isUserInitiated {
                            DispatchQueue.main.async { [weak self] in
                                guard let self = self else { return }
                                NSApp.activate(ignoringOtherApps: true)
                                let alert = NSAlert()
                                alert.messageText = "Update Available"
                                alert.informativeText = "A new version (\(latestVersion)) is available. You are running version \(currentVersion).\n\nWould you like to automatically update and restart the app?"
                                alert.alertStyle = .informational
                                alert.addButton(withTitle: "Update & Restart")
                                alert.addButton(withTitle: "Cancel")

                                if alert.runModal() == .alertFirstButtonReturn {
                                    self.performUpdateAndRestart(isSilent: false)
                                }
                            }
                        } else {
                            DispatchQueue.main.async { [weak self] in
                                self?.performUpdateAndRestart(isSilent: true)
                            }
                        }
                    } else if isUserInitiated {
                        DispatchQueue.main.async {
                            NSApp.activate(ignoringOtherApps: true)
                            let alert = NSAlert()
                            alert.messageText = "Up to Date"
                            alert.informativeText = "You are running the latest version (\(currentVersion))."
                            alert.alertStyle = .informational
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                        }
                    }
                }
            } catch {
                print("Failed to parse GitHub response: \(error)")
            }
        }
        task.resume()
    }

    func performUpdateAndRestart(isSilent: Bool) {
        guard let button = appDelegate.statusItem?.button else { return }

        let oldVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let bundlePath = Bundle.main.bundlePath

        if !isSilent {
            button.title = "🌤️ Updating..."
            if let menu = appDelegate.statusItem?.menu, menu.items.count > 1 {
                menu.items[1].title = "Status: Downloading update via Homebrew..."
            }

            NSApp.activate(ignoringOtherApps: true)
            let progressAlert = NSAlert()
            progressAlert.messageText = "Updating Weather Overlay"
            progressAlert.informativeText = "The update is downloading and installing via Homebrew in the background.\n\nThe app will automatically restart once finished. This may take a few moments."
            progressAlert.alertStyle = .informational
            progressAlert.addButton(withTitle: "OK")
            progressAlert.runModal()
        }

        Task.detached { [weak self] in
            guard let self = self else { return }

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
            var brewURL: URL?
            for path in brewPaths {
                if FileManager.default.isExecutableFile(atPath: path) {
                    brewURL = URL(fileURLWithPath: path)
                    break
                }
            }

            if let brewURL = brewURL {
                task.executableURL = brewURL
                task.arguments = ["upgrade", "rajanchavda/tap/weatheroverlay"]
            } else {
                task.executableURL = URL(fileURLWithPath: "/bin/sh")
                task.arguments = ["-c", "brew upgrade rajanchavda/tap/weatheroverlay"]
            }

            do {
                try task.run()
                task.waitUntilExit()

                if task.terminationStatus == 0 {
                    let infoPlistPath = "\(bundlePath)/Contents/Info.plist"
                    let newVersion = (NSDictionary(contentsOfFile: infoPlistPath)?["CFBundleShortVersionString"] as? String) ?? oldVersion

                    if newVersion != oldVersion {
                        if isSilent {
                            DispatchQueue.main.async {
                                self.appDelegate.isUpdateReady = true
                                self.appDelegate.menuBarManager.updateStatusItem()
                                if let menu = self.appDelegate.statusItem?.menu,
                                   let item = menu.items.first(where: { $0.action == #selector(AppDelegate.checkForUpdates) }) {
                                    item.title = "Update and Restart ⚠️"
                                    item.action = #selector(AppDelegate.triggerRelaunch)
                                }
                            }
                        } else {
                            DispatchQueue.main.async {
                                self.relaunchApp()
                            }
                        }
                    } else {
                        print("[Update] brew exited 0 but version unchanged (\(oldVersion)). No update applied.")
                        if !isSilent {
                            DispatchQueue.main.async {
                                let alert = NSAlert()
                                alert.messageText = "Already Up to Date"
                                alert.informativeText = "You are already running version \(oldVersion)."
                                alert.alertStyle = .informational
                                alert.addButton(withTitle: "OK")
                                alert.runModal()
                            }
                        }
                    }
                } else {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"

                    if !isSilent {
                        DispatchQueue.main.async {
                            let alert = NSAlert()
                            alert.messageText = "Update Failed"
                            alert.informativeText = "Could not update via Homebrew. Please run 'brew upgrade rajanchavda/tap/weatheroverlay' manually in Terminal.\n\nError:\n\(errorString.prefix(200))"
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: "OK")
                            alert.runModal()

                            self.appDelegate.weatherManager.fetchWeather()
                        }
                    } else {
                        print("[Update] Silent background update failed: \(errorString)")
                    }
                }
            } catch {
                if !isSilent {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Update Failed"
                        alert.informativeText = "Failed to launch update process: \(error.localizedDescription)"
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()

                        self.appDelegate.weatherManager.fetchWeather()
                    }
                } else {
                    print("[Update] Silent background update failed to launch: \(error.localizedDescription)")
                }
            }
        }
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
