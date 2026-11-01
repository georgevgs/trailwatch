import AppIntents

/// Pausing and resuming with Siri ("Pause hike in TrailWatch") or the system's workout controls.
struct PauseHikeIntent: PauseWorkoutIntent {
    static let title: LocalizedStringResource = "Pause Hike"
    @Dependency private var hikes: HikeManager

    @MainActor func perform() async throws -> some IntentResult {
        hikes.current?.pause()
        return .result()
    }
}

struct ResumeHikeIntent: ResumeWorkoutIntent {
    static let title: LocalizedStringResource = "Resume Hike"
    @Dependency private var hikes: HikeManager

    @MainActor func perform() async throws -> some IntentResult {
        hikes.current?.resume()
        return .result()
    }
}

struct TrailWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PauseHikeIntent(),
            phrases: ["Pause hike in \(.applicationName)", "Pause \(.applicationName)"],
            shortTitle: "Pause Hike", systemImageName: "pause.fill")
        AppShortcut(
            intent: ResumeHikeIntent(),
            phrases: ["Resume hike in \(.applicationName)", "Resume \(.applicationName)"],
            shortTitle: "Resume Hike", systemImageName: "play.fill")
    }
}
