import Foundation
import CoreGraphics
import Darwin
// Parent writes a pulse every 200ms. EOF, parent death, or 900ms stall restores input.
let parent=Int32(CommandLine.arguments.dropFirst().first ?? "0") ?? 0
let flags=fcntl(STDIN_FILENO,F_GETFL,0);_ = fcntl(STDIN_FILENO,F_SETFL,flags | O_NONBLOCK)
var last=Date();var bytes=[UInt8](repeating:0,count:64)
while true {
    let count=read(STDIN_FILENO,&bytes,bytes.count)
    // A deliberate handback already restored the cursor. Never undo a newer
    // takeover when this old watchdog eventually observes the closed pipe.
    if count>0 && bytes.prefix(count).contains(2) {exit(0)}
    if count>0 {last=Date()}
    if count==0 || parent<=1 || kill(parent,0) != 0 || Date().timeIntervalSince(last)>0.9 {
        CGAssociateMouseAndMouseCursorPosition(1)
        CGDisplayShowCursor(CGMainDisplayID())
        exit(0)
    }
    usleep(50_000)
}
