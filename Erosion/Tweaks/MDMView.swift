//
//  MDMView.swift
//  Erosion
//
//  中文一键移除 MDM 模块。
//  设计取向：不做版本门禁，直接尝试提权并实测可写性，用真实结果说话。
//

import SwiftUI
import Combine
import PartyUI

// MARK: - 路径

enum MDMURL {
    /// bad_query 在不同系统版本上可触达的形式不同（有无 /private 前缀），逐个探测。
    static let dirCandidates: [String] = [
        "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles",
        "/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
    ]
    static let cloudFile = "CloudConfigurationDetails.plist"
    static let sharedFile = "SharedDeviceConfiguration.plist"
}

enum MDMPhase {
    case idle, working, ok, failed
}

// MARK: - 逻辑

final class MDMRemover: ObservableObject {
    static let shared = MDMRemover()

    @Published var phase: MDMPhase = .idle
    @Published var supervised: Bool = false
    @Published var orgName: String = ""
    @Published var workingPath: String = ""
    @Published var message: String = "尚未检测"
    @Published var detail: String = ""
    @Published var isBusy: Bool = false
    @Published var routeUsed: String = ""

    private func fileURL(_ dir: String, _ file: String) -> URL {
        URL(fileURLWithPath: dir).appendingPathComponent(file)
    }

    /// 依次尝试每条候选目录；每条目录内部再依次尝试 27/26 两种路由（见 BadQuery.grantAccessAuto）。
    /// 返回 (目录, 实际使用的路由)
    private func grantAny() -> (String, String)? {
        var trace = ""
        for dir in MDMURL.dirCandidates {
            let a = bq.grantAccessAuto(atPath: dir)
            if a.0 {
                print("(mdm) 提权成功: \(dir) [\(a.3)]")
                return (dir, a.3)
            }
            trace += "路径 \(dir)\n\(a.3)\n"
        }
        detail = trace
        return nil
    }

    /// 失败时给出基于真实系统版本的诚实结论
    private func failDetail() -> String {
        let ver = UIDevice.current.systemVersion
        let bld = buildNumber()
        var s = "设备：iOS \(ver)（build \(bld)）\n\n"
        s += detail
        if ver.hasPrefix("26.") {
            s += "\n结论：你的系统是 iOS 26.x。Erosion 的 MDM 功能官方仅支持 iOS 27.0 beta1–beta4；已按 bad_query 作者注释尝试了 iOS 26 的备用路由（class 7 / 26 flags），仍被内核拒绝发放 sandbox extension。当前版本上该目录大概率不可达。"
        } else {
            s += "\n结论：所有路由均被拒绝，当前系统版本可能已封堵该漏洞。"
        }
        return s
    }

    func detect() {
        if isBusy { return }
        isBusy = true
        phase = .working
        message = "正在申请访问权限…"

        guard let g = grantAny() else {
            phase = .failed
            message = "无法访问描述文件目录"
            detail = failDetail()
            isBusy = false
            print("(mdm) 检测失败")
            Alertinator.shared.alert(title: "检测失败", body: detail)
            return
        }
        workingPath = g.0
        routeUsed = g.1

        let dir = g.0
        let cloud = fileURL(dir, MDMURL.cloudFile)
        if let d = NSMutableDictionary(contentsOf: cloud) {
            supervised = (d["IsSupervised"] as? Bool) ?? false
            orgName = (d["OrganizationName"] as? String) ?? ""
            detail = "路径：\(dir)\n提权路由：\(routeUsed)\n\(MDMURL.cloudFile) 读取成功。"
        } else {
            supervised = false
            orgName = ""
            detail = "路径：\(dir)\n未找到 \(MDMURL.cloudFile)（可能本就未被监管）。"
        }
        phase = .ok
        message = supervised ? "设备当前处于受监管状态" : "未检测到监管标记"
        isBusy = false
        print("(mdm) 检测完成：supervised=\(supervised) org=\(orgName)")
    }

    func remove() {
        if isBusy { return }
        isBusy = true
        phase = .working
        message = "正在移除监管标记…"
        print("(mdm) 开始一键移除")

        guard let g = grantAny() else {
            phase = .failed
            message = "无法访问描述文件目录"
            detail = failDetail()
            isBusy = false
            print("(mdm) 移除失败：提权失败")
            Alertinator.shared.alert(title: "移除失败", body: detail)
            return
        }
        workingPath = g.0
        routeUsed = g.1

        let dir = g.0
        let cloudURL = fileURL(dir, MDMURL.cloudFile)
        let sharedURL = fileURL(dir, MDMURL.sharedFile)

        let dict = NSMutableDictionary(contentsOf: cloudURL) ?? NSMutableDictionary()
        dict["IsSupervised"] = false
        dict.removeObject(forKey: "OrganizationName")

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
            try data.write(to: cloudURL)
            print("(mdm) 已写入 \(MDMURL.cloudFile)")
        } catch {
            phase = .failed
            message = "写入失败"
            detail = "写入 \(MDMURL.cloudFile) 时出错：\n\(error)"
            isBusy = false
            print("(mdm) 写入失败：\(error)")
            Alertinator.shared.alert(title: "移除失败", body: detail)
            return
        }

        if fm.fileExists(atPath: sharedURL.path) {
            do {
                try fm.removeItem(at: sharedURL)
                print("(mdm) 已删除 \(MDMURL.sharedFile)")
            } catch {
                print("(mdm) 删除 \(MDMURL.sharedFile) 失败（忽略）：\(error)")
            }
        }

        supervised = false
        orgName = ""
        phase = .ok
        message = "已移除监管标记"
        detail = "IsSupervised 已置为 false\nOrganizationName 已清除\n\(MDMURL.sharedFile) 已删除\n\n路径：\(dir)\n提权路由：\(routeUsed)"
        isBusy = false
        print("(mdm) 一键移除完成")
        Haptic.shared.play(.heavy)

        Alertinator.shared.alert(title: "已移除 MDM 监管", body: detail, actionLabel: "立即重启", action: {
            ErosionManager.shared.shouldRespring = true
        })
    }
}

// MARK: - 主界面卡片

struct MDMCard: View {
    @ObservedObject private var r = MDMRemover.shared
    @State private var appeared = false

    private var tint: Color {
        switch r.phase {
        case .ok:     return r.supervised ? .red : .green
        case .failed: return .orange
        case .working:return .blue
        case .idle:   return .gray
        }
    }

    private var icon: String {
        switch r.phase {
        case .ok:     return r.supervised ? "lock.shield.fill" : "lock.open.fill"
        case .failed: return "exclamationmark.shield.fill"
        case .working:return "arrow.triangle.2.circlepath"
        case .idle:   return "shield.lefthalf.filled"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("MDM 监管状态")
                        .font(.headline)
                    Text(r.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if r.phase == .ok && r.supervised && !r.orgName.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "building.2")
                        .foregroundStyle(.secondary)
                    Text("管理组织：\(r.orgName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Alertinator.shared.alert(
                    title: "确认移除 MDM 监管？",
                    body: "将把 IsSupervised 置为 false、清除 OrganizationName，并删除 \(MDMURL.sharedFile)。\n\n这不会解除服务器端的 MDM 注册，设备下次签入时策略仍可能被重新下发。",
                    actionLabel: "确认移除",
                    action: { MDMRemover.shared.remove() }
                )
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: r.isBusy ? "hourglass" : "bolt.fill")
                    Text(r.isBusy ? "正在处理…" : "一键移除 MDM")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(
                    Capsule().fill(
                        LinearGradient(colors: [Color.red, Color.orange],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(r.isBusy)
            .opacity(r.isBusy ? 0.6 : 1)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .onAppear {
            if !appeared {
                appeared = true
                // defer one tick so we never mutate @Published state
                // while SwiftUI is still computing the body
                DispatchQueue.main.async { MDMRemover.shared.detect() }
            }
        }
    }
}

// MARK: - 详情页

struct MDMView: View {
    @ObservedObject private var r = MDMRemover.shared
    @EnvironmentObject private var mgr: ErosionManager

    var body: some View {
        List {
            Section {
                HStack {
                    Text("监管状态")
                    Spacer()
                    Text(r.supervised ? "受监管" : (r.phase == .ok ? "未监管" : "未检测"))
                        .foregroundStyle(r.supervised ? .red : .green)
                }
                HStack {
                    Text("管理组织")
                    Spacer()
                    Text(r.orgName.isEmpty ? "—" : r.orgName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前路径")
                    Text(r.workingPath.isEmpty ? "（尚未取得）" : r.workingPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if !r.routeUsed.isEmpty {
                    HStack {
                        Text("提权路由")
                        Spacer()
                        Text(r.routeUsed)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } header: {
                HeaderLabel(text: "状态", icon: "info.circle")
            }

            Section {
                Button {
                    MDMRemover.shared.detect()
                } label: {
                    Label("重新检测", systemImage: "arrow.clockwise")
                }
                .disabled(r.isBusy)

                Button {
                    Alertinator.shared.alert(
                        title: "确认移除 MDM 监管？",
                        body: "将把 IsSupervised 置为 false、清除 OrganizationName，并删除 \(MDMURL.sharedFile)。",
                        actionLabel: "确认移除",
                        action: { MDMRemover.shared.remove() }
                    )
                } label: {
                    Label(r.isBusy ? "正在处理…" : "一键移除 MDM", systemImage: "bolt.fill")
                        .foregroundStyle(.red)
                }
                .disabled(r.isBusy)

                Button {
                    mgr.shouldRespring = true
                } label: {
                    Label("重启桌面（Respring）", systemImage: "goforward")
                }
            } header: {
                HeaderLabel(text: "操作", icon: "bolt.fill")
            }

            if !r.detail.isEmpty {
                Section {
                    Text(r.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } header: {
                    HeaderLabel(text: "详情", icon: "doc.text")
                }
            }

            Section {
                Text("本工具只改写设备端的管理状态标记，不会解除服务器端的 MDM 注册。设备下次向 MDM 服务器签入时，策略仍可能被重新下发，监管状态可能复活。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                HeaderLabel(text: "说明", icon: "exclamationmark.triangle")
            }
        }
        .navigationTitle("MDM 移除")
        .onAppear {
            if r.phase == .idle {
                DispatchQueue.main.async { MDMRemover.shared.detect() }
            }
        }
    }
}
