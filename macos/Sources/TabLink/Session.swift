import AppKit
import TabLinkCore
final class TabletSession {
    let adb: ADB;let device: Device
    private let queue=DispatchQueue(label:"app.tablink.control",qos:.userInteractive)
    private let heartbeatQueue=DispatchQueue(label:"app.tablink.heartbeat",qos:.userInteractive)
    private var control:SocketChannel?;private var server:Process?
    private var ready=false
    private var pointerTimer:DispatchSourceTimer?;private var trackingPointer=false
    private let pointerQueue=DispatchQueue(label:"app.tablink.pointer",qos:.userInteractive)
    private var heartbeat:DispatchSourceTimer?;private var port:String?;private var stopped=false
    private let stateLock=NSLock()
    let scid=String(format:"%08x",UInt32.random(in:1...0x7fffffff))
    var onPointer:((TabletPointerPosition)->Void)?
    var onSize:((Int,Int,String)->Void)?;var onError:((String)->Void)?;var onClipboard:((String)->Void)?;var onLog:((String)->Void)?
    init(adb:ADB,device:Device) {self.adb=adb;self.device=device}
    var isStopped:Bool {stateLock.lock();defer{stateLock.unlock()};return stopped}
    func start() {
        DispatchQueue.global(qos:.userInitiated).async { [self] in
            defer {
                if isStopped {
                    if server?.isRunning == true {server?.terminate()}
                    if let p=port {_ = try? adb.device(device.serial,["forward","--remove","tcp:\(p)"],timeout:2)}
                }
            }
            do {
                guard !isStopped else{return}
                guard let jar=Bundle.main.resourceURL?.appendingPathComponent("scrcpy-server.jar") else {throw AppError("Android server is missing.")}
                let remote="/data/local/tmp/tablink-\(scid).jar"
                try adb.device(device.serial,["push",jar.path,remote])
                guard !isStopped else{_ = try? adb.device(device.serial,["shell","rm","-f",remote],timeout:2);return}
                let portText=try adb.device(device.serial,["forward","tcp:0","localabstract:scrcpy_\(scid)"]).trimmingCharacters(in:.whitespacesAndNewlines)
                guard let localPort=UInt16(portText) else {throw AppError("ADB did not allocate a local port.")};port=portText
                let marker="/data/local/tmp/tablink-\(scid).alive"
                let options="3.3.4 scid=\(scid) audio=false video=false tunnel_forward=true clipboard_autosync=true power_on=true cleanup=true"
                // Independent Android shell watchdog: kill this server if host pulses stop for 3s.
                let command="touch \(marker); CLASSPATH=\(remote) app_process / com.genymobile.scrcpy.Server \(options) & child=$!; (while kill -0 $child 2>/dev/null; do sleep 1; now=$(date +%s); stamp=$(stat -c %Y \(marker) 2>/dev/null || echo 0); if [ $((now-stamp)) -ge 3 ]; then kill $child; break; fi; done) & guardpid=$!; trap 'kill $child $guardpid 2>/dev/null; rm -f \(marker) \(remote)' EXIT HUP INT TERM; wait $child"
                let p=adb.process(["-s",device.serial,"shell",command]);let log=Pipe();p.standardOutput=log;p.standardError=log
                log.fileHandleForReading.readabilityHandler = { [weak self] h in let d=h.availableData;if !d.isEmpty {self?.onLog?(String(decoding:d,as:UTF8.self))} }
                server=p;guard !isStopped else{return};try p.run();guard !isStopped else{p.terminate();return};startHeartbeat(marker:marker)
                var v:SocketChannel?;let deadline=Date().addingTimeInterval(9)
                while Date()<deadline && !isStopped {
                    do {let candidate=try SocketChannel(port:localPort);let dummy=try candidate.read(1);if dummy==Data([0]) {v=candidate;break};candidate.close()} catch {Thread.sleep(forTimeInterval:0.12)}
                }
                guard let v=v,!isStopped else {throw AppError("Could not start the tablet server. Check Android 11+, USB authorization, and try reconnecting.")}
                // With video and audio disabled the first and only socket is CONTROL.
                let c=v;control=c
                let header=try c.read(64)
                let name=String(decoding:header.prefix(64).prefix(while:{$0 != 0}),as:UTF8.self)
                let viewport=try adb.device(device.serial,["shell","dumpsys","input"],timeout:3)
                guard let display=TabletDisplay.parse(viewport) else{throw AppError("Could not read the tablet’s screen dimensions.")}
                ready=true
                startPointerFeedback()
                onSize?(display.width,display.height,name)
                readControl(c)
            } catch { fail(error.localizedDescription) }
        }
    }
    private func startHeartbeat(marker:String) {
        let t=DispatchSource.makeTimerSource(queue:heartbeatQueue);t.schedule(deadline:.now(),repeating:1)
        t.setEventHandler { [weak self] in guard let self=self,!self.isStopped else{return};do {let output=try self.adb.device(self.device.serial,["shell","touch \(marker); dumpsys input | grep 'Viewport INTERNAL:' | head -1"],timeout:0.8);if self.ready,let display=TabletDisplay.parse(output) {self.onSize?(display.width,display.height,self.device.model)}} catch {self.fail("Heartbeat lost. Mac control has been restored.")} };heartbeat=t;t.resume()
    }
    func trackPointer(_ enabled:Bool){stateLock.lock();trackingPointer=enabled;stateLock.unlock()}
    private var shouldTrackPointer:Bool {stateLock.lock();defer{stateLock.unlock()};return trackingPointer && !stopped}
    private func startPointerFeedback() {
        let timer=DispatchSource.makeTimerSource(queue:pointerQueue)
        timer.schedule(deadline:.now(),repeating:0.15)
        timer.setEventHandler {[weak self] in
            guard let self=self,self.shouldTrackPointer else{return}
            // Read only compositor metadata for the system cursor sprite; no screen capture.
            if let text=try? self.adb.device(self.device.serial,["shell","dumpsys SurfaceFlinger | grep -A 5 -E '^\\+ .*Layer \\((Sprite|Pointer|Cursor)'"],timeout:0.7),
               let position=TabletPointerPosition.parse(text) {self.onPointer?(position)}
        }
        pointerTimer=timer;timer.resume()
    }
    private func readControl(_ c:SocketChannel) {
        do {while !isStopped {let type=try c.read(1)[0];switch type {
        case 0:let n=Int(try c.read(4).uint(0,4));guard n<=262144 else{throw AppError("Invalid clipboard packet.")};onClipboard?(String(decoding:try c.read(n),as:UTF8.self))
        case 1:_ = try c.read(8)
        case 2:let h=try c.read(4);_ = try c.read(Int(h.uint(2,2)))
        default:throw AppError("Unexpected server control message.")
        }}} catch {fail(error.localizedDescription)}
    }
    func send(_ data:Data) {queue.async { [weak self] in guard let self=self,!self.isStopped else{return};do {try self.control?.send(data)}catch{self.fail(error.localizedDescription)} }}
    func releaseInput() {
        send(Control.uhidInput(id:1,report:HID.mouseReport()))
        send(Control.uhidInput(id:2,report:HID.keyboardReport(modifiers:0,keys:[])))
    }
    private func fail(_ reason:String) {guard !isStopped else{return};stop();onError?(reason)}
    func stop() {
        stateLock.lock();if stopped {stateLock.unlock();return};stopped=true;stateLock.unlock()
        heartbeat?.cancel();heartbeat=nil;pointerTimer?.cancel();pointerTimer=nil
        control?.close();if server?.isRunning == true {server?.terminate()}
        let p=port, a=adb, s=device.serial
        DispatchQueue.global().async {if let p=p {_ = try? a.device(s,["forward","--remove","tcp:\(p)"],timeout:2)}}
    }
    deinit {stop()}
}
