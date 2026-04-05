//
//  WhitelistView.swift
//  lara
//
//  Created by ruter on 29.03.26.
//

import SwiftUI

struct WhitelistView: View {
    @ObservedObject private var mgr = laramgr.shared

    private struct wlfile: Identifiable {
        let id = UUID()
        let name: String
        let path: String
    }

    private let files: [wlfile] = [
        .init(name: "Rejections.plist", path: "/private/var/db/MobileIdentityData/Rejections.plist"),
        .init(name: "AuthListBannedUpps.plist", path: "/private/var/db/MobileIdentityData/AuthListBannedUpps.plist"),
        .init(name: "AuthListBannedCdHashes.plist", path: "/private/var/db/MobileIdentityData/AuthListBannedCdHashes.plist"),
    ]

    @State private var contents: [String: String] = [:]
    @State private var status: String?
    @State private var patching = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        loadall()
                    } label: {
                        if patching {
                            HStack {
                                ProgressView()
                                Text("Working...")
                            }
                        } else {
                            Text("Refresh")
                        }
                    }
                    .disabled(!mgr.sbxready || patching)

                    Button("Patch (Empty Plist)") {
                        patchall()
                    }
                    .disabled(!mgr.sbxready || patching)
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Overwrites MobileIdentityData blacklist files with an empty plist.")
                }

                if 1 == 2 {
                    ForEach(files) { f in
                        Section {
                            ScrollView {
                                Text(contents[f.path] ?? "(not loaded)")
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .frame(minHeight: 120)
                        } header: {
                            Text(f.name)
                        } footer: {
                            Text(f.path)
                        }
                    }
                }
            }
            .navigationTitle("Whitelist")
            .alert("Status", isPresented: .constant(status != nil)) {
                Button("OK") { status = nil }
            } message: {
                Text(status ?? "")
            }
            .onAppear {
                if mgr.sbxready {
                    loadall()
                }
            }
        }
    }

    private func loadall() {
        guard mgr.sbxready else {
            status = "sandbox escape not ready"
            return
        }
        patching = true
        defer { patching = false }
        var next: [String: String] = [:]
        for f in files {
            guard let data = sbxread(path: f.path, maxSize: 2 * 1024 * 1024) else {
                next[f.path] = "(failed to read)"
                continue
            }
            next[f.path] = render(data: data)
        }
        contents = next
    }

    private func patchall() {
        guard mgr.sbxready else {
            status = "sandbox escape not ready"
            return
        }
        patching = true
        defer { patching = false }

        let emptyPlist = """
        [
            
        ]
        """

        guard let data = emptyPlist.data(using: .utf8) else {
            status = "failed to build empty plist"
            return
        }

        var failures: [String] = []
        for f in files {
            let ok = sbxwrite(path: f.path, data: data)
            if !ok { failures.append(f.name) }
        }

        if failures.isEmpty {
            status = "patched all files"
        } else {
            status = "failed to patch: \(failures.joined(separator: ", "))"
        }

        loadall()
    }

    private func sbxread(path: String, maxSize: Int) -> Data? {
        do {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            if data.count > maxSize {
                return data.prefix(maxSize)
            }
            return data
        } catch {
            return nil
        }
    }

    private func sbxwrite(path: String, data: Data) -> Bool {
        do {
            let url = URL(fileURLWithPath: path)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func render(data: Data) -> String {
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let xmlData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
           let xml = String(data: xmlData, encoding: .utf8) {
            return xml
        }

        if let s = String(data: data, encoding: .utf8) {
            return s
        }

        let maxBytes = min(data.count, 4096)
        let hex = data.prefix(maxBytes).map { String(format: "%02x", $0) }.joined(separator: " ")
        if data.count > maxBytes {
            return hex + "\n... (\(data.count) bytes total)"
        }
        return hex
    }
}
