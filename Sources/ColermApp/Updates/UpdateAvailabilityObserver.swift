import Sparkle

@MainActor
final class UpdateAvailabilityObserver: NSObject, SPUUpdaterDelegate {
    var onUpdateReady: ((Bool) -> Void)?
    var onUpdateError: ((any Error) -> Void)?
    private var userInitiatedUpdateCheck = false
    private var immediateInstallHandler: (() -> Void)?

    func markUserInitiatedUpdateCheck() {
        userInitiatedUpdateCheck = true
    }

    @discardableResult
    func installAndRelaunch() -> Bool {
        guard let immediateInstallHandler else { return false }
        userInitiatedUpdateCheck = true
        immediateInstallHandler()
        return true
    }

    func updater(
        _: SPUUpdater,
        willInstallUpdateOnQuit _: SUAppcastItem,
        immediateInstallationBlock: @escaping () -> Void
    ) -> Bool {
        immediateInstallHandler = immediateInstallationBlock
        onUpdateReady?(true)
        return true
    }

    func updater(_: SPUUpdater, willInstallUpdate _: SUAppcastItem) {
        onUpdateReady?(false)
    }

    func updaterDidNotFindUpdate(_: SPUUpdater, error _: any Error) {
        userInitiatedUpdateCheck = false
        immediateInstallHandler = nil
        onUpdateReady?(false)
    }

    func updater(_: SPUUpdater, didAbortWithError error: any Error) {
        immediateInstallHandler = nil
        onUpdateReady?(false)
        guard userInitiatedUpdateCheck else {
            return
        }
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
