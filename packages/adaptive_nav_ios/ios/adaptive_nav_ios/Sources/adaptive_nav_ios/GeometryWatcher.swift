import Flutter
import UIKit

/// A transparent view the size of the Flutter view, laid on top of it.
///
/// Reserved regions are reported in a view's coordinate space, and UIKit has
/// no callback for "the regions moved": a layout pass, a safe-area change or a
/// new window is the signal that they may have. This view gets all three.
final class GeometryProbeView: UIView {
    var onChange: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onChange?()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onChange?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onChange?()
    }
}

/// Reads the geometry off a [GeometryProbeView] and sends it on whenever it
/// changes. Everything runs on the main thread, and the class says so: the
/// iOS 27.1 SDK declares the trait registration main-actor isolated.
///
/// The iPhone Duo APIs are iOS 27.1 and are checked at run time; building
/// needs the iOS 27.1 SDK. Below 27.1 the state says `supported: false` and
/// still carries the safe area, so the Dart side can tell the two apart.
@MainActor
final class GeometryWatcher: NSObject {
    private let host: () -> UIView?
    private var sink: FlutterEventSink?
    private var probe: GeometryProbeView?
    private var traitRegistration: AnyObject?
    private var last: NSDictionary?

    private var hingeStatus: Int?
    private var hingeAngle: Double?

    init(host: @escaping () -> UIView?) {
        self.host = host
        super.init()
    }

    func start(sink: @escaping FlutterEventSink) {
        self.sink = sink
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(attach),
            name: UIWindow.didBecomeKeyNotification, object: nil)
        center.addObserver(
            self, selector: #selector(attach),
            name: UIScene.didActivateNotification, object: nil)
        last = nil
        attach()
        emit()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        traitRegistration = nil
        probe?.removeFromSuperview()
        probe = nil
        sink = nil
        last = nil
    }

    @objc private func attach() {
        guard let view = host() else { return }
        if let probe, probe.superview === view { return }
        probe?.removeFromSuperview()

        let probe = GeometryProbeView(frame: view.bounds)
        probe.onChange = { [weak self] in self?.emit() }
        view.addSubview(probe)
        self.probe = probe

        if #available(iOS 27.1, *) {
            // The bar's edge is a trait. A rotation also lays the probe out,
            // but an edge that changes without a resize — another app taking
            // the other half of the display — would be missed.
            traitRegistration =
                probe.registerForTraitChanges(
                    UITraitCollection.systemTraitsAffectingVerticalBarEdge
                ) { [weak self] (_: GeometryProbeView, _: UITraitCollection) in
                    self?.emit()
                } as AnyObject

            probe.addInteraction(
                UIHingeInteraction { [weak self] _, update in
                    guard let self else { return }
                    if let hinge = update.hinge {
                        self.hingeStatus = Int(hinge.status.rawValue)
                        self.hingeAngle = Double(hinge.angle)
                    } else {
                        // No hinge in this hierarchy: forget the last one.
                        self.hingeStatus = nil
                        self.hingeAngle = nil
                    }
                    self.emit()
                })
        }
        emit()
    }

    private func emit() {
        guard let sink else { return }
        let state = NSDictionary(dictionary: read())
        if let last, last.isEqual(state) { return }
        last = state
        sink(state)
    }

    private func read() -> [String: Any] {
        guard let probe, let window = probe.window else {
            return ["attached": false]
        }
        let traits = probe.traitCollection
        var state: [String: Any] = [
            "attached": true,
            "supported": false,
            "size": Self.size(probe.bounds.size),
            "safeArea": Self.insets(probe.safeAreaInsets),
            "layoutDirection": Self.direction(traits.layoutDirection),
            "appLayoutDirection": Self.direction(
                UIApplication.shared.userInterfaceLayoutDirection),
            "horizontalSizeClass": Self.sizeClass(traits.horizontalSizeClass),
            "verticalSizeClass": Self.sizeClass(traits.verticalSizeClass),
            "hingeStatus": hingeStatus ?? NSNull(),
            "hingeAngle": hingeAngle ?? NSNull(),
        ]

        // Where the window is on the screen: under Split View the window is
        // half the display, and only this says which half.
        if let screen = window.windowScene?.screen {
            state["screenSize"] = Self.size(screen.bounds.size)
            state["frameInScreen"] = Self.rect(
                probe.convert(probe.bounds, to: screen.coordinateSpace))
        }

        if #available(iOS 26.0, *) {
            state["cornerSafeArea"] = Self.insets(
                probe.edgeInsets(for: .safeArea(cornerAdaptation: .horizontal)))
        }

        if #available(iOS 27.1, *) {
            state["supported"] = true
            // Sent raw: the Dart side names it, and the probe shows the raw
            // value next to the name so a wrong mapping is visible.
            state["verticalBarEdge"] = Int(traits.verticalBarEdge.rawValue)

            var regions: [[String: Any]] = []
            let kinds: [(UIView.ReservedRegion.Kind, String)] = [
                (.division, "division"),
                (.occlusion, "occlusion"),
            ]
            for (kind, name) in kinds {
                // Inactive ones too: the flat fold is still where the panes
                // would part, and the Dart side filters on `active`.
                for region in probe.reservedRegions(kind: kind, options: .includeInactive) {
                    regions.append([
                        "kind": name,
                        "active": region.isActive,
                        "frame": Self.rect(region.frame),
                        "margins": Self.insets(region.margins),
                    ])
                }
            }
            state["regions"] = regions
        }
        return state
    }

    private static func size(_ size: CGSize) -> [String: Double] {
        ["width": Double(size.width), "height": Double(size.height)]
    }

    private static func rect(_ rect: CGRect) -> [String: Double] {
        [
            "left": Double(rect.minX), "top": Double(rect.minY),
            "right": Double(rect.maxX), "bottom": Double(rect.maxY),
        ]
    }

    private static func insets(_ insets: UIEdgeInsets) -> [String: Double] {
        [
            "left": Double(insets.left), "top": Double(insets.top),
            "right": Double(insets.right), "bottom": Double(insets.bottom),
        ]
    }

    private static func direction(_ direction: UITraitEnvironmentLayoutDirection) -> String {
        direction == .rightToLeft ? "rtl" : "ltr"
    }

    private static func direction(_ direction: UIUserInterfaceLayoutDirection) -> String {
        direction == .rightToLeft ? "rtl" : "ltr"
    }

    private static func sizeClass(_ sizeClass: UIUserInterfaceSizeClass) -> String {
        switch sizeClass {
        case .compact: return "compact"
        case .regular: return "regular"
        default: return "unspecified"
        }
    }
}
