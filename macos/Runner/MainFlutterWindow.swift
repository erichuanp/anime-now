import Cocoa
import FlutterMacOS
import IOKit

/// The app is drawn for a phone screen, so the window opens in that shape.
///
/// Resizing is free in every direction; only the height is remembered between
/// launches. Every launch starts from `defaultRatio` at the height the user
/// left behind, so the window comes back phone-shaped however they stretched it.
class MainFlutterWindow: NSWindow {
  /// The reference device (1264 × 2800), the shape the layout was drawn for.
  private static let defaultRatio: CGFloat = 1264.0 / 2800.0
  private static let defaultHeight: CGFloat = 860
  private static let minWidth: CGFloat = 320
  private static let minHeight: CGFloat = 560
  private static let heightKey = "windowHeight"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    self.minSize = NSSize(width: MainFlutterWindow.minWidth, height: MainFlutterWindow.minHeight)
    self.setFrame(NSRect(origin: frame.origin, size: restoredSize()), display: true)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerPlatformChannel(flutterViewController)

    super.awakeFromNib()
  }

  // MARK: - Sizing

  private func restoredSize() -> NSSize {
    let stored = UserDefaults.standard.double(forKey: MainFlutterWindow.heightKey)
    let height = stored >= Double(MainFlutterWindow.minHeight)
      ? CGFloat(stored)
      : MainFlutterWindow.defaultHeight
    // Never taller than the screen it opens on.
    let usable = (self.screen ?? NSScreen.main)?.visibleFrame.height ?? height
    let h = min(height, usable)
    return NSSize(width: (h * MainFlutterWindow.defaultRatio).rounded(), height: h)
  }

  func saveHeight() {
    UserDefaults.standard.set(Double(frame.height), forKey: MainFlutterWindow.heightKey)
  }

  override func close() {
    saveHeight()
    super.close()
  }

  // MARK: - anime_now/platform

  private func registerPlatformChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "anime_now/platform",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "deviceId":
        result(MainFlutterWindow.hardwareUUID())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// The Mac's own `IOPlatformUUID`: stable across reinstalls, different on
  /// every machine.
  private static func hardwareUUID() -> String {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    guard service != 0 else { return "" }
    defer { IOObjectRelease(service) }
    let value = IORegistryEntryCreateCFProperty(
      service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
    return (value?.takeRetainedValue() as? String) ?? ""
  }
}
