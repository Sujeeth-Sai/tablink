import AppKit
import AVFoundation
import TabLinkCore
final class MirrorView:NSView,NSTextInputClient {
    weak var model:AppModel?
    let decoder:VideoDecoder
    private var marked=NSMutableAttributedString(string:"")
    private var tracking:NSTrackingArea?
    private var lastTouch:(Int32,Int32)?
    private var pinch=false
    init(model:AppModel,decoder:VideoDecoder) {self.model=model;self.decoder=decoder;super.init(frame:NSRect(x:0,y:0,width:1000,height:700));wantsLayer=true;layer?.backgroundColor=NSColor.black.cgColor;layer?.addSublayer(decoder.layer);registerForDraggedTypes([.fileURL])}
    required init?(coder:NSCoder) {fatalError()}
    override var acceptsFirstResponder:Bool {true}
    override func layout() {super.layout();CATransaction.begin();CATransaction.setDisableActions(true);decoder.layer.frame=bounds;CATransaction.commit()}
    override func updateTrackingAreas() {super.updateTrackingAreas();if let t=tracking {removeTrackingArea(t)};let t=NSTrackingArea(rect:.zero,options:[.activeInKeyWindow,.inVisibleRect,.mouseMoved,.mouseEnteredAndExited],owner:self,userInfo:nil);addTrackingArea(t);tracking=t}
    private func position(_ e:NSEvent) -> (Int32,Int32)? {
        guard let m=model,m.width>0,m.height>0 else{return nil};let p=convert(e.locationInWindow,from:nil)
        let scale=min(bounds.width/Double(m.width),bounds.height/Double(m.height));let w=Double(m.width)*scale,h=Double(m.height)*scale
        let x=(p.x-(bounds.width-w)/2)/scale,y=(bounds.height-p.y-(bounds.height-h)/2)/scale
        guard x>=0,y>=0,x<Double(m.width),y<Double(m.height) else{return nil};return(Int32(x),Int32(y))
    }
    private func touch(_ e:NSEvent,_ action:UInt8) {
        guard let m=model,let (x,y)=position(e) ?? (action != 0 ? lastTouch:nil) else{return};window?.makeFirstResponder(self)
        if action==0 {pinch=e.modifierFlags.contains(.option)}
        if pinch {
            let x2=Int32(max(0,min(m.width-1,m.width-Int(x)))),y2=Int32(max(0,min(m.height-1,m.height-Int(y))))
            if action==0 {
                m.send(Control.touch(action:0,x:x,y:y,width:UInt16(clamping:m.width),height:UInt16(clamping:m.height),pointer:0))
                m.send(Control.touch(action:0,x:x2,y:y2,width:UInt16(clamping:m.width),height:UInt16(clamping:m.height),pointer:1))
            }else {
                m.send(Control.touch(action:action,x:x2,y:y2,width:UInt16(clamping:m.width),height:UInt16(clamping:m.height),pointer:1))
                m.send(Control.touch(action:action,x:x,y:y,width:UInt16(clamping:m.width),height:UInt16(clamping:m.height),pointer:0))
            }
        }else{m.send(Control.touch(action:action,x:x,y:y,width:UInt16(clamping:m.width),height:UInt16(clamping:m.height)))}
        lastTouch=action==1 ? nil:(x,y)
    }
    override func mouseDown(with e:NSEvent) {touch(e,0)}
    override func mouseDragged(with e:NSEvent) {touch(e,2)}
    override func mouseUp(with e:NSEvent) {touch(e,1)}
    override func rightMouseDown(with e:NSEvent) {if model?.rightClickBack == true {model?.androidKey(4)}else{secondary(e,down:true)}}
    override func rightMouseUp(with e:NSEvent) {if model?.rightClickBack == false {secondary(e,down:false)}}
    private func secondary(_ e:NSEvent,down:Bool) {guard let m=model,let(x,y)=position(e)else{return};m.send(Control.touch(action:down ? 0:1,x:x,y:y,width:UInt16(clamping:m.width),height:UInt16(clamping:m.height),buttons:2,pointer:UInt64.max-1))}
    override func scrollWheel(with e:NSEvent) {
        guard let m=model,let(x,y)=position(e)else{return};let factor=e.hasPreciseScrollingDeltas ? 0.035:1.0;let sign=m.naturalScroll ? 1.0 : -1.0
        m.send(Control.scroll(x:x,y:y,width:UInt16(clamping:m.width),height:UInt16(clamping:m.height),horizontal:e.scrollingDeltaX*factor*sign,vertical:e.scrollingDeltaY*factor*sign))
    }
    override func keyDown(with e:NSEvent) {
        guard let m=model else{return}
        if m.keyboardMode == "physical" {m.physicalKey(e,down:true);return}
        if let code=KeyMapper.android[e.keyCode] {m.send(Control.key(code,down:true,meta:m.androidModifiers(e.modifierFlags)));return}
        if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control) {m.injectKey(e,down:true);return}
        interpretKeyEvents([e])
    }
    override func keyUp(with e:NSEvent) {guard let m=model else{return};if m.keyboardMode == "physical" {m.physicalKey(e,down:false)}else{m.injectKey(e,down:false)}}
    override func flagsChanged(with e:NSEvent) {model?.physicalModifiers(e.modifierFlags)}
    override func resignFirstResponder()->Bool {model?.releaseKeys();return super.resignFirstResponder()}
    func insertText(_ string:Any,replacementRange:NSRange) {let s=(string as? NSAttributedString)?.string ?? (string as? String ?? "");marked=NSMutableAttributedString(string:"");model?.pasteText(s)}
    func setMarkedText(_ string:Any,selectedRange:NSRange,replacementRange:NSRange) {marked=NSMutableAttributedString(string:(string as? NSAttributedString)?.string ?? (string as? String ?? ""))}
    func unmarkText() {marked=NSMutableAttributedString(string:"")}
    func selectedRange()->NSRange {NSRange(location:0,length:0)}
    func markedRange()->NSRange {marked.length>0 ? NSRange(location:0,length:marked.length):NSRange(location:NSNotFound,length:0)}
    func hasMarkedText()->Bool {marked.length>0}
    func attributedSubstring(forProposedRange range:NSRange,actualRange:NSRangePointer?)->NSAttributedString? {nil}
    func validAttributesForMarkedText()->[NSAttributedString.Key] {[]}
    func firstRect(forCharacterRange range:NSRange,actualRange:NSRangePointer?)->NSRect {window?.convertToScreen(convert(bounds,to:nil)) ?? .zero}
    func characterIndex(for point:NSPoint)->Int {0}
    override func doCommand(by selector:Selector) {}
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation {model?.connected == true ? .copy:[]}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        guard let urls=sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL] else{return false};model?.transfer(urls);return true
    }
}
