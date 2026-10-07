//
//  ConfigView.swift
//  Erosion
//
//  Created by lunginspector on 8/21/26.
//

import SwiftUI
import PartyUI

enum FSURL {
    static var sysGroup = URL(fileURLWithPath: "/private/var/containers/Shared/SystemGroup")
    static var configProfiles = FSURL.sysGroup.appendingPathComponent("systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles")
}

enum CNURL {
    static var sharedDevConfig = FSURL.configProfiles.appendingPathComponent("SharedDeviceConfiguration.plist")
    static var cloudConfig = FSURL.configProfiles.appendingPathComponent("CloudConfigurationDetails.plist")
}

enum CNMsg {
    static var supWarning = "如果你的设备已配置 MDM，请不要改动这个开关！另外请注意：所有用户在重启桌面后都可能看到一个设置引导界面。请自行承担风险。"
    static var resetInfo = "点击“确认”后，锁屏脚注将被移除，设备将变为未受监管状态。"
}

struct ConfigView: View {
    @EnvironmentObject private var mgr: ErosionManager
    @AppStorage("showTips") private var showTips = true
    @State private var ftCurrentDict = NSMutableDictionary()
    @State private var ccCurrentDict = NSMutableDictionary()
    @State private var footnoteText = ""
    @State private var supervised = false
    @State private var orgName = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 14) {
                        HStack {
                            Image(systemName: "flashlight.off.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 26, height: 26)
                                .padding()
                                .modifier(QuickActionBackground())
                            Spacer()
                            Image(systemName: "camera.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 26, height: 26)
                                .padding()
                                .modifier(QuickActionBackground())
                        }
                        .padding(.horizontal, 35)
                        
                        VStack {
                            Text(footnoteText)
                                .font(.system(size: 9))
                                .frame(height: 10)
                            Capsule()
                                .frame(width: 145, height: 4)
                        }
                    }
                    .padding(.top, 25)
                    .padding(.bottom, 10)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(
                        Group {
                            Image("solarium")
                                .resizable()
                                .scaledToFill()
                                .offset(y: 10)
                        }
                    )
                    
                    TextField("自定义锁屏脚注", text: $footnoteText)
                }
                
                Section {
                    PlainToggle(text: "启用监管（Supervision）", infoType: .warning, infoTitle: "监管警告", infoMessage: CNMsg.supWarning, isOn: $supervised)
                    if supervised {
                        TextField("组织名称", text: $orgName)
                    }
                } header: {
                    HeaderLabel(text: "监管状态", icon: "eye")
                }
            }
            .navigationTitle("配置调整")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if showTips {
                            Alertinator.shared.alert(title: "确认要恢复调整吗？", body: CNMsg.resetInfo, actionLabel: "确认", action: {
                                reset()
                            })
                        } else {
                            reset()
                        }
                    } label: {
                        Label("恢复调整", systemImage: "gobackward")
                            .labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("应用", role: .adaptiveConfirm) {
                        apply()
                    }
                }
            }
            .onAppear {
                doSetup()
            }
        }
    }
    
    private func doSetup() {
        if !fm.isWritableFile(atPath: CNURL.sharedDevConfig.path) {
            let res = bq.grantAccess(atPath: FSURL.configProfiles.path)
            if !res.0 {
                Alertinator.shared.alert(title: "无法获取写入权限！", body: AppMsg.opFailed)
                return
            }
        }
        if !fm.fileExists(atPath: CNURL.sharedDevConfig.path) {
            do {
                let dict = ["LockScreenFootnote" : ""]
                let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
                try data.write(to: CNURL.sharedDevConfig)
            } catch {
                print("(ft) failed to create footnote file: \(error)")
                Alertinator.shared.alert(title: "创建脚注文件失败！", body: AppMsg.opFailed)
            }
        }
        loadData()
    }
    
    private func loadData() {
        if let ftDict = NSMutableDictionary(contentsOf: CNURL.sharedDevConfig) {
            ftCurrentDict = ftDict
            footnoteText = ftDict["LockScreenFootnote"] as? String ?? ""
        }
        if let ccDict = NSMutableDictionary(contentsOf: CNURL.cloudConfig) {
            ccCurrentDict = ccDict
            supervised = ccDict["IsSupervised"] as? Bool ?? false
            orgName = ccDict["OrganizationName"] as? String ?? ""
        }
    }
    
    private func apply() {
        let ftDict = ["LockScreenFootnote" : footnoteText]
        ccCurrentDict["IsSupervised"] = supervised
        ccCurrentDict["OrganizationName"] = orgName
        do {
            let ftData = try PropertyListSerialization.data(fromPropertyList: ftDict, format: .binary, options: 0)
            try ftData.write(to: CNURL.sharedDevConfig)
            let ccData = try PropertyListSerialization.data(fromPropertyList: ccCurrentDict, format: .binary, options: 0)
            try ccData.write(to: CNURL.cloudConfig)
            print("(cn) successfully applied config tweaks!")
            Haptic.shared.play(.soft)
            if showTips {
                Alertinator.shared.alert(title: "配置调整已应用！", body: AppMsg.applied, actionLabel: "重启桌面", action: { mgr.shouldRespring = true })
            }
        } catch {
            print("(cn) failed to write config files: \(error)")
            Alertinator.shared.alert(title: "应用失败！", body: AppMsg.opFailed)
        }
    }
    
    private func reset() {
        ccCurrentDict["IsSupervised"] = false
        ccCurrentDict.removeObject(forKey: "OrganizationName")
        do {
            try fm.removeItem(at: CNURL.sharedDevConfig)
            let ccData = try PropertyListSerialization.data(fromPropertyList: ccCurrentDict, format: .binary, options: 0)
            try ccData.write(to: CNURL.cloudConfig)
            print("(cn) successfully reset config tweaks!")
            Haptic.shared.play(.soft)
            loadData()
            footnoteText = ""
            if showTips {
                Alertinator.shared.alert(title: "配置已恢复！", body: AppMsg.applied, actionLabel: "重启桌面", action: { mgr.shouldRespring = true })
            }
        } catch {
            print("(cn) failed to reset config files: \(error)")
            Alertinator.shared.alert(title: "恢复失败！", body: AppMsg.opFailed)
        }
    }
}

// MARK: ui
struct QuickActionBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 19.0, *) {
            content
                .glassEffect(.clear.interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: .circle)
        }
    }
}
