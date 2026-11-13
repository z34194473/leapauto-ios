//
//  SettingsView.swift
//  设置页：账号 / 车辆 / 诊断 / 关于
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: LeapModel
    @State private var showLogoutConfirm = false
    @State private var showDiagnostics = false
    @State private var showAdvanced = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                accountCard
                vehicleCard
                refreshCard
                if showAdvanced { advancedCard }
                aboutCard
                logoutCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(Theme.bg.ignoresSafeArea())
        .alert("确认退出登录？", isPresented: $showLogoutConfirm) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { model.logout() }
        } message: {
            Text("将清除本机保存的账号令牌与车辆信息")
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsSheet()
        }
    }

    // ---------------------------------------------------------- 账号

    private var accountCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.brand.opacity(0.18)).frame(width: 44, height: 44)
                        Image(systemName: "person.fill")
                            .font(.system(size: 17))
                            .foregroundColor(Theme.brand)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(maskedAccount)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.text)
                        Text(model.api.isLoggedIn ? "已登录" : "未登录")
                            .font(.system(size: 11.5))
                            .foregroundColor(model.api.isLoggedIn ? Theme.green : Theme.textFaint)
                    }
                    Spacer()
                }

                Divider().background(Color.white.opacity(0.07))

                InfoRow(title: "网关账号", value: shortId(model.api.newAuth?.accountId), icon: "number")
                InfoRow(title: "Token 到期", value: expiryText, icon: "clock")
                InfoRow(title: "deviceId", value: shortId(model.api.deviceId, 10), icon: "iphone")
            }
        }
    }

    private var maskedAccount: String {
        let phone = model.api.phone
        if phone.count == 11 {
            return phone.prefix(3) + "****" + phone.suffix(4)
        }
        return phone.isEmpty ? "零跑账号" : phone
    }

    private func shortId(_ value: String?, _ keep: Int = 8) -> String {
        guard let value = value, !value.isEmpty else { return "-" }
        if value.count <= keep { return value }
        return String(value.prefix(keep)) + "…"
    }

    private var expiryText: String {
        guard let at = model.api.newAuth?.accessTokenExpiresAt, at > 0 else { return "-" }
        let date = Date(timeIntervalSince1970: Double(at) / 1000)
        let remain = date.timeIntervalSinceNow
        if remain <= 0 { return "已过期" }
        let hours = Int(remain / 3600)
        let mins = Int(remain.truncatingRemainder(dividingBy: 3600) / 60)
        return hours > 0 ? "\(hours) 小时 \(mins) 分" : "\(mins) 分"
    }

    // ---------------------------------------------------------- 车辆

    private var vehicleCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "当前车辆", trailing: "\(model.vehicles.count) 台")
                if let v = model.selectedVehicle {
                    InfoRow(title: "名称", value: v.title, icon: "car.fill")
                    InfoRow(title: "车型", value: v.carType.isEmpty ? "-" : v.carType, icon: "tag.fill")
                    InfoRow(title: "VIN", value: String(v.vin.suffix(8)), icon: "number")
                } else {
                    Text("暂无车辆")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textFaint)
                        .padding(.vertical, 8)
                }
                Button {
                    Task { await model.loadVehicles() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12))
                        Text("刷新车辆列表").font(.system(size: 13.5, weight: .medium))
                    }
                    .foregroundColor(Theme.brand)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ---------------------------------------------------------- 刷新

    private var refreshCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "刷新")
                Toggle(isOn: Binding(
                    get: { model.autoRefresh },
                    set: { _ in model.toggleAutoRefresh() }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动刷新车况")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textDim)
                        Text("每 30 秒拉取一次，仅前台生效")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textFaint)
                    }
                }
                .tint(Theme.brand)

                if let last = model.lastRefresh {
                    HStack {
                        Text("上次更新")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textFaint)
                        Spacer()
                        Text(timeText(last))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textDim)
                    }
                }
            }
        }
    }

    private func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    // ---------------------------------------------------------- 高级

    private var advancedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "高级")
                Toggle(isOn: $model.autoRefresh) {
                    Text("内部开关")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textDim)
                }
                .hidden()
                .frame(height: 0)

                Button {
                    showDiagnostics = true
                } label: {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textFaint)
                            .frame(width: 18)
                        Text("诊断信息")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textDim)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Theme.textFaint)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ---------------------------------------------------------- 关于

    private var aboutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "关于")
                InfoRow(title: "版本", value: "1.0.0", icon: "info.circle")
                InfoRow(title: "协议来源", value: "Android 4.5.15", icon: "doc.text")
                InfoRow(title: "签名版本", value: "MD5 / HMAC-SHA256", icon: "key.horizontal")
                InfoRow(title: "蓝牙加密", value: "AES-128 / SM4", icon: "lock.rotation")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
                } label: {
                    HStack {
                        Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                        Text(showAdvanced ? "隐藏高级选项" : "显示高级选项")
                            .font(.system(size: 12.5))
                    }
                    .foregroundColor(Theme.textFaint)
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ---------------------------------------------------------- 退出

    private var logoutCard: some View {
        Button {
            showLogoutConfirm = true
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14))
                Text("退出登录")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(Theme.red)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.red.opacity(0.12))
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// ============================================================ 诊断面板

struct DiagnosticsSheet: View {
    @EnvironmentObject var model: LeapModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filteredKeys: [String] {
        let keys = model.status.raw.keys.sorted()
        if search.isEmpty { return keys }
        return keys.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        summaryCard
                        signalCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("诊断信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(Theme.textDim)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        model.copyDiagnostics()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(Theme.brand)
                    }
                }
            }
        }
        .presentationBackground(Theme.bg)
    }

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: "运行状态")
                InfoRow(title: "deviceId", value: model.api.deviceId, icon: "iphone")
                InfoRow(title: "smDeviceId",
                        value: model.api.smDeviceId.isEmpty ? "(空)" : String(model.api.smDeviceId.prefix(16)) + "…",
                        icon: "shield")
                InfoRow(title: "VIN", value: model.api.selectedVin.isEmpty ? "-" : model.api.selectedVin,
                        icon: "car.fill")
                InfoRow(title: "carType", value: model.api.selectedCarType.isEmpty ? "-" : model.api.selectedCarType,
                        icon: "tag.fill")
                InfoRow(title: "路由", value: model.api.route?.appRegion ?? "-", icon: "network")
                InfoRow(title: "蓝牙", value: "\(model.ble.phase.label) · MTU \(model.ble.mtu)",
                        icon: "antenna.radiowaves.left.and.right")
                InfoRow(title: "信号字段", value: "\(model.status.raw.count) 个", icon: "list.bullet")
            }
        }
    }

    private var signalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "原始信号值")

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textFaint)
                    TextField("搜索字段", text: $search)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Theme.text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )

                if filteredKeys.isEmpty {
                    Text("暂无数据，请先刷新车况")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textFaint)
                        .padding(.vertical, 10)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(filteredKeys, id: \.self) { key in
                            HStack(alignment: .top, spacing: 8) {
                                Text(key)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(Theme.brand.opacity(0.85))
                                    .frame(width: 120, alignment: .leading)
                                Text(String(describing: model.status.raw[key] ?? "-"))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(Theme.textDim)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.28))
                    )
                }
            }
        }
    }
}
