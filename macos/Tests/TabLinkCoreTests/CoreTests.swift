#if canImport(XCTest)
import XCTest
@testable import TabLinkCore
#else
import Foundation
class XCTestCase {}
var assertionCount=0
func XCTAssertTrue(_ a:@autoclosure()->Bool,_ message:String="",file:StaticString=#filePath,line:UInt=#line) {assertionCount+=1;precondition(a(),"\(file):\(line) \(message)")}
func XCTAssertFalse(_ a:@autoclosure()->Bool,_ message:String="",file:StaticString=#filePath,line:UInt=#line) {XCTAssertTrue(!a(),message,file:file,line:line)}
func XCTAssertEqual<T:Equatable>(_ a:@autoclosure()->T,_ b:@autoclosure()->T,_ message:String="",file:StaticString=#filePath,line:UInt=#line) {let x=a(),y=b();assertionCount+=1;precondition(x==y,"\(file):\(line) \(message): \(x) != \(y)")}
func XCTAssertNil<T>(_ a:@autoclosure()->T?,file:StaticString=#filePath,line:UInt=#line) {XCTAssertTrue(a()==nil,file:file,line:line)}
func XCTAssertNotNil<T>(_ a:@autoclosure()->T?,file:StaticString=#filePath,line:UInt=#line) {XCTAssertTrue(a() != nil,file:file,line:line)}
func XCTAssertThrowsError<T>(_ a:@autoclosure()throws->T,file:StaticString=#filePath,line:UInt=#line) {do{_ = try a();preconditionFailure("\(file):\(line): Expected an error")}catch{assertionCount+=1}}
#endif
final class CoreTests:XCTestCase {
    func testAdbStatesAndModels() {
        let text="""
        * daemon started successfully
        List of devices attached
        USB_TEST_001 device usb:12 model:Lenovo_Tab_M9 transport_id:1
        192.168.1.42:37123 offline transport_id:2
        abc unauthorized usb:2
        """
        let d=Device.parse(text);XCTAssertEqual(d.count,3);XCTAssertEqual(d[0].model,"Lenovo Tab M9");XCTAssertTrue(d[0].isReady);XCTAssertTrue(d[1].isWireless);XCTAssertFalse(d[2].isReady)
        XCTAssertEqual(Device.parse("List of devices attached\n\n"),[])
    }
    func testEndpointValidation() throws {
        let endpoint=try Endpoint("192.168.1.4:5555");XCTAssertEqual(endpoint.value,"192.168.1.4:5555")
        for s in ["", "localhost", "-x:123", "x:0", "x:65536", "x;touch a:123", "x:abc", "x\n:1"] {XCTAssertThrowsError(try Endpoint(s))}
    }
    func testLocalAlwaysPassesInput() {
        var r=InputRouter();XCTAssertTrue(r.passesLocalEvents);r.connect();XCTAssertTrue(r.passesLocalEvents)
        XCTAssertFalse(r.observe(atEdge:false,proportion:0.5,now:0));XCTAssertTrue(r.passesLocalEvents)
        _=r.observe(atEdge:true,proportion:0.5,now:1);XCTAssertTrue(r.passesLocalEvents)
    }
    func testDwellAndExit() {
        var r=InputRouter();r.connect()
        XCTAssertFalse(r.observe(atEdge:true,proportion:0.4,now:1));XCTAssertFalse(r.observe(atEdge:true,proportion:0.4,now:1.1));XCTAssertTrue(r.observe(atEdge:true,proportion:0.4,now:1.2))
        XCTAssertEqual(r.state,.remote);XCTAssertFalse(r.passesLocalEvents)
        XCTAssertFalse(r.move(dx:-20,dy:0));XCTAssertTrue(r.move(dx:-21,dy:0));XCTAssertEqual(r.state,.local)
    }
    func testAllEdgesAndFailsafe() {
        for e in Edge.allCases {
            var r=InputRouter();r.edge=e;r.connect();r.enter(proportion:0.5);XCTAssertEqual(r.state,.remote)
            let dx:Double=e == .left ? 50:e == .right ? -50:0
            let dy:Double=e == .top ? 50:e == .bottom ? -50:0
            XCTAssertTrue(r.move(dx:dx,dy:dy));XCTAssertEqual(r.state,.local)
            r.enter(proportion:0);r.disconnect();XCTAssertTrue(r.passesLocalEvents);XCTAssertEqual(r.state,.disconnected)
        }
    }
    func testDwellResetsWhenPointerLeaves() {
        var r=InputRouter();r.connect();_ = r.observe(atEdge:true,proportion:0.5,now:0);_ = r.observe(atEdge:false,proportion:0.5,now:0.2)
        XCTAssertFalse(r.observe(atEdge:true,proportion:0.5,now:0.3))
    }
    func testGoldenVectors() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir=root.appendingPathComponent("protocol/vectors")
        let vectors:[String:Data]=[
            "key-a-down":Control.key(29,down:true),
            "text-hello":Control.text("hello")!,
            "clipboard-unicode":Control.clipboard("Hi 🌍",sequence:42,paste:true)!,
            "mouse-relative":Control.uhidInput(id:1,report:HID.mouseReport(buttons:1,dx:-300,dy:500,wheel:-1,pan:2)),
            "touch-down":Control.touch(action:0,x:100,y:200,width:1920,height:1080),
            "scroll":Control.scroll(x:100,y:200,width:1920,height:1080,horizontal:1,vertical:-1)
        ]
        for (name,data) in vectors {let expected=try String(contentsOf:dir.appendingPathComponent(name+".hex"),encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines);XCTAssertEqual(data.hex,expected,name)}
    }
    func testUTF8LimitIsBytes() {XCTAssertNotNil(Control.text(String(repeating:"é",count:150)));XCTAssertNil(Control.text(String(repeating:"é",count:151)));XCTAssertNil(Control.clipboard(String(repeating:"x",count:262131),sequence:1,paste:false))}
    func testHidReportLengthsAndLittleEndian() {XCTAssertEqual(HID.mouseReport(dx:-300,dy:500).hex,"00d4fef4010000");XCTAssertEqual(HID.keyboardReport(modifiers:3,keys:[4,5]).hex,"0300040500000000");XCTAssertEqual(HID.keyboardReport(modifiers:0,keys:Set(4...20)).count,8)}
    func testAnnexBSplitsThreeAndFourByteMarkers() {XCTAssertEqual(AnnexB.units(Data([0,0,0,1,0x67,2,0,0,1,0x68,3])),[Data([0x67,2]),Data([0x68,3])]);XCTAssertEqual(AnnexB.units(Data([1,2,3])),[])}
    func testVideoHeaderBoundsAndFlags() {var d=Data();d.put(UInt64(0xc000000000000123));d.put(UInt32(42));let h=VideoPacketHeader(d);XCTAssertTrue(h!.config);XCTAssertTrue(h!.keyframe);XCTAssertEqual(h!.pts,0x123);XCTAssertEqual(h!.size,42);XCTAssertNil(VideoPacketHeader(Data(count:12)));XCTAssertNil(VideoPacketHeader(Data(count:11)))}
    func testKeymapCoversCommonKeys() {XCTAssertEqual(KeyMapper.hid[0],4);XCTAssertEqual(KeyMapper.androidCode(0),29);XCTAssertEqual(KeyMapper.androidCode(36),66);XCTAssertEqual(KeyMapper.hid[126],82)}
    func testDirectControlStartsAtTabletCenter() {
        var r=InputRouter();r.width=1340;r.height=800;r.connect();r.enterAtCenter()
        XCTAssertEqual(r.state,.remote);XCTAssertEqual(r.x,670);XCTAssertEqual(r.y,400)
        XCTAssertFalse(r.move(dx:-10,dy:20));r.leave();XCTAssertTrue(r.passesLocalEvents)
    }
    func testViewportDimensionsWithoutVideo() {
        let landscape="Viewport INTERNAL: displayId=0, uniqueId=local:0, orientation=1, logicalFrame=[0, 0, 1340, 800], physicalFrame=[0, 0, 1340, 800]"
        XCTAssertEqual(TabletDisplay.parse(landscape)?.width,1340);XCTAssertEqual(TabletDisplay.parse(landscape)?.height,800)
        XCTAssertEqual(TabletDisplay.parse("Viewport INTERNAL: displayId=0, logicalFrame=[0, 0, 800, 1340]")?.height,1340)
        XCTAssertNil(TabletDisplay.parse("Viewport INTERNAL: displayId=4, logicalFrame=[0, 0, 800, 1340]"))
        XCTAssertNil(TabletDisplay.parse("Viewport INTERNAL: displayId=0, logicalFrame=[0, 0, 0, 0]"))
    }

    func testRotationPreservesTabletControl() {
        var r=InputRouter();r.width=1340;r.height=800;r.connect();r.enterAtCenter()
        r.resize(width:800,height:1340)
        XCTAssertEqual(r.state,.remote);XCTAssertEqual(r.x,400);XCTAssertEqual(r.y,670)
    }

    func testCursorSpriteMetadata() {
        let sample="""
        + BufferStateLayer (Sprite#17965) uid=1000
          Region TransparentRegion (this=0 count=0)
          Region VisibleRegion (this=0 count=0)
              layerStack=0, z=351000, pos=(-4.5,793), size=(-1,-1)
        """
        XCTAssertEqual(TabletPointerPosition.parse(sample),TabletPointerPosition(x:-4.5,y:793))
        XCTAssertNil(TabletPointerPosition.parse("+ BufferStateLayer (App#1) uid=1000 pos=(4,5)"))
        XCTAssertNil(TabletPointerPosition.parse("+ BufferStateLayer (Sprite#1) uid=1000\n+ BufferStateLayer (App#2) uid=1000\n pos=(40,50)"))
    }
    func testAllPhysicalTabletCornersReturn() {
        for point in [TabletPointerPosition(x:-4,y:-6),.init(x:1335,y:-6),.init(x:-4,y:793),.init(x:1335,y:793)] {
            var corner=CornerReturn()
            XCTAssertFalse(corner.observe(point,width:1340,height:800,now:1))
            XCTAssertFalse(corner.observe(point,width:1340,height:800,now:1.1))
            XCTAssertTrue(corner.observe(point,width:1340,height:800,now:1.25))
        }
    }
    func testCornerReturnIgnoresMovementAndResets() {
        var c=CornerReturn()
        XCTAssertFalse(c.observe(.init(x:0,y:0),width:1340,height:800,now:0))
        XCTAssertFalse(c.observe(.init(x:670,y:400),width:1340,height:800,now:0.5))
        XCTAssertFalse(c.observe(.init(x:0,y:0),width:1340,height:800,now:1))
        XCTAssertFalse(c.observe(.init(x:1335,y:793),width:1340,height:800,now:1.5))
        XCTAssertTrue(c.observe(.init(x:1335,y:793),width:1340,height:800,now:1.8))
        c.reset();XCTAssertFalse(c.observe(.init(x:1335,y:793),width:1340,height:800,now:2))
    }
    func testPhysicalFeedbackPreventsAcceleratedEstimateExit() {
        var r=InputRouter();r.connect();r.enterAtCenter();r.automaticReturn=false
        XCTAssertFalse(r.move(dx:5000,dy:-5000));XCTAssertEqual(r.state,.remote)
        r.synchronize(x:450,y:500);XCTAssertEqual(r.x,450);XCTAssertEqual(r.y,500)
    }
    func testFallbackAllowsEveryEdge() {
        for delta in [(5000.0,0.0),(-5000.0,0.0),(0.0,5000.0),(0.0,-5000.0)] {
            var r=InputRouter();r.returnAtAnyEdge=true;r.connect();r.enterAtCenter()
            XCTAssertTrue(r.move(dx:delta.0,dy:delta.1));XCTAssertEqual(r.state,.local)
        }
    }
    func testWirelessDiscoveryResolvesPortsInternally() {
        let services=WirelessService.parse("""
        List of discovered mdns services
        adb-LENOVO-abc _adb-tls-connect._tcp 192.0.2.42:43687
        adb-LENOVO-xyz _adb-tls-pairing._tcp. 192.0.2.42:39655
        garbage _http._tcp 192.0.2.42:80
        invalid _adb-tls-connect._tcp invalid
        """)
        XCTAssertEqual(services.count,2);XCTAssertEqual(services[0].endpoint,"192.0.2.42:43687")
        XCTAssertFalse(services[0].pairing);XCTAssertTrue(services[1].pairing)
    }

    func testReturnAcrossEveryAdjoiningTabletEdge() {
        let cases:[(Edge,TabletPointerPosition,Double,Double)]=[
            (.right,.init(x:0,y:400),-25,0),(.left,.init(x:1334,y:400),25,0),
            (.top,.init(x:670,y:794),0,25),(.bottom,.init(x:670,y:0),0,-25)]
        for (edge,p,dx,dy) in cases {
            var r=EdgeReturn()
            XCTAssertFalse(r.observe(p,width:1340,height:800,edge:edge,now:1))
            r.motion(dx:dx,dy:dy,edge:edge,now:1.1)
            XCTAssertTrue(r.observe(p,width:1340,height:800,edge:edge,now:1.2))
        }
    }
    func testEdgeReturnRequiresFreshBoundaryAndOutwardPush() {
        var r=EdgeReturn()
        r.motion(dx:-100,dy:0,edge:.right,now:0)
        XCTAssertFalse(r.observe(.init(x:500,y:400),width:1340,height:800,edge:.right,now:0.1))
        XCTAssertFalse(r.observe(.init(x:0,y:400),width:1340,height:800,edge:.right,now:0.2))
        r.motion(dx:-30,dy:0,edge:.right,now:1)
        r.motion(dx:5,dy:0,edge:.right,now:1.1)
        XCTAssertFalse(r.observe(.init(x:0,y:400),width:1340,height:800,edge:.right,now:1.2))
        r.motion(dx:-30,dy:0,edge:.right,now:2)
        XCTAssertFalse(r.observe(.init(x:0,y:400),width:1340,height:800,edge:.right,now:2.5))
    }
    func testStationaryEdgeDwellCanCompleteOnTimerSample() {
        var r=InputRouter();r.connect();r.dwell=0.2
        XCTAssertFalse(r.observe(atEdge:true,proportion:0.4,now:1))
        // No additional hardware event: the common-mode timer samples the same position.
        XCTAssertTrue(r.observe(atEdge:true,proportion:0.4,now:1.21))
        XCTAssertEqual(r.state,.remote)
    }

    func testCommandShiftPTogglesBothDirectionsAndEmergencyStaysAvailable() {
        XCTAssertEqual(HandoffShortcut.action(keyCode:35,command:true,shift:true,control:false,option:false),.toggle)
        XCTAssertNil(HandoffShortcut.action(keyCode:35,command:true,shift:false,control:false,option:false))
        XCTAssertNil(HandoffShortcut.action(keyCode:35,command:true,shift:true,control:true,option:false))
        XCTAssertEqual(HandoffShortcut.action(keyCode:53,command:true,shift:false,control:true,option:true),.returnToMac)
        XCTAssertEqual(HandoffShortcut.action(keyCode:17,command:true,shift:false,control:true,option:true),.toggle)
    }

}
