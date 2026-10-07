//
//  ContentView.swift
//  Erosion
//
//  Created by lunginspector on 8/14/26.
//

import SwiftUI
import PartyUI

struct ContentView: View {
    @AppStorage("ogMachineName") var ogMachineName = ""
    @EnvironmentObject var mgr: ErosionManager
    @State private var showSettings = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    MDMCard()
                } header: {
                    HeaderLabel(text: "一键操作", icon: "bolt.fill")
                }
                
                Section {
                    LogView()
                        .modifier(TerminalPlatter())
                } header: {
                    HeaderLabel(text: "运行日志 · 版本 0.1 (\(build))", icon: "info.circle")
                } footer: {
                    Text("Made with love by the [jailbreak.party](https://jailbreak.party/) team. Thanks to forcequitOS for the [bad_query](https://github.com/forcequitOS/bad_query) sandbox escape that this app relies on.")
                }
                
                Section {
                    NavigationLink("MDM 详情与手动操作", destination: MDMView())
                    NavigationLink("配置调整（监管 / 锁屏脚注）", destination: ConfigView())
                    if mgSupported() || weOnADebugBuild {
                        NavigationLink("功能特性（MobileGestalt）", destination: GestaltView())
                    }
                    NavigationLink("自定义壁纸", destination: PosterBoardView())
                    NavigationLink("文件操作（覆盖 / 删除）", destination: OperationsView())
                } header: {
                    HeaderLabel(text: "功能", icon: "wrench.and.screwdriver")
                }
            }
            .navigationTitle("Erosion")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        mgr.shouldRespring = true
                    } label: {
                        Label("重启桌面", systemImage: "goforward")
                            .labelStyle(.iconOnly)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("设置", systemImage: "gear")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onAppear {
                if ogMachineName.isEmpty {
                    ogMachineName = machineName()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
