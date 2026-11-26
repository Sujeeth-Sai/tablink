import Foundation
public extension Data {
    mutating func put<T: FixedWidthInteger>(_ value: T) { var v = value.bigEndian; Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) } }
    func uint(_ offset: Int, _ count: Int) -> UInt64 { self[offset..<(offset+count)].reduce(0) { ($0 << 8) | UInt64($1) } }
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
/// Wire-compatible with the pinned scrcpy 3.3.4 server. See protocol/PROTOCOL.md.
public enum Control {
    public static func key(_ code: Int32, down: Bool, meta: UInt32 = 0, repeatCount: UInt32 = 0) -> Data {
        var d = Data([0, down ? 0 : 1]); d.put(code); d.put(repeatCount); d.put(meta); return d
    }
    public static func text(_ text: String) -> Data? {
        let bytes = Data(text.utf8); guard bytes.count <= 300 else { return nil }
        var d = Data([1]); d.put(UInt32(bytes.count)); d.append(bytes); return d
    }
    public static func touch(action: UInt8, x: Int32, y: Int32, width: UInt16, height: UInt16, buttons: UInt32 = 1, pointer: UInt64 = UInt64.max, pressure: UInt16? = nil) -> Data {
        var d = Data([2,action]); d.put(pointer); d.put(x); d.put(y); d.put(width); d.put(height)
        d.put(pressure ?? (action == 1 ? UInt16(0) : UInt16.max)); d.put(buttons); d.put(action == 1 ? UInt32(0) : buttons); return d
    }
    public static func scroll(x: Int32, y: Int32, width: UInt16, height: UInt16, horizontal: Double, vertical: Double) -> Data {
        var d = Data([3]); d.put(x); d.put(y); d.put(width); d.put(height)
        d.put(Int16(clamping: Int((max(-16,min(15.999,horizontal))*2048).rounded())))
        d.put(Int16(clamping: Int((max(-16,min(15.999,vertical))*2048).rounded()))); d.put(UInt32(0)); return d
    }
    public static func clipboard(_ text: String, sequence: UInt64, paste: Bool) -> Data? {
        let b=Data(text.utf8); guard b.count <= 262130 else { return nil }
        var d=Data([9]); d.put(sequence); d.append(paste ? 1 : 0); d.put(UInt32(b.count)); d.append(b); return d
    }
    public static func uhidCreate(id: UInt16, name: String, descriptor: Data) -> Data {
        let n=Data(name.utf8.prefix(127)); var d=Data([12]); d.put(id); d.put(UInt16(0)); d.put(UInt16(0)); d.append(UInt8(n.count)); d.append(n); d.put(UInt16(descriptor.count)); d.append(descriptor); return d
    }
    public static func uhidInput(id: UInt16, report: Data) -> Data { var d=Data([13]); d.put(id); d.put(UInt16(report.count)); d.append(report); return d }
    public static func uhidDestroy(id: UInt16) -> Data { var d=Data([14]); d.put(id); return d }
}
public enum HID {
    // Original descriptor: 3 buttons, signed 16-bit relative axes, wheel and AC pan.
    public static let mouse = Data([0x05,0x01,0x09,0x02,0xa1,0x01,0x09,0x01,0xa1,0x00,0x05,0x09,0x19,0x01,0x29,0x03,0x15,0x00,0x25,0x01,0x95,0x03,0x75,0x01,0x81,0x02,0x95,0x01,0x75,0x05,0x81,0x03,0x05,0x01,0x09,0x30,0x09,0x31,0x16,0x00,0x80,0x26,0xff,0x7f,0x75,0x10,0x95,0x02,0x81,0x06,0x09,0x38,0x15,0x81,0x25,0x7f,0x75,0x08,0x95,0x01,0x81,0x06,0x05,0x0c,0x0a,0x38,0x02,0x95,0x01,0x81,0x06,0xc0,0xc0])
    public static let keyboard = Data([0x05,0x01,0x09,0x06,0xa1,0x01,0x05,0x07,0x19,0xe0,0x29,0xe7,0x15,0x00,0x25,0x01,0x75,0x01,0x95,0x08,0x81,0x02,0x95,0x01,0x75,0x08,0x81,0x03,0x95,0x05,0x75,0x01,0x05,0x08,0x19,0x01,0x29,0x05,0x91,0x02,0x95,0x01,0x75,0x03,0x91,0x03,0x95,0x06,0x75,0x08,0x15,0x00,0x25,0x65,0x05,0x07,0x19,0x00,0x29,0x65,0x81,0x00,0xc0])
    public static func mouseReport(buttons: UInt8=0, dx: Int=0, dy: Int=0, wheel: Int=0, pan: Int=0) -> Data {
        let x=UInt16(bitPattern:Int16(clamping:dx)), y=UInt16(bitPattern:Int16(clamping:dy))
        return Data([buttons,UInt8(truncatingIfNeeded:x),UInt8(x>>8),UInt8(truncatingIfNeeded:y),UInt8(y>>8),UInt8(bitPattern:Int8(clamping:wheel)),UInt8(bitPattern:Int8(clamping:pan))])
    }
    public static func keyboardReport(modifiers: UInt8, keys: Set<UInt8>) -> Data { Data([modifiers,0] + Array(keys.sorted().prefix(6)) + Array(repeating:0,count:max(0,6-keys.count))) }
}
public struct VideoPacketHeader {
    public let config: Bool; public let keyframe: Bool; public let pts: UInt64; public let size: Int
    public init?(_ data: Data) {
        guard data.count==12 else { return nil }; let f=data.uint(0,8)
        config=f & (1<<63) != 0; keyframe=f & (1<<62) != 0; pts=f & 0x3fffffffffffffff; size=Int(data.uint(8,4))
        guard size>0 && size<=32*1024*1024 else { return nil }
    }
}
public enum AnnexB {
    public static func units(_ data: Data) -> [Data] {
        let a=[UInt8](data); var starts:[(Int,Int)]=[]; var i=0
        while i+2<a.count {
            if a[i]==0 && a[i+1]==0 {
                if a[i+2]==1 { starts.append((i,3)); i+=3; continue }
                if i+3<a.count && a[i+2]==0 && a[i+3]==1 { starts.append((i,4)); i+=4; continue }
            }; i+=1
        }
        return starts.enumerated().compactMap { j,s in let end=j+1<starts.count ? starts[j+1].0:a.count; let begin=s.0+s.1; return begin<end ? Data(a[begin..<end]):nil }
    }
}
