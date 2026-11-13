//
//  BluetoothView.swift
//  蓝牙钥匙页：证书同步 / 扫描 / 连接 / 认证 / 控车 / 诊断
//

import SwiftUI
import Foundation

struct BluetoothView: View {
    @EnvironmentObject var model: LeapModel

    private var ble: BluetoothKeyController { model.ble }

    var body: some View {
        BluetoothBody(model: model, ble: ble)
    }
}

/// 用独立结构持有 ObservedObject，确保视图刷新跟随蓝牙控制器
struct BluetoothBody: View {
    @ObservedObject var model: LeapModel
    @ObservedObject var ble: BluetoothKeyController

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusCard
                actionCard
                if !ble.devices.isEmpty { deviceList }
                if ble.phase == .ready || ble.phase == .sending { controlCard }
                logCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    // ---------------------------------------------------------- 状态

    private var statusCard: some View {
        Card {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(phaseColor.opacity(0.16))
                            .frame(width: 46, height: 46)
                        Image(systemName: phaseIcon)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(phaseColor)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ble.phase.label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.text)
                        Text(ble.message.isEmpty ? statusHint : ble.message)
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.textFaint)
                            .lineLimit(2)
                    }
                    Spacer()
                }

                if ble.phase.isBusy {
                    ProgressView().tint(Theme.brand)
                }

                HStack(spacing: 8) {
                    chip("MTU \(ble.mtu)", "antenna.radiowaves.left.and.right")
                    chip(ble.hasCertificate ? "证书就绪" : "未同步证书",
                         ble.hasCertificate ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    if !ble.connectedName.isEmpty {
                        chip(ble.connectedName, "car.fill")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var statusHint: String {
        switch ble.phase {
        case .idle:
            return ble.hasCertificate ? "点击扫描搜索车辆" : "请先同步蓝牙钥匙证书"
        case .failed:
            return "可重新同步证书或重新扫描"
        default:
            return "请保持 App 在前台"
        }
    }

    private var phaseColor: Color {
        switch ble.phase {
        case .ready: return Theme.green
        case .sending, .authenticating, .configuring: return Theme.blue
        case .failed: return Theme.red
        case .scanning, .connecting, .discovering, .subscribing: return Theme.orange
        case .idle: return Theme.textDim
        }
    }

    private var phaseIcon: String {
        switch ble.phase {
        case .ready: return "checkmark.shield.fill"
        case .sending: return "arrow.up.circle.fill"
        case .authenticating: return "lock.rotation"
        case .configuring: return "slider.horizontal.3"
        case .failed: return "exclamationmark.triangle.fill"
        case .scanning: return "dot.radiowaves.left.and.right"
        case .connecting, .discovering, .subscribing: return "antenna.radiowaves.left.and.right"
        case .idle: return "bluetooth"
        }
    }

    private func chip(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(Theme.textFaint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    // ---------------------------------------------------------- 操作

    private var actionCard: some View {
        Card {
            VStack(spacing: 10) {
                if !ble.hasCertificate {
                    PrimaryButton(title: "同步蓝牙钥匙证书",
                                  icon: "arrow.down.doc.fill",
                                  enabled: !model.isBusy && model.isLoggedIn) {
                        Task { await model.syncBleCertificate() }
                    }
                    Text("首次使用需从云端下发证书；证书与账号和设备绑定")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textFaint)
                } else {
                    HStack(spacing: 10) {
                        PrimaryButton(title: ble.phase == .scanning ? "扫描中…" : "扫描车辆",
                                      icon: "dot.radiowaves.left.and.right",
                                      enabled: !ble.phase.isBusy && model.isLoggedIn) {
                            ble.startScan()
                        }
                        PrimaryButton(title: "断开",
                                      icon: "bolt.slash.fill",
                                      enabled: ble.phase != .idle,
                                      color: Color.white.opacity(0.14)) {
                            ble.disconnect()
                        }
                    }
                    PrimaryButton(title: "重新同步证书",
                                  icon: "arrow.clockwise",
                                  enabled: !model.isBusy && model.isLoggedIn,
                                  color: Theme.cardHi) {
                        Task { await model.syncBleCertificate() }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- 设备列表

    private var deviceList: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "附近车辆", trailing: "\(ble.devices.count) 台")
                ForEach(ble.devices) { device in
                    Button {
                        Task { await model.bleConnect(device) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "car.side.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.brand)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.displayName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Theme.text)
                                Text("协议 v\(device.protocolMinor) · \(device.rssi) dBm")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(Theme.textFaint)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Theme.textFaint)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(ble.phase.isBusy)
                }
            }
        }
    }

    // ---------------------------------------------------------- 控车

    private var controlCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "蓝牙控车")
                HStack(spacing: 10) {
                    ActionButton(title: "蓝牙解锁",
                                 icon: "lock.open.fill",
                                 active: ble.confirmedAction == .unlock,
                                 tint: Theme.orange,
                                 disabled: ble.phase != .ready) {
                        model.bleControl(.unlock)
                    }
                    ActionButton(title: "蓝牙上锁",
                                 icon: "lock.fill",
                                 active: ble.confirmedAction == .lock,
                                 tint: Theme.green,
                                 disabled: ble.phase != .ready) {
                        model.bleControl(.lock)
                    }
                }
                if let action = ble.pendingAction {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7).tint(Theme.brand)
                        Text("正在执行\(action.label)…")
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.textFaint)
                    }
                }
                Text("蓝牙直连不依赖蜂窝网络，靠近车辆即可使用")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textFaint)
            }
        }
    }

    // ---------------------------------------------------------- 日志

    private var logCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "蓝牙诊断", trailing: "\(ble.logs.count) 条")
                if ble.logs.isEmpty {
                    Text("暂无记录")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textFaint)
                        .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(ble.logs.prefix(16))) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(timeText(entry.time))
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundColor(Theme.textFaint)
                                Text(entry.text)
                                    .font(.system(size: 11))
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
                            .fill(Color.black.opacity(0.25))
                    )
                }
            }
        }
    }

    private func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
