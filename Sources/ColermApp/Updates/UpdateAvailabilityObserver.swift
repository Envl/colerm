import Sparkle

@MainActor
final class UpdateAvailabilityObserver: NSObject, SPUUpdaterDelegate {
    var onAvailabilityChanged: ((Bool) -> Void)?
    var onUpdateError: ((any Error) -> Void)?
    private var userInitiatedUpdateCheck = false

    func markUserInitiatedUpdateCheck() {
        userInitiatedUpdateCheck = true
    }

    func updater(_: SPUUpdater, didFindValidUpdate _: SUAppcastItem) {
        onAvailabilityChanged?(true)
    }

    func updaterDidNotFindUpdate(_: SPUUpdater, error _: any Error) {
        userInitiatedUpdateCheck = false
        onAvailabilityChanged?(false)
    }

    func updater(_: SPUUpdater, didAbortWithError error: any Error) {
        guard userInitiatedUpdateCheck else { return }
        userInitiatedUpdateCheck = false

        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain,
           nsError.code == SUError.noUpdateError.rawValue ||
           nsError.code == SUError.installationCanceledError.rawValue {
            return
        }

        onUpdateError?(error)
    }
}
