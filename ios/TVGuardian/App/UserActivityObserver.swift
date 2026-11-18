import SwiftUI
import UIKit

/// Observe activity without a SwiftUI ancestor gesture competing with Form rows.
/// These UIKit recognizers never cancel or delay the controls' own touches.
struct UserActivityObserver: UIViewRepresentable {
    var onActivity: () -> Void
    func makeUIView(context: Context) -> ActivityObservationView { ActivityObservationView(onActivity: onActivity) }
    func updateUIView(_ view: ActivityObservationView, context: Context) { view.onActivity = onActivity }
}

final class ActivityObservationView: UIView, UIGestureRecognizerDelegate {
    var onActivity: () -> Void
    private weak var observedWindow: UIWindow?
    private var recognizers: [UIGestureRecognizer] = []
    init(onActivity: @escaping () -> Void) {
        self.onActivity = onActivity
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { return nil }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard observedWindow !== window else { return }
        for recognizer in recognizers { observedWindow?.removeGestureRecognizer(recognizer) }
        recognizers = []; observedWindow = window
        guard let window else { return }
        recognizers = [UITapGestureRecognizer(target: self, action: #selector(activity)), UIPanGestureRecognizer(target: self, action: #selector(activity))]
        for recognizer in recognizers {
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
        }
    }
    @objc private func activity() { onActivity() }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
