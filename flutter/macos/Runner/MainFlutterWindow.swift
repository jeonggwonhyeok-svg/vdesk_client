import Cocoa
import AVFoundation
import FlutterMacOS
import desktop_multi_window
// import bitsdojo_window_macos

import desktop_drop
import device_info_plus
import flutter_custom_cursor
import package_info_plus
import path_provider_foundation
import screen_retriever
import sqflite_darwin
// import tray_manager
import uni_links_desktop
import url_launcher_macos
import wakelock_plus
import window_manager
import window_size
import texture_rgba_renderer

class MainFlutterWindow: NSWindow {
    override func awakeFromNib() {
        // Hide background processes (--server, --cm) from Dock
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--server") || args.contains("--cm") {
            NSApp.setActivationPolicy(.accessory)
        }
        onedesk_core_main();
        let flutterViewController = FlutterViewController.init()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)
        // register self method handler
        let registrar = flutterViewController.registrar(forPlugin: "OneDeskPlugin")
        setMethodHandler(registrar: registrar)

        RegisterGeneratedPlugins(registry: flutterViewController)

        FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
            // Register the plugin which you want access from other isolate.
            // DesktopLifecyclePlugin.register(with: controller.registrar(forPlugin: "DesktopLifecyclePlugin"))
            // Note: copy below from above RegisterGeneratedPlugins
            self.setMethodHandler(registrar: controller.registrar(forPlugin: "OneDeskPlugin"))
            DesktopDropPlugin.register(with: controller.registrar(forPlugin: "DesktopDropPlugin"))
            DeviceInfoPlusMacosPlugin.register(with: controller.registrar(forPlugin: "DeviceInfoPlusMacosPlugin"))
            FlutterCustomCursorPlugin.register(with: controller.registrar(forPlugin: "FlutterCustomCursorPlugin"))
            FPPPackageInfoPlusPlugin.register(with: controller.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
            PathProviderPlugin.register(with: controller.registrar(forPlugin: "PathProviderPlugin"))
            SqflitePlugin.register(with: controller.registrar(forPlugin: "SqflitePlugin"))
            // TrayManagerPlugin.register(with: controller.registrar(forPlugin: "TrayManagerPlugin"))
            UniLinksDesktopPlugin.register(with: controller.registrar(forPlugin: "UniLinksDesktopPlugin"))
            UrlLauncherPlugin.register(with: controller.registrar(forPlugin: "UrlLauncherPlugin"))
            WakelockPlusMacosPlugin.register(with: controller.registrar(forPlugin: "WakelockPlusMacosPlugin"))
            WindowSizePlugin.register(with: controller.registrar(forPlugin: "WindowSizePlugin"))
            TextureRgbaRendererPlugin.register(with: controller.registrar(forPlugin: "TextureRgbaRendererPlugin"))
        }

        super.awakeFromNib()
    }

    override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        hiddenWindowAtLaunch()
        // Only promote to .regular when window is actually visible.
        // Don't set .accessory here — let orderOut() handle that.
        // Setting .accessory here races with makeKeyAndOrderFront/orderFront
        // which set .regular before the window is fully visible.
        if place != .out && self.isVisible {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // window_manager show() calls makeKeyAndOrderFront
    override public func orderFront(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        super.orderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    // window_manager hide() calls orderOut
    override public func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        NSApp.setActivationPolicy(.accessory)
    }

    // window_manager show() calls this via makeKeyAndOrderFront
    override public func makeKeyAndOrderFront(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        super.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Override window theme.
    public func setWindowInterfaceMode(window: NSWindow, themeName: String) {
        window.appearance = NSAppearance(named: themeName == "light" ? .aqua : .darkAqua)
    }

    public func setMethodHandler(registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "org.onedesk.onedesk/host", binaryMessenger: registrar.messenger)
        channel.setMethodCallHandler({
            (call, result) -> Void in
                switch call.method {
                case "setWindowTheme":
                    let arg = call.arguments as! [String: Any]
                    let themeName = arg["themeName"] as? String
                    guard let window = registrar.view?.window else {
                        result(nil)
                        return
                    }
                    self.setWindowInterfaceMode(window: window,themeName: themeName ?? "light")
                    result(nil)
                    break;
                case "terminate":
                    NSApplication.shared.terminate(self)
                    result(nil)
                case "canRecordAudio":
                    switch AVCaptureDevice.authorizationStatus(for: .audio) {
                    case .authorized:
                        result(1)
                        break
                    case .notDetermined:
                        result(0)
                        break
                    default:
                        result(-1)
                        break
                    }
                case "requestRecordAudio":
                    AVCaptureDevice.requestAccess(for: .audio, completionHandler: { granted in
                        result(granted)
                    })
                    break
                case "bumpMouse":
                    var dx = 0
                    var dy = 0

                    if let argMap = call.arguments as? [String: Any] {
                        dx = (argMap["dx"] as? Int) ?? 0
                        dy = (argMap["dy"] as? Int) ?? 0
                    }
                    else if let argList = call.arguments as? [Any] {
                        dx = argList.count >= 1 ? (argList[0] as? Int) ?? 0 : 0
                        dy = argList.count >= 2 ? (argList[1] as? Int) ?? 0 : 0
                    }

                    var mouseLoc: CGPoint

                    if let dummyEvent = CGEvent(source: nil) { // can this ever fail?
                        mouseLoc = dummyEvent.location
                    }
                    else if let screenFrame = NSScreen.screens.first?.frame {
                        // NeXTStep: Origin is lower-left of primary screen, positive is up
                        // Cocoa Core Graphics: Origin is upper-left of primary screen, positive is down
                        let nsMouseLoc = NSEvent.mouseLocation

                        mouseLoc = CGPoint(
                            x: nsMouseLoc.x,
                            y: NSHeight(screenFrame) - nsMouseLoc.y)
                    }
                    else {
                        result(false)
                        break
                    }

                    let newLoc = CGPoint(x: mouseLoc.x + CGFloat(dx), y: mouseLoc.y + CGFloat(dy))

                    CGDisplayMoveCursorToPoint(0, newLoc)

                    // By default, Cocoa suppresses mouse events briefly after a call to warp the
                    // cursor to a new location. This is good if you want to draw the user's
                    // attention to the fact that the mouse is now in a particular location, but
                    // it's bad in this case; we get called as part of the handling of edge
                    // scrolling, which means the mouse is typically still in motion, and we want
                    // the cursor to keep moving smoothly uninterrupted.
                    //
                    // This function's main action is to toggle whether the mouse cursor is
                    // associated with the mouse position, but setting it to true when it's
                    // already true has the side-effect of cancelling this motion suppression.
                    CGAssociateMouseAndMouseCursorPosition(1 /* true */)

                    result(true)

                    break

                default:
                    result(FlutterMethodNotImplemented)
                }
        })
    }
}
