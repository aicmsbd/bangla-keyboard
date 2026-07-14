import Carbon
import Foundation
// Register (or re-register) the installed input method and list matching sources.
if CommandLine.arguments.count > 1 {
    let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
    let st = TISRegisterInputSource(url)
    print("TISRegisterInputSource status: \(st)")
}
if let cf = TISCreateInputSourceList(nil, true)?.takeRetainedValue() {
    let arr = cf as! [TISInputSource]
    var hits = 0
    for src in arr {
        func str(_ k: CFString) -> String? {
            guard let p = TISGetInputSourceProperty(src, k) else { return nil }
            return (Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String)
        }
        let id = str(kTISPropertyInputSourceID) ?? ""
        if id.contains("com.bangla.inputmethod") || (str(kTISPropertyLocalizedName) ?? "").contains("বাঙলা") {
            print("FOUND input source: id=\(id) name=\(str(kTISPropertyLocalizedName) ?? "")")
            hits += 1
        }
    }
    print("matching input sources: \(hits)")
}
