import Foundation
import TabLinkCore
/// Bonjour resolves the addresses/ports internally. The UI only shows tablet names.
final class WirelessDiscovery:NSObject,NetServiceBrowserDelegate,NetServiceDelegate {
    private var browsers:[NetServiceBrowser]=[]
    private var resolving:[String:NetService]=[:]
    private var found:[String:WirelessService]=[:]
    var onChange:(([WirelessService])->Void)?
    var onStatus:((String)->Void)?
    func start() {
        browsers.forEach{$0.stop()};resolving.values.forEach{$0.stop()}
        browsers=[];resolving=[:];found=[:];publish()
        for type in ["_adb-tls-connect._tcp.","_adb-tls-pairing._tcp."] {
            let b=NetServiceBrowser();b.delegate=self;b.schedule(in:.main,forMode:.common);browsers.append(b);b.searchForServices(ofType:type,inDomain:"local.")
        }
    }
    func netServiceBrowser(_ browser:NetServiceBrowser,didFind service:NetService,moreComing:Bool) {
        onStatus?("Tablet discovered on Wi-Fi. Resolving connection…")
        let key=service.name+service.type;resolving[key]=service;service.delegate=self;service.schedule(in:.main,forMode:.common);service.resolve(withTimeout:5)
    }
    func netServiceBrowser(_ browser:NetServiceBrowser,didRemove service:NetService,moreComing:Bool) {
        let key=service.name+service.type;found.removeValue(forKey:key);resolving.removeValue(forKey:key);publish()
    }
    func netServiceDidResolveAddress(_ service:NetService) {
        guard service.port>0,let host=service.hostName else{return}
        var name=host.trimmingCharacters(in:CharacterSet(charactersIn:"."))
        for data in service.addresses ?? [] {
            let address=data.withUnsafeBytes {raw->String? in
                guard let base=raw.baseAddress,raw.count>=MemoryLayout<sockaddr>.size else{return nil}
                let sa=base.assumingMemoryBound(to:sockaddr.self)
                guard sa.pointee.sa_family==AF_INET else{return nil}
                var output=[CChar](repeating:0,count:Int(NI_MAXHOST))
                guard getnameinfo(sa,socklen_t(data.count),&output,socklen_t(output.count),nil,0,NI_NUMERICHOST)==0 else{return nil}
                return String(cString:output)
            }
            if let address=address {name=address;break}
        }
        let endpoint="\(name):\(service.port)"
        guard (try? Endpoint(endpoint)) != nil else{return}
        found[service.name+service.type]=WirelessService(name:service.name,endpoint:endpoint,pairing:service.type.contains("pairing"));publish()
    }
    func netServiceBrowser(_ browser:NetServiceBrowser,didNotSearch errorDict:[String:NSNumber]) {
        onStatus?("Wi-Fi discovery needs Local Network access. Enable TabLink in System Settings → Privacy & Security → Local Network, then retry.")
    }
    func netService(_ service:NetService,didNotResolve errorDict:[String:NSNumber]) {
        onStatus?("The tablet was found but did not respond. Keep it awake on the same Wi-Fi and retry.")
    }
    private func publish(){onChange?(found.values.sorted{$0.name<$1.name})}
    deinit {browsers.forEach{$0.stop()};resolving.values.forEach{$0.stop()}}
}
