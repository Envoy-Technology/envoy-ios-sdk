#if canImport(UIKit)
import UIKit

@available(iOS 13.0, *)
class GiftButton: UIButton {

    var token: String?
    var request: CreateLinkRequest?

    public override func awakeFromNib() {
        super.awakeFromNib()
        initialize()
    }

    func initialize() {
        setupUI()
    }

    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
    }
}

@available(iOS 13.0, *)
private extension GiftButton {
    func setupUI() {
        setTitle("", for: .normal)
        setImage(
            UIImage(named: "ic_gift_button", in: .module, with: nil),
            for: .normal
        )
        backgroundColor = .white
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 64),
            widthAnchor.constraint(equalToConstant: 64)
        ])
        layer.cornerRadius = 32
    }
}
#endif
