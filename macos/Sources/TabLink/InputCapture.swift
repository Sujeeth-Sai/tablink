import AppKit
import ApplicationServices
import TabLinkCore
final class InputCapture {
    weak var model:AppModel?
    var router=InputRouter()
    private var tap:CFMachPort?;private var source:CFRunLoopSource?
    private var watchdog:Process?;private var pulse:Pipe?;private var timer:Timer?
    private var lastPoint=CGPoint.zero;private var activeDisplay=CGRect.zero
    private let overlays=CursorOverlays();private var transition=UUID();private var entering=false;private var cursorHidden=false
    private var movedSinceEntry=false;private var edgeCandidate=false;private var nextEntryAt=0.0
    private var anchor=CGPoint.zero;private var edgeReturn=EdgeReturn()
    private var regressionEdgePoint:CGPoint?
    private var cornerReturn=CornerReturn();private var lastPointerFeedback=0.0;private var enteredAt=0.0
    private var remainderX=0.0;private var remainderY=0.0
    private var wheelRemainder=0.0;private var panRemainder=0.0;private var buttons:UInt8=0
    init(model:AppModel) {self.model=model}
    var hidesMacCursor:Bool {cursorHidden}
    private(set) var lastReturnReason=""
    var isInstalled:Bool {if let tap=tap {return CFMachPortIsValid(tap)};return false}
    func install()->Bool {
        if let tap=tap,CFMachPortIsValid(tap) {if !CGEvent.tapIsEnabled(tap:tap) {CGEvent.tapEnable(tap:tap,enable:true)};return true}
        if tap != nil {stop()}
        let types:[CGEventType]=[.mouseMoved,.leftMouseDown,.leftMouseUp,.leftMouseDragged,.rightMouseDown,.rightMouseUp,.rightMouseDragged,.otherMouseDown,.otherMouseUp,.otherMouseDragged,.scrollWheel,.keyDown,.keyUp,.flagsChanged]
        let mask=types.reduce(CGEventMask(0)){$0 | (1<<$1.rawValue)}
        guard let t=CGEvent.tapCreate(tap:.cghidEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:mask,callback:{_,type,event,refcon in
            guard let refcon=refcon else{return Unmanaged.passUnretained(event)}
            return Unmanaged<InputCapture>.fromOpaque(refcon).takeUnretainedValue().handle(type,event)
        },userInfo:Unmanaged.passUnretained(self).toOpaque()) else{return false}
        tap=t;let s=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,t,0);source=s;CFRunLoopAddSource(CFRunLoopGetMain(),s,.commonModes);CGEvent.tapEnable(tap:t,enable:true)
        let timer=Timer(timeInterval:0.025,repeats:true){[weak self]_ in self?.tick()};self.timer=timer;RunLoop.main.add(timer,forMode:.common);return true
    }
    private func handle(_ type:CGEventType,_ e:CGEvent)->Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {leave(reason:"event tap disabled");if let t=tap {CGEvent.tapEnable(tap:t,enable:true)};return Unmanaged.passUnretained(e)}
        if type == .keyDown,let action=HandoffShortcut.action(
            keyCode:UInt16(truncatingIfNeeded:e.getIntegerValueField(.keyboardEventKeycode)),
            command:e.flags.contains(.maskCommand),shift:e.flags.contains(.maskShift),
            control:e.flags.contains(.maskControl),option:e.flags.contains(.maskAlternate)) {
            if e.getIntegerValueField(.keyboardEventAutorepeat) != 0 {return nil}
            if action == .returnToMac {leave(reason:"emergency shortcut");return nil}
            if model?.connected==true,model?.uhidAvailable==true {toggle();return nil}
        }
        guard let m=model else{return Unmanaged.passUnretained(e)}
        if router.state != .remote {
            if m.edgeEnabled && m.connected && m.uhidAvailable && type == .mouseMoved {
                if regressionEdgePoint==nil {sampleLocalEdge(e.location,arm:true)}
            }
            return Unmanaged.passUnretained(e)
        }
        guard m.isRemote else{return Unmanaged.passUnretained(e)}
        guard NSApp.isActive else{leave(reason:"foreground lost");return Unmanaged.passUnretained(e)}
        switch type {
        case .mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged:
            routeMotion(dx:e.getDoubleValueField(.mouseEventDeltaX),dy:e.getDoubleValueField(.mouseEventDeltaY))
        case .leftMouseDown:buttons |= 1;mouseReport()
        case .leftMouseUp:buttons &= ~1;mouseReport()
        case .rightMouseDown:buttons |= 2;mouseReport()
        case .rightMouseUp:buttons &= ~2;mouseReport()
        case .otherMouseDown:buttons |= 4;mouseReport()
        case .otherMouseUp:buttons &= ~4;mouseReport()
        case .scrollWheel:
            let sign=m.naturalScroll ? 1.0 : -1.0
            wheelRemainder+=Double(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))*sign/30
            panRemainder+=Double(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))*sign/30
            let w=Int(wheelRemainder),p=Int(panRemainder);wheelRemainder-=Double(w);panRemainder-=Double(p)
            m.send(Control.uhidInput(id:1,report:HID.mouseReport(buttons:buttons,wheel:w,pan:p)))
        case .keyDown,.keyUp:
            if let event=NSEvent(cgEvent:e) {
                if m.keyboardMode=="text",event.modifierFlags.intersection([.command,.control,.option]).isEmpty,
                   let text=event.characters,!text.isEmpty,text.unicodeScalars.allSatisfy({$0.value>=32 && $0.value<0xf700}) {
                    if type == .keyDown {m.pasteText(text)}
                }else {m.physicalKey(event,down:type == .keyDown)}
            }
        case .flagsChanged:if let event=NSEvent(cgEvent:e) {m.physicalModifiers(event.modifierFlags)}
        default:break
        }
        return nil
    }
    /// Shared by the event tap and the live hardware regression runner.
    func routeMotion(dx:Double,dy:Double) {
        guard let m=model,m.isRemote,router.state == .remote else{return}
        let now=ProcessInfo.processInfo.systemUptime
        edgeReturn.motion(dx:dx,dy:dy,edge:router.edge,now:now)
        remainderX+=dx*m.sensitivity;remainderY+=dy*m.sensitivity
        let x=Int(remainderX),y=Int(remainderY);if x != 0 || y != 0 {movedSinceEntry=true}
        remainderX-=Double(x);remainderY-=Double(y)
        if router.move(dx:Double(x),dy:Double(y)){leave(reason:"fallback edge");return}
        m.send(Control.uhidInput(id:1,report:HID.mouseReport(buttons:buttons,dx:x,dy:y)))
        CGWarpMouseCursorPosition(anchor)
    }
    private func mouseReport() {model?.send(Control.uhidInput(id:1,report:HID.mouseReport(buttons:buttons)))}
    private func displayAt(_ p:CGPoint)->CGRect {
        var ids=[CGDirectDisplayID](repeating:0,count:16);var count:UInt32=0
        if CGGetDisplaysWithPoint(p,16,&ids,&count) == .success,count>0{return CGDisplayBounds(ids[0])};return CGDisplayBounds(CGMainDisplayID())
    }
    private func sampleLocalEdge(_ point:CGPoint,arm:Bool) {
        guard let m=model,m.edgeEnabled,m.connected,m.uhidAvailable,router.state == .local else{edgeCandidate=false;return}
        let now=ProcessInfo.processInfo.systemUptime
        guard now>=nextEntryAt else{return}
        lastPoint=point;let display=displayAt(point);let edge=Edge(rawValue:m.edge) ?? .right
        router.edge=edge;router.dwell=m.dwell/1000;router.width=Double(m.width);router.height=Double(m.height)
        let pinned:Bool;let proportion:Double
        switch edge {
        case .right:pinned=point.x>=display.maxX-4;proportion=(point.y-display.minY)/display.height
        case .left:pinned=point.x<=display.minX+3;proportion=(point.y-display.minY)/display.height
        case .top:pinned=point.y<=display.minY+3;proportion=(point.x-display.minX)/display.width
        case .bottom:pinned=point.y>=display.maxY-4;proportion=(point.x-display.minX)/display.width
        }
        if !pinned {edgeCandidate=false;_ = router.observe(atEdge:false,proportion:proportion,now:now);return}
        if arm {edgeCandidate=true}
        guard edgeCandidate else{return}
        if router.observe(atEdge:true,proportion:proportion,now:now) {edgeCandidate=false;activeDisplay=display;enter()}
    }
    /// Exercise the same callback as the event tap without posting OS events.
    func shortcutForRegression(emergency:Bool=false,repeating:Bool=false)->Bool {
        guard CommandLine.arguments.contains("--self-test-shortcut"),let e=CGEvent(keyboardEventSource:nil,virtualKey:emergency ? 53:35,keyDown:true) else{return false}
        e.flags=emergency ? [.maskCommand,.maskControl,.maskAlternate]:[.maskCommand,.maskShift]
        e.setIntegerValueField(.keyboardEventAutorepeat,value:repeating ? 1:0)
        return handle(.keyDown,e)==nil
    }
    /// Arms exactly one edge observation; only the production timer completes dwell.
    func armEdgeForRegression(_ edge:Edge) {
        guard CommandLine.arguments.contains("--self-test-edges"),let m=model else{return}
        m.edge=edge.rawValue;m.edgeEnabled=true
        let d=CGDisplayBounds(CGMainDisplayID());let p:CGPoint
        switch edge {case .right:p=CGPoint(x:d.maxX-1,y:d.midY);case .left:p=CGPoint(x:d.minX,y:d.midY);case .top:p=CGPoint(x:d.midX,y:d.minY);case .bottom:p=CGPoint(x:d.midX,y:d.maxY-1)}
        nextEntryAt=0;regressionEdgePoint=p;sampleLocalEdge(p,arm:true)
    }
    var macAnchorDistance:Double {
        guard let p=CGEvent(source:nil)?.location else{return .infinity}
        return hypot(p.x-anchor.x,p.y-anchor.y)
    }
    private func enter() {
        guard !entering else{return};entering=true
        let token=UUID();transition=token
        // Process launch and window lifecycle never run inside the event-tap callback.
        DispatchQueue.main.async {[weak self] in
            guard let self=self,self.transition==token,self.router.state == .remote,let m=self.model,m.connected,m.uhidAvailable else{return}
            self.overlays.prepare(frames:NSScreen.screens.map(\.frame))
            NSApp.activate(ignoringOtherApps:true)
            self.finishEnter(token:token,attempts:40)
        }
    }
    private func finishEnter(token:UUID,attempts:Int) {
            guard transition==token,router.state == .remote,let m=model,m.connected,m.uhidAvailable else{return}
            guard NSApp.isActive else {
                if attempts>0 {DispatchQueue.main.asyncAfter(deadline:.now()+0.025){[weak self] in self?.finishEnter(token:token,attempts:attempts-1)}}
                else {leave(reason:"activation timeout");m.report("TabLink could not take foreground control. Try Control tablet again.")}
                return
            }
            m.ensurePointerReady {[weak self] ready in
                guard let self=self,self.transition==token else{return}
                guard ready else{self.leave(reason:"mouse not ready");m.report("Android did not register the tablet mouse. Reconnect and retry.");return}
                guard NSApp.isActive else{self.leave(reason:"foreground lost");return}
                self.startCapture(token:token)
            }
    }
    private func startCapture(token:UUID) {
            guard transition==token,let m=model else{return}
            self.entering=false;self.regressionEdgePoint=nil
            do {
                let p=Process();p.executableURL=Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("TabLinkWatchdog");p.arguments=[String(getpid())]
                let pipe=Pipe();p.standardInput=pipe;p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice
                try p.run();self.watchdog=p;self.pulse=pipe
                _ = Darwin.write(pipe.fileHandleForWriting.fileDescriptor,[UInt8(1)],1)
            }catch{self.leave();m.report("Could not start the input watchdog. Mac control remains available.");return}
            self.remainderX=0;self.remainderY=0;self.buttons=0;self.cornerReturn.reset();self.edgeReturn.reset()
            self.enteredAt=ProcessInfo.processInfo.systemUptime;self.lastPointerFeedback=0;self.movedSinceEntry=false
            self.router.returnAtAnyEdge=false;self.router.automaticReturn=false
            m.send(Control.uhidInput(id:1,report:HID.mouseReport(dx:1)))
            self.anchor=CGPoint(x:self.activeDisplay.midX,y:self.activeDisplay.midY)
            guard CGAssociateMouseAndMouseCursorPosition(0) == .success else{self.leave();return}
            CGWarpMouseCursorPosition(self.anchor)
            CGDisplayHideCursor(CGMainDisplayID());self.cursorHidden=true;m.isRemote=true
    }
    func receivePointer(_ position:TabletPointerPosition) {
        guard router.state == .remote,model?.isRemote==true else{return}
        let now=ProcessInfo.processInfo.systemUptime
        lastPointerFeedback=now;router.automaticReturn=false
        router.synchronize(x:position.x,y:position.y)
        guard movedSinceEntry,now-enteredAt>0.25 else{cornerReturn.reset();return}
        if edgeReturn.observe(position,width:router.width,height:router.height,edge:router.edge,now:now) {leave(reason:"tablet edge")}
        else if cornerReturn.observe(position,width:router.width,height:router.height,now:now) {leave(reason:"tablet corner")}
    }
    func takeControl() {if router.state != .remote {toggle()}}
    func toggle() {
        if router.state == .remote {leave();return}
        guard let m=model,m.connected,m.uhidAvailable,m.accessibility else{return}
        lastPoint=CGEvent(source:nil)?.location ?? .zero;activeDisplay=displayAt(lastPoint)
        router.edge=Edge(rawValue:m.edge) ?? .right;router.width=Double(m.width);router.height=Double(m.height);router.enterAtCenter();enter()
    }
    func leave(reason:String="manual") {
        if cursorHidden || entering {lastReturnReason=reason
            if CommandLine.arguments.contains("--self-test-edges") {print("Return reason: \(reason)")}}
        transition=UUID();entering=false;cornerReturn.reset();edgeReturn.reset();edgeCandidate=false
        nextEntryAt=ProcessInfo.processInfo.systemUptime+0.5;regressionEdgePoint=nil
        // Disarm before closing: an older watchdog must not restore a newer session.
        if let fd=pulse?.fileHandleForWriting.fileDescriptor {_ = Darwin.write(fd,[UInt8(2)],1)}
        let wasRemote=cursorHidden;cursorHidden=false
        router.leave();model?.releaseKeys();buttons=0
        if wasRemote {CGAssociateMouseAndMouseCursorPosition(1);CGDisplayShowCursor(CGMainDisplayID())
            var p=lastPoint
            switch router.edge {case .right:p=CGPoint(x:activeDisplay.maxX-24,y:activeDisplay.minY+max(0,min(1,router.y/max(1,router.height)))*activeDisplay.height)
            case .left:p=CGPoint(x:activeDisplay.minX+24,y:activeDisplay.minY+max(0,min(1,router.y/max(1,router.height)))*activeDisplay.height)
            case .top:p=CGPoint(x:activeDisplay.minX+max(0,min(1,router.x/max(1,router.width)))*activeDisplay.width,y:activeDisplay.minY+24)
            case .bottom:p=CGPoint(x:activeDisplay.minX+max(0,min(1,router.x/max(1,router.width)))*activeDisplay.width,y:activeDisplay.maxY-24)}
            CGWarpMouseCursorPosition(p)
        }
        DispatchQueue.main.async {[overlays] in overlays.close()}
        try? pulse?.fileHandleForWriting.close();pulse=nil;watchdog=nil;model?.isRemote=false
    }
    private func tick() {
        if router.state == .remote && !entering {
            if ProcessInfo.processInfo.systemUptime-lastPointerFeedback>1.5 {router.automaticReturn=true}
            guard NSApp.isActive else{leave(reason:"foreground lost");return}
            CGWarpMouseCursorPosition(anchor)
            guard let m=model,m.connected,watchdog?.isRunning==true else{leave();return}
            if let fd=pulse?.fileHandleForWriting.fileDescriptor, Darwin.write(fd,[UInt8(1)],1) != 1 {leave()}
        }else if edgeCandidate,let point=regressionEdgePoint ?? CGEvent(source:nil)?.location {sampleLocalEdge(point,arm:false)}
    }
    func stop() {leave();timer?.invalidate();if let s=source {CFRunLoopRemoveSource(CFRunLoopGetMain(),s,.commonModes)};if let t=tap {CFMachPortInvalidate(t)};tap=nil;source=nil}
    deinit {stop()}
}
