#if canImport(UIKit)
import UIKit
@available(iOS 13.0, *)
final class ShareGiftPresenter {
    var wireframe: ShareGiftWireframeProtocol
    var interactor: ShareGiftInteractorProtocol
    weak var view: ShareGiftViewProtocol?

    var viewState = ShareGiftViewState()
    let request: CreateLinkRequest

    init(
        with interactor: ShareGiftInteractor,
        wireframe: ShareGiftWireframe,
        view: ShareGiftViewProtocol,
        request: CreateLinkRequest
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.view = view
        self.request = request
    }
}
@available(iOS 13.0, *)
extension ShareGiftPresenter: ShareGiftViewDelegate {
    func viewDidLoad() {
        createLink()
        updateView()
    }

    func shareAction() {
        startSharing()
    }

    func shareCompleted(with type: UIActivity.ActivityType) {
        guard let _ = viewState.response?.url else { return }
    }
}
@available(iOS 13.0, *)
private extension ShareGiftPresenter {
    func updateView() {
        view?.updateWith(viewState: viewState)
    }

    func createLink() {
        view?.updateWith(isLoading: true)

        interactor.getCreateLink(
            request: request
        ) { [weak self] response, error in
            guard let self = self else { return }
            self.view?.updateWith(isLoading: false)
            if let _ = error {
                self.viewState.isError = true
            } else {
                self.viewState.response = response
                self.startSharing()
            }
            self.updateView()
        }
    }

    func startSharing() {
        guard let url = viewState.response?.url else { return }
        view?.presentShare(for: url)
    }
}
#endif
