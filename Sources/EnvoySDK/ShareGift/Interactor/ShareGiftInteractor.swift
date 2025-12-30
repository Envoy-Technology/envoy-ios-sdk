#if canImport(UIKit)
import UIKit

final class ShareGiftInteractor {
    
    private let createLinkService: CreateLinkServiceType
    private let request: CreateLinkRequest

    init(
        createLinkService: CreateLinkServiceType,
        request: CreateLinkRequest
    ) {
        self.createLinkService = createLinkService
        self.request = request
    }
}

extension ShareGiftInteractor: ShareGiftInteractorProtocol {
    func getCreateLink(
        request: CreateLinkRequest,
        completion: @escaping (CreateLinkResponse?, WebError?) -> ()
    ) {
        createLinkService.createLink(
            request: request,
            completion: completion
        )
    }
}
#endif
