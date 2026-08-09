import Combine
import Sparkle
import SwiftUI

/// Owns Sparkle's updater for the whole life of the app — Sparkle wants
/// exactly one, created once (same pattern as DockKeep).
///
/// **Live since 0.2.0**: Info.plist carries `SUFeedURL` (the appcast on
/// roster.lndev.me) and `SUPublicEDKey`, so the updater starts, checks
/// once a day, and offers updates whose signature verifies against the
/// key. The guard below still protects the other direction: strip the
/// feed from project.yml and the whole path goes silent again — no
/// scheduling, no prompt, no network.
///
/// This is the one type in Roster using `ObservableObject` rather than
/// `@Observable`: `canCheckForUpdates` is a KVO property on Sparkle's
/// Objective-C updater, and Combine's KVO publisher is what turns it
/// into something SwiftUI can watch.
final class UpdaterModel: ObservableObject {

    /// False while no feed is configured, and while a check is already
    /// running — the menu item dims itself accordingly.
    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController?

    init() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            // No feed, no updater. The menu item stays disabled.
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// The visible "checking…" flow, behind the menu item.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
