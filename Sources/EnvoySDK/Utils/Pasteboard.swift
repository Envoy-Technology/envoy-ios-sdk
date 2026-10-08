#if canImport(UIKit)
import UIKit

protocol PasteboardType {
    /// Reports whether the pasteboard may hold a web URL, without reading its content.
    /// Completes on the main queue.
    func detectProbableWebURL(completion: @escaping (Swift.Result<Bool, Error>) -> Void)
    /// Reads the pasteboard content. On iOS 16+ this can show the system paste prompt.
    var string: String? { get }
}

struct SystemPasteboard: PasteboardType {
    func detectProbableWebURL(completion: @escaping (Swift.Result<Bool, Error>) -> Void) {
        guard #available(iOS 14.0, *) else {
            // No pattern detection before iOS 14, and no paste prompt either,
            // so the content is always worth reading.
            completion(.success(true))
            return
        }
        // Detection calls back on a background queue; `completion` is only ever called on the main queue.
        nonisolated(unsafe) let completion = completion
        UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
            let detected = result.map { $0.contains(.probableWebURL) }
            DispatchQueue.main.async {
                completion(detected)
            }
        }
    }

    var string: String? {
        UIPasteboard.general.string
    }
}
#endif
