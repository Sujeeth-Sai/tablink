public enum HandoffShortcut:Equatable {
    case toggle, returnToMac
    public static func action(keyCode:UInt16,command:Bool,shift:Bool,control:Bool,option:Bool)->Self? {
        if command && shift && !control && !option && keyCode==35 {return .toggle}
        if command && control && option {
            if keyCode==53 {return .returnToMac}
            if keyCode==17 {return .toggle}
        }
        return nil
    }
}
