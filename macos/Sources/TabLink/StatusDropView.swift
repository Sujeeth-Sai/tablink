import AppKit
final class StatusDropView:NSView {
    weak var model:AppModel?
    var onClick:(()->Void)?
    init(frame:NSRect,model:AppModel) {self.model=model;super.init(frame:frame);registerForDraggedTypes([.fileURL]);setAccessibilityRole(.button);setAccessibilityLabel("TabLink menu and file drop")}
    required init?(coder:NSCoder) {return nil}
    override func mouseDown(with event:NSEvent) {onClick?()}
    override func rightMouseDown(with event:NSEvent) {onClick?()}
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation {model?.connected==true && model?.busy==false ? .copy:[]}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        guard model?.connected==true,let urls=sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],!urls.isEmpty else{return false}
        model?.transfer(urls);return true
    }
}
