import SwiftUI
import TabLinkCore
final class InterfaceState:ObservableObject {
    @Published var selection="Connect"
    @Published var code=""
}
private let accent=Color(red:0.29,green:0.72,blue:0.94)
struct RootView:View {
    @ObservedObject var model:AppModel
    @ObservedObject var ui=InterfaceState()
    var body:some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:9){Image(systemName:"rectangle.connected.to.line.below").font(.title2).foregroundStyle(accent);Text("TabLink").font(.system(size:23,weight:.semibold,design:.rounded))}.padding(.bottom,30)
                ForEach([("Connect","rectangle.on.rectangle"),("Setup","checkmark.shield"),("Settings","slider.horizontal.3"),("Activity","list.bullet.rectangle")],id:\.0){item in
                    Button {ui.selection=item.0} label:{HStack(spacing:12){Image(systemName:item.1).frame(width:18);Text(item.0);Spacer()}.padding(.horizontal,12).padding(.vertical,11).background(ui.selection==item.0 ? Color.white.opacity(0.09):.clear,in:RoundedRectangle(cornerRadius:9))}.buttonStyle(.plain).foregroundStyle(ui.selection==item.0 ? .white:Color.white.opacity(0.6))
                }
                Spacer()
                VStack(alignment:.leading,spacing:8){Label(model.isRemote ? "Controlling tablet":model.connected ? "Tablet connected":"Ready when you are",systemImage:model.connected ? "link":"laptopcomputer").font(.system(size:12,weight:.medium)).foregroundStyle(model.connected ? accent:Color.white.opacity(0.6));Text("Switch between devices").font(.system(size:11)).foregroundStyle(.white.opacity(0.4));Text("⌘ ⇧ P").font(.system(size:15,weight:.medium,design:.monospaced)).foregroundStyle(.white.opacity(0.8))}.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:10))
                Text("v1.4 · Tablet control").font(.system(size:10)).foregroundStyle(.white.opacity(0.35)).padding(.top,10)
            }.padding(22).frame(width:215).background(Color(red:0.055,green:0.075,blue:0.11))
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    HStack {VStack(alignment:.leading,spacing:7){Text(title).font(.system(size:30,weight:.semibold));Text(subtitle).font(.system(size:14)).foregroundStyle(.secondary)};Spacer();if model.busy || model.connecting {ProgressView().controlSize(.small)}}
                    if !model.notice.isEmpty {HStack(alignment:.top){Image(systemName:"info.circle").foregroundStyle(accent);Text(model.notice).font(.system(size:13)).textSelection(.enabled);Spacer();Button{model.notice=""}label:{Image(systemName:"xmark")}.buttonStyle(.plain).accessibilityLabel("Dismiss message")}.padding(14).background(accent.opacity(0.08),in:RoundedRectangle(cornerRadius:10))}
                    switch ui.selection {case "Connect":connect;case "Setup":setup;case "Settings":settings;default:activity}
                }.padding(32).frame(maxWidth:950,alignment:.leading)
            }.background(Color(red:0.075,green:0.095,blue:0.135))
        }.foregroundStyle(.white).preferredColorScheme(.dark).frame(minWidth:900,minHeight:690)
    }
    private var title:String {ui.selection=="Connect" ? "Work on your tablet.":ui.selection=="Setup" ? "A little setup. A seamless connection.":ui.selection=="Settings" ? "Make it feel like your Mac.":"Connection activity"}
    private var subtitle:String {ui.selection=="Connect" ? "Use your MacBook keyboard and trackpad on the tablet’s own screen.":ui.selection=="Setup" ? "Connect over USB first, then add wireless when you’re ready.":ui.selection=="Settings" ? "Changes are saved automatically.":"Local diagnostics, without clipboard contents."}
    private var connect:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(spacing:24) {
                VStack(spacing:8){Image(systemName:"laptopcomputer").font(.system(size:75,weight:.ultraLight));Text("This Mac").font(.system(size:13)).foregroundStyle(.secondary)}
                VStack(spacing:9){Image(systemName:model.connected ? "link":"ellipsis").font(.system(size:22)).foregroundStyle(accent);Text(model.connected ? "Connected":"USB or Wi-Fi").font(.system(size:11)).foregroundStyle(.secondary)}
                VStack(spacing:8){Image(systemName:"ipad.landscape").font(.system(size:70,weight:.ultraLight)).foregroundStyle(model.connected ? accent:Color.white.opacity(0.45));Text(model.connected ? model.deviceName:"Android tablet").font(.system(size:13)).foregroundStyle(.secondary)}
            }.frame(maxWidth:.infinity).padding(.vertical,32).background(LinearGradient(colors:[accent.opacity(0.07),.clear],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).strokeBorder(.white.opacity(0.07)))
            card {
                HStack {Label("Your tablet",systemImage:"cable.connector").font(.headline);Spacer();Button("Refresh"){model.refresh()}.buttonStyle(.borderless)}
                if model.devices.isEmpty {
                    VStack(alignment:.leading,spacing:12){Text("Connect your tablet with a USB data cable.").font(.system(size:16,weight:.medium));Text("Enable USB debugging, unlock the tablet, and accept “Allow USB debugging?” on its screen.").foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true);Button("View setup guide"){ui.selection="Setup"}.buttonStyle(.bordered)}.padding(.vertical,8)
                } else {
                    ForEach(model.devices){d in HStack(spacing:14){Image(systemName:d.isWireless ? "wifi":"ipad").font(.title2).foregroundStyle(accent);VStack(alignment:.leading,spacing:5){Text(d.model).fontWeight(.medium);Text(d.state=="unauthorized" ? "Unlock tablet and allow USB debugging":d.isReady ? (d.isWireless ? "Wireless debugging":"USB · Ready to connect"):d.state).font(.system(size:12)).foregroundStyle(d.isReady ? .secondary:Color.orange)};Spacer();if model.connected && model.session?.device.serial==d.serial {Button("Disconnect"){model.disconnect()}.buttonStyle(.bordered)}else{Button("Connect & control"){model.selected=d.serial;model.connectSelected()}.buttonStyle(.borderedProminent).tint(accent).disabled(!d.isReady || model.connecting || model.connected)}}.padding(.vertical,6)}
                }
            }
            if model.connected {
                HStack(spacing:14) {
                    actionTile(model.isRemote ? "Return to Mac":"Control tablet",detail:model.isRemote ? "⌃⌥⌘Esc returns your keyboard and trackpad":"The cursor and keyboard move onto the physical tablet",icon:"cursorarrow.motionlines"){if model.isRemote {model.capture?.leave()}else{model.controlTablet()}}
                    actionTile("Send files",detail:"Choose files or drop them on the menu bar icon",icon:"square.and.arrow.up"){model.chooseFiles()}
                }
                card {
                    HStack{Image(systemName:"cursorarrow.motionlines").font(.title2).foregroundStyle(accent);VStack(alignment:.leading,spacing:5){Text("Move between devices").font(.headline);Text("Enter from the Mac’s \(model.edge) edge. Push back across the adjoining tablet edge, or pause at any corner, to return.").font(.system(size:13)).foregroundStyle(.secondary)};Spacer();Toggle("Edge crossing",isOn:$model.edgeEnabled).labelsHidden().toggleStyle(.switch).disabled(!model.accessibility || !model.uhidAvailable)}
                    if !model.accessibility {Button("Enable Mac input permissions"){ui.selection="Setup"}.buttonStyle(.borderless)}
                    if model.edgeEnabled {Text("Return with ⌃⌥⌘Esc · Toggle with ⌃⌥⌘T").font(.system(size:12,design:.monospaced)).foregroundStyle(.secondary);Button(model.isRemote ? "Return to Mac":"Control tablet now"){model.capture?.toggle()}.buttonStyle(.bordered)}
                }
                Text("Android \(model.androidVersion) · \(model.width) × \(model.height) · Direct mouse & keyboard").font(.system(size:12,design:.monospaced)).foregroundStyle(.secondary)
            }
            if !model.transferStatus.isEmpty {Label(model.transferStatus,systemImage:model.busy ? "clock":"checkmark.circle").font(.system(size:13)).foregroundStyle(accent)}
            HStack{Image(systemName:"wifi");Text("Prefer to connect wirelessly?");Button("Connect over Wi-Fi"){ui.selection="Setup";model.connectOverWiFi()}}.font(.system(size:13)).foregroundStyle(.secondary)
        }
    }
    private func actionTile(_ title:String,detail:String,icon:String,action:@escaping()->Void)->some View {Button(action:action){HStack(alignment:.top,spacing:12){Image(systemName:icon).font(.title2).foregroundStyle(accent);VStack(alignment:.leading,spacing:7){Text(title).font(.system(size:16,weight:.medium));Text(detail).font(.system(size:12)).foregroundStyle(.secondary).multilineTextAlignment(.leading)};Spacer()}.padding(20).frame(maxWidth:.infinity,minHeight:94).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(.white.opacity(0.07)))}.buttonStyle(.plain).disabled(model.busy)}
    private var setup:some View {
        VStack(spacing:20) {
            card {Label("Prepare your Android tablet",systemImage:"ipad").font(.headline)
                instruction("Enable Developer options","Open Settings › About tablet. Tap Build number seven times.")
                instruction("Turn on USB debugging","Open Settings › System › Developer options. Connect a USB data cable and accept the authorization prompt.")
                instruction("Keep the screen unlocked","Some brands also need “USB debugging (Security settings)” enabled for keyboard and mouse control.")
            }
            card {Label("Mac permission for tablet control",systemImage:"hand.raised").font(.headline)
                permission("Device control (Accessibility)",detail:"Send your MacBook keyboard and trackpad to the tablet.",granted:model.accessibility){model.requestPermission(true)}
                Text("On this Mac, enable TabLink in Privacy & Security › Device Control and Data Access. This grant includes keyboard and trackpad monitoring. If macOS asks to quit and reopen TabLink, do so after enabling it.").font(.system(size:12)).foregroundStyle(.secondary)
            }
            WirelessPanel(model:model,ui:ui)
        }
    }
    private func instruction(_ title:String,_ detail:String)->some View {VStack(alignment:.leading,spacing:5){Text(title).font(.system(size:14,weight:.medium));Text(detail).font(.system(size:13)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}.padding(.vertical,5)}
    private func permission(_ title:String,detail:String,granted:Bool,action:@escaping()->Void)->some View {HStack{VStack(alignment:.leading,spacing:5){Text(title).font(.system(size:14,weight:.medium));Text(detail).font(.system(size:12)).foregroundStyle(.secondary)};Spacer();if granted {Label("Allowed",systemImage:"checkmark.circle.fill").foregroundStyle(accent).font(.system(size:12))}else{Button("Open Settings",action:action).buttonStyle(.bordered)}}.padding(.vertical,5)}
    private var settings:some View {
        VStack(spacing:20){
            card {Label("Screen arrangement",systemImage:"display.2").font(.headline)
                HStack {Text("Tablet is to the");Picker("Tablet position",selection:$model.edge){ForEach(Edge.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0.rawValue)}}.labelsHidden().frame(width:140);Spacer()}
                HStack{Text("Edge dwell");Slider(value:$model.dwell,in:150...700,step:50);Text("\(Int(model.dwell)) ms").monospacedDigit().frame(width:64)}
                HStack{Text("Pointer speed");Slider(value:$model.sensitivity,in:0.25...3,step:0.05);Text(String(format:"%.2f×",model.sensitivity)).monospacedDigit().frame(width:64)}
            }
            card {Label("Keyboard & trackpad",systemImage:"keyboard").font(.headline)
                Picker("Keyboard input",selection:$model.keyboardMode){Text("Physical keyboard").tag("physical");Text("Text / Unicode / IME").tag("text")}.pickerStyle(.segmented)
                Text("Physical mode uses the tablet’s keyboard layout. Text mode uses committed Mac text and pastes it on Android, including emoji and other scripts.").font(.system(size:12)).foregroundStyle(.secondary)
                Toggle("Map Command to Android Control",isOn:$model.commandToControl)
                Toggle("Natural scrolling",isOn:$model.naturalScroll)
                Text("Right click uses the tablet’s normal mouse secondary button.").font(.system(size:12)).foregroundStyle(.secondary)
            }
            card {Label("Connection & sharing",systemImage:"link").font(.headline)
                Toggle("Sync text clipboard in both directions",isOn:$model.clipboardSync)
                Toggle("Reconnect when the tablet returns",isOn:$model.autoReconnect)

                Text("USB and local Wi-Fi connections. Tablet control does not capture its screen.").font(.system(size:12)).foregroundStyle(.secondary)
            }
            card {Label("Emergency return",systemImage:"escape").font(.headline);Text("Control + Option + Command + Escape").font(.system(size:16,weight:.medium,design:.monospaced));Text("Always returns input to this Mac. This shortcut cannot be changed.").font(.system(size:12)).foregroundStyle(.secondary)}
        }.font(.system(size:14))
    }
    private var activity:some View {
        card {HStack{Text("Recent events").font(.headline);Spacer();Button("Export diagnostics"){model.exportDiagnostics()};Button("Clear"){model.activities=[]}};if model.activities.isEmpty {Text("Connection events will appear here.").foregroundStyle(.secondary).padding(.vertical,20)}else{ForEach(model.activities){a in HStack(alignment:.top){Text(a.time,style:.time).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary).frame(width:85,alignment:.leading);Text(a.message).font(.system(size:13)).textSelection(.enabled);Spacer()}.padding(.vertical,7);Divider()}}}
    }
    private func card<Content:View>(@ViewBuilder _ content:()->Content)->some View {VStack(alignment:.leading,spacing:16,content:content).padding(22).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:13)).overlay(RoundedRectangle(cornerRadius:13).strokeBorder(.white.opacity(0.065)))}
}
struct WirelessPanel:View {
    @ObservedObject var model:AppModel
    @ObservedObject var ui:InterfaceState
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Label("Wi-Fi connection",systemImage:"wifi").font(.headline)
            Text("Keep your Mac and tablet on the same Wi-Fi. TabLink finds the connection details automatically.").font(.system(size:13)).foregroundStyle(.secondary)
            Button(model.wirelessSearching ? "Connecting…":"Connect over Wi-Fi"){model.connectOverWiFi()}
                .buttonStyle(.borderedProminent).tint(accent).disabled(model.wirelessSearching)
            if !model.wirelessMessage.isEmpty {Text(model.wirelessMessage).font(.system(size:13)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
            if model.needsWirelessPairing {
                HStack {
                    SecureField("One-time tablet code",text:$ui.code).frame(width:190)
                    Button("Pair & connect"){model.pairWireless(code:ui.code);ui.code=""}.disabled(model.wirelessSearching || ui.code.count != 6)
                }
            }
            Text("First connection: keep USB plugged in and approve Wireless debugging on the tablet. If Android requests pairing, enter its six-digit code once; later connections use the single button.").font(.system(size:12)).foregroundStyle(.secondary)
        }.textFieldStyle(.roundedBorder).padding(22).frame(maxWidth:.infinity,alignment:.leading)
        .background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:13))
        .overlay(RoundedRectangle(cornerRadius:13).strokeBorder(.white.opacity(0.065)))
    }
}
