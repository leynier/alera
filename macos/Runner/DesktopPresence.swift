import Cocoa
import FlutterMacOS

/// Tray icon (NSStatusItem) and Dock badge for pending agent review.
final class DesktopPresence: NSObject {
  private let channel: FlutterMethodChannel
  private var statusItem: NSStatusItem?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "dev.leynier.alera/desktop_presence",
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setTray":
      let args = call.arguments as? [String: Any]
      let visible = args?["visible"] as? Bool ?? false
      let tooltip = args?["tooltip"] as? String ?? ""
      setTray(visible: visible, tooltip: tooltip)
      result(nil)
    case "setBadgeCount":
      let args = call.arguments as? [String: Any]
      let count = args?["count"] as? Int ?? 0
      setBadgeCount(count)
      result(nil)
    case "destroy":
      destroy()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setTray(visible: Bool, tooltip: String) {
    NSApp.setActivationPolicy(.regular)
    if visible {
      if statusItem == nil {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSApp.applicationIconImage
        item.button?.image?.isTemplate = false
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
      }
      statusItem?.button?.toolTip = tooltip
    } else {
      removeStatusItem()
    }
  }

  private func setBadgeCount(_ count: Int) {
    if count <= 0 {
      NSApp.dockTile.badgeLabel = nil
    } else {
      NSApp.dockTile.badgeLabel = "\(count)"
    }
    NSApp.dockTile.display()
  }

  private func destroy() {
    removeStatusItem()
    NSApp.dockTile.badgeLabel = nil
    NSApp.dockTile.display()
  }

  private func removeStatusItem() {
    if let item = statusItem {
      NSStatusBar.system.removeStatusItem(item)
      statusItem = nil
    }
  }

  private func buildMenu() -> NSMenu {
    let menu = NSMenu()
    let show = NSMenuItem(
      title: "Show \(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Alera")",
      action: #selector(showWindow),
      keyEquivalent: ""
    )
    show.target = self
    menu.addItem(show)
    menu.addItem(.separator())
    let quit = NSMenuItem(
      title: "Quit",
      action: #selector(quitApp),
      keyEquivalent: ""
    )
    quit.target = self
    menu.addItem(quit)
    return menu
  }

  @objc
  private func statusItemClicked(_ sender: Any?) {
    let event = NSApp.currentEvent
    if event?.type == .rightMouseUp, let button = statusItem?.button {
      buildMenu().popUp(
        positioning: nil,
        at: NSPoint(x: 0, y: button.bounds.height),
        in: button
      )
      return
    }
    showWindow()
  }

  func requestShow() {
    showWindow()
  }

  @objc
  private func showWindow() {
    channel.invokeMethod("trayShow", arguments: nil)
  }

  @objc
  private func quitApp() {
    channel.invokeMethod("trayQuit", arguments: nil)
  }
}
