import Foundation
#if canImport(UIKit)
import UIKit

@available(iOS 13.0, *)
@MainActor
final class ShareGiftBuilder {
    class func viewController(
        request: CreateLinkRequest,
        apiKey: String,
        baseURL: String
    ) -> ShareGiftViewController {
        let webClient = WebClient(baseURL: baseURL)
        let createLinkService = CreateLinkService(
            client: webClient,
            apiKey: apiKey
        )
        let interactor = ShareGiftInteractor(
            createLinkService: createLinkService,
            request: request
        )
        let wireframe = ShareGiftWireframe()
        let nibName = String(describing: ShareGiftViewController.self)
        let viewController = ShareGiftViewController(
            nibName: nibName,
            bundle: .module
        )
        let presenter = ShareGiftPresenter(
            with: interactor,
            wireframe: wireframe,
            view: viewController,
            request: request
        )

        viewController.presenter = presenter
        wireframe.viewController = viewController

        return viewController
    }
}
#endif
