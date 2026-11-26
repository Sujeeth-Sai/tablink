import Foundation
public struct WirelessService:Identifiable,Equatable,Sendable {
    public let name:String
    public let endpoint:String
    public let pairing:Bool
    public var id:String {name+(pairing ? ":pair":":connect")}
    public init(name:String,endpoint:String,pairing:Bool){self.name=name;self.endpoint=endpoint;self.pairing=pairing}
    public static func parse(_ text:String)->[Self] {
        text.split(separator:"\n").compactMap {line in
            let p=line.split(whereSeparator:{$0.isWhitespace}).map(String.init)
            guard p.count>=3,let serviceIndex=p.firstIndex(where:{$0.contains("_adb-tls-")}),serviceIndex>0,serviceIndex+1<p.count,
                  (try? Endpoint(p[serviceIndex+1])) != nil else{return nil}
            return Self(name:p[serviceIndex-1],endpoint:p[serviceIndex+1],pairing:p[serviceIndex].contains("pairing"))
        }
    }
}
