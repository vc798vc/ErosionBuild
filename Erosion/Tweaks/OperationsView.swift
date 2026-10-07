//
//  OperationsView.swift
//  Erosion
//
//  Created by lunginspector on 8/17/26.
//

import SwiftUI
import UniformTypeIdentifiers
import PartyUI

struct OperationsView: View {
    @State private var directory = ""
    @State private var fileName = ""
    @State private var isAcc = false
    @State private var showImporter = false
    
    @State private var imprtName = ""
    @State private var imprtData = Data()
    
    var body: some View {
        List {
            Section {
                TextField("目录", text: $directory)
                    .disabled(isAcc)
                TextField("文件名", text: $fileName)
                    .disabled(isAcc)
                HStack {
                    Button("获取访问权限") {
                        let res = bq.grantAccess(atPath: directory, toFileName: fileName)
                        if !res.0 {
                            Alertinator.shared.alert(title: "无法访问目标文件！", body: "\(res.1): \(res.2)")
                        } else {
                            isAcc = true
                        }
                    }
                    .disabled(isAcc)
                    if isAcc {
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark")
                            Text("已获得权限")
                        }
                        .foregroundStyle(.green)
                    }
                }
                if isAcc {
                    Button("更改路径", role: .destructive) {
                        isAcc = false
                        imprtName = ""
                        imprtData = Data()
                    }
                    
                    Button("导出文件") {
                        let fileDir = "\(directory)/\(fileName)"
                        presentShareSheet(with: URL(fileURLWithPath: fileDir))
                    }
                }
            } header: {
                HeaderLabel(text: "目标", icon: "dot.scope")
            }
            
            Section {
                HStack {
                    Button("导入文件") {
                        showImporter = true
                    }
                    .disabled(!imprtData.isEmpty)
                    if !imprtName.isEmpty {
                        Spacer()
                        Text(imprtName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                
                Button("覆盖写入") {
                    do {
                        let targetURL = URL(fileURLWithPath: "\(directory)/\(fileName)")
                        try imprtData.write(to: targetURL)
                        print("(ov) successfully overwrote file: \(targetURL.path) (\(imprtData.count))")
                        Haptic.shared.play(.soft)
                    } catch {
                        print("(ov) failed to overwrite: \(error)")
                        Alertinator.shared.alert(title: "覆盖文件失败！", body: "请确认路径填写正确且已成功获取访问权限。详细错误可查看主界面日志。")
                    }
                }
                .disabled(imprtData.isEmpty)
                
                Button("移动写入") {
                    do {
                        let targetURL = URL(fileURLWithPath: "\(directory)").appendingPathComponent(imprtName)
                        try imprtData.write(to: targetURL)
                        print("(ov) successfully moved file: \(imprtName) -> \(targetURL.path)")
                        Haptic.shared.play(.soft)
                    } catch {
                        print("(ov) failed to move: \(error)")
                        Alertinator.shared.alert(title: "移动文件失败！", body: "请确认路径填写正确且已成功获取访问权限。详细错误可查看主界面日志。")
                    }
                }
                .disabled(imprtData.isEmpty)
                
                Button("删除文件", role: .destructive) {
                    do {
                        let targetURL = URL(fileURLWithPath: "\(directory)/\(fileName)")
                        try fm.removeItem(at: targetURL)
                        print("(ov) successfully deleted file: \(targetURL.path)")
                        Haptic.shared.play(.heavy)
                    } catch {
                        print("(ov) failed to delete: \(error)")
                        Alertinator.shared.alert(title: "删除文件失败！", body: "请确认路径填写正确且已成功获取访问权限。详细错误可查看主界面日志。")
                    }
                }
                .disabled(imprtData.isEmpty)
            } header: {
                HeaderLabel(text: "操作", icon: "wrench.and.screwdriver")
            }
        }
        .navigationTitle("文件操作")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
            handleImport(result)
        }
    }
    
    func handleImport(_ res: Result<URL, Error>) {
        switch res {
        case .success(let recURL):
            do {
                let stopAccess = recURL.startAccessingSecurityScopedResource()
                defer {
                    if stopAccess {
                        recURL.stopAccessingSecurityScopedResource()
                    }
                }
                
                imprtData = try Data(contentsOf: recURL)
                imprtName = recURL.lastPathComponent
            } catch {
                print("(ov) failed to import file: \(error)")
                Alertinator.shared.alert(title: "导入文件失败！", body: "该文件可能无效、已损坏或无法读取，请换一个文件重试。")
            }
        case .failure(let error):
            print("(ov) failed to import file: \(error)")
            Alertinator.shared.alert(title: "导入文件失败！", body: "该文件可能无效、已损坏或无法读取，请换一个文件重试。")
        }
    }
}
