#if canImport(UIKit)
import UIKit

struct ShareGiftViewState {
    var response: CreateLinkResponse?
    var isError = false

    var title: String {
        if isError {
            return "Oops, you ran out of gifts to send!"
        } else {
            return "Send a gift"
        }
    }

    var subtitle: String {
        if isError {
            return "Sorry, you’ve used up all your gift links for the month."
        } else {
            return "People won’t need to download\nthe app to enjoy the video"
        }
    }

    var message: String {
        if let response = response {
            return String(format: "%i gifts left", response.userRemainingQuota)
        }
        return ""
    }

    var isSharePossible: Bool {
        !(response?.url.isEmpty ?? true)
    }
}
#endif
