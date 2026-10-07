//
//  SettingsView.swift
//  Erosion
//
//  Created by lunginspector on 8/20/26.
//

import SwiftUI
import PartyUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("showTips") private var showTips = true
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    AppInfoCell(build: build)
                    NavigationLink("致谢") {
                        List {
                            LinkCreditCell(image: Image("lunginspector"), name: "lunginspector", description: "主要开发者。", url: "https://github.com/lunginspector")
                            LinkCreditCell(image: Image("forcequit"), name: "forcequit", description: "本应用依赖的 bad_query 沙箱逃逸漏洞作者。", url: "https://github.com/forcequitOS/bad_query")
                            LinkCreditCell(image: Image("rooootdev"), name: "rooootdev", description: "来自 mond 的部分后端实现。", url: "https://github.com/rooootdev/mond")
                        }
                        .navigationTitle("致谢")
                    }
                } footer: {
                    Text("Made with love by the [jailbreak.party](https://jailbreak.party) team.\nJoin the [jailbreak.party](https://jailbreak.party/discord) Discord!")
                }
                
                Section {
                    Toggle("显示操作提示", isOn: $showTips)
                } header: {
                    HeaderLabel(text: "显示选项", icon: "eyes")
                } footer: {
                    Text("关闭后，执行某些操作将不再弹出说明与确认提示。")
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        ToolbarLabel("关闭", icon: "xmark")
                    }
                }
            }
        }
    }
}
