import UIKit

final class FeedViewController: UIViewController {
    private let bottomBar = UIToolbar()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(bottomBar)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Share", style: .plain, target: self, action: #selector(share))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = UIScreen.main.bounds.width
        if UIDevice.current.userInterfaceIdiom == .pad || view.window?.windowScene?.interfaceOrientation.isLandscape == true {
            layoutTwoColumns(width: width)
        } else {
            layoutOneColumn(width: width)
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    @objc private func share() {
        let root = UIApplication.shared.keyWindow?.rootViewController
        root?.present(UIActivityViewController(activityItems: [], applicationActivities: nil), animated: true)
    }

    private func layoutTwoColumns(width: CGFloat) {}
    private func layoutOneColumn(width: CGFloat) {}
}
