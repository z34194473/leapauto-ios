//
//  Models.swift
//  信号解码 / 指令表 / 状态映射（与 SignalTable.kt + Models.kt + VehicleStatusMapper.kt 对齐）
//

import Foundation

// ============================================================ 基础类型（与网络层解耦）

/// 控车指令
struct ControlCommand {
    let cmdid: String
    let state: String
    let label: String
}

/// 定时空调预约
struct ScheduledAcPlan {
    var enabled: Bool = false
    var startTime: String = "07:30"
    var days: String = "1,1,1,1,1,1,1"
    var temperatureC: Int = 26
    var windLevel: Int = 5
    var mode: String = "cold"          // nohotcold / cold / hot
    var circle: String = "in"          // in / out
    var windshieldDefogging: Bool = true
}

// ============================================================ 信号表：数字 ID → 命名字段

enum LeapSignalTable {
    static let map: [String: String] = [
        // 电池 / 充电
        "47": "acInputSlowCharge",
        "1204": "soc",
        "100003": "preciseSoc",
        "3235": "fuelSoc",
        "1200": "chargeRemainTime",
        "1178": "batteryCurrent",
        "1177": "batteryVoltage",
        "1197": "dcInputFastCharge",
        "1149": "chargeState",
        "1182": "minBatteryTemp",
        "1186": "batteryThermalRequest",
        "3736": "chargeCompleted",
        "48": "healthyChargeEnabled",
        "3737": "chargeScheduleCancelledOnce",
        // 续航
        "3260": "expectedMileage",
        "2188": "liveRemainingRange",
        "3257": "electricRangeStandard",
        "3262": "rangeMode",
        "3256": "fuelRangeStandard",
        "3258": "combinedRangeStandard",
        "3259": "fuelRangeDynamic",
        "3261": "combinedRangeDynamic",
        // 行驶
        "1319": "speed",
        "1318": "totalMileage",
        "1010": "gearStatus",
        "1944": "vehicleState",
        "1480": "parkingBrakeState",
        "6048": "speedLimit",
        "6047": "speedLimitUnit",
        "12054": "speedLimitActive",
        // 位置
        "3725": "latitude",
        "3724": "longitude",
        // 空调
        "1938": "acSwitch",
        "2183": "acSetting",
        "2184": "acSettingRight",
        "1349": "interiorTemp",
        "1943": "recirculationMode",
        "1945": "windshieldDefrost",
        "1946": "rearWindowHeating",
        "3713": "climateMode",
        "2669": "rapidCooling",
        "2681": "rapidHeating",
        "1939": "acOperateMode",
        "1941": "acAirVolume",
        // 车窗
        "1693": "driverWindowStatus",
        "1694": "rightFrontWindowStatus",
        "1695": "leftRearWindowStatus",
        "1696": "rightRearWindowStatus",
        // 车门 / 锁
        "1298": "driverDoorLockStatus",
        "1277": "lbcmDriverDoorStatus",
        "1278": "rbcmDriverDoorStatus",
        "1279": "lbcmLeftRearDoorStatus",
        "1280": "rbcmRightRearDoorStatus",
        "1281": "bbcmBackDoorStatus",
        "1282": "hoodStatus",
        "1276": "fbcmHoodStatus",
        // 胎压
        "2646": "leftFrontTirePressure",
        "2653": "rightFrontTirePressure",
        "2667": "rightRearTirePressure",
        "2660": "leftRearTirePressure",
        "2641": "leftFrontTirePressureState",
        "2648": "rightFrontTirePressureState",
        "2655": "rightRearTirePressureState",
        "2662": "leftRearTirePressureState",
        // 电源档位
        "1256": "bcmKeyPositionOn1",
        "1257": "bcmKeyPositionOn2",
        "1258": "bcmKeyPositionOn3",
        // 座椅 / 舒适
        "2100": "driverSeatHeating",
        "2101": "driverSeatVentilation",
        "2118": "passengerSeatHeating",
        "2119": "passengerSeatVentilation",
        "1879": "leftRearSeatHeating",
        "3727": "leftRearSeatVentilation",
        "1880": "rightRearSeatHeating",
        "3728": "rightRearSeatVentilation",
        "1816": "steeringWheelHeating",
        "1624": "steeringWheelHeaterMinutes",
        // 安防 / 外设
        "1255": "vehicleSecurityActive",
        "3636": "sentryMode",
        "49": "leftMirrorHeating",
        "50": "rightMirrorHeating",
        "1718": "sunroofOpening",
        "1724": "roofOpening",
        // 冰箱
        "10707": "fridgeTargetTemp",
        "10708": "fridgeMode",
        "10709": "fridgeSwitch",
        "10711": "fridgeStyle",
        "10712": "fridgeFault",
        "11189": "fridgeParkDurationHours",
        "11190": "fridgeParkSwitch",
        "11191": "fridgeParkCycles",
        "11260": "fridgeParkEndTime"
    ]

    /// 数字 ID 查表；命名字段透传
    static func decode(_ signal: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in signal {
            if let name = map[key] {
                if out[name] == nil { out[name] = value }
            } else if !key.allSatisfy({ $0.isNumber }) || key == "2" || key == "3" {
                out[key] = value
            }
        }
        return out
    }
}

// ============================================================ 值解析

enum LeapValue {
    static func double(_ v: Any?) -> Double? {
        guard let v = v, !(v is NSNull) else { return nil }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String {
            let cleaned = s.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespaces)
            return Double(cleaned)
        }
        return nil
    }

    static func int(_ v: Any?) -> Int? {
        guard let d = double(v), d.isFinite else { return nil }
        return Int(d)
    }

    static func bool(_ v: Any?) -> Bool? {
        guard let v = v, !(v is NSNull) else { return nil }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.intValue != 0 }
        if let s = v as? String {
            switch s.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "1", "on": return true
            case "false", "0", "off": return false
            default: return nil
            }
        }
        return nil
    }

    /// 去单位文本
    static func text(_ v: Any?, unit: String? = nil) -> String? {
        guard let v = v, !(v is NSNull) else { return nil }
        var s = String(describing: v).trimmingCharacters(in: .whitespaces)
        if let unit = unit, s.hasSuffix(unit) {
            s = String(s.dropLast(unit.count)).trimmingCharacters(in: .whitespaces)
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "k m"))
        return (s.isEmpty || s == "--") ? nil : s
    }

    static func fixed(_ v: Double?, _ digits: Int = 1) -> String? {
        guard let v = v, v.isFinite else { return nil }
        return String(format: "%.\(digits)f", v)
    }
}

// ============================================================ 充电状态

enum LeapCharge {
    /// signal 1149：0 未插枪 / 1 充电中 / 2 充电完成 / 3 故障 / 4 预约等待 / 6 暂停
    static func label(_ state: Int?) -> String {
        switch state {
        case 0: return "未插枪"
        case 1: return "充电中"
        case 2: return "充电完成"
        case 3: return "充电故障"
        case 4: return "预约充电等待"
        case 6: return "充电暂停"
        default: return "充电状态未知"
        }
    }

    static func isCharging(_ state: Int?) -> Bool { state == 1 }

    /// 充电功率 kW = |V × A| / 1000
    static func power(voltage: Any?, current: Any?) -> String? {
        guard let v = LeapValue.double(voltage), let a = LeapValue.double(current) else { return nil }
        return String(format: "%.1f kW", abs(v * a) / 1000.0)
    }

    static func currentText(_ v: Any?) -> String? {
        guard let s = LeapValue.text(v) else { return nil }
        return s.hasPrefix("-") ? String(s.dropFirst()) : s
    }

    static func remainingText(_ v: Any?) -> String? {
        guard let minutes = LeapValue.int(v), minutes > 0 else { return nil }
        if minutes < 60 { return "\(minutes) 分钟" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) 小时" : "\(h) 小时 \(m) 分"
    }
}

// ============================================================ 车辆状态快照

struct LeapStatus {
    let raw: [String: Any]

    func any(_ key: String) -> Any? { raw[key] }

    // ---------------- 电量与续航

    /// 电量百分比（优先 preciseSoc，回退 soc），向上取整
    var socPercent: Int? {
        if let precise = LeapValue.double(raw["preciseSoc"]) {
            return Int(min(max(ceil(precise), 0), 100))
        }
        if let soc = LeapValue.double(raw["soc"]) {
            return Int(min(max(ceil(soc), 0), 100))
        }
        return nil
    }

    var fuelSocPercent: Int? {
        guard let v = LeapValue.double(raw["fuelSoc"]) else { return nil }
        return Int(min(max(ceil(v), 0), 100))
    }

    var isReev: Bool { fuelSocPercent != nil }

    /// 剩余续航：rangeMode 0 → 标准，1 → 动态
    var remainingRange: String? {
        let mode = LeapValue.text(raw["rangeMode"])
        switch mode {
        case "0":
            return LeapValue.text(raw["electricRangeStandard"]) ?? LeapValue.text(raw["maxRange"])
        case "1":
            return LeapValue.text(raw["expectedMileage"])
        default:
            return LeapValue.text(raw["expectedMileage"]) ?? LeapValue.text(raw["electricRangeStandard"])
        }
    }

    var combinedRange: String? {
        switch LeapValue.text(raw["rangeMode"]) {
        case "0": return LeapValue.text(raw["combinedRangeStandard"])
        case "1": return LeapValue.text(raw["combinedRangeDynamic"])
        default: return LeapValue.text(raw["combinedRangeStandard"]) ?? LeapValue.text(raw["combinedRangeDynamic"])
        }
    }

    var fuelRange: String? {
        switch LeapValue.text(raw["rangeMode"]) {
        case "0": return LeapValue.text(raw["fuelRangeStandard"])
        case "1": return LeapValue.text(raw["fuelRangeDynamic"])
        default: return LeapValue.text(raw["fuelRangeStandard"]) ?? LeapValue.text(raw["fuelRangeDynamic"])
        }
    }

    var totalMileage: String? { LeapValue.text(raw["totalMileage"], unit: "km") }

    // ---------------- 充电

    var chargeState: Int? { LeapValue.int(raw["chargeState"]) }
    var chargeLabel: String { LeapCharge.label(chargeState) }
    var isCharging: Bool { LeapCharge.isCharging(chargeState) }
    var chargePower: String? { LeapCharge.power(voltage: raw["batteryVoltage"], current: raw["batteryCurrent"]) }
    var chargeCurrent: String? { LeapCharge.currentText(raw["batteryCurrent"]) }
    var chargeRemaining: String? { LeapCharge.remainingText(raw["chargeRemainTime"]) }
    var batteryTemp: String? { LeapValue.text(raw["minBatteryTemp"]) }

    var healthyChargeEnabled: Bool? { LeapValue.bool(raw["healthyChargeEnabled"]) }
    var targetSoc: Int? { LeapValue.int(raw["chargesocSetting"]) }

    var chargeScheduleEnabled: Bool? {
        guard let v = LeapValue.int(raw["chargeScheduleEnabled"]) else { return nil }
        return v != 0
    }
    var chargeScheduleStart: String? { LeapValue.text(raw["chargeScheduleStart"]) }
    var chargeScheduleEnd: String? { LeapValue.text(raw["chargeScheduleEnd"]) }

    // ---------------- 门锁与开合

    var isLocked: Bool? {
        // 1298 driverDoorLockStatus：1 = 已锁
        guard let v = LeapValue.int(raw["driverDoorLockStatus"]) else { return nil }
        return v == 1
    }

    var trunkOpen: Bool? { LeapValue.bool(raw["bbcmBackDoorStatus"]) }
    var hoodOpen: Bool? { LeapValue.bool(raw["hoodStatus"]) ?? LeapValue.bool(raw["fbcmHoodStatus"]) }
    var sunroofOpen: Bool? {
        guard let v = LeapValue.int(raw["sunroofOpening"]) else { return nil }
        return v != 0
    }

    var windows: [OpeningItem] {
        var out: [OpeningItem] = []
        let mapping: [(String, String)] = [
            ("主驾", "driverWindowStatus"),
            ("右前", "rightFrontWindowStatus"),
            ("左后", "leftRearWindowStatus"),
            ("右后", "rightRearWindowStatus")
        ]
        for (name, key) in mapping {
            if let v = LeapValue.int(raw[key]) {
                out.append(OpeningItem(name: name, open: v != 0))
            }
        }
        return out
    }

    var anyWindowOpen: Bool { windows.contains { $0.open } }

    var doors: [OpeningItem] {
        var out: [OpeningItem] = []
        let mapping: [(String, String)] = [
            ("主驾", "lbcmDriverDoorStatus"),
            ("右前", "rbcmDriverDoorStatus"),
            ("左后", "lbcmLeftRearDoorStatus"),
            ("右后", "rbcmRightRearDoorStatus")
        ]
        for (name, key) in mapping {
            if let v = LeapValue.int(raw[key]) {
                out.append(OpeningItem(name: name, open: v != 0))
            }
        }
        return out
    }

    // ---------------- 胎压

    var tires: [TireItem] {
        var out: [TireItem] = []
        let mapping: [(String, String, String)] = [
            ("左前", "leftFrontTirePressure", "leftFrontTirePressureState"),
            ("右前", "rightFrontTirePressure", "rightFrontTirePressureState"),
            ("左后", "leftRearTirePressure", "leftRearTirePressureState"),
            ("右后", "rightRearTirePressure", "rightRearTirePressureState")
        ]
        for (name, valueKey, stateKey) in mapping {
            let value = LeapValue.text(raw[valueKey])
            let abnormal = (LeapValue.int(raw[stateKey]) ?? 0) != 0
            if value != nil || abnormal {
                out.append(TireItem(name: name, value: value, abnormal: abnormal))
            }
        }
        return out
    }

    // ---------------- 空调

    var acOn: Bool? { LeapValue.bool(raw["acSwitch"]) }
    var interiorTemp: String? { LeapValue.text(raw["interiorTemp"]) }
    var acSetting: String? { LeapValue.text(raw["acSetting"]) }
    var acAirVolume: String? { LeapValue.text(raw["acAirVolume"]) }
    var windshieldDefrost: Bool? { LeapValue.bool(raw["windshieldDefrost"]) }

    var climateTone: ClimateTone {
        guard acOn == true else { return .idle }
        if let mode = LeapValue.int(raw["climateMode"]) {
            switch mode {
            case 4, 0: return .ventilation
            case 1: return .cooling
            case 2, 3: return .heating
            default: break
            }
        }
        if let target = LeapValue.int(raw["acSetting"]) {
            return target >= 27 ? .heating : .cooling
        }
        return .cooling
    }

    // ---------------- 座椅 / 方向盘

    func seatHeating(_ key: String) -> Int? { LeapValue.int(raw[key]) }
    func seatVentilation(_ key: String) -> Int? { LeapValue.int(raw[key]) }
    var steeringWheelHeating: Int? { LeapValue.int(raw["steeringWheelHeating"]) }

    // ---------------- 安防

    var sentryMode: Bool? { LeapValue.bool(raw["sentryMode"]) }
    var securityActive: Bool? { LeapValue.bool(raw["vehicleSecurityActive"]) }
    var mirrorHeatingLeft: Bool? { LeapValue.bool(raw["leftMirrorHeating"]) }
    var mirrorHeatingRight: Bool? { LeapValue.bool(raw["rightMirrorHeating"]) }
    var mirrorHeating: Bool? {
        guard let l = mirrorHeatingLeft, let r = mirrorHeatingRight else { return mirrorHeatingLeft ?? mirrorHeatingRight }
        return l || r
    }

    // ---------------- 行驶

    var speed: String? { LeapValue.text(raw["speed"]) }
    var gear: String? { LeapValue.text(raw["gearStatus"]) }
    var parkingBrake: Bool? {
        guard let v = LeapValue.int(raw["parkingBrakeState"]) else { return nil }
        return v != 0
    }
    var speedLimit: String? { LeapValue.text(raw["speedLimit"]) }

    // ---------------- 冰箱

    var fridgeOn: Bool? { LeapValue.bool(raw["fridgeSwitch"]) }
    var fridgeTemp: String? { LeapValue.text(raw["fridgeTargetTemp"]) }
    var fridgeMode: Int? { LeapValue.int(raw["fridgeMode"]) }

    // ---------------- 位置

    var coordinate: (lat: Double, lon: Double)? {
        guard let lat = LeapValue.double(raw["latitude"]),
              let lon = LeapValue.double(raw["longitude"]),
              abs(lat) > 0.0001, abs(lon) > 0.0001 else { return nil }
        return (lat, lon)
    }

    var hasAnyData: Bool { !raw.isEmpty }
}

enum ClimateTone {
    case idle, cooling, heating, ventilation
}

/// 车门 / 车窗开合项
struct OpeningItem: Identifiable {
    let name: String
    let open: Bool
    var id: String { name }
}

/// 胎压项
struct TireItem: Identifiable {
    let name: String
    let value: String?
    let abnormal: Bool
    var id: String { name }
}

// ============================================================ 指令表（cmdid 全部来自 APK / 官方抓包）

enum LeapCommands {

    // 空调常用 state 常量
    static let acOnState = #"{"operate":"auto","temperature":"24","windlevel":"2","mode":"nohotcold","circle":"in","wshld":"1","position":"all"}"#
    static let acOffState = #"{"operate":"off","temperature":"24","windlevel":"3","mode":"nohotcold","circle":"in","wshld":"1","position":"all"}"#
    static let quickCoolState = #"{"operate":"manual","temperature":"18","windlevel":"7","mode":"cold","circle":"in","wshld":"1","position":"all"}"#
    static let quickHeatState = #"{"operate":"manual","temperature":"32","windlevel":"7","mode":"hot","circle":"in","wshld":"1","position":"all"}"#
    static let defrostState = #"{"operate":"manual","temperature":"24","windlevel":"5","mode":"cold","circle":"out","wshld":"1","position":"wshld"}"#
    static let deodorizeState = #"{"operate":"manual","temperature":"24","windlevel":"7","mode":"nohotcold","circle":"out","wshld":"0","position":"all"}"#

    static let lock = ControlCommand(cmdid: "110", state: #"{"value":"lock"}"#, label: "上锁")
    static let unlock = ControlCommand(cmdid: "110", state: #"{"value":"unlock"}"#, label: "解锁")
    static let trunkOpen = ControlCommand(cmdid: "130", state: #"{"value":"true"}"#, label: "开后备箱")
    static let trunkClose = ControlCommand(cmdid: "130", state: #"{"value":"false"}"#, label: "关后备箱")
    static let frunkOpen = ControlCommand(cmdid: "131", state: #"{"value":"100"}"#, label: "开前备箱")
    static let frunkClose = ControlCommand(cmdid: "131", state: #"{"value":"0"}"#, label: "关前备箱")
    static let windowHalf = ControlCommand(cmdid: "230", state: #"{"value":"5"}"#, label: "车窗半开")
    static let windowVent = ControlCommand(cmdid: "230", state: #"{"value":"2"}"#, label: "车窗通风")
    static let windowClose = ControlCommand(cmdid: "230", state: #"{"value":"0"}"#, label: "车窗全关")
    static let sunshadeOpen = ControlCommand(cmdid: "240", state: #"{"value":"10"}"#, label: "遮阳帘打开")
    static let sunshadeClose = ControlCommand(cmdid: "240", state: #"{"value":"0"}"#, label: "遮阳帘关闭")
    static let sunroofOpen = ControlCommand(cmdid: "300", state: #"{"value":"1"}"#, label: "天窗打开")
    static let sunroofClose = ControlCommand(cmdid: "300", state: #"{"value":"0"}"#, label: "天窗关闭")
    static let horn = ControlCommand(cmdid: "120", state: #"{"value":"true"}"#, label: "鸣笛寻车")
    static let preheatOn = ControlCommand(cmdid: "160", state: #"{"value":"ptcon"}"#, label: "电池预热开")
    static let preheatOff = ControlCommand(cmdid: "160", state: #"{"value":"ptcoff"}"#, label: "电池预热关")

    static let acOn = ControlCommand(cmdid: "170", state: acOnState, label: "开空调")
    static let acOff = ControlCommand(cmdid: "170", state: acOffState, label: "关空调")
    static let quickCool = ControlCommand(cmdid: "170", state: quickCoolState, label: "极速降温")
    static let quickHeat = ControlCommand(cmdid: "170", state: quickHeatState, label: "极速升温")
    static let defrost = ControlCommand(cmdid: "170", state: defrostState, label: "开启除雾")
    static let deodorize = ControlCommand(cmdid: "170", state: deodorizeState, label: "快速除味")

    static let sentryOn = ControlCommand(cmdid: "400", state: #"{"operation":"on"}"#, label: "开启哨兵模式")
    static let sentryOff = ControlCommand(cmdid: "400", state: #"{"operation":"off"}"#, label: "关闭哨兵模式")

    static let chargeStart = ControlCommand(cmdid: "193", state: #"{"value":"start"}"#, label: "开始充电")
    static let chargeStop = ControlCommand(cmdid: "193", state: #"{"value":"finish"}"#, label: "停止充电")
    static let unlockCharger = ControlCommand(cmdid: "192", state: #"{"operation":"unlock"}"#, label: "解锁充电枪")

    static let mirrorHeatingOn = ControlCommand(cmdid: "440", state: #"{"value":"2"}"#, label: "开启后视镜加热")
    static let mirrorHeatingOff = ControlCommand(cmdid: "440", state: #"{"value":"1"}"#, label: "关闭后视镜加热")

    static func ac(_ temperature: Int) -> ControlCommand {
        let t = min(max(temperature, 16), 32)
        let mode = t <= 26 ? "cold" : "hot"
        return ControlCommand(
            cmdid: "170",
            state: #"{"operate":"manual","temperature":"\#(t)","windlevel":"7","mode":"\#(mode)","circle":"in","wshld":"0","position":"all"}"#,
            label: "开空调（\(t)°C）")
    }

    /// 座椅加热 cmdid=301
    static func seatHeating(_ position: String, level: Int) -> ControlCommand {
        let lv = min(max(level, 0), 3)
        let name = position == "left_front" ? "主驾" : (position == "right_front" ? "副驾" : (position == "left_rear" ? "左后" : "右后"))
        return ControlCommand(cmdid: "301",
                              state: #"{"position":"\#(position)","level":"\#(lv)"}"#,
                              label: "\(name)加热\(lv == 0 ? "关闭" : "\(lv)档")")
    }

    /// 座椅通风 cmdid=370
    static func seatVentilation(_ position: String, level: Int) -> ControlCommand {
        let lv = min(max(level, 0), 3)
        let name = position == "left_front" ? "主驾" : (position == "right_front" ? "副驾" : (position == "left_rear" ? "左后" : "右后"))
        return ControlCommand(cmdid: "370",
                              state: #"{"position":"\#(position)","level":"\#(lv)"}"#,
                              label: "\(name)通风\(lv == 0 ? "关闭" : "\(lv)档")")
    }

    /// 方向盘加热 cmdid=320：0 关 / 1 弱 / 2 强
    static func steeringWheelHeating(_ level: Int) -> ControlCommand {
        let lv = min(max(level, 0), 2)
        let text = lv == 0 ? "关闭" : (lv == 1 ? "弱档" : "强档")
        return ControlCommand(cmdid: "320", state: #"{"level":"\#(lv)"}"#, label: "方向盘加热\(text)")
    }

    /// 车载冰箱 cmdid=500
    static func fridge(enable: Bool, mode: Int = 0, temp: Int = 4,
                       style: Int = 0, parkEnable: Bool = false,
                       durationSeconds: Int = 7200, cycles: Int = 1) -> ControlCommand {
        let clampedTemp = mode == 1 ? 50 : min(max(temp, -6), 15)
        let state = """
        {"cycles":"\(cycles == 2 ? "2" : "1")","duration":\(max(durationSeconds, 1800)),"enable":\(enable ? 1 : 0),"mode":\(mode),"parkEnable":\(parkEnable ? 1 : 0),"style":\(style),"temp":\(clampedTemp),"value":\(enable ? 1 : 0)}
        """
        let label = enable
            ? "开启车载冰箱（\(mode == 1 ? "制热 50°C" : "制冷 \(clampedTemp)°C") \(style == 1 ? "急速" : "标准")）"
            : "关闭车载冰箱"
        return ControlCommand(cmdid: "500", state: state, label: label)
    }

    /// 定时空调 cmdid=171
    static func buildScheduledAc(plan: ScheduledAcPlan, deviceId: String) -> ControlCommand {
        guard plan.enabled else {
            return ControlCommand(cmdid: "171", state: #"{"controls":[]}"#, label: "取消定时空调")
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let temperature = min(max(plan.temperatureC, 16), 32)
        let wind = min(max(plan.windLevel, 1), 7)
        let today = LeapDate.string(Date())
        let start = plan.startTime.count == 5 ? "\(today) \(plan.startTime):00" : plan.startTime
        let days = LeapDays.toScheduleDaysIntList(LeapDays.parseToDaySet(plan.days))
        let dayList = days.map { String($0) }.joined(separator: ",")

        let item = """
        {"on":"1","set_id":"ios_\(deviceId)\(now)00","start_time":"\(start)","update_time":"\(now)","days":[\(dayList)],"temperature":"\(temperature)","windlevel":"\(wind)","mode":"\(plan.mode)","circle":"\(plan.circle)","wshld":"\(plan.windshieldDefogging ? 1 : 0)","position":"all","operate":"manual"}
        """
        return ControlCommand(cmdid: "171", state: "{\"controls\":[\(item)]}", label: "定时空调已设置")
    }

    /// 解析 getappointment 返回的定时空调
    static func parseScheduledAc(_ payload: Any?) -> (has: Bool, plan: ScheduledAcPlan)? {
        let text: String
        switch payload {
        case nil, is NSNull:
            return nil
        case let s as String:
            text = s.trimmingCharacters(in: .whitespaces)
        case let d as [String: Any]:
            guard let data = try? JSONSerialization.data(withJSONObject: d),
                  let s = String(data: data, encoding: .utf8) else { return nil }
            text = s
        default:
            return nil
        }
        guard !text.isEmpty else { return nil }
        guard let data = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let controls = data["controls"] as? [Any] else { return nil }
        if controls.isEmpty { return (false, ScheduledAcPlan()) }
        guard let item = controls.first as? [String: Any] else { return nil }

        var plan = ScheduledAcPlan()
        plan.enabled = (item["on"] as? String) == "1"
        if let start = item["start_time"] as? String,
           let re = try? NSRegularExpression(pattern: "(\\d{1,2}):(\\d{2})"),
           let m = re.firstMatch(in: start, range: NSRange(start.startIndex..., in: start)),
           let hRange = Range(m.range(at: 1), in: start),
           let mRange = Range(m.range(at: 2), in: start),
           let h = Int(start[hRange]) {
            plan.startTime = String(format: "%02d:%@", h, String(start[mRange]))
        }
        if let days = item["days"] as? [Any] {
            var set = Set<Int>()
            for raw in days {
                guard let d = LeapValue.int(raw) else { continue }
                if d == 0 { set.insert(7) }
                else if (1...6).contains(d) { set.insert(d) }
            }
            if !set.isEmpty {
                plan.days = (1...7).map { set.contains($0) ? "1" : "0" }.joined(separator: ",")
            }
        }
        if let t = LeapValue.int(item["temperature"]) { plan.temperatureC = t }
        if let w = LeapValue.int(item["windlevel"]) { plan.windLevel = w }
        if let mode = item["mode"] as? String, ["nohotcold", "cold", "hot"].contains(mode) { plan.mode = mode }
        if let circle = item["circle"] as? String, ["in", "out"].contains(circle) { plan.circle = circle }
        plan.windshieldDefogging = (item["wshld"] as? String) == "1"
        return (true, plan)
    }
}

// ============================================================ 日期工具

enum LeapDate {
    static func string(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}

// ============================================================ 星期编解码

enum LeapDays {
    /// "1,1,1,1,1,0,0" 或 "1,2,3,4,5" → {1...7}（1=周一）
    static func parseToDaySet(_ cycles: String?) -> Set<Int> {
        let text = (cycles ?? "").trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return Set(1...7) }
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 7, parts.allSatisfy({ $0 == "0" || $0 == "1" }) {
            var days = Set<Int>()
            for (idx, flag) in parts.enumerated() where flag == "1" { days.insert(idx + 1) }
            return days.isEmpty ? Set(1...7) : days
        }
        let nums = Set(parts.compactMap { Int($0) }.filter { (1...7).contains($0) })
        return nums.isEmpty ? Set(1...7) : nums
    }

    /// 周一…周日 → controls.days（0=周日）
    static func toScheduleDaysIntList(_ days: Set<Int>) -> [Int] {
        let effective = days.isEmpty ? Set(1...7) : days
        return effective.map { $0 == 7 ? 0 : $0 }.sorted()
    }

    static func toVehicleMask(_ days: Set<Int>) -> String {
        let effective = days.isEmpty ? Set(1...7) : days
        return (1...7).map { effective.contains($0) ? "1" : "0" }.joined(separator: ",")
    }

    static func summary(_ cycles: String?) -> String {
        summary(parseToDaySet(cycles))
    }

    static func summary(_ days: Set<Int>) -> String {
        let effective = days.isEmpty ? Set(1...7) : days
        if effective == Set(1...7) { return "每天" }
        if effective == Set(1...5) { return "工作日" }
        if effective == Set([6, 7]) { return "周末" }
        let names: [Int: String] = [1: "一", 2: "二", 3: "三", 4: "四", 5: "五", 6: "六", 7: "日"]
        return effective.sorted().compactMap { names[$0].map { "周\($0)" } }.joined(separator: "、")
    }
}

// ============================================================
//  验证结果
// ============================================================

struct GeetestResult {
    /// 极验 getValidate() 返回的原始 JSON
    let raw: [String: Any]

    var captchaOutput: String { raw["captcha_output"] as? String ?? raw["captchaOutput"] as? String ?? "" }
    var genTime: String { raw["gen_time"] as? String ?? raw["genTime"] as? String ?? "" }
    var lotNumber: String { raw["lot_number"] as? String ?? raw["lotNumber"] as? String ?? "" }
    var passToken: String { raw["pass_token"] as? String ?? raw["passToken"] as? String ?? "" }

    /// 全字段非空才算有效
    var isValid: Bool {
        !captchaOutput.isEmpty && !genTime.isEmpty
            && !lotNumber.isEmpty && !passToken.isEmpty
    }

    /// 转成登录接口需要的参数
    var queryItems: [String: String] {
        [
            "captchaOutput": captchaOutput,
            "genTime": genTime,
            "lotNumber": lotNumber,
            "passToken": passToken
        ]
    }
}

// ============================================================
//  HTML 模板
// ============================================================

enum GeetestPage {
    /// 零跑 APK 内置的默认 captchaId（服务端未下发时兜底）
    static let defaultCaptchaId = "278c775b5dcb8dda2a2f196f60a28a34"

    /// 从 risk_type 中提取 captchaId
    /// 格式：`phrase|1794565955614|4c22bc9e85bf492bb1d44df0150addba|51d39f14...`
    /// 规则：取第一个 32 位 hex 段
    static func captchaId(from riskType: String) -> String {
        for part in riskType.components(separatedBy: "|") {
            let t = part.trimmingCharacters(in: .whitespaces)
            if t.count == 32, t.allSatisfy({ $0.isHexDigit }) {
                return t
            }
        }
        return defaultCaptchaId
    }

    /// 是否需要人机验证（risk_type 非空即需要）
    static func needsCaptcha(_ riskType: String) -> Bool {
        let t = riskType.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty
    }

    /// 生成 HTML
    static func html(captchaId: String, riskType: String) -> String {
        // riskType 注入 JS 前做 JSON 转义，避免引号破坏脚本
        let safeRisk = riskType
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <title>安全验证</title>
            <script>
                window.onerror = function(msg, url, line) {
                    window.webkit && window.webkit.messageHandlers.AndroidBridge
                        && window.webkit.messageHandlers.AndroidBridge.postMessage(
                            {type: "error", message: "脚本错误: " + msg + " (行" + line + ")"});
                };
            </script>
            <script src="https://static.geetest.com/v4/gt4.js"></script>
            <style>
                html, body {
                    margin: 0; padding: 0; width: 100%; height: 100%;
                    background-color: transparent;
                    display: flex; justify-content: center; align-items: center;
                    overflow: hidden;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                }
                #captcha { width: 100%; display: flex; justify-content: center; align-items: center; }
            </style>
        </head>
        <body>
            <div id="captcha"></div>
            <script>
                function bridge(payload) {
                    try {
                        window.webkit.messageHandlers.AndroidBridge.postMessage(payload);
                    } catch (e) {}
                }

                function startGeetest() {
                    if (typeof initGeetest4 !== 'function') {
                        bridge({type: "error", message: "极验脚本未能成功下载，请检查网络"});
                        return;
                    }
                    var config = {
                        captchaId: "\(captchaId)",
                        product: "float",
                        language: "zho",
                        protocol: "https://",
                        timeout: 8000
                    };
                    config.riskType = "\(safeRisk)";
                    config.risk_type = "\(safeRisk)";

                    initGeetest4(config, function (captchaObj) {
                        window.captchaObj = captchaObj;
                        captchaObj.appendTo("#captcha");
                        captchaObj.onReady(function () {
                            bridge({type: "ready"});
                            try {
                                if (typeof captchaObj.showBox === 'function') {
                                    captchaObj.showBox();
                                } else if (typeof captchaObj.showCaptcha === 'function') {
                                    captchaObj.showCaptcha();
                                }
                            } catch (e) {}
                        });
                        captchaObj.onSuccess(function () {
                            var result = captchaObj.getValidate();
                            if (result) {
                                bridge({type: "success", data: result});
                            }
                        });
                        captchaObj.onError(function (error) {
                            var errStr = "";
                            try { errStr = JSON.stringify(error || {}); }
                            catch (e) { errStr = String(error); }
                            bridge({type: "error", message: "验证码服务提示: " + errStr});
                        });
                        captchaObj.onClose(function () {
                            bridge({type: "close"});
                        });
                    });
                }

                if (document.readyState === 'complete' || document.readyState === 'interactive') {
                    startGeetest();
                } else {
                    window.addEventListener('DOMContentLoaded', startGeetest);
                }
            </script>
        </body>
        </html>
        """
    }
}
