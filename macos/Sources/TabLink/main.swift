import AppKit
import SwiftUI
import CoreImage
import TabLinkCore
final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    private var regressionTimer:Timer?;private var regressionCycles=0;private var cornerPhase=0;private var cornerIndex=0;private var cornerDeadline=Date()
    var model:AppModel!;var window:NSWindow!;var status:NSStatusItem!
    func applicationDidFinishLaunching(_ notification:Notification) {
        model=AppModel()
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1080,height:780),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title="TabLink";window.titlebarAppearsTransparent=true;window.titleVisibility = .hidden;window.minSize=NSSize(width:900,height:690);window.isReleasedWhenClosed=false;window.delegate=self
        window.contentView=NSHostingView(rootView:RootView(model:model));window.center();window.makeKeyAndOrderFront(nil)
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        status.button?.image=NSImage(systemSymbolName:"rectangle.connected.to.line.below",accessibilityDescription:"TabLink")
        let menu=NSMenu();item("Open TabLink",#selector(show),menu);item("Switch devices (⌘⇧P)",#selector(switchDevices),menu);item("Control tablet",#selector(controlTablet),menu);item("Return control to Mac",#selector(local),menu);menu.addItem(.separator());item("Send files…",#selector(files),menu);item("Export diagnostics…",#selector(diagnostics),menu);menu.addItem(.separator());item("Disconnect",#selector(disconnect),menu);item("Quit TabLink",#selector(quit),menu,key:"q");status.menu=menu
        if let button=status.button {
            let drop=StatusDropView(frame:button.bounds,model:model);drop.autoresizingMask=[.width,.height]
            drop.onClick={ [weak button] in button?.performClick(nil) };button.addSubview(drop)
        }
        let main=NSMenu();let appMenu=NSMenu();let root=NSMenuItem();root.submenu=appMenu;main.addItem(root);item("About TabLink",#selector(about),appMenu);appMenu.addItem(.separator());item("Quit TabLink",#selector(quit),appMenu,key:"q")
        let edit=NSMenu(title:"Edit");let editRoot=NSMenuItem(title:"Edit",action:nil,keyEquivalent:"");editRoot.submenu=edit;main.addItem(editRoot)
        for (title,action,key) in [("Cut","cut:","x"),("Copy","copy:","c"),("Paste","paste:","v"),("Select All","selectAll:","a")] {edit.addItem(withTitle:title,action:Selector(action),keyEquivalent:key)}
        let windows=NSMenu(title:"Window");let windowRoot=NSMenuItem(title:"Window",action:nil,keyEquivalent:"");windowRoot.submenu=windows;main.addItem(windowRoot)
        item("Open TabLink",#selector(show),windows,key:"0")
        let close=NSMenuItem(title:"Close Window",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w");windows.addItem(close)
        windows.addItem(withTitle:"Minimize",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        NSApp.windowsMenu=windows
        let switchItem=NSMenuItem(title:"Switch devices",action:#selector(switchDevices),keyEquivalent:"p");switchItem.keyEquivalentModifierMask=[.command,.shift];switchItem.target=self;appMenu.insertItem(switchItem,at:1)
        NSApp.mainMenu=main
        model.onControlChanged = {[weak self] remote in
            guard let self=self else{return}
            self.status.button?.title=remote ? " Tablet":""
            self.status.button?.toolTip=remote ? "Keyboard and trackpad control the tablet. Switch with Command–Shift–P. Emergency return: Control–Option–Command–Escape.":"TabLink"
            if remote {self.window.orderOut(nil);NSApp.activate(ignoringOtherApps:true)}
        }
        NSApp.activate(ignoringOtherApps:true)
        if CommandLine.arguments.contains("--self-test-handoffs") {
            regressionTimer=Timer.scheduledTimer(withTimeInterval:0.3,repeats:true){[weak self]_ in
                guard let self=self,self.model.connected,self.model.accessibility,self.model.uhidAvailable else{return}
                if self.regressionCycles>=40 {
                    self.regressionTimer?.invalidate();self.model.capture?.leave()
                    print("40 live handoff transitions completed without a crash")
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.5){NSApp.terminate(nil)};return
                }
                self.model.capture?.toggle();self.regressionCycles+=1
            }
        }
        if CommandLine.arguments.contains("--self-test-corners") {
            regressionTimer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true){[weak self]_ in
                guard let self=self,self.model.connected,self.model.accessibility,self.model.uhidAvailable else{return}
                if self.cornerIndex>=4 {
                    print("4 physical tablet corners returned control to Mac")
                    self.regressionTimer?.invalidate();self.model.capture?.leave()
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.4){NSApp.terminate(nil)};return
                }
                if self.cornerPhase==0 {
                    if !self.model.isRemote {self.model.controlTablet();self.cornerDeadline=Date().addingTimeInterval(0.9);return}
                    guard self.model.hasPointerFeedback,Date()>self.cornerDeadline else{return}
                    let directions:[(Double,Double)]=[(-240,-240),(240,-240),(240,240),(-240,240)]
                    let d=directions[self.cornerIndex];self.model.capture?.routeMotion(dx:d.0,dy:d.1)
                    print("Corner \(self.cornerIndex): moving toward physical corner")
                    self.cornerPhase=1;self.cornerDeadline=Date().addingTimeInterval(6)
                }else if !self.model.isRemote {
                    print("Corner \(self.cornerIndex): returned control")
                    self.cornerIndex+=1;self.cornerPhase=0;self.cornerDeadline=Date().addingTimeInterval(0.5)
                }else if Date()>self.cornerDeadline {
                    print("FAIL: corner \(self.cornerIndex) did not return control")
                    self.regressionTimer?.invalidate();self.model.capture?.leave()
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.4){NSApp.terminate(nil)}
                }else {
                    let directions:[(Double,Double)]=[(-240,-240),(240,-240),(240,240),(-240,240)]
                    let d=directions[self.cornerIndex];self.model.capture?.routeMotion(dx:d.0,dy:d.1)
                }
            }
        }
        if CommandLine.arguments.contains("--self-test-edges") {
            let originalEdge=model.edge
            var index=0;var phase=0;var deadline=Date()
            let edges:[TabLinkCore.Edge]=[.right,.left,.top,.bottom]
            func finish(_ message:String) {
                print(message);self.regressionTimer?.invalidate();self.model.capture?.leave();self.model.edge=originalEdge
                DispatchQueue.main.asyncAfter(deadline:.now()+0.5){NSApp.terminate(nil)}
            }
            regressionTimer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true){[weak self]_ in
                guard let self=self,self.model.connected,self.model.accessibility,self.model.uhidAvailable else{return}
                if index>=edges.count {finish("PASS: 4 timer-driven Mac edge entries, 4 adjoining tablet edge returns, Mac cursor remained anchored");return}
                let edge=edges[index]
                if phase==0 {
                    self.model.capture?.leave();self.model.capture?.armEdgeForRegression(edge)
                    deadline=Date().addingTimeInterval(1.5);phase=1
                }else if phase==1 {
                    if self.model.isRemote {print("Entered through \(edge.rawValue) after one edge observation");phase=2;deadline=Date().addingTimeInterval(6)}
                    else if Date()>deadline {finish("FAIL: stationary Mac edge \(edge.rawValue) did not enter")}
                }else if !self.model.isRemote {
                    guard self.model.capture?.lastReturnReason=="tablet edge" else{finish("FAIL: returned for \(self.model.capture?.lastReturnReason ?? "unknown") instead of tablet edge");return}
                    print("Returned through adjoining tablet edge for \(edge.rawValue)");index+=1;phase=0
                }else {
                    guard (self.model.capture?.macAnchorDistance ?? .infinity)<3 else{finish("FAIL: Mac cursor moved while tablet had control");return}
                    let dx:Double=edge == .right ? -200:edge == .left ? 200:0
                    let dy:Double=edge == .top ? 200:edge == .bottom ? -200:0
                    self.model.capture?.routeMotion(dx:dx,dy:dy)
                    if Date()>deadline {finish("FAIL: adjoining tablet edge \(edge.rawValue) did not return")}
                }
            }
        }
        if CommandLine.arguments.contains("--self-test-shortcut") {
            var phase=0;var deadline=Date()
            func finish(_ message:String) {
                print(message);self.regressionTimer?.invalidate();self.model.capture?.leave()
                DispatchQueue.main.asyncAfter(deadline:.now()+0.4){NSApp.terminate(nil)}
            }
            regressionTimer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true){[weak self]_ in
                guard let self=self,self.model.connected,self.model.accessibility,self.model.uhidAvailable else{return}
                if phase==0 {
                    self.model.capture?.leave()
                    guard self.model.capture?.shortcutForRegression()==true else{finish("FAIL: shortcut not consumed");return}
                    phase=1;deadline=Date().addingTimeInterval(2)
                }else if phase==1 || phase==4 {
                    if self.model.isRemote {phase+=1;deadline=Date().addingTimeInterval(0.4)}
                    else if Date()>deadline {finish("FAIL: Command Shift P did not enter tablet")}
                }else if phase==2,Date()>deadline {
                    guard self.model.capture?.shortcutForRegression(repeating:true)==true,self.model.isRemote else{finish("FAIL: repeated shortcut toggled control");return}
                    guard self.model.capture?.shortcutForRegression()==true,!self.model.isRemote else{finish("FAIL: Command Shift P did not return to Mac");return}
                    print("PASS: Command Shift P entered and returned; autorepeat ignored")
                    phase=3;deadline=Date().addingTimeInterval(0.2)
                }else if phase==3,Date()>deadline {
                    _ = self.model.capture?.shortcutForRegression();phase=4;deadline=Date().addingTimeInterval(2)
                }else if phase==5,Date()>deadline {
                    guard self.model.capture?.shortcutForRegression(emergency:true)==true,!self.model.isRemote else{finish("FAIL: emergency return failed");return}
                    finish("PASS: emergency return remains available after Command Shift P takeover")
                }
            }
        }
        if CommandLine.arguments.contains("--request-access") {DispatchQueue.main.asyncAfter(deadline:.now()+0.5){if !self.model.accessibility {self.model.requestPermission(true)}}}
        if CommandLine.arguments.contains("--connect-wifi") {DispatchQueue.main.asyncAfter(deadline:.now()+1){self.model.connectOverWiFi()}}
        if CommandLine.arguments.contains("--connect-first") {DispatchQueue.main.asyncAfter(deadline:.now()+1){self.model.connectSelected()}}
    }
    private func item(_ title:String,_ action:Selector,_ menu:NSMenu,key:String="") {let i=NSMenuItem(title:title,action:action,keyEquivalent:key);i.target=self;menu.addItem(i)}
    @objc func show(){window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
    @objc func controlTablet(){model.controlTablet()}
    @objc func switchDevices(){model.capture?.toggle()}
    @objc func local(){model.capture?.leave()}
    @objc func files(){model.chooseFiles()}
    @objc func diagnostics(){model.exportDiagnostics()}
    @objc func disconnect(){model.disconnect()}
    @objc func quit(){NSApp.terminate(nil)}
    @objc func about(){NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"TabLink",.applicationVersion:"1.4 development",.credits:NSAttributedString(string:"Native Android control for macOS.\nAndroid server: scrcpy 3.3.4 (Apache-2.0).\nADB: Android Platform Tools (see Resources/adb-NOTICE.txt).")])}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
    func applicationWillTerminate(_ notification:Notification){model.shutdown()}
    func windowShouldClose(_ sender:NSWindow)->Bool {sender.orderOut(nil);return false}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool{show();return true}
}
if CommandLine.arguments.contains("--self-test-overlays") {
    _=NSApplication.shared
    for _ in 0..<1000 {
        autoreleasepool {
            let overlays=CursorOverlays()
            overlays.prepare(frames:[NSRect(x:0,y:0,width:10,height:10)],visible:false)
            overlays.close();overlays.close()
        }
    }
    print("1000 overlay create/close/deallocate cycles passed")
    exit(0)
}
if let index=CommandLine.arguments.firstIndex(of:"--verify-video"),CommandLine.arguments.count>index+1 {
    let decoder=VideoDecoder();var dimensions:[String]=[];var saved=false
    decoder.onResolution={w,h in dimensions.append("\(w)x\(h)")}
    decoder.onDecoded={image in
        guard !saved else{return};saved=true
        if let cg=CIContext().createCGImage(CIImage(cvPixelBuffer:image),from:CGRect(x:0,y:0,width:CVPixelBufferGetWidth(image),height:CVPixelBufferGetHeight(image))) {
            let rep=NSBitmapImageRep(cgImage:cg);if let data=rep.representation(using:.png,properties:[:]) {try? data.write(to:URL(fileURLWithPath:CommandLine.arguments[index+1]+".png"))}
        }
    }
    do {
        let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[index+1]));var offset=0
        while offset+12<=data.count {
            guard let header=VideoPacketHeader(Data(data[offset..<offset+12])),offset+12+header.size<=data.count else{throw AppError("Bad capture file")}
            offset+=12;decoder.consume(Data(data[offset..<offset+header.size]),config:header.config);offset+=header.size
        }
        decoder.finish {
            let result:[String:Any]=["decoded_frames":decoder.decodedCount,"decode_errors":decoder.errorCount,"hardware_accelerated":decoder.hardwareAccelerated,"dimensions":dimensions]
            let json=try! JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]);print(String(decoding:json,as:UTF8.self));exit(decoder.decodedCount>0 && decoder.errorCount==0 ? 0:1)
        }
        RunLoop.main.run()
    }catch{fputs(error.localizedDescription+"\n",stderr);exit(1)}
}
let app=NSApplication.shared
let delegate=AppDelegate();app.delegate=delegate;app.setActivationPolicy(.regular);app.run()
