//
//  LeapModel.swift
//  全局状态与动作（MVVM 的 VM 层）
//

import Foundation
import SwiftUI
import Combine
import UIKit

enum AppRoute: Hashable {
    case login
    case main
}

@MainActor
final class LeapModel: ObservableObject {
    // ---------------------------------------------------------- 依赖

    let api: LeapAPI
    let ble: BluetoothKeyController

    // ---------------------------------------------------------- 登录态

    @Published var route: AppRoute = .login
    @Published var phone = ""
    @Published var smsCode = ""
    @Published var smDeviceIdInput = ""
    @Published var rawAuthText = ""
    @Published var pin = ""

    // ---------------------------------------------------------- 数据

    @Published private(set) var vehicles: [Vehicle] = []
    @Published private(set) var status: LeapStatus = LeapStatus(raw: [:])
    @Published private(set) var chassisPhoto: ChassisPhoto?
    @Published private(set) var scheduledAc: ScheduledAcPlan = ScheduledAcPlan()

    // ---------------------------------------------------------- 界面状态

    @Published var busyCount = 0
    @Published var banner: Banner?
    @Published var lastRefresh: Date?
    @Published var autoRefresh = false

    /// 极验人机验证协调器
    let geetest = GeetestCoordinator()

    private var refreshTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    var isBusy: Bool { busyCount > 0 }
    var isLoggedIn: Bool { api.isLoggedIn }
    var selectedVehicle: Vehicle? {
        vehicles.first { $0.vin == api.selectedVin }
    }

    struct Banner: Identifiable, Equatable {
        enum Kind { case info, success, warning, error }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    init() {
        let api = LeapAPI()
        self.api = api
        let controller = BluetoothKeyController()
        self.ble = controller
        self.phone = api.phone
        self.smDeviceIdInput = api.smDeviceId
        self.route = api.isLoggedIn ? .main : .login
        controller.attach(api: api)
        controller.start()
    }

    // ---------------------------------------------------------- 提示

    func show(_ kind: Banner.Kind, _ text: String) {
        bannerTask?.cancel()
        banner = Banner(kind: kind, text: text)
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            self?.clearBanner(text)
        }
    }

    private func clearBanner(_ text: String) {
        if banner?.text == text { banner = nil }
    }

    // ---------------------------------------------------------- 忙碌包装

    func perform<T>(_ label: String, _ work: @escaping () async throws -> T) async -> T? {
        busyCount += 1
        defer { busyCount -= 1 }
        do {
            return try await work()
        } catch {
            show(.error, "\(label)失败：\(error.localizedDescription)")
            return nil
        }
    }

    // ---------------------------------------------------------- 登录

    func sendSms() async {
        let target = phone.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { show(.warning, "请先输入手机号"); return }
        await perform("发送验证码") { [self] in
            try await self.api.sendSms(phone: target)
        }
        if busyCount == 0 { show(.success, "验证码已发送") }
    }

    func loginWithSms() async {
        guard !smsCode.trimmingCharacters(in: .whitespaces).isEmpty else {
            show(.warning, "请输入验证码")
            return
        }
        await performSmsLogin(captcha: nil)
    }

    /// 极验验证完成后重试登录
    func loginWithSms(captcha: GeetestResult) async {
        await performSmsLogin(captcha: captcha)
    }

    private func performSmsLogin(captcha: GeetestResult?) async {
        busyCount += 1
        defer { busyCount -= 1 }
        do {
            let outcome = try await api.loginWithSms(phone: phone,
                                                     code: smsCode,
                                                     captcha: captcha)
            switch outcome {
            case .needCaptcha(let riskType):
                // 弹出人机验证，完成后重试
                geetest.begin(riskType: riskType) { [weak self] result in
                    guard let self = self else { return }
                    guard let result = result else {
                        self.show(.warning, "已取消安全验证")
                        return
                    }
                    Task { await self.loginWithSms(captcha: result) }
                }
            case .success:
                applySmDevice()
                show(.success, "登录成功")
                route = .main
                await bootstrap()
            }
        } catch {
            show(.error, error.localizedDescription)
        }
    }

    func importCredentials() async {
        busyCount += 1
        defer { busyCount -= 1 }
        do {
            try await api.loginWithRawAuth(rawAuthText, phone: phone)
            show(.success, "凭据导入成功")
            route = .main
            await bootstrap()
        } catch {
            show(.error, error.localizedDescription)
        }
    }

    private func applySmDevice() {
        let v = smDeviceIdInput.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty { api.setSmDeviceId(v) }
    }

    func logout() {
        refreshTask?.cancel()
        ble.disconnect()
        api.reset()
        vehicles = []
        status = LeapStatus(raw: [:])
        chassisPhoto = nil
        lastRefresh = nil
        rawAuthText = ""
        smsCode = ""
        route = .login
        show(.info, "已退出并清除本地凭据")
    }

    // ---------------------------------------------------------- 启动加载

    func bootstrap() async {
        guard api.isLoggedIn else { return }
        ble.start()
        await pairSmDeviceIfNeeded()
        _ = await loadVehicles()
        await refresh()
    }

    /// 若没有 smDeviceId，尝试用设备自身 id 兜底（云端通常接受）
    private func pairSmDeviceIfNeeded() async {
        if !api.smDeviceId.isEmpty { return }
        // iOS 无法生成数美设备号；保留空值，由服务端按 deviceID 判断
    }

    // ---------------------------------------------------------- 车辆与状态

    @discardableResult
    func loadVehicles() async -> Bool {
        do {
            let list = try await api.listVehicles()
            vehicles = list
            if list.isEmpty { show(.warning, "该账号下没有可用车辆") }
            return true
        } catch {
            show(.error, "拉取车辆失败：\(error.localizedDescription)")
            return false
        }
    }

    func selectVehicle(_ v: Vehicle) {
        api.selectVehicle(v)
        status = LeapStatus(raw: [:])
        chassisPhoto = nil
        Task { await refresh() }
    }

    func refresh() async {
        guard api.isLoggedIn, !api.selectedVin.isEmpty else { return }
        busyCount += 1
        defer { busyCount -= 1 }
        do {
            let decoded = try await api.getVehicleState()
            status = LeapStatus(raw: decoded)
            lastRefresh = Date()
        } catch {
            show(.error, "车况刷新失败：\(error.localizedDescription)")
        }
    }

    func loadChassisPhoto() async {
        guard api.isLoggedIn, !api.selectedVin.isEmpty else { return }
        do {
            chassisPhoto = try await api.getChassisPhoto()
            if chassisPhoto == nil { show(.info, "该车型暂无驻车照片") }
        } catch {
            show(.error, "获取驻车照片失败")
        }
    }

    // ---------------------------------------------------------- 控车

    func run(_ cmd: ControlCommand, successText: String? = nil) async {
        guard api.isLoggedIn else { show(.warning, "请先登录"); return }
        busyCount += 1
        defer { busyCount -= 1 }
        do {
            let result = try await api.sendControl(cmd, pin: pin)
            show(.success, successText ?? "\(cmd.label)已下发")
            if !result.msgID.isEmpty {
                await confirmControl(msgID: result.msgID, label: cmd.label)
            }
            await refresh()
        } catch {
            show(.error, error.localizedDescription)
        }
    }

    private func confirmControl(msgID: String, label: String) async {
        for attempt in 0..<4 {
            try? await Task.sleep(nanoseconds: UInt64(1_200_000_000 * (attempt + 1)))
            guard let resp = try? await api.queryControlResult(msgID: msgID) else { continue }
            let code = (resp["result"] as? String) ?? (resp["code"] as? String) ?? ""
            if code == "0" || code == "200" {
                let msg = (resp["msg"] as? String) ?? ""
                if !msg.isEmpty { show(.info, "\(label)：\(msg)") }
                return
            }
        }
    }

    // 空调
    func setAc(_ cmd: ControlCommand) async { await run(cmd) }

    // 座椅
    func setSeatHeating(_ position: String, level: Int) async {
        await run(LeapCommands.seatHeating(position, level: level))
    }
    func setSeatVentilation(_ position: String, level: Int) async {
        await run(LeapCommands.seatVentilation(position, level: level))
    }
    func setSteeringWheel(_ level: Int) async {
        await run(LeapCommands.steeringWheelHeating(level))
    }
    func setMirrorHeating(_ on: Bool) async {
        await run(on ? LeapCommands.mirrorHeatingOn : LeapCommands.mirrorHeatingOff)
    }
    func setFridge(_ on: Bool) async {
        await run(LeapCommands.fridge(enable: on))
    }

    // 预约
    func saveScheduledAc(_ plan: ScheduledAcPlan) async {
        busyCount += 1
        defer { busyCount -= 1 }
        do {
            _ = try await api.setScheduledAirConditioning(plan, pin: pin)
            scheduledAc = plan
            show(.success, plan.enabled ? "定时空调已设置" : "定时空调已取消")
        } catch {
            show(.error, error.localizedDescription)
        }
    }

    func loadScheduledAc() async {
        guard api.isLoggedIn, !api.selectedVin.isEmpty else { return }
        if let result = try? await api.getScheduledAirConditioning() {
            if result.has { scheduledAc = result.plan }
        }
    }

    func setScheduledCharging(enabled: Bool, start: String, end: String, soc: Int) async {
        busyCount += 1
        defer { busyCount -= 1 }
        do {
            _ = try await api.setScheduledCharging(enabled: enabled, startTime: start,
                                                   endTime: end, targetSoc: soc, pin: pin)
            show(.success, enabled ? "预约充电已设置" : "预约充电已关闭")
            await refresh()
        } catch {
            show(.error, error.localizedDescription)
        }
    }

    func setScheduledPreheat(enabled: Bool, start: String) async {
        busyCount += 1
        defer { busyCount -= 1 }
        do {
            _ = try await api.setScheduledPreheat(enabled: enabled, startTime: start, pin: pin)
            show(.success, enabled ? "电池预热已设置" : "电池预热已关闭")
        } catch {
            show(.error, error.localizedDescription)
        }
    }

    func setHealthyCharging(enabled: Bool, soc: Int) async {
        busyCount += 1
        defer { busyCount -= 1 }
        do {
            _ = try await api.setHealthyCharging(enabled: enabled, targetSoc: soc)
            show(.success, "健康充电已更新")
            await refresh()
        } catch {
            show(.error, error.localizedDescription)
        }
    }

    // ---------------------------------------------------------- 自动刷新

    func toggleAutoRefresh() {
        autoRefresh.toggle()
        refreshTask?.cancel()
        guard autoRefresh else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    // ---------------------------------------------------------- 蓝牙钥匙

    func syncBleCertificate() async {
        busyCount += 1
        defer { busyCount -= 1 }
        await ble.syncCertificate()
    }

    func bleConnect(_ device: BleNearbyDevice) async {
        let config = BlePassiveConfiguration.defaultForModel(api.selectedCarType, protocolMinor: nil)
        ble.connect(device, configuration: config)
    }

    func bleControl(_ action: BleLockAction) {
        ble.control(action)
    }

    // ---------------------------------------------------------- 调试

    func copyDiagnostics() {
        let text = diagnosticsText()
        UIPasteboard.general.string = text
        show(.success, "诊断信息已复制")
    }

    func diagnosticsText() -> String {
        var lines: [String] = []
        lines.append("LeapAuto iOS 诊断")
        lines.append("deviceId: \(api.deviceId)")
        lines.append("smDeviceId: \(api.smDeviceId.isEmpty ? "(空)" : String(api.smDeviceId.prefix(12)) + "…")")
        lines.append("accountId: \(api.newAuth?.accountId ?? "-")")
        lines.append("Vin: \(api.selectedVin)")
        lines.append("carType: \(api.selectedCarType)")
        lines.append("route: \(api.route?.appRegion ?? "-")")
        lines.append("token到期: \(api.newAuth?.accessTokenExpiresAt ?? 0)")
        lines.append("BLE: \(ble.phase.label) mtu=\(ble.mtu)")
        lines.append("状态字段: \(status.raw.count)")
        return lines.joined(separator: "\n")
    }
}
