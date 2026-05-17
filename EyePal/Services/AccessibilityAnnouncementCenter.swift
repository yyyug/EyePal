import UIKit

@MainActor
final class AccessibilityAnnouncementCenter {
    private var lastAnnouncement = ""
    private var lastAnnouncementDate = Date.distantPast

    func announce(_ text: String, minimumInterval: TimeInterval, duplicateSuppressionWindow: TimeInterval = 2) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let now = Date()

        if trimmed == lastAnnouncement,
           now.timeIntervalSince(lastAnnouncementDate) < duplicateSuppressionWindow {
            return
        }

        guard now.timeIntervalSince(lastAnnouncementDate) >= minimumInterval else {
            return
        }

        lastAnnouncement = trimmed
        lastAnnouncementDate = now
        UIAccessibility.post(notification: .announcement, argument: trimmed)
    }
}
