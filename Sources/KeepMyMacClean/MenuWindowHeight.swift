import AppKit
import SwiftUI

/// Keeps the menu bar window exactly as tall as its content.
///
/// `MenuBarExtra` windows grow with their content but don't always shrink back (for example after
/// a scan fills in or a category collapses), which leaves empty space above and below the content.
/// This resizes the window to the measured height, keeping its top edge under the menu bar.
struct MenuWindowHeight: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> SizingView {
        SizingView()
    }

    func updateNSView(_ view: SizingView, context: Context) {
        view.targetHeight = height
    }

    final class SizingView: NSView {
        var targetHeight: CGFloat = 0 {
            didSet {
                if targetHeight != oldValue { scheduleResize() }
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleResize()
        }

        /// Runs after SwiftUI's own layout pass so this size wins.
        private func scheduleResize() {
            Task { @MainActor [weak self] in
                self?.resizeWindow()
            }
        }

        private func resizeWindow() {
            guard let window, targetHeight > 0 else { return }
            let chrome = window.frame.height - (window.contentView?.frame.height ?? window.frame.height)
            let newHeight = (targetHeight + chrome).rounded()
            var frame = window.frame
            guard abs(frame.height - newHeight) > 0.5 else { return }
            frame.origin.y += frame.height - newHeight
            frame.size.height = newHeight
            window.setFrame(frame, display: true)
        }
    }
}
