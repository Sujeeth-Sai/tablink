import Foundation
public enum Edge: String, CaseIterable, Sendable { case left, right, top, bottom }
public enum RouteState: Equatable { case disconnected, local, remote }
/// Pure state machine. Coordinates are normalized with origin at the top left.
public struct InputRouter {
    public private(set) var state: RouteState = .disconnected
    public private(set) var x: Double = 0
    public private(set) var y: Double = 0
    private var pinnedSince: Double?
    public var edge: Edge = .right
    public var dwell: Double = 0.15
    public var width: Double = 1920
    public var height: Double = 1080
    public var overshoot: Double = 40
    public var automaticReturn=true
    public var returnAtAnyEdge=false
    public init() {}
    public var passesLocalEvents: Bool { state != .remote }
    public mutating func connect() { state = .local; pinnedSince=nil }
    public mutating func disconnect() { state = .disconnected; pinnedSince=nil }
    public mutating func leave() { if state != .disconnected { state = .local }; pinnedSince=nil }
    @discardableResult public mutating func observe(atEdge: Bool, proportion: Double, now: Double) -> Bool {
        guard state == .local, atEdge else { pinnedSince=nil; return false }
        if pinnedSince==nil { pinnedSince=now }
        guard now-(pinnedSince ?? now) >= dwell else { return false }
        enter(proportion: proportion); return true
    }
    public mutating func enter(proportion: Double) {
        guard state == .local else { return }
        let p=max(0,min(1,proportion))
        switch edge { case .right: x=0;y=p*height; case .left:x=width;y=p*height;case .top:x=p*width;y=height;case .bottom:x=p*width;y=0 }
        state = .remote; pinnedSince=nil
    }
    public mutating func synchronize(x newX:Double,y newY:Double){x=max(0,min(width,newX));y=max(0,min(height,newY))}
    public mutating func resize(width newWidth:Double,height newHeight:Double) {
        let px=max(0,min(1,x/max(1,width))),py=max(0,min(1,y/max(1,height)))
        width=max(1,newWidth);height=max(1,newHeight);x=px*width;y=py*height
    }
    public mutating func enterAtCenter() {guard state == .local else{return};state = .remote;x=width/2;y=height/2;pinnedSince=nil}
    @discardableResult public mutating func move(dx: Double, dy: Double) -> Bool {
        guard state == .remote else { return false }
        x+=dx; y+=dy
        let exit: Bool
        switch edge {case .right:exit=x < -overshoot;case .left:exit=x > width+overshoot;case .top:exit=y > height+overshoot;case .bottom:exit=y < -overshoot}
        let anyExit=x < -overshoot || y < -overshoot || x > width+overshoot || y > height+overshoot
        if automaticReturn && (returnAtAnyEdge ? anyExit:exit) { leave(); return true }
        if !automaticReturn {x=max(0,min(width,x));y=max(0,min(height,y));return false}
        if returnAtAnyEdge {return false}
        switch edge { case .right:x=min(width,x);y=max(0,min(height,y));case .left:x=max(0,x);y=max(0,min(height,y));case .top:y=max(0,y);x=max(0,min(width,x));case .bottom:y=min(height,y);x=max(0,min(width,x)) }
        return false
    }
}
public enum KeyMapper {
    // macOS ANSI virtual key positions to USB HID usages; independent of keyboard layout.
    public static let hid: [UInt16:UInt8] = [0:4,1:22,2:7,3:9,4:11,5:10,6:29,7:27,8:6,9:25,11:5,12:20,13:26,14:8,15:21,16:28,17:23,18:30,19:31,20:32,21:33,22:35,23:34,24:46,25:38,26:36,27:45,28:37,29:39,30:48,31:18,32:24,33:47,34:12,35:19,36:40,37:15,38:13,39:52,40:14,41:51,42:49,43:54,44:56,45:17,46:16,47:55,48:43,49:44,50:53,51:42,53:41,57:57,65:99,67:85,69:87,71:83,75:84,76:88,78:86,81:103,82:98,83:89,84:90,85:91,86:92,87:93,88:94,89:95,91:96,92:97,96:62,97:63,98:64,99:60,100:65,101:66,103:68,109:67,111:69,115:74,116:75,117:76,118:61,119:77,120:59,121:78,122:58,123:80,124:79,125:81,126:82]
    public static let android: [UInt16:Int32] = [36:66,48:61,49:62,51:67,53:111,57:115,115:122,116:92,117:112,119:123,121:93,123:21,124:22,125:20,126:19]
    public static func androidCode(_ mac: UInt16) -> Int32? {
        if let code=android[mac] { return code }
        guard let usage=hid[mac] else { return nil }
        if (4...29).contains(usage) { return Int32(usage)-4+29 }
        if (30...38).contains(usage) { return Int32(usage)-30+8 }
        if usage==39 { return 7 }; return nil
    }
}
