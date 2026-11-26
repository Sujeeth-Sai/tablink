import AppKit
import TabLinkCore
struct AppError: LocalizedError { let message: String; var errorDescription: String? { message }; init(_ message: String) { self.message=message } }
final class ADB {
    let path: String
    init() { path = Bundle.main.resourceURL!.appendingPathComponent("adb").path }
    func process(_ args: [String]) -> Process { let p=Process();p.executableURL=URL(fileURLWithPath:path);p.arguments=args;return p }
    @discardableResult func run(_ args: [String], timeout: Double=15) throws -> String {
        let p=process(args), pipe=Pipe();p.standardOutput=pipe;p.standardError=pipe
        // Drain while the child runs, including large adb diagnostics, without a pipe-buffer deadlock.
        let lock=NSLock();var bytes=Data()
        pipe.fileHandleForReading.readabilityHandler = { h in let d=h.availableData;lock.lock();bytes.append(d);lock.unlock() }
        try p.run()
        let deadline=Date().addingTimeInterval(timeout)
        while p.isRunning && Date()<deadline { Thread.sleep(forTimeInterval:0.03) }
        if p.isRunning { p.terminate();Thread.sleep(forTimeInterval:0.1);if p.isRunning { kill(p.processIdentifier,SIGKILL) };p.waitUntilExit();pipe.fileHandleForReading.readabilityHandler=nil;throw AppError("ADB timed out. Check the cable, Wi-Fi connection, and the tablet’s authorization prompt.") }
        p.waitUntilExit();pipe.fileHandleForReading.readabilityHandler=nil
        let tail=pipe.fileHandleForReading.readDataToEndOfFile();lock.lock();bytes.append(tail);let result=String(decoding:bytes,as:UTF8.self);lock.unlock()
        guard p.terminationStatus==0 else { throw AppError(result.trimmingCharacters(in:.whitespacesAndNewlines)) };return result
    }
    @discardableResult func device(_ serial: String, _ args: [String], timeout: Double=15) throws -> String { try run(["-s",serial]+args,timeout:timeout) }
}
final class SocketChannel {
    private let lock=NSLock();private var fd: Int32
    init(port: UInt16) throws {
        fd=socket(AF_INET,SOCK_STREAM,0);guard fd>=0 else { throw AppError("Could not open local connection.") }
        var one:Int32=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&one,socklen_t(MemoryLayout.size(ofValue:one)))
        var timeout=timeval(tv_sec:2,tv_usec:0);setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout.size(ofValue:timeout)))
        var address=sockaddr_in();address.sin_len=UInt8(MemoryLayout<sockaddr_in>.size);address.sin_family=sa_family_t(AF_INET);address.sin_port=port.bigEndian;address.sin_addr.s_addr=inet_addr("127.0.0.1")
        let ok=withUnsafePointer(to:&address) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard ok==0 else { Darwin.close(fd);fd = -1;throw AppError("Tablet server is not ready.") }
    }
    func read(_ count: Int) throws -> Data {
        guard count>=0 && count<=32*1024*1024 else { throw AppError("Invalid packet size.") }
        var data=Data(count:count);var offset=0
        try data.withUnsafeMutableBytes { raw in
            while offset<count { let n=recv(fd,raw.baseAddress!.advanced(by:offset),count-offset,0);if n<=0 { throw AppError("The tablet disconnected.") };offset+=n }
        };return data
    }
    func send(_ data: Data) throws {
        lock.lock();defer { lock.unlock() };guard fd>=0 else { throw AppError("Disconnected") }
        try data.withUnsafeBytes { raw in var offset=0;while offset<data.count { let n=Darwin.send(fd,raw.baseAddress!.advanced(by:offset),data.count-offset,0);if n<=0 { throw AppError("Control connection lost.") };offset+=n } }
    }
    func close() { if fd>=0 {shutdown(fd,SHUT_RDWR)};lock.lock();defer {lock.unlock()};if fd>=0 {Darwin.close(fd);fd = -1} }
    deinit { close() }
}
