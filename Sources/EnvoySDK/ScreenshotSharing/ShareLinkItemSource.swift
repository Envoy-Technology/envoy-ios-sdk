#if canImport(UIKit)
import UIKit
import LinkPresentation

/// The link in the share sheet, previewed with the article title and image; only the link is shared.
final class ShareLinkItemSource: NSObject, UIActivityItemSource {
    let url: URL
    let title: String?
    let image: UIImage?

    init(url: URL, title: String?, image: UIImage?) {
        self.url = url
        self.title = title
        self.image = image
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        url
    }

    /// Used by Mail.
    func activityViewController(_ activityViewController: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        title ?? ""
    }

    /// The header of the share sheet.
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = title
        if let image = image {
            metadata.imageProvider = NSItemProvider(object: image)
            metadata.iconProvider = NSItemProvider(object: image)
        }
        return metadata
    }
}
#endif
