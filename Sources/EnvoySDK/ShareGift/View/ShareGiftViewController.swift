#if canImport(UIKit)
import UIKit

@available(iOS 13.0, *)
final class ShareGiftViewController: UIViewController {

    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var subtitleLabel: UILabel!
    @IBOutlet private weak var statusLabel: UILabel!
    @IBOutlet private weak var activity: UIActivityIndicatorView!
    @IBOutlet private weak var shareButton: UIButton!

    var presenter: ShareGiftViewDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        presenter?.viewDidLoad()
    }
}

@available(iOS 13.0, *)
private extension ShareGiftViewController {
    private func setupUI() {
        setupNavigationBar()
        setupButtons()
    }

    func setupNavigationBar() {
        let closeItem = UIBarButtonItem(
            image: UIImage(named: "ic_arrow_right", in: .module, with: nil),
            style: .plain,
            target: self,
            action: #selector(onBack)
        )
        closeItem.tintColor = .white
        navigationItem.leftBarButtonItem = closeItem
    }

    func setupButtons() {
        shareButton.layer.cornerRadius = 6
    }

    @objc private func onBack() {
        if navigationController?.viewControllers.count ?? 0 > 1 {
            navigationController?.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    @IBAction func shareAction(_ sender: Any?) {
        presenter?.shareAction()
    }
}

@MainActor
extension ShareGiftViewController: @MainActor ShareGiftViewProtocol {
    @MainActor
    func updateWith(viewState: ShareGiftViewState) {
        DispatchQueue.main.async {
            self.titleLabel.text = viewState.title
            self.subtitleLabel.text = viewState.subtitle
            self.statusLabel.text = viewState.message
            self.shareButton.isHidden = !viewState.isSharePossible
        }
    }

    @MainActor
    func updateWith(isLoading: Bool) {
        DispatchQueue.main.async {
            if isLoading {
                self.activity.startAnimating()
            } else {
                self.activity.stopAnimating()
            }
        }
    }
    @MainActor
    func presentShare(for url: String) {
        let textToShare = [url]
        let activityViewController = UIActivityViewController(
            activityItems: textToShare,
            applicationActivities: nil
        )
        DispatchQueue.main.async {
            activityViewController.popoverPresentationController?.sourceView = self.view
            self.present(activityViewController, animated: true)
        }
    }
}
#endif
