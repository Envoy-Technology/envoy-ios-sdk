protocol ShareGiftWireframeProtocol: AnyObject {

}

protocol ShareGiftInteractorProtocol: AnyObject {
    func getCreateLink(
        request: CreateLinkRequest,
        completion: @escaping (CreateLinkResponse?, WebError?) -> ()
    )
}

protocol ShareGiftViewProtocol: AnyObject {
    func updateWith(viewState: ShareGiftViewState)
    func updateWith(isLoading: Bool)
    func presentShare(for url: String)
}

protocol ShareGiftViewDelegate {
    func viewDidLoad()
    func shareAction()
}
