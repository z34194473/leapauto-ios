//
//  BluetoothKey.swift
//  CoreBluetooth 蓝牙钥匙：扫描 → 连接 → 协商 MTU → 订阅通知 → 认证 → 控车
//  状态机与 BluetoothKeyController.kt 对齐。
//
//  并发模型：CBCentralManager 以 .main 队列创建，所有代理回调天然在主线程；
//  类本身不标注 @MainActor，避免与 CoreBluetooth 的 Sendable 约束冲突。
//

import Foundation
import CoreBluetooth
import Combine
import UIKit

// ============================================================ 阶段

struct BleNearbyDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let rssi: Int
    let serviceUUIDs: [String]
    var protocolMinor: Int

    var displayName: String { name.isEmpty ? "未知设备" : name }
}

struct BleLogEntry: Identifiable {
    let id = UUID()
    let time = Date()
    let text: String
}

// ============================================================ 控制器

final class BluetoothKeyController: NSObject, ObservableObject {

    @Published private(set) var phase: BleConnectionPhase = .idle
    @Published private(set) var message: String = ""
    @Published private(set) var devices: [BleNearbyDevice] = []
    @Published private(set) var connectedName: String = ""
    @Published private(set) var pendingAction: BleLockAction?
    @Published private(set) var confirmedAction: BleLockAction?
    @Published private(set) var logs: [BleLogEntry] = []
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var mtu: Int = 23
    @Published private(set) var hasCertificate: Bool = false

    var isReady: Bool { phase == .ready }

    // 依赖
    private weak var api: LeapAPI?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var session: BleKeySession?
    private var certificate: BleKeyCertificate?
    private var configuration: BlePassiveConfiguration = .manual
    private var profile: BleCompatibilityProfile = .forConnection
    private var discovered: [String: CBPeripheral] = [:]

    private let decoder = BleFrameDecoder()
    private var writeQueue: [[UInt8]] = []

    private var scanTimer: Timer?
    private var phaseTimer: Timer?
    private var commandTimer: Timer?

    private var writesComplete = false
    private var awaitingMtu = false
    private var configurationUsed = false
    private var configurationPending: BlePassiveConfiguration?
    private var configurationWriteStarted = false
    private var configurationAcknowledged = false
    private var onConfigurationConfirmed: (() -> Void)?
    private var lastControlAt: Date = .distantPast
    private var commandDeadline: Date = .distantPast
    private(set) var storedCredential: String?

    override init() {
        super.init()
    }

    func attach(api: LeapAPI) {
        self.api = api
    }

    // ---------------------------------------------------------- 日志与阶段

    private func log(_ text: String) {
        logs.insert(BleLogEntry(text: text), at: 0)
        if logs.count > 200 { logs.removeLast(logs.count - 200) }
    }

    private func setPhase(_ p: BleConnectionPhase, _ text: String = "") {
        phase = p
        message = text
    }

    private func fail(_ text: String) {
        cancelTimers()
        setPhase(.failed, text)
        log("失败: \(text)")
        teardown()
    }

    private func cancelTimers() {
        phaseTimer?.invalidate(); phaseTimer = nil
        commandTimer?.invalidate(); commandTimer = nil
    }

    private func armPhase(_ seconds: TimeInterval, _ handler: @escaping () -> Void) {
        phaseTimer?.invalidate()
        phaseTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.phaseTimer = nil
            handler()
        }
    }

    // ---------------------------------------------------------- 生命周期

    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func setCertificate(_ cert: BleKeyCertificate?, configuration: BlePassiveConfiguration) {
        certificate = cert
        hasCertificate = cert != nil
        self.configuration = configuration
        if let cert = cert {
            log("证书就绪 keyType=\(cert.keyType) vin=…\(cert.vin.suffix(6))")
        }
    }

    /// 从云端同步证书
    func syncCertificate() async {
        guard let api = api else { return }
        setPhase(.idle, "正在同步蓝牙钥匙证书")
        do {
            let cert = try await api.fetchBluetoothCertificate()
            let carType = api.selectedCarType
            let config = BlePassiveConfiguration.defaultForModel(carType, protocolMinor: nil)
            setCertificate(cert, configuration: config)
            setPhase(.idle, "证书已就绪，可以扫描车辆")
        } catch {
            fail("证书同步失败: \(error.localizedDescription)")
        }
    }

    // ---------------------------------------------------------- 扫描

    func startScan() {
        guard let central = central else {
            start()
            return
        }
        guard central.state == .poweredOn else {
            fail("蓝牙未开启，请在系统设置中开启")
            return
        }
        guard certificate != nil else {
            fail("请先同步蓝牙钥匙证书")
            return
        }
        cancelTimers()
        devices = []
        discovered = [:]
        decoder.clear()
        setPhase(.scanning, "正在搜索车辆蓝牙")
        log("开始扫描")
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.stopScan()
            if self.devices.isEmpty {
                self.setPhase(.idle, "未发现车辆，请靠近车辆后重试")
            } else {
                self.setPhase(.idle, "请选择要连接的车辆")
            }
        }
    }

    func stopScan() {
        scanTimer?.invalidate(); scanTimer = nil
        central?.stopScan()
    }

    // ---------------------------------------------------------- 连接

    func connect(_ device: BleNearbyDevice, configuration: BlePassiveConfiguration) {
        guard let central = central, let cert = certificate else { return }
        guard let target = discovered[device.id] else {
            fail("设备已失效，请重新扫描")
            return
        }
        stopScan()
        teardown()

        self.configuration = configuration
        self.profile = .forConnection
        connectedName = device.displayName
        configurationUsed = false
        writesComplete = false
        storedCredential = nil

        setPhase(.connecting, "正在建立蓝牙连接")
        log("连接 \(device.displayName) protocolMinor=\(device.protocolMinor)")
        armPhase(15) { [weak self] in self?.fail("蓝牙连接超时，请靠近车辆后重试") }

        let vin = cert.vin
        // 会话派生涉及 SM2/SM3 大数运算，放到后台线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try BleKeySession.create(certificate: cert, vin: vin) }
            DispatchQueue.main.async {
                guard let self = self, self.phase == .connecting else { return }
                switch result {
                case .success(let session):
                    self.session = session
                    self.log("会话密钥已派生")
                    target.delegate = self
                    self.peripheral = target
                    central.connect(target, options: nil)
                case .failure:
                    self.fail("蓝牙钥匙认证材料无效或类型不受支持，请重新同步钥匙")
                }
            }
        }
    }

    func disconnect() {
        cancelTimers()
        teardown()
        setPhase(.idle, "未连接")
    }

    private func teardown() {
        if let p = peripheral {
            if let ch = characteristic, ch.isNotifying {
                p.setNotifyValue(false, for: ch)
            }
            central?.cancelPeripheralConnection(p)
        }
        peripheral?.delegate = nil
        peripheral = nil
        characteristic = nil
        session = nil
        writeQueue = []
        decoder.clear()
        awaitingMtu = false
        writesComplete = false
        configurationPending = nil
        configurationWriteStarted = false
        configurationAcknowledged = false
        onConfigurationConfirmed = nil
    }

    // ---------------------------------------------------------- 控车

    func control(_ action: BleLockAction) {
        guard phase == .ready, let session = session else {
            log("控车被拒绝：当前状态 \(phase.label)")
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastControlAt) > 1.5 else { return }
        lastControlAt = now

        pendingAction = action
        confirmedAction = nil
        commandDeadline = now.addingTimeInterval(6)
        setPhase(.sending, "等待车辆确认\(action.label)")
        log("下发\(action.label)")

        do {
            let frame = try session.buildCommand(action, epochSeconds: Int64(Date().timeIntervalSince1970))
            queueWrite(frame)
        } catch {
            fail("蓝牙指令构造失败")
        }
    }

    /// 下发钥匙设置（每次连接仅允许一次）
    func configure(_ config: BlePassiveConfiguration, onConfirmed: @escaping () -> Void) {
        guard phase == .ready, let session = session, !configurationUsed else { return }
        configurationUsed = true
        configurationPending = config
        configurationWriteStarted = false
        configurationAcknowledged = false
        onConfigurationConfirmed = onConfirmed
        setPhase(.configuring, "等待车辆确认钥匙设置")

        let minor = currentProtocolMinor
        do {
            let frame = try session.buildConfiguration(config, protocolMinor: minor,
                                                      epochSeconds: Int64(Date().timeIntervalSince1970),
                                                      profile: profile,
                                                      supportsButton: minor >= 9)
            configurationWriteStarted = true
            queueWrite(frame)
        } catch {
            finishConfiguration(confirmed: false)
        }
    }

    private func finishConfiguration(confirmed: Bool) {
        let callback = onConfigurationConfirmed
        onConfigurationConfirmed = nil
        configurationPending = nil
        configurationWriteStarted = false
        configurationAcknowledged = false
        setPhase(.ready, confirmed ? "钥匙设置已同步" : "钥匙设置已送达")
        if confirmed { callback?() }
    }

    // ---------------------------------------------------------- 写入

    private func queueWrite(_ frame: [UInt8]) {
        writeQueue = BleKeyProtocol.chunks(frame, mtu: mtu)
        writesComplete = false
        writeNext()
    }

    private func writeNext() {
        guard let peripheral = peripheral, let ch = characteristic else { return }
        guard !writeQueue.isEmpty else {
            writesComplete = true
            finishConfigurationIfReady()
            return
        }
        let chunk = writeQueue.removeFirst()
        let type: CBCharacteristicWriteType = ch.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(Data(chunk), for: ch, type: type)
        if type == .withoutResponse {
            // 无响应写入没有回调，立即推进下一个分片
            writeNext()
        }
    }

    private func finishConfigurationIfReady() {
        guard phase == .configuring, writesComplete, configurationAcknowledged else { return }
        finishConfiguration(confirmed: true)
    }

    // ---------------------------------------------------------- 接收

    private func handle(_ bytes: [UInt8]) {
        for frame in decoder.append(bytes) {
            switch frame.type {
            case .encrypted:
                guard let session = session else { continue }
                guard let resp = try? session.decodeResponse(frame) else {
                    log("回执解码失败")
                    continue
                }
                switch resp {
                case .authenticated(let state):
                    if phase == .authenticating {
                        setPhase(.ready, "已认证 · \(state)")
                        log("认证成功 lockState=\(state)")
                        commandTimer?.invalidate(); commandTimer = nil
                        phaseTimer?.invalidate(); phaseTimer = nil
                        if !configurationUsed {
                            let cfg = configuration
                            configure(cfg) { [weak self] in
                                self?.log("钥匙设置已同步到车辆")
                            }
                        }
                    }
                case .reconnectCredential(let hex):
                    storedCredential = hex
                    log("已接收快速重连凭据")
                case .commandResult(let identifier, let result):
                    if phase == .configuring, identifier == "3" {
                        if result == "0" || result == "00" {
                            configurationAcknowledged = true
                            log("配置已被车辆确认")
                            finishConfigurationIfReady()
                        } else {
                            log("配置被车辆拒绝 result=\(result ?? "nil")")
                            finishConfiguration(confirmed: false)
                        }
                    }
                case .unknown:
                    break
                }

            case .event:
                switch BleKeyProtocol.parseEvent(frame) {
                case .rejected(let code):
                    log("车辆拒绝请求，结果码 \(code)")
                    if phase == .sending {
                        let label = pendingAction?.label ?? "操作"
                        pendingAction = nil
                        fail("车辆拒绝\(label)（结果码 \(code)）")
                    } else if phase == .authenticating {
                        fail("车辆拒绝钥匙认证（结果码 \(code)）")
                    } else if phase == .configuring {
                        finishConfiguration(confirmed: false)
                    }
                case .lockAction(_, let trigger, let action):
                    guard trigger == 1, let action = action, action == pendingAction else { break }
                    guard phase == .sending else { break }
                    confirmedAction = action
                    pendingAction = nil
                    commandTimer?.invalidate(); commandTimer = nil
                    phaseTimer?.invalidate(); phaseTimer = nil
                    setPhase(.ready, "\(action.label)成功")
                    log("车辆确认\(action.label)")
                    if let api = api {
                        Task { await api.uploadBluetoothRecord(action: action) }
                    }
                case .unknown:
                    break
                }

            case .authentication, .reconnect:
                break
            }
        }
    }

    private var currentProtocolMinor: Int {
        if let d = devices.first { return d.protocolMinor }
        return BleKeyProtocol.defaultMinorForModel(carType: api?.selectedCarType)
    }

    fileprivate func authenticate() {
        guard let session = session, let cert = certificate, let api = api else { return }
        let accountId = api.oldAuth?.accountId ?? ""
        guard !accountId.isEmpty, !api.deviceId.isEmpty else {
            fail("登录设备信息已变化，请重新同步钥匙")
            return
        }
        let minor = currentProtocolMinor
        setPhase(.authenticating, "正在验证蓝牙钥匙")
        log("开始认证 protocolMinor=\(minor)")

        do {
            let frame = try session.buildAuthentication(certificate: cert,
                                                        accountId: accountId,
                                                        deviceId: api.deviceId,
                                                        protocolMinor: minor,
                                                        epochSeconds: Int64(Date().timeIntervalSince1970),
                                                        configuration: configuration,
                                                        profile: profile,
                                                        supportsButton: minor >= 9)
            queueWrite(frame)
        } catch {
            fail("蓝牙钥匙认证帧构造失败，请重新同步钥匙")
            return
        }
        armPhase(12) { [weak self] in
            self?.fail("车辆未确认蓝牙钥匙，请重新同步后连接")
        }
    }
}

// ============================================================ CBCentralManagerDelegate

extension BluetoothKeyController: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        switch central.state {
        case .poweredOn:
            log("蓝牙已就绪")
        case .poweredOff:
            log("蓝牙已关闭")
            if phase != .idle { fail("蓝牙未开启，请在系统设置中开启") }
        case .unauthorized:
            fail("未授予蓝牙权限，请在系统设置中授权")
        case .unsupported:
            fail("当前设备不支持低功耗蓝牙")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? ""
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map { $0.uuidString.uppercased() }

        let advertised = BleKeyProtocol.advertisedProtocolMinor(services)
        let looksLikeVehicle = services.contains(BleKeyProtocol.serviceUUID)
            || advertised != nil
            || name.uppercased().contains("LEAP")
            || name.contains("零跑")
        guard looksLikeVehicle else { return }

        let minor = advertised
            ?? BleKeyProtocol.defaultMinorForModel(carType: api?.selectedCarType)
        let device = BleNearbyDevice(id: peripheral.identifier.uuidString,
                                     name: name,
                                     rssi: RSSI.intValue,
                                     serviceUUIDs: services,
                                     protocolMinor: minor)
        discovered[device.id] = peripheral
        if let idx = devices.firstIndex(where: { $0.id == device.id }) {
            devices[idx] = device
        } else {
            devices.append(device)
            devices.sort { $0.rssi > $1.rssi }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("已连接，开始发现服务")
        awaitingMtu = false
        let writeLength = peripheral.maximumWriteValueLength(for: .withoutResponse)
        mtu = max(23, writeLength + 3)
        log("MTU 使用 \(mtu)")
        setPhase(.discovering, "正在识别车辆蓝牙服务")
        armPhase(10) { [weak self] in self?.fail("蓝牙服务发现超时") }
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        fail("蓝牙连接失败，请重试")
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        let hadPending = pendingAction
        teardown()
        if let action = hadPending {
            setPhase(.idle, "蓝牙已断开，\(action.label)结果未确认")
        } else {
            setPhase(.idle, "蓝牙已断开")
        }
        log("连接已断开")
    }
}

// ============================================================ CBPeripheralDelegate

extension BluetoothKeyController: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            fail("车辆服务发现失败")
            return
        }
        guard let service = peripheral.services?.first(where: {
            $0.uuid.uuidString.uppercased() == BleKeyProtocol.serviceUUID
        }) else {
            fail("设备不支持当前蓝牙钥匙服务")
            return
        }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil,
              let ch = service.characteristics?.first(where: {
                  $0.uuid.uuidString.uppercased() == BleKeyProtocol.characteristicUUID
              }) else {
            fail("设备缺少蓝牙钥匙特征通道")
            return
        }
        characteristic = ch
        setPhase(.subscribing, "正在初始化蓝牙数据通道")
        armPhase(8) { [weak self] in self?.fail("蓝牙通知订阅超时") }
        peripheral.setNotifyValue(true, for: ch)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid.uuidString.uppercased() == BleKeyProtocol.characteristicUUID else { return }
        guard error == nil else {
            fail("蓝牙通知订阅失败")
            return
        }
        authenticate()
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid.uuidString.uppercased() == BleKeyProtocol.characteristicUUID else { return }
        guard error == nil else {
            fail("蓝牙写入失败")
            return
        }
        writeNext()
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil,
              characteristic.uuid.uuidString.uppercased() == BleKeyProtocol.characteristicUUID,
              let data = characteristic.value, !data.isEmpty else { return }
        handle([UInt8](data))
    }
}
