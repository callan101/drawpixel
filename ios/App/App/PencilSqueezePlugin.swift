import UIKit
import Capacitor
import WebKit

/// Bridge view controller that registers the app's own plugins.
class AppViewController: CAPBridgeViewController {
    // Full-screen drawing: no status bar (clock, battery) over the canvas.
    override var prefersStatusBarHidden: Bool { true }

    private var offsetLock: NSKeyValueObservation?

    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(PencilSqueezePlugin())
        // The app does its own zooming; never let the web view zoom the page
        // (a double-tap on a button used to zoom it with no way back).
        if let scrollView = webView?.scrollView {
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 1
            scrollView.bouncesZoom = false
            scrollView.pinchGestureRecognizer?.isEnabled = false
            // The page never scrolls. When the keyboard comes up WebKit scrolls
            // it to reveal the focused field, pushing the whole UI up; pin the
            // offset at zero so the keyboard simply overlays the app instead.
            scrollView.isScrollEnabled = false
            offsetLock = scrollView.observe(\.contentOffset, options: [.new]) { view, _ in
                if view.contentOffset != .zero { view.contentOffset = .zero }
            }
        }
    }
}

/// Forwards Apple Pencil squeeze and double-tap to the web app as
/// `PencilSqueeze` events:
///   "squeeze"   { phase: "began" | "changed" | "ended" | "cancelled", x?, y? }
///   "doubleTap" {}
/// x/y are the hover location in web view (CSS) points, present only while
/// the Pencil is hovering.
///
/// Also `setTextInput({ enabled })`: the web app calls it with true while a
/// text field is focused and false otherwise. When false, the web view's
/// long-press / loupe / text-selection gestures are switched off, so the
/// iPadOS magnifier and selection never appear over the drawing UI.
@objc(PencilSqueezePlugin)
public class PencilSqueezePlugin: CAPPlugin, CAPBridgedPlugin, UIPencilInteractionDelegate {
    public let identifier = "PencilSqueezePlugin"
    public let jsName = "PencilSqueeze"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setTextInput", returnType: CAPPluginReturnPromise),
    ]

    private var interaction: UIPencilInteraction?

    override public func load() {
        DispatchQueue.main.async {
            guard let webView = self.bridge?.webView else { return }
            let interaction = UIPencilInteraction()
            interaction.delegate = self
            webView.addInteraction(interaction)
            self.interaction = interaction
            self.setTextGestures(enabled: false)
            // WebKit installs some text gestures lazily; switch them off again
            // once the page has settled.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.reapplyTextGestures() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.reapplyTextGestures() }
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardChanged(_:)),
                           name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardChanged(_:)),
                           name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    // MARK: Keyboard

    /// Tells the web app how much of the web view the keyboard covers
    /// ("keyboard" { height }), so it can lift just the window being edited.
    @objc private func keyboardChanged(_ note: Notification) {
        guard let webView = bridge?.webView else { return }
        var covered: CGFloat = 0
        if note.name != UIResponder.keyboardWillHideNotification,
           let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            let local = webView.convert(frame, from: nil)
            covered = max(0, webView.bounds.maxY - local.minY)
        }
        notifyListeners("keyboard", data: ["height": covered])
        if covered == 0 { reapplyTextGestures() }
    }

    // MARK: Text interaction only while editing

    /// Gesture recognizer classes (matched by name) that start text selection
    /// or show the loupe. Taps, scrolling and touch events are left alone.
    private static let textGestureNames = [
        "LongPress", "Loupe", "TapAndAHalf", "TextSelection", "TextInteraction",
        "TextTap", "MultiTap", "Highlight",
    ]
    private var textInputActive = false

    private func reapplyTextGestures() {
        if !textInputActive { setTextGestures(enabled: false) }
    }

    @objc func setTextInput(_ call: CAPPluginCall) {
        let enabled = call.getBool("enabled") ?? false
        DispatchQueue.main.async {
            self.textInputActive = enabled
            self.setTextGestures(enabled: enabled)
            call.resolve()
        }
    }

    private func setTextGestures(enabled: Bool) {
        guard let webView = bridge?.webView else { return }
        func walk(_ view: UIView) {
            for recognizer in view.gestureRecognizers ?? [] {
                let name = String(describing: type(of: recognizer))
                // Double-tap recognizers start double-tap-and-hold selection
                // (and page zoom); the app never uses the native double-tap.
                let doubleTap = ((recognizer as? UITapGestureRecognizer)?.numberOfTapsRequired ?? 0) >= 2
                if doubleTap || Self.textGestureNames.contains(where: { name.contains($0) }) {
                    recognizer.isEnabled = enabled
                }
            }
            view.subviews.forEach(walk)
        }
        walk(webView)
    }

    // MARK: iOS 17.5+ (Pencil Pro squeeze, and taps with phases)

    @available(iOS 17.5, *)
    public func pencilInteraction(_ interaction: UIPencilInteraction,
                                  didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        var data: [String: Any] = ["phase": Self.name(of: squeeze.phase)]
        if let pose = squeeze.hoverPose {
            // The interaction is attached to the web view, so this is already
            // in its coordinate space (contentInset is "never").
            data["x"] = pose.location.x
            data["y"] = pose.location.y
        }
        notifyListeners("squeeze", data: data)
    }

    @available(iOS 17.5, *)
    public func pencilInteraction(_ interaction: UIPencilInteraction,
                                  didReceiveTap tap: UIPencilInteraction.Tap) {
        notifyListeners("doubleTap", data: [:])
    }

    @available(iOS 17.5, *)
    private static func name(of phase: UIPencilInteraction.Phase) -> String {
        switch phase {
        case .began: return "began"
        case .changed: return "changed"
        case .ended: return "ended"
        case .cancelled: return "cancelled"
        @unknown default: return "cancelled"
        }
    }

    // MARK: Earlier iOS (2nd-gen Pencil double-tap only)

    public func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        notifyListeners("doubleTap", data: [:])
    }
}
