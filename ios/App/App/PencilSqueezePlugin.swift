import UIKit
import Capacitor

/// Bridge view controller that registers the app's own plugins.
class AppViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(PencilSqueezePlugin())
    }
}

/// Forwards Apple Pencil squeeze and double-tap to the web app as
/// `PencilSqueeze` events:
///   "squeeze"   { phase: "began" | "changed" | "ended" | "cancelled", x?, y? }
///   "doubleTap" {}
/// x/y are the hover location in web view (CSS) points, present only while
/// the Pencil is hovering.
@objc(PencilSqueezePlugin)
public class PencilSqueezePlugin: CAPPlugin, CAPBridgedPlugin, UIPencilInteractionDelegate {
    public let identifier = "PencilSqueezePlugin"
    public let jsName = "PencilSqueeze"
    public let pluginMethods: [CAPPluginMethod] = []

    private var interaction: UIPencilInteraction?

    override public func load() {
        DispatchQueue.main.async {
            guard let webView = self.bridge?.webView else { return }
            let interaction = UIPencilInteraction()
            interaction.delegate = self
            webView.addInteraction(interaction)
            self.interaction = interaction
        }
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
