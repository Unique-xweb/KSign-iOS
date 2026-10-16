// [LISTN] Sources/KSignApp/Views/MainTabView.swift
// Language: Swift 5.9 | File: MainTabView.swift | Target: Primary 4-Tab Navigation Shell
import SwiftUI

public struct MainTabView: View {
    @State private var selectedTab: Int = 0

    public var body: some View {
        TabView(selection: $selectedTab) {
            FilesView()
                .tabItem {
                    Label("Files", systemImage: "folder.fill")
                }
                .tag(0)

            AppsView()
                .tabItem {
                    Label("Apps", systemImage: "square.stack.3d.up.fill")
                }
                .tag(1)

            CertificatesView()
                .tabItem {
                    Label("Certificates", systemImage: "checkmark.seal.fill")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .accentColor(.blue)
    }
}
