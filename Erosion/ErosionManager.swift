//
//  ErosionManager.swift
//  Erosion
//
//  Created by lunginspector on 8/24/26.
//

import Foundation
import Combine

let build = "Release"

enum AppURL {
    static let pb = URL.documentsDirectory.appendingPathComponent("PosterBoard")
    static let pbFolders = AppURL.pb.appendingPathComponent("Wallpapers")
}

enum AppMsg {
    static let opFailed = "请重启应用后重试。若问题依旧，可能是当前设备/系统不受支持，或该功能在你的设备上无法正常工作。"
    static let applied = "请重启桌面（Respring）以使更改生效。"
    static let unsupported = "很抱歉，Erosion 依赖的漏洞在当前系统版本中已被封堵，请退出应用。"
}

final class ErosionManager: ObservableObject {
    static let shared = ErosionManager()
    @Published var logOutput = ""
    @Published var shouldRespring = false
    
    init() {}
}
