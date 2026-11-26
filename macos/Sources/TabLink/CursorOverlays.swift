import AppKit
private final class CaptureWindow:NSWindow {
    override var canBecomeKey:Bool {true}
}
/// Swift owns these windows. AppKit must never release them a second time on close.
final class CursorOverlays {
    private var windows:[NSWindow]=[]
    func prepare(frames:[NSRect],visible:Bool=true) {
        close()
        for frame in frames {
            let w=CaptureWindow(contentRect:frame,styleMask:.borderless,backing:.buffered,defer:false)
            w.isReleasedWhenClosed=false
            w.isOpaque=false;w.backgroundColor = .clear;w.level = .screenSaver
            w.ignoresMouseEvents=true;w.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
            if visible {w.orderFrontRegardless()}
            windows.append(w)
        }
        if visible {windows.first?.makeKeyAndOrderFront(nil)}
    }
    func close() {
        let previous=windows;windows=[]
        for w in previous {w.orderOut(nil);w.close()}
    }
    deinit {close()}
}
