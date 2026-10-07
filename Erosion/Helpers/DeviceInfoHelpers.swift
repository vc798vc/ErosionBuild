//
//  DeviceInfoHelpers.swift
//  Erosion
//
//  Created by lunginspector on 8/14/26.
//

import Foundation
import PartyUI

// version support for different functions
// NOTE (build patch): upstream only whitelisted 4 specific iOS 27.0 beta
// build numbers. bad_query is confirmed working through 27.0b5, so we accept
// the whole 27.x line to avoid the "unsupported -> exit" gate on TQ's device.
// Tighten back if a later 27.x GM patches the sandbox escape.
func mgSupported() -> Bool {
    let v = doubleSystemVersion()
    if v >= 27.0 && v < 28.0 {
        return true
    }
    return false
}

func isSupported() -> Bool {
    if (doubleSystemVersion() >= 19.0 && doubleSystemVersion() < 27.0) || mgSupported() {
        return true
    }
    return false
}

// device info getters
func machineName() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    return machineMirror.children.reduce("") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return identifier }
        return identifier + String(UnicodeScalar(UInt8(value)))
    }
}

func buildNumber() -> String {
    var versString = [CChar](repeating: 0, count: 16)
    var versStringLen = size_t(versString.count - 1)
    let res = sysctlbyname("kern.osversion", &versString, &versStringLen, nil, 0)
    if res == 0, let buildNum = String(validatingUTF8: versString) {
        return buildNum
    }
    return "Unknown"
}
