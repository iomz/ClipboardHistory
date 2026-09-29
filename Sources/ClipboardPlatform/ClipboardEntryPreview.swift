import AppKit
import ClipboardCore
import Foundation

/// Shared read-only detail semantics for Manager and picker hover previews.
public struct ClipboardEntryPreviewModel {
    public let text: String
    public let image: NSImage?
    public let typeDescription: String

    public init(entry: ClipboardEntry) {
        text = entry.plainText ?? entry.preview
        image = Self.image(for: entry)
        typeDescription = "\(entry.typeSummary) · \(entry.compactTypeLabel)"
    }

    private static func image(for entry: ClipboardEntry) -> NSImage? {
        let representations = entry.pasteboardItems.flatMap(\.representations)
        for type in ["public.png", "public.tiff", "public.jpeg"] {
            if let data = representations.first(where: { $0.typeIdentifier == type })?.data,
               let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }
}

/// Event-driven hover lifetime shared by a source row and its preview window.
public struct PickerHoverRegionState {
    public private(set) var entryID: UUID?
    public private(set) var pointerOverRow = false
    public private(set) var pointerOverPreview = false

    public init() {}

    public var shouldDismiss: Bool { !pointerOverRow && !pointerOverPreview }

    public mutating func enterRow(_ id: UUID) {
        entryID = id
        pointerOverRow = true
    }

    @discardableResult
    public mutating func exitRow(_ id: UUID) -> Bool {
        guard entryID == id else { return false }
        pointerOverRow = false
        return true
    }

    public mutating func enterPreview() { pointerOverPreview = true }
    public mutating func exitPreview() { pointerOverPreview = false }

    public mutating func reset() {
        entryID = nil
        pointerOverRow = false
        pointerOverPreview = false
    }
}

/// Focus-neutral visual preview. Never makes key/main or activates its parent app.
public final class ClipboardEntryHoverPreview: NSObject {
    private let panel: NonActivatingPreviewPanel
    private let parentWindow: NSWindow
    private let typeLabel = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    private let textView = NSTextView()
    private let textScroll = NSScrollView()
    private var imageHeightConstraint: NSLayoutConstraint!
    private var textHeightConstraint: NSLayoutConstraint!
    private var isAttached = false
    public var onPointerEntered: (() -> Void)?
    public var onPointerExited: (() -> Void)?

    public init(parentWindow: NSWindow) {
        self.parentWindow = parentWindow
        panel = NonActivatingPreviewPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        super.init()
        configurePanel()
        configureContent()
    }

    public var isVisible: Bool { panel.isVisible }

    public func show(model: ClipboardEntryPreviewModel, anchoredTo rowRect: NSRect) {
        typeLabel.stringValue = model.typeDescription
        imageView.image = model.image
        let hasImage = model.image != nil
        imageView.isHidden = !hasImage
        imageHeightConstraint.constant = hasImage ? 112 : 0
        textView.string = model.text
        textHeightConstraint.constant = hasImage ? 72 : 184
        panel.setContentSize(NSSize(width: 340, height: 260))
        panel.setFrameOrigin(origin(for: rowRect, size: panel.frame.size))
        if !isAttached {
            parentWindow.addChildWindow(panel, ordered: .above)
            isAttached = true
        }
        panel.orderFrontRegardless()
    }

    public func hide() {
        guard panel.isVisible || isAttached else { return }
        panel.orderOut(nil)
        if isAttached {
            parentWindow.removeChildWindow(panel)
            isAttached = false
        }
    }

    private func configurePanel() {
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = parentWindow.level
    }

    private func configureContent() {
        let root = PreviewTrackingView(frame: NSRect(x: 0, y: 0, width: 340, height: 260))
        root.onPointerEntered = { [weak self] in self?.onPointerEntered?() }
        root.onPointerExited = { [weak self] in self?.onPointerExited?() }
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true

        typeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        typeLabel.translatesAutoresizingMaskIntoConstraints = false

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true

        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 12)
        textView.textContainerInset = NSSize(width: 6, height: 5)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textScroll.documentView = textView
        textScroll.hasVerticalScroller = true
        textScroll.drawsBackground = false
        textScroll.borderType = .noBorder
        textScroll.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(typeLabel)
        root.addSubview(imageView)
        root.addSubview(textScroll)
        imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 0)
        textHeightConstraint = textScroll.heightAnchor.constraint(equalToConstant: 184)
        NSLayoutConstraint.activate([
            typeLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            typeLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),
            typeLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            imageView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            imageView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            imageView.topAnchor.constraint(equalTo: typeLabel.bottomAnchor, constant: 8),
            imageHeightConstraint,
            textScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            textScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            textScroll.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 2),
            textHeightConstraint,
            textScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
        ])
        panel.contentView = root
    }

    private func origin(for rowRect: NSRect, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(rowRect) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = rowRect.maxX + 8
        if x + size.width > visible.maxX { x = rowRect.minX - size.width - 8 }
        x = min(max(x, visible.minX), visible.maxX - size.width)
        let y = min(max(rowRect.midY - size.height / 2, visible.minY), visible.maxY - size.height)
        return NSPoint(x: x, y: y)
    }

}

private final class NonActivatingPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PreviewTrackingView: NSView {
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onPointerEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointerExited?()
    }
}
