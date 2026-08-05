import Sparkle

@MainActor
final class UpdateAvailabilityObserver: NSObject, SPUUpdaterDelegate {
    var onAvailabilityChanged: ((Bool) -> Void)?

    func updater(_: SPUUpdater, didFindValidUpdate _: SUAppcastItem) {
        onAvailabilityChanged?(true)
    }

    func updaterDidNotFindUpdate(_: SPUUpdater, error _: any Error) {
        onAvailabilityChanged?(false)
    }
}
