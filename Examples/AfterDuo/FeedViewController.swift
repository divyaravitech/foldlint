import UIKit

final class FeedViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.isToolbarHidden = false
        toolbarItems = [.flexibleSpace()]
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Share",
            image: UIImage(systemName: "square.and.arrow.up"),
            primaryAction: UIAction { [weak self] _ in self?.share() }
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.inset(by: view.safeAreaInsets).width
        if traitCollection.horizontalSizeClass == .regular {
            layoutTwoColumns(width: width)
        } else {
            layoutOneColumn(width: width)
        }
    }

    private func share() {
        present(UIActivityViewController(activityItems: [], applicationActivities: nil), animated: true)
    }

    private func layoutTwoColumns(width: CGFloat) {}
    private func layoutOneColumn(width: CGFloat) {}
}
