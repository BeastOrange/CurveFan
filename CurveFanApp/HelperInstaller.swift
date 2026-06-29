import AppKit
import Foundation

/// Installs the privileged helper on first launch by extracting the embedded
/// binary from the app bundle and running a shell script with admin privileges
/// via the native macOS password dialog (osascript).
@MainActor
enum HelperInstaller {

    private static let helperDst = "/Library/PrivilegedHelperTools/curvefan-helper"
    private static let plistDst  = "/Library/LaunchDaemons/com.curvefan.helper.plist"

    /// Returns true if the helper binary is already installed.
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: helperDst)
    }

    /// Shows a permission dialog and installs the helper if needed.
    /// Returns true if the helper is ready to use after this call.
    static func installIfNeeded() -> Bool {
        guard !isInstalled else { return true }

        guard let src = Bundle.main.path(forResource: "CurveFanHelper", ofType: nil) else {
            showError("Embedded helper not found in app bundle. Re-download CurveFan.")
            return false
        }

        let alert = NSAlert()
        alert.messageText = "CurveFan needs to install a helper"
        alert.informativeText = "A privileged helper is required to read and control your fans. macOS will ask for your password once."
        alert.addButton(withTitle: "Install Helper")
        alert.addButton(withTitle: "Quit")
        alert.alertStyle = .informational
        if alert.runModal() != .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
            return false
        }

        let plist = plistContent()
        // Write the install script to a temp file to avoid shell-escaping issues.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("curvefan_install_\(ProcessInfo().processIdentifier).sh")
        let script = """
        #!/bin/bash
        set -e
        mkdir -p /Library/PrivilegedHelperTools
        cp '\(src)' '\(helperDst)'
        chown root:wheel '\(helperDst)'
        chmod 755 '\(helperDst)'
        cat > '\(plistDst)' << 'ENDPLIST'
        \(plist)
        ENDPLIST
        chown root:wheel '\(plistDst)'
        chmod 644 '\(plistDst)'
        launchctl unload '\(plistDst)' 2>/dev/null || true
        launchctl load -w '\(plistDst)'
        """
        do {
            try script.write(to: tmp, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        } catch {
            showError("Failed to write install script: \(error.localizedDescription)")
            return false
        }

        let appleScript = "do shell script \"\(tmp.path)\" with administrator privileges"
        var errDict: NSDictionary?
        NSAppleScript(source: appleScript)?.executeAndReturnError(&errDict)
        try? FileManager.default.removeItem(at: tmp)

        if let err = errDict {
            // User cancelled the password dialog
            let msg = err[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            if !msg.contains("User cancelled") {
                showError("Helper installation failed: \(msg)")
            }
            return false
        }
        return isInstalled
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "CurveFan couldn't install the helper"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }

    private static func plistContent() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>      <string>com.curvefan.helper</string>
            <key>ProgramArguments</key>
            <array><string>/Library/PrivilegedHelperTools/curvefan-helper</string></array>
            <key>RunAtLoad</key>  <true/>
            <key>KeepAlive</key>  <true/>
            <key>StandardErrorPath</key> <string>/var/log/curvefan-helper.log</string>
            <key>StandardOutPath</key>   <string>/var/log/curvefan-helper.log</string>
        </dict>
        </plist>
        """
    }
}
