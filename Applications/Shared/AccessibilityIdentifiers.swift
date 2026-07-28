import Foundation

/// Stable accessibility identifiers, compiled into **both** the app and the UI
/// test target (see `project.yml`) so tests never match on user-facing English.
///
/// Identifiers are for automation only — they are never read aloud. VoiceOver
/// uses `accessibilityLabel`, which stays localized.
enum A11y {

    enum Onboarding {
        static let root = "onboarding.root"
        static let progress = "onboarding.progress"
        static let continueButton = "onboarding.continue"
        static let backButton = "onboarding.back"
        static let anchorPicker = "onboarding.anchor"
        static let startDatePicker = "onboarding.startDate"
        static let raceDatePicker = "onboarding.raceDate"
        static let derivedDate = "onboarding.derivedDate"
        static let weekdayTime = "onboarding.weekdayTime"
        static let weekendTime = "onboarding.weekendTime"
        static let longBikeDay = "onboarding.longBikeDay"
        static let longRunDay = "onboarding.longRunDay"
        static let restDay = "onboarding.restDay"
        static let units = "onboarding.units"
        static let safetyAcknowledge = "onboarding.safetyAcknowledge"
        static func category(_ raw: String) -> String { "onboarding.category.\(raw)" }
    }

    enum Tab {
        static let today = "tab.today"
        static let plan = "tab.plan"
        static let progress = "tab.progress"
        static let settings = "tab.settings"
    }

    enum Today {
        static let list = "today.list"
        static let date = "today.date"
        static let weekPhase = "today.weekPhase"
        static let weekProgress = "today.weekProgress"
        static let status = "today.status"
        static let empty = "today.empty"
        static let upNext = "today.upNext"
        /// Row at a stable position in today's chronological list.
        static func row(_ index: Int) -> String { "today.row.\(index)" }
        static func rowStatus(_ index: Int) -> String { "today.row.\(index).status" }
        static let completeAction = "today.action.complete"
        static let rescheduleAction = "today.action.reschedule"
        static let skipAction = "today.action.skip"
        static let replaceAction = "today.action.replace"
        static let undoAction = "today.action.undo"
    }

    enum Completion {
        static let sheet = "completion.sheet"
        static let minutes = "completion.minutes"
        static let minutesValue = "completion.minutes.value"
        static let logDistance = "completion.logDistance"
        static let distance = "completion.distance"
        static let rpe = "completion.rpe"
        static let notes = "completion.notes"
        static let save = "completion.save"
        static let cancel = "completion.cancel"
    }

    enum Reschedule {
        static let sheet = "reschedule.sheet"
        static let datePicker = "reschedule.date"
        static let confirm = "reschedule.confirm"
        static let cancel = "reschedule.cancel"
        static let warnings = "reschedule.warnings"
    }

    enum Detail {
        static let list = "detail.list"
        static let complete = "detail.complete"
        static let scheduledDate = "detail.scheduledDate"
        static let status = "detail.status"
        static func intervalToggle(_ id: String) -> String { "detail.interval.\(id)" }
    }

    enum Plan {
        static let list = "plan.list"
        static let filterMenu = "plan.filter"
        static func filterOption(_ raw: String) -> String { "plan.filter.\(raw)" }
        static let filterClear = "plan.filter.clear"
        static func week(_ number: Int) -> String { "plan.week.\(number)" }
        static let weekDetailList = "plan.weekDetail.list"
    }

    enum Progress {
        static let list = "progress.list"
        static let durationChart = "progress.chart.duration"
        static let empty = "progress.empty"
    }

    enum Settings {
        static let list = "settings.list"
        static let units = "settings.units"
        static let planDates = "settings.planDates"
        static let preferredDays = "settings.preferredDays"
        static let notifications = "settings.notifications"
        static let trainingZones = "settings.trainingZones"
        static let export = "settings.export"
        static let exportSummary = "settings.exportSummary"
        static let resetHistory = "settings.resetHistory"
        static let deleteAll = "settings.deleteAll"
        static let version = "settings.version"
    }

    enum PlanDates {
        static let startDate = "planDates.startDate"
        static let apply = "planDates.apply"
        static let longBikeDay = "planDates.longBikeDay"
        static let longRunDay = "planDates.longRunDay"
        static let restDay = "planDates.restDay"
    }

    enum Notifications {
        static let list = "notifications.list"
        static let authStatus = "notifications.authStatus"
        static let openSettings = "notifications.openSettings"
        static func category(_ raw: String) -> String { "notifications.category.\(raw)" }
        static let sendTest = "notifications.sendTest"
        static let diagnostics = "notifications.diagnostics"
        static let pendingCount = "notifications.pendingCount"
        static let resync = "notifications.resync"
        static let resyncResult = "notifications.resyncResult"
    }

    /// Release 2 — Health (§R).
    enum Health {
        static let settingsLink = "health.settingsLink"
        static let status = "health.status"
        static let connect = "health.connect"
        static let disconnect = "health.disconnect"
        static let importToggle = "health.importToggle"
        static let exportToggle = "health.exportToggle"
        static let exportState = "health.exportState"
        static let exportOpenSettings = "health.exportOpenSettings"
        static let saveToHealth = "health.saveToHealth"
        static let retryExport = "health.retryExport"
        static let lastImport = "health.lastImport"
        static let errorState = "health.errorState"
        static let skipped = "health.skipped"
        static let rescan = "health.rescan"
        static let rawCount = "health.rawCount"
        static let unmapped = "health.unmapped"
        static let readAccessHint = "health.readAccessHint"
        static let openSystemSettings = "health.openSystemSettings"
        static let inboxLink = "health.inboxLink"
        static let inboxEmpty = "health.inbox.empty"
        static func inboxRow(_ index: Int) -> String { "health.inbox.row.\(index)" }
        static func confirmMatch(_ index: Int) -> String { "health.inbox.confirm.\(index)" }
        static func rejectMatch(_ index: Int) -> String { "health.inbox.reject.\(index)" }
        static func chooseOther(_ index: Int) -> String { "health.inbox.choose.\(index)" }
        static func keepUnplanned(_ index: Int) -> String { "health.inbox.unplanned.\(index)" }
    }

    /// Release 2 — WorkoutKit (§R).
    enum WorkoutKit {
        static let settingsLink = "workoutkit.settingsLink"
        static let authorization = "workoutkit.authorization"
        static let enableToggle = "workoutkit.enableToggle"
        static let horizon = "workoutkit.horizon"
        static let lastSync = "workoutkit.lastSync"
        static let failure = "workoutkit.failure"
        static let failureCode = "workoutkit.failureCode"
        static let resync = "workoutkit.resync"
        static let removeAll = "workoutkit.removeAll"
        static func previewRow(_ index: Int) -> String { "workoutkit.preview.\(index)" }
        static func approve(_ index: Int) -> String { "workoutkit.approve.\(index)" }
    }

    enum Alert {
        static let dataError = "alert.dataError"
        static let exportFailed = "alert.exportFailed"
    }

    /// Launch arguments the UI tests use to get a deterministic app.
    enum LaunchArgument {
        /// Wipe persisted state so the run always begins at onboarding.
        static let freshInstall = "-uiTestFreshInstall"
        /// Skip the notification authorization prompt, which cannot be dismissed
        /// reliably from XCUITest across OS versions.
        static let suppressNotificationPrompt = "-uiTestNoNotificationPrompt"
        /// DEBUG-only. Backdates onboarding's start date by N days so a capture
        /// or test can land on a chosen day of the plan (e.g. a recovery day, or
        /// a day with two sessions). Followed by an integer argument.
        static let startDayOffset = "-uiTestStartDayOffset"
    }
}
