import AppKit

// Headless login-item management, used by install scripts so launch-at-login can be
// toggled without opening the UI. Registers/unregisters via SMAppService, then exits.
let cliArgs = CommandLine.arguments
if cliArgs.contains("--register-login-item") {
    LoginItem.setEnabled(true)
    print("login item enabled: \(LoginItem.isEnabled)")
    exit(LoginItem.isEnabled ? 0 : 1)
}
if cliArgs.contains("--unregister-login-item") {
    LoginItem.setEnabled(false)
    print("login item enabled: \(LoginItem.isEnabled)")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

app.run()
