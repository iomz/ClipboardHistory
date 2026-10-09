import AppKit
import Carbon
import Foundation
import OSLog

/// Isolated first-party Carbon hotkey registration shim. No event tap is installed.
public final class GlobalHotkey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private let identifier: EventHotKeyID
    private let keyCode: UInt32
    private let modifiers: UInt32

    public init(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.identifier = EventHotKeyID(signature: OSType(0x434C4950), id: id)
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }

    public func register() -> OSStatus {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(), Self.eventCallback, 1, &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard installStatus == noErr else { return installStatus }
        return RegisterEventHotKey(
            keyCode, modifiers, identifier,
            GetApplicationEventTarget(), 0, &hotKey
        )
    }

    public func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }

    deinit { unregister() }

    private static let eventCallback: EventHandlerProcPtr = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var received = EventHotKeyID()
        let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &received
        )
        guard status == noErr, received.signature == OSType(0x434C4950) else { return OSStatus(eventNotHandledErr) }
        let instance = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
        guard received.id == instance.identifier.id else { return OSStatus(eventNotHandledErr) }
        DispatchQueue.main.async { instance.action() }
        return noErr
    }
}

public enum PasteCommand {
    private static let logger = Logger(subsystem: "com.iomz.TheClipboard", category: "Paste")

    /// Request event-synthesizing authorization while picker is still active,
    /// before destination activation/focus handoff begins.
    public static func ensureEventPostingAccess() -> Bool {
        let alreadyAuthorized = CGPreflightPostEventAccess()
        logger.info("paste permission preflight=\(alreadyAuthorized, privacy: .public)")
        guard !alreadyAuthorized else { return true }
        let requested = CGRequestPostEventAccess()
        let authorizedAfterRequest = CGPreflightPostEventAccess()
        logger.info("paste permission requested=\(requested, privacy: .public) authorizedAfterRequest=\(authorizedAfterRequest, privacy: .public)")
        return requested && authorizedAfterRequest
    }

    /// Synthesize Command-V directly to captured process. CGEventPostToPid has
    /// no result value; log records that dispatch was issued, not app receipt.
    @discardableResult
    public static func post(to processIdentifier: pid_t) -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        logger.info("paste events keyCode=\(kVK_ANSI_V, privacy: .public) flags=Command targetPID=\(processIdentifier, privacy: .public) route=CGEventPostToPid sequence=down/up")
        down.postToPid(processIdentifier)
        up.postToPid(processIdentifier)
        return true
    }
}
