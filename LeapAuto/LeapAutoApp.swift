//
//  LeapAutoApp.swift
//  入口与根视图
//

import SwiftUI

@main
struct LeapAutoApp: App {
    @StateObject private var model = LeapModel()

    init() {
        // 导航栏 / 标签栏统一深色外观
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.bg)
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.card)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Theme.brand)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: LeapModel

    var body: some View {
        Group {
            switch model.route {
            case .login:
                LoginView()
                    .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.route)
    }
}

struct MainTabView: View {
    @EnvironmentObject var model: LeapModel
    @State private var selection: Tab = .home

    enum Tab: Hashable { case home, control, bluetooth, settings }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView()
                    .navigationTitle("车辆")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbarContent }
            }
            .tabItem { Label("车辆", systemImage: "car.fill") }
            .tag(Tab.home)

            NavigationStack {
                ControlView()
                    .navigationTitle("控制")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbarContent }
            }
            .tabItem { Label("控制", systemImage: "slider.horizontal.3") }
            .tag(Tab.control)

            NavigationStack {
                BluetoothView()
                    .navigationTitle("蓝牙钥匙")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("蓝牙钥匙", systemImage: "key.fill") }
            .tag(Tab.bluetooth)

            NavigationStack {
                SettingsView()
                    .navigationTitle("设置")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("设置", systemImage: "gearshape.fill") }
            .tag(Tab.settings)
        }
        .overlay(alignment: .bottom) { BannerHost() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                Task { await model.refresh() }
            } label: {
                if model.isBusy {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(Theme.brand)
                }
            }
            .disabled(model.isBusy)
        }
    }
}
