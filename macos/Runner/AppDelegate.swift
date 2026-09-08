import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Cmd-Q never closes the window, so the height is written here too.
  override func applicationWillTerminate(_ notification: Notification) {
    for case let window as MainFlutterWindow in NSApplication.shared.windows {
      window.saveHeight()
    }
  }
}
