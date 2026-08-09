import Combine
import Sparkle
import SwiftUI

/// Owns Sparkle's updater for the whole life of the app — Sparkle wants
/// exactly one, created once (same pattern as DockKeep).
///
/// **Wired but silent**: the app ships without `SUFeedURL` in its
/// Info.plist, and without a feed there is nothing to check against, so
/// the updater is not even started — no scheduling, no first-launch
/// permission prompt, no network. The day roster.lndev.me serves the
/// appcast, adding `SUFeedURL` and `SUPublicEDKey` to project.yml turns
/// the whole path on without touching this file.
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
