import Foundation
public struct TabletPointerPosition:Equatable {
    public let x:Double;public let y:Double
    public init(x:Double,y:Double){self.x=x;self.y=y}
    /// SurfaceFlinger sprite metadata, never screen pixels or captured video.
    public static func parse(_ text:String)->Self? {
        let lines=text.components(separatedBy:.newlines)
        let re=try? NSRegularExpression(pattern:#"pos=\(\s*(-?[\d.]+),\s*(-?[\d.]+)\)"#)
        var result:Self?
        for (index,line) in lines.enumerated() where line.contains("(Sprite") || line.contains("(Pointer") || line.contains("(Cursor") {
            for next in lines.dropFirst(index+1).prefix(8) {
                if next.hasPrefix("+") || next=="--" {break}
                guard let re=re,let m=re.firstMatch(in:next,range:NSRange(next.startIndex...,in:next)) else{continue}
                let ns=next as NSString
                if let x=Double(ns.substring(with:m.range(at:1))),let y=Double(ns.substring(with:m.range(at:2))),x.isFinite,y.isFinite {
                    result=Self(x:x,y:y)
                }
                break
            }
        }
        return result
    }
}
public struct CornerReturn {
    private var corner:Int?
    private var since:Double?
    public var dwell:Double=0.18
    public var margin:Double=16
    public init(){}
    public mutating func reset(){corner=nil;since=nil}
    public mutating func observe(_ position:TabletPointerPosition,width:Double,height:Double,now:Double)->Bool {
        let horizontal:Int? = position.x<=margin ? 0:position.x>=width-margin ? 1:nil
        let vertical:Int? = position.y<=margin ? 0:position.y>=height-margin ? 1:nil
        guard width>margin*2,height>margin*2,let h=horizontal,let v=vertical else{reset();return false}
        let next=h*2+v
        if next != corner {corner=next;since=now;return false}
        return now-(since ?? now)>=dwell
    }
}

/// Return across the tablet side adjoining the Mac after an outward push.
/// A fresh physical position must confirm the boundary; integrated deltas alone
/// never determine the tablet's cursor location.
public struct EdgeReturn {
    private var pushed=0.0
    private var lastPush = -Double.infinity
    public var margin=16.0
    public var threshold=18.0
    public init(){}
    public mutating func reset(){pushed=0;lastPush = -Double.infinity}
    public mutating func motion(dx:Double,dy:Double,edge:Edge,now:Double) {
        let outward:Double
        switch edge {case .right:outward = -dx;case .left:outward=dx;case .top:outward=dy;case .bottom:outward = -dy}
        if outward>0 {if now-lastPush>0.35 {pushed=0};pushed+=outward;lastPush=now}
        else if outward<0 {reset()}
    }
    public mutating func observe(_ p:TabletPointerPosition,width:Double,height:Double,edge:Edge,now:Double)->Bool {
        let boundary:Bool
        switch edge {case .right:boundary=p.x<=margin;case .left:boundary=p.x>=width-margin;case .top:boundary=p.y>=height-margin;case .bottom:boundary=p.y<=margin}
        guard boundary,now-lastPush<0.35 else{pushed=0;return false}
        return pushed>=threshold
    }
}
