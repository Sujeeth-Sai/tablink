import Foundation
/// Reads the active tablet viewport without capturing or encoding its screen.
public struct TabletDisplay: Equatable {
    public let width:Int
    public let height:Int
    public static func parse(_ text:String)->TabletDisplay? {
        let pattern = #"Viewport INTERNAL:[^\n]*displayId=0[^\n]*logicalFrame=\[\s*(-?\d+),\s*(-?\d+),\s*(\d+),\s*(\d+)\]"#
        guard let re=try? NSRegularExpression(pattern:pattern),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else{return nil}
        let ns=text as NSString
        guard let left=Int(ns.substring(with:m.range(at:1))),let top=Int(ns.substring(with:m.range(at:2))),let right=Int(ns.substring(with:m.range(at:3))),let bottom=Int(ns.substring(with:m.range(at:4))),right>left,bottom>top else{return nil}
        return TabletDisplay(width:right-left,height:bottom-top)
    }
}
