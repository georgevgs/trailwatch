import BackgroundTasks
import Foundation

/// Keeps work started by a tap going after you leave the app, with its progress in a Live Activity
/// (iOS 26 continued processing). In the foreground the work runs the same either way.
final class ContinuedWork {
    private var task: BGContinuedProcessingTask?
    private let steps: Int64
    private var done: Int64 = 0
    private var result: Bool?

    /// Starts tracking `steps` steps. If the system can't take it now, the work just runs in the foreground.
    init(title: String, subtitle: String, steps: Int64) {
        self.steps = steps
        let identifier = "\(Bundle.main.bundleIdentifier ?? "eu.vagdas.trailwatch").map.\(UUID().uuidString)"
        // Each run registers its own identifier: registering one twice is an error. Holding on to
        // self means a task that starts late is still completed.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated { self.started(task as! BGContinuedProcessingTask) }
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
        request.strategy = .fail
        try? BGTaskScheduler.shared.submit(request)
    }

    func advance() {
        done = min(done + 1, steps)
        task?.progress.completedUnitCount = done
    }

    func finish(success: Bool) {
        result = success
        task?.setTaskCompleted(success: success)
        task = nil
    }

    private func started(_ task: BGContinuedProcessingTask) {
        if let result {
            task.setTaskCompleted(success: result)
            return
        }
        self.task = task
        task.progress.totalUnitCount = steps
        task.progress.completedUnitCount = done
        // Cancelled from the Live Activity, or the system needs the resources back.
        task.expirationHandler = { [weak task] in task?.setTaskCompleted(success: false) }
    }
}
