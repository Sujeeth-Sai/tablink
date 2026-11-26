import AppKit
import SwiftUI
import ApplicationServices
import TabLinkCore
struct Activity:Identifiable {let id=UUID();let time=Date();let message:String}
final class AppModel:ObservableObject {
    @Published var devices:[Device]=[]
    @Published var selected:String=""
    @Published var connected=false
    @Published var connecting=false
    @Published var deviceName="Android tablet"
    @Published var width=1920
    @Published var height=1080
    @Published var androidVersion=""
    @Published var isRemote=false {didSet{session?.trackPointer(isRemote);onControlChanged?(isRemote);writeStatus()}}
    var onControlChanged:((Bool)->Void)?
    private var pendingTakeover=false
    private var pointerAttached=false;private var pointerVerified=false
    @Published var uhidAvailable=false
    @Published var busy=false
    @Published var transferStatus=""
    @Published var notice=""
    @Published var activities:[Activity]=[]
    @Published var wirelessServices:[WirelessService]=[]
    @Published var wirelessSearching=false
    @Published var wirelessMessage=""
    @Published var needsWirelessPairing=false
    private let wirelessDiscovery=WirelessDiscovery()
    private var bonjourServices:[WirelessService]=[]
    private var wirelessAttempt=UUID()
    private var lastPointer:TabletPointerPosition?
    var hasPointerFeedback:Bool {lastPointer != nil}
    @Published var accessibility=false
    @Published var inputMonitoring=false
    @Published var edgeEnabled=false {didSet{if !edgeEnabled {capture?.leave()}}}
    @Published var edge=UserDefaults.standard.string(forKey:"edge") ?? "right" {didSet{UserDefaults.standard.set(edge,forKey:"edge");capture?.leave()}}
    @Published var dwell=UserDefaults.standard.object(forKey:"dwell") as? Double ?? 200 {didSet{UserDefaults.standard.set(dwell,forKey:"dwell")}}
    @Published var sensitivity=UserDefaults.standard.object(forKey:"sensitivity") as? Double ?? 1 {didSet{UserDefaults.standard.set(sensitivity,forKey:"sensitivity")}}
    @Published var naturalScroll=UserDefaults.standard.object(forKey:"naturalScroll") as? Bool ?? true {didSet{UserDefaults.standard.set(naturalScroll,forKey:"naturalScroll")}}
    @Published var commandToControl=UserDefaults.standard.object(forKey:"commandToControl") as? Bool ?? true {didSet{UserDefaults.standard.set(commandToControl,forKey:"commandToControl")}}
    @Published var rightClickBack=UserDefaults.standard.object(forKey:"rightClickBack") as? Bool ?? true {didSet{UserDefaults.standard.set(rightClickBack,forKey:"rightClickBack")}}
    @Published var clipboardSync=UserDefaults.standard.object(forKey:"clipboardSync") as? Bool ?? true {didSet{UserDefaults.standard.set(clipboardSync,forKey:"clipboardSync");pasteboardCount=NSPasteboard.general.changeCount}}
    @Published var keyboardMode=UserDefaults.standard.string(forKey:"keyboardMode") ?? "physical" {didSet{releaseKeys();UserDefaults.standard.set(keyboardMode,forKey:"keyboardMode")}}
    @Published var quality=UserDefaults.standard.string(forKey:"quality") ?? "balanced" {didSet{UserDefaults.standard.set(quality,forKey:"quality")}}
    @Published var autoReconnect=UserDefaults.standard.object(forKey:"autoReconnect") as? Bool ?? true {didSet{UserDefaults.standard.set(autoReconnect,forKey:"autoReconnect")}}
    let adb=ADB()
    var session:TabletSession?
    var capture:InputCapture?
    private var deviceTimer:Timer?;private var clipboardTimer:Timer?
    private let work=DispatchQueue(label:"app.tablink.jobs",qos:.userInitiated)
    private var refreshing=false
    private var lastCapsLock=NSEvent.modifierFlags.contains(.capsLock)
    private var keys:Set<UInt8>=[];private var injected:Set<Int32>=[]
    private var pasteboardCount=NSPasteboard.general.changeCount
    private var sequence:UInt64=1
    private var reconnectSerial:String?
    private var retryAfter=Date.distantPast
    private var generation=UUID()
    init() {
        signal(SIGPIPE,SIG_IGN)
        capture=InputCapture(model:self)
        wirelessDiscovery.onChange = {[weak self] services in
            self?.bonjourServices=services
            self?.wirelessServices=services
            self?.log("Wi-Fi discovery resolved \(services.count) service(s)")
        }
        wirelessDiscovery.onStatus = {[weak self] message in self?.wirelessMessage=message;self?.log(message)}
        refresh();checkPermissions()
        deviceTimer=Timer.scheduledTimer(withTimeInterval:2,repeats:true){[weak self]_ in self?.refresh();self?.checkPermissions()}
        clipboardTimer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true){[weak self]_ in self?.pollClipboard()}
    }
    func log(_ text:String) {activities.insert(Activity(message:text),at:0);if activities.count>200 {activities.removeLast(activities.count-200)}}
    func report(_ text:String) {notice=text;log(text)}
    func refresh() {
        guard !refreshing else{return};refreshing=true
        work.async {[weak self] in guard let self=self else{return};let result=Result{try self.adb.run(["devices","-l"],timeout:4)}
            DispatchQueue.main.async {self.refreshing=false;switch result {
            case .success(let text):self.devices=Device.parse(text);if self.selected.isEmpty || !self.devices.contains(where:{$0.serial==self.selected}) {self.selected=self.devices.first(where:{$0.isReady})?.serial ?? self.devices.first?.serial ?? ""}
                if self.connected,let active=self.session?.device.serial,!self.devices.contains(where:{$0.serial==active && $0.isReady}) {self.disconnect(manual:false);self.report("Tablet disconnected. Mac input restored.")}
                if self.autoReconnect,!self.connected,!self.connecting,Date()>self.retryAfter,let serial=self.reconnectSerial,let d=self.devices.first(where:{$0.serial==serial && $0.isReady}) {self.connect(d)}
            case .failure(let error):if self.notice.isEmpty {self.report(error.localizedDescription)}
            }}
        }
    }
    func connectSelected() {guard let d=devices.first(where:{$0.serial==selected && $0.isReady}) else{report("Select an authorized tablet first.");return};connect(d)}
    func connect(_ device:Device) {
        guard !connecting,!connected else{return};connecting=true;notice="";deviceName=device.model;reconnectSerial=device.serial
        generation=UUID();let token=generation;lastPointer=nil
        let s=TabletSession(adb:adb,device:device);session=s
        pendingTakeover = !CommandLine.arguments.contains("--start-local")
        s.onSize = {[weak self] w,h,name in DispatchQueue.main.async {
            guard let self=self,self.generation==token else{return}
            if self.width != w || self.height != h {
                self.width=w;self.height=h;self.capture?.router.resize(width:Double(w),height:Double(h))
            }
            if !self.connected {
                self.deviceName=name;self.connected=true;self.connecting=false;self.capture?.router.connect()
                self.log("Connected to \(name) · physical tablet control · video disabled")
                self.createHID()
            }
            self.writeStatus()
        }}
        s.onPointer = {[weak self] position in DispatchQueue.main.async {
            guard let self=self,self.generation==token else{return}
            self.lastPointer=position;self.capture?.receivePointer(position)
            if CommandLine.arguments.contains("--self-test-corners") {print("Pointer \(position.x),\(position.y); remote=\(self.isRemote)")}
        }}
        s.onClipboard = {[weak self] text in DispatchQueue.main.async {guard let self=self,self.generation==token,self.clipboardSync else{return};NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string);self.pasteboardCount=NSPasteboard.general.changeCount}}
        s.onError = {[weak self] error in DispatchQueue.main.async {guard let self=self,self.generation==token else{return};self.disconnect(manual:false);self.report(error);self.retryAfter=Date().addingTimeInterval(4)}}
        s.onLog = {[weak self] text in DispatchQueue.main.async {guard let self=self,self.generation==token else{return}
            let lower=text.lowercased()
            if lower.contains("uhid") && (lower.contains("error") || lower.contains("failed") || lower.contains("could not")) {self.uhidAvailable=false;self.edgeEnabled=false;self.keyboardMode="text";self.report("This tablet could not create the mouse and keyboard needed for direct tablet control.")}
            if lower.contains("inject") && (lower.contains("exception") || lower.contains("permission")) {self.report("Android blocked input. Check the tablet’s USB debugging security setting, then reconnect.")}
            // Server output is intentionally omitted from diagnostics: it may contain third-party clipboard logs.
        }}
        s.start()
        work.async {[weak self] in guard let self=self else{return};let version=try? self.adb.device(device.serial,["shell","getprop","ro.build.version.release"],timeout:3)
            DispatchQueue.main.async {if self.generation==token {self.androidVersion=version?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""}}
        }
    }
    func disconnect(manual:Bool=true) {
        if manual {reconnectSerial=nil};capture?.leave();releaseKeys();capture?.router.disconnect();suspendPointer();session?.stop();session=nil;generation=UUID();connected=false;connecting=false;uhidAvailable=false;edgeEnabled=false
        pendingTakeover=false
        writeStatus()
    }
    func createHID() {
        resumePointer()
        send(Control.uhidCreate(id:2,name:"TabLink Keyboard",descriptor:HID.keyboard))
        let token=generation
        work.asyncAfter(deadline:.now()+0.5){[weak self] in
            guard let self=self,let serial=self.session?.device.serial else{return}
            let dump=try? self.adb.device(serial,["shell","dumpsys","input"],timeout:3)
            let ready=dump?.contains("TabLink Mouse")==true && dump?.contains("TabLink Keyboard")==true
            DispatchQueue.main.async {
                guard self.generation==token,self.connected else{return}
                self.uhidAvailable=ready
                if !ready {self.pendingTakeover=false;self.report("Android did not register the virtual mouse and keyboard. Reconnect the tablet.")}
                self.pointerVerified=ready
                if ready && self.accessibility {self.edgeEnabled=true}
                self.prepareControl()
            }
        }
    }
    func resumePointer() {
        guard !pointerAttached else{return};pointerAttached=true
        send(Control.uhidCreate(id:1,name:"TabLink Mouse",descriptor:HID.mouse))
    }
    func ensurePointerReady(_ completion:@escaping(Bool)->Void) {
        completion(pointerAttached && pointerVerified)
    }
    func suspendPointer() {
        pointerVerified=false
        guard pointerAttached else{return};pointerAttached=false
        send(Control.uhidDestroy(id:1))
    }
    func send(_ data:Data) {session?.send(data)}
    func androidKey(_ code:Int32) {send(Control.key(code,down:true));send(Control.key(code,down:false))}
    func androidModifiers(_ flags:NSEvent.ModifierFlags)->UInt32 {
        var m:UInt32=0;if flags.contains(.shift){m |= 1};if flags.contains(.option){m |= 2};if flags.contains(.control) || (commandToControl && flags.contains(.command)){m |= 0x1000};if !commandToControl && flags.contains(.command){m |= 0x10000};return m
    }
    private func modifiers(_ flags:NSEvent.ModifierFlags)->UInt8 {
        var m:UInt8=0;if flags.contains(.shift){m |= 2};if flags.contains(.option){m |= 4};if flags.contains(.control) || (commandToControl && flags.contains(.command)){m |= 1};if !commandToControl && flags.contains(.command){m |= 8};if flags.contains(.capsLock){ /* Android tracks its own Caps Lock LED. */ };return m
    }
    func physicalModifiers(_ flags:NSEvent.ModifierFlags) {
        guard connected,uhidAvailable else{return}
        let caps=flags.contains(.capsLock)
        if caps != lastCapsLock {
            lastCapsLock=caps
            send(Control.uhidInput(id:2,report:HID.keyboardReport(modifiers:modifiers(flags),keys:keys.union([57]))))
        }
        send(Control.uhidInput(id:2,report:HID.keyboardReport(modifiers:modifiers(flags),keys:keys)))
    }
    func physicalKey(_ event:NSEvent,down:Bool) {
        guard uhidAvailable else {injectKey(event,down:down);return}
        guard let usage=KeyMapper.hid[event.keyCode] else{return}
        if down {keys.insert(usage)}else{keys.remove(usage)}
        send(Control.uhidInput(id:2,report:HID.keyboardReport(modifiers:modifiers(event.modifierFlags),keys:keys)))
    }
    func injectKey(_ event:NSEvent,down:Bool) {
        guard let code=KeyMapper.androidCode(event.keyCode) else {if down,let s=event.characters,!s.isEmpty {pasteText(s)};return}
        if down {injected.insert(code)}else{injected.remove(code)}
        send(Control.key(code,down:down,meta:androidModifiers(event.modifierFlags)))
    }
    func releaseKeys() {
        keys=[];for code in injected {send(Control.key(code,down:false))};injected=[]
        if uhidAvailable {session?.releaseInput()}
    }
    func pasteText(_ text:String) {guard connected,!text.isEmpty else{return};sequence+=1;if let d=Control.clipboard(text,sequence:sequence,paste:true){send(d)}else{report("Text is too long. Transfer a file instead.")}}
    private func pollClipboard() {
        let count=NSPasteboard.general.changeCount;guard count != pasteboardCount else{return};pasteboardCount=count
        guard clipboardSync,connected,let text=NSPasteboard.general.string(forType:.string) else{return};sequence+=1;if let d=Control.clipboard(text,sequence:sequence,paste:false){send(d)}
    }
    func checkPermissions() {
        accessibility=AXIsProcessTrusted()
        // Accessibility authorizes both event listening and posting. A separate
        // ListenEvent grant is not required for our active event tap.
        inputMonitoring=accessibility || CGPreflightListenEventAccess()
        if accessibility {_ = capture?.install();prepareControl()}
        if !accessibility {edgeEnabled=false}
    }
    func requestPermission(_ accessibilityPane:Bool) {
        if accessibilityPane {let opts=[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary;_ = AXIsProcessTrustedWithOptions(opts)}else{_ = CGRequestListenEventAccess()}
        let pane=accessibilityPane ? "Privacy_Accessibility":"Privacy_ListenEvent"
        if let u=URL(string:"x-apple.systempreferences:com.apple.preference.security?\(pane)"){NSWorkspace.shared.open(u)}
    }
    func connectOverWiFi() {
        guard !wirelessSearching else{return}
        capture?.leave();wirelessDiscovery.start();wirelessSearching=true;needsWirelessPairing=false
        wirelessMessage="Looking for your tablet on Wi-Fi…"
        let token=UUID();wirelessAttempt=token
        let usb=devices.first(where:{$0.isReady && !$0.isWireless})
        work.async {[weak self] in
            guard let self=self else{return}
            if let usb=usb {
                // Use the already authorized USB connection to open Android's TLS debugging setup.
                _ = try? self.adb.device(usb.serial,["shell","settings","put","global","adb_wifi_enabled","1"],timeout:3)
                let opened=try? self.adb.device(usb.serial,["shell","am","start","-a","android.settings.WIRELESS_DEBUGGING_SETTINGS"],timeout:3)
                if opened==nil || opened?.contains("Error")==true {
                    _ = try? self.adb.device(usb.serial,["shell",#"am start -n com.android.settings/.SubSettings --es ':settings:show_fragment' com.android.settings.development.WirelessDebuggingFragment"#],timeout:3)
                }
            }
            self.lookForWireless(token:token,usb:usb)
        }
    }
    private func lookForWireless(token:UUID,usb:Device?) {
        for _ in 0..<12 {
            let existing=(try? adb.run(["devices","-l"],timeout:3)).map(Device.parse) ?? []
            if let connected=existing.first(where:{$0.isReady && $0.isWireless}) {
                finishWireless(connected,token:token);return
            }
            let text=(try? adb.run(["mdns","services"],timeout:3)) ?? ""
            var services=WirelessService.parse(text)
            if let cached=UserDefaults.standard.string(forKey:"lastWirelessEndpoint"),(try? Endpoint(cached)) != nil {services.append(WirelessService(name:"Your paired tablet",endpoint:cached,pairing:false))}
            DispatchQueue.main.sync {services += self.bonjourServices}
            if let usb=usb,
               let ip=(try? adb.device(usb.serial,["shell",#"ip -4 route get 1.1.1.1 | sed -n 's/.* src \([0-9.]*\).*/\1/p'"#],timeout:2))?.trimmingCharacters(in:.whitespacesAndNewlines),
               let port=(try? adb.device(usb.serial,["shell","getprop","service.adb.tls.port"],timeout:2))?.trimmingCharacters(in:.whitespacesAndNewlines),
               let n=UInt16(port),n>0,(try? Endpoint("\(ip):\(n)")) != nil {
                services.append(WirelessService(name:usb.model,endpoint:"\(ip):\(n)",pairing:false))
            }
            let unique=Dictionary(services.map{($0.id,$0)},uniquingKeysWith:{$1}).values.sorted{$0.name<$1.name}
            DispatchQueue.main.async {if self.wirelessAttempt==token {self.wirelessServices=unique}}
            for service in unique where !service.pairing {
                if let response=try? adb.run(["connect",service.endpoint],timeout:3),
                   response.lowercased().contains("connected to") && !response.lowercased().contains("failed") {
                    let all=(try? adb.run(["devices","-l"],timeout:3)).map(Device.parse) ?? []
                    if let device=all.first(where:{$0.isReady && $0.isWireless}) {finishWireless(device,token:token);return}
                }
            }
            if unique.contains(where:{$0.pairing}) {
                DispatchQueue.main.async {if self.wirelessAttempt==token {self.wirelessSearching=false;self.needsWirelessPairing=true;self.wirelessMessage="Enter the one-time code displayed on your tablet. Addresses and ports are handled automatically."}};return
            }
            Thread.sleep(forTimeInterval:0.5)
        }
        DispatchQueue.main.async {
            guard self.wirelessAttempt==token else{return}
            self.wirelessSearching=false
            self.wirelessMessage=usb == nil ? "Enable Wireless debugging on your tablet, then tap Connect over Wi-Fi again. For first setup, connect USB or choose Pair with pairing code on the tablet.":"On the tablet, allow Wireless debugging for this Wi-Fi network. If Android asks to pair, choose Pair with pairing code, then tap Connect over Wi-Fi again."
        }
    }
    func pairWireless(code:String) {
        guard code.count==6,code.allSatisfy({$0.isASCII && $0.isNumber}),let target=wirelessServices.first(where:{$0.pairing}) else{wirelessMessage="Choose Pair with pairing code on the tablet, then search again.";return}
        wirelessSearching=true;let token=UUID();wirelessAttempt=token
        work.async {[weak self] in
            guard let self=self else{return}
            do {
                let response=try self.adb.run(["pair",target.endpoint,code],timeout:15)
                guard response.lowercased().contains("successfully paired") else{throw AppError("Pairing was not accepted. Generate a new code on the tablet and retry.")}
                DispatchQueue.main.async {self.needsWirelessPairing=false;self.wirelessMessage="Paired. Connecting automatically…"}
                self.lookForWireless(token:token,usb:nil)
            }catch{DispatchQueue.main.async {self.wirelessSearching=false;self.wirelessMessage=error.localizedDescription}}
        }
    }
    private func finishWireless(_ device:Device,token:UUID) {
        DispatchQueue.main.async {
            guard self.wirelessAttempt==token else{return}
            self.wirelessSearching=false;self.needsWirelessPairing=false
            if device.serial.contains(":"),(try? Endpoint(device.serial)) != nil {UserDefaults.standard.set(device.serial,forKey:"lastWirelessEndpoint")}
            self.wirelessMessage="Connected over Wi-Fi. You can unplug the USB cable."
            self.disconnect();self.devices.removeAll(where:{$0.serial==device.serial});self.devices.append(device)
            self.selected=device.serial;self.connect(device)
        }
    }
    func chooseFiles() {let panel=NSOpenPanel();panel.allowsMultipleSelection=true;panel.canChooseDirectories=true;panel.prompt="Send to tablet";if panel.runModal() == .OK{transfer(panel.urls)}}
    func transfer(_ urls:[URL]) {
        guard connected,let serial=session?.device.serial,!busy else{return}
        var plans:[(URL,Bool)]=[]
        for url in urls {
            var install=false
            if url.pathExtension.lowercased()=="apk" {
                let alert=NSAlert();alert.messageText="Install \(url.lastPathComponent)?";alert.informativeText="Install this Android app on your tablet, or copy the APK to Downloads.";alert.addButton(withTitle:"Copy to Downloads");alert.addButton(withTitle:"Install app");alert.addButton(withTitle:"Cancel")
                let response=alert.runModal();if response == .alertThirdButtonReturn{return};install=response == .alertSecondButtonReturn
            }
            plans.append((url,install))
        }
        busy=true;transferStatus="Sending \(plans.count) item(s)…"
        work.async {[weak self] in guard let self=self else{return}
            let result=Result {
                for (url,install) in plans {
                    DispatchQueue.main.async {self.transferStatus="\(install ? "Installing":"Sending") \(url.lastPathComponent)…"}
                    if install {try self.adb.device(serial,["install","-r",url.path],timeout:180)}
                    else {try self.adb.device(serial,["push",url.path,"/sdcard/Download/"],timeout:180)}
                }
            }
            DispatchQueue.main.async {self.busy=false;switch result {case .success:self.transferStatus="Transfer completed. Files are in Downloads; selected apps are installed.";self.log("File transfer completed (\(plans.count) items)");case .failure(let e):self.transferStatus="Transfer stopped; earlier items may have completed.";self.report(e.localizedDescription)}}
        }
    }
    func exportDiagnostics() {
        let panel=NSSavePanel();panel.nameFieldStringValue="TabLink-diagnostics.txt";guard panel.runModal() == .OK,let url=panel.url else{return}
        let rows=activities.map{"\($0.time.formatted()): \($0.message)"}.joined(separator:"\n")
        let text="TabLink development build 1.4\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nAndroid: \(androidVersion)\nDevice: \(deviceName)\nResolution: \(width)x\(height)\nAccessibility: \(accessibility)\nInput Monitoring: \(inputMonitoring)\nConnected: \(connected)\n\nNo clipboard contents or server output are included.\n\n\(rows)\n"
        do{try text.write(to:url,atomically:true,encoding:.utf8);report("Diagnostics exported.")}catch{report(error.localizedDescription)}
    }
    func controlTablet() {
        pendingTakeover=true;prepareControl()
        if !accessibility {report("Enable TabLink under Device Control and Data Access (Accessibility) to send your keyboard and trackpad to the tablet.")}
    }
    private func prepareControl() {
        guard pendingTakeover,connected,uhidAvailable,accessibility,capture?.install()==true else{return}
        pendingTakeover=false;edgeEnabled=true;capture?.takeControl()
    }
    private func writeStatus() {
        guard let i=CommandLine.arguments.firstIndex(of:"--status-file"),CommandLine.arguments.count>i+1 else{return}
        let state:[String:Any]=["connected":connected,"remote":isRemote,"accessibility":accessibility,"inputMonitoring":inputMonitoring,"hidReady":uhidAvailable,"eventTapInstalled":capture?.isInstalled ?? false,"videoEnabled":false,"mirrorWindows":NSApp.windows.filter{$0.contentView is MirrorView}.count,"pointerFeedback":lastPointer != nil,"pointerX":lastPointer?.x ?? -1,"pointerY":lastPointer?.y ?? -1,"width":width,"height":height,"wirelessSearching":wirelessSearching,"wirelessServices":wirelessServices.count,"wirelessMessage":wirelessMessage,"activeTransport":session?.device.isWireless == true ? "Wi-Fi":"USB","tabletMouseRegistered":pointerAttached,"tabletInputActive":isRemote,"macCursorHiddenByTabLink":capture?.hidesMacCursor ?? false,"applicationActive":NSApp.isActive,"lastReturnReason":capture?.lastReturnReason ?? "","notice":notice]
        if let data=try? JSONSerialization.data(withJSONObject:state,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:URL(fileURLWithPath:CommandLine.arguments[i+1]),options:.atomic)}
    }
    func shutdown() {disconnect();capture?.stop();deviceTimer?.invalidate();clipboardTimer?.invalidate()}
}
