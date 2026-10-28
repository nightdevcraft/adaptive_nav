import Flutter
import UIKit

/// Streams the geometry of the Flutter view's window on
/// `adaptive_nav_ios/geometry`.
///
/// The watcher only runs while Dart listens, so an app that never puts a
/// `DuoGeometryProvider` in its tree pays for nothing but the registration.
///
/// Flutter registers the plugin and calls the stream handler on the main
/// thread; the protocols just do not say so, hence `@preconcurrency`.
@MainActor
public final class AdaptiveNavIosPlugin: NSObject, @preconcurrency FlutterPlugin,
    @preconcurrency FlutterStreamHandler
{
    private weak var registrar: FlutterPluginRegistrar?
    private lazy var watcher = GeometryWatcher { [weak self] in self?.flutterView() }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AdaptiveNavIosPlugin()
        instance.registrar = registrar
        let channel = FlutterEventChannel(
            name: "adaptive_nav_ios/geometry", binaryMessenger: registrar.messenger())
        channel.setStreamHandler(instance)
    }

    public func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        watcher.start(sink: events)
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        watcher.stop()
        return nil
    }

    /// The view Flutter draws into, so that a region's frame is already in
    /// Flutter's logical pixels with Flutter's origin.
    ///
    /// With the scene lifecycle the registrar can be asked before it has a
    /// view controller, so the connected scenes are searched as well.
    private func flutterView() -> UIView? {
        if let view = registrar?.viewController?.viewIfLoaded {
            return view
        }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let ordered = windows.filter(\.isKeyWindow) + windows.filter { !$0.isKeyWindow }
        for window in ordered {
            if let root = window.rootViewController, let view = Self.flutterView(in: root) {
                return view
            }
        }
        return nil
    }

    private static func flutterView(in controller: UIViewController) -> UIView? {
        if let flutter = controller as? FlutterViewController {
            return flutter.viewIfLoaded
        }
        for child in controller.children {
            if let view = flutterView(in: child) {
                return view
            }
        }
        if let presented = controller.presentedViewController {
            return flutterView(in: presented)
        }
        return nil
    }
}
