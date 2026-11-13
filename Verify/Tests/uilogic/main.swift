// ============================================================
//  UI 层业务逻辑验证（独立可执行，不依赖 SwiftUI）
//  验证 View 中承载的派生逻辑与核心层协同正确
// ============================================================

import Foundation

var passCount = 0
var failCount = 0

func check(_ name: String, _ got: String, _ expect: String) {
    if got == expect {
        passCount += 1
        print("  PASS  \(name)")
    } else {
        failCount += 1
        print("  FAIL  \(name)")
        print("        got:    \(got)")
        print("        expect: \(expect)")
    }
}

func checkInt(_ name: String, _ got: Int, _ expect: Int) {
    check(name, "\(got)", "\(expect)")
}

// ============================================================ 首页状态派生

print("\n=== 首页状态派生 ===")
let raw: [String: Any] = [
    "1204": 62, "100003": 61.2,
    "3260": 388, "3262": 1,
    "1318": 23456,
    "1149": 1, "1177": 396.5, "1178": -8.3, "1200": 95,
    "1938": 1, "2183": 26, "1349": 22.5, "1941": 4,
    "1298": 1,
    "1277": 0, "1278": 0, "1279": 0, "1280": 0,
    "1693": 0, "1694": 1, "1695": 0, "1696": 0,
    "2646": 2.4, "2653": 2.5, "2660": 2.3, "2667": 0.9,
    "2641": 0, "2648": 0, "2655": 0, "2662": 1,
    "3636": 1, "1480": 1, "1319": 0, "1010": "P",
    "49": 1, "50": 0,
    "3724": 120.1234, "3725": 30.5678
]
let s = LeapStatus(raw: LeapSignalTable.decode(raw))

checkInt("SOC 向上取整 61.2 → 62", s.socPercent ?? -1, 62)
check("动态续航 rangeMode=1", s.remainingRange ?? "nil", "388")
check("总里程", s.totalMileage ?? "nil", "23456")
check("充电状态", s.chargeLabel, "充电中")
checkInt("充电中", s.isCharging ? 1 : 0, 1)
check("充电功率 |396.5×-8.3|/1000", s.chargePower ?? "nil", "3.3 kW")
check("电流绝对值", s.chargeCurrent ?? "nil", "8.3")
check("剩余时间 95 分", s.chargeRemaining ?? "nil", "1 小时 35 分")
check("已上锁", "\(s.isLocked == true)", "true")
checkInt("车门项数", s.doors.count, 4)
checkInt("车门开启数", s.doors.filter { $0.open }.count, 0)
checkInt("车窗项数", s.windows.count, 4)
checkInt("车窗开启数", s.windows.filter { $0.open }.count, 1)
checkInt("胎压项数", s.tires.count, 4)
checkInt("胎压异常数", s.tires.filter { $0.abnormal }.count, 1)
check("哨兵", "\(s.sentryMode == true)", "true")
check("手刹", "\(s.parkingBrake == true)", "true")
check("后视镜加热（或运算）", "\(s.mirrorHeating == true)", "true")
check("空调", "\(s.acOn == true)", "true")
check("车内温度", s.interiorTemp ?? "nil", "22.5")
check("位置存在", "\(s.coordinate != nil)", "true")
check("climateTone", "\(s.climateTone)", "cooling")

// ============================================================ 车锁按钮语义

print("\n=== 车锁按钮语义 ===")
check("已上锁 → 显示解锁",
      s.isLocked == true ? LeapCommands.unlock.label : LeapCommands.lock.label, "解锁")
let s2 = LeapStatus(raw: LeapSignalTable.decode(["1298": 0]))
check("未上锁 → 显示上锁",
      s2.isLocked == true ? LeapCommands.unlock.label : LeapCommands.lock.label, "上锁")
check("锁状态未知 → 显示上锁",
      LeapStatus(raw: [:]).isLocked == true ? "解锁" : "上锁", "上锁")

// ============================================================ 座椅档位

print("\n=== 座椅档位 ===")
let seatRaw: [String: Any] = ["2100": 2, "2101": 0, "2118": 1, "1879": 3, "1816": 1]
let seat = LeapStatus(raw: LeapSignalTable.decode(seatRaw))
checkInt("主驾加热", seat.seatHeating("driverSeatHeating") ?? -1, 2)
checkInt("主驾通风", seat.seatVentilation("driverSeatVentilation") ?? -1, 0)
checkInt("副驾加热", seat.seatHeating("passengerSeatHeating") ?? -1, 1)
checkInt("左后加热", seat.seatHeating("leftRearSeatHeating") ?? -1, 3)
checkInt("方向盘加热", seat.steeringWheelHeating ?? -1, 1)

let seatCases: [(String, Int, String, String)] = [
    ("left_front", 0, "301", #"{"position":"left_front","level":"0"}"#),
    ("left_front", 3, "301", #"{"position":"left_front","level":"3"}"#),
    ("right_front", 2, "301", #"{"position":"right_front","level":"2"}"#),
    ("left_rear", 1, "301", #"{"position":"left_rear","level":"1"}"#),
    ("right_rear", 0, "301", #"{"position":"right_rear","level":"0"}"#)
]
for (pos, lv, expectCmd, expectState) in seatCases {
    let cmd = LeapCommands.seatHeating(pos, level: lv)
    check("座椅加热 \(pos) L\(lv)", "\(cmd.cmdid)|\(cmd.state)", "\(expectCmd)|\(expectState)")
}
check("越界钳制 level=9", LeapCommands.seatHeating("left_front", level: 9).state,
      #"{"position":"left_front","level":"3"}"#)
check("越界钳制 level=-1", LeapCommands.seatHeating("left_front", level: -1).state,
      #"{"position":"left_front","level":"0"}"#)

// ============================================================ 自定义温度

print("\n=== 自定义温度 ===")
check("18°C 制冷", LeapCommands.ac(18).state.contains("\"mode\":\"cold\"") ? "cold" : "?", "cold")
check("26°C 制冷", LeapCommands.ac(26).state.contains("\"mode\":\"cold\"") ? "cold" : "?", "cold")
check("27°C 制热", LeapCommands.ac(27).state.contains("\"mode\":\"hot\"") ? "hot" : "?", "hot")
check("32°C 制热", LeapCommands.ac(32).state.contains("\"mode\":\"hot\"") ? "hot" : "?", "hot")
check("钳制 10→16", LeapCommands.ac(10).state.contains("\"temperature\":\"16\"") ? "16" : "?", "16")
check("钳制 40→32", LeapCommands.ac(40).state.contains("\"temperature\":\"32\"") ? "32" : "?", "32")
check("风量 7", LeapCommands.ac(24).state.contains("\"windlevel\":\"7\"") ? "7" : "?", "7")

// ============================================================ 定时空调

print("\n=== 定时空调 ===")
var plan = ScheduledAcPlan()
plan.enabled = true
plan.startTime = "07:30"
plan.days = "1,1,1,1,1,0,0"
plan.temperatureC = 24
plan.windLevel = 5
plan.mode = "cold"
plan.circle = "in"
plan.windshieldDefogging = true

let schedCmd = LeapCommands.buildScheduledAc(plan: plan, deviceId: "abc123")
check("cmdid", schedCmd.cmdid, "171")
check("controls 数组", schedCmd.state.contains("\"controls\":[") ? "yes" : "no", "yes")
check("on=1", schedCmd.state.contains("\"on\":\"1\"") ? "yes" : "no", "yes")
check("温度 24", schedCmd.state.contains("\"temperature\":\"24\"") ? "24" : "?", "24")
check("风量 5", schedCmd.state.contains("\"windlevel\":\"5\"") ? "5" : "?", "5")
check("模式 cold", schedCmd.state.contains("\"mode\":\"cold\"") ? "cold" : "?", "cold")
check("除雾 1", schedCmd.state.contains("\"wshld\":\"1\"") ? "1" : "?", "1")
check("set_id 前缀", schedCmd.state.contains("\"set_id\":\"ios_") ? "yes" : "no", "yes")
check("days [1,2,3,4,5]", schedCmd.state.contains("\"days\":[1,2,3,4,5]") ? "yes" : "no", "yes")

var offPlan = ScheduledAcPlan()
offPlan.enabled = false
check("关闭定时空调", LeapCommands.buildScheduledAc(plan: offPlan, deviceId: "x").state,
      #"{"controls":[]}"#)

let parseText = """
{"controls":[{"on":"1","set_id":"t","start_time":"2026-11-12 07:30:00","update_time":"1","days":[1,2,3,4,5],"temperature":"24","windlevel":"5","mode":"cold","circle":"in","wshld":"1","position":"all","operate":"manual"}]}
"""
if let parsed = LeapCommands.parseScheduledAc(parseText) {
    check("解析 has", "\(parsed.has)", "true")
    check("解析 enabled", "\(parsed.plan.enabled)", "true")
    check("解析 startTime", parsed.plan.startTime, "07:30")
    check("解析 days", parsed.plan.days, "1,1,1,1,1,0,0")
    checkInt("解析温度", parsed.plan.temperatureC, 24)
    checkInt("解析风量", parsed.plan.windLevel, 5)
    check("解析模式", parsed.plan.mode, "cold")
    check("解析除雾", "\(parsed.plan.windshieldDefogging)", "true")
} else {
    check("parseScheduledAc", "nil", "非 nil")
}

check("空 controls → has=false",
      "\(LeapCommands.parseScheduledAc(#"{"controls":[]}"#)?.has ?? true)", "false")
check("无效输入 → nil", "\(LeapCommands.parseScheduledAc("not json") == nil)", "true")
check("null → nil", "\(LeapCommands.parseScheduledAc(nil) == nil)", "true")

// ============================================================ 星期

print("\n=== 星期选择 ===")
check("工作日", LeapDays.toVehicleMask(Set(1...5)), "1,1,1,1,1,0,0")
check("周末", LeapDays.toVehicleMask(Set([6, 7])), "0,0,0,0,0,1,1")
check("每天", LeapDays.toVehicleMask(Set(1...7)), "1,1,1,1,1,1,1")
check("描述-工作日", LeapDays.summary("1,1,1,1,1,0,0"), "工作日")
check("描述-单日", LeapDays.summary("0,1,0,0,0,0,0"), "周二")
check("描述-多日", LeapDays.summary("1,0,0,0,0,1,0"), "周一、周六")

// ============================================================ 时间格式化

print("\n=== 时间格式化 ===")
let timeCases: [(Int, String)] = [(22, "22:00"), (6, "06:00"), (0, "00:00"), (23, "23:00")]
for (hour, expect) in timeCases {
    check("h=\(hour)", String(format: "%02d:00", hour), expect)
}

// ============================================================ 健康充电钳制

print("\n=== 健康充电 SOC 钳制 ===")
let socCases: [(Int, Int)] = [(40, 50), (50, 50), (80, 80), (100, 100), (120, 100)]
for (input, expect) in socCases {
    checkInt("SOC \(input)", min(max(input, 50), 100), expect)
}

// ============================================================ 蓝牙阶段

print("\n=== 蓝牙阶段映射 ===")
let phases: [(BleConnectionPhase, String, Bool)] = [
    (.idle, "未连接", false),
    (.scanning, "正在扫描", false),
    (.connecting, "正在连接", true),
    (.discovering, "正在检查车辆服务", true),
    (.subscribing, "正在建立通信", true),
    (.authenticating, "正在认证", true),
    (.configuring, "正在同步钥匙设置", true),
    (.ready, "已认证", false),
    (.sending, "等待车辆确认", true),
    (.failed, "连接不可用", false)
]
for (phase, label, busy) in phases {
    check("\(phase.rawValue) 标签", phase.label, label)
    check("\(phase.rawValue) busy", "\(phase.isBusy)", "\(busy)")
}

// ============================================================ MAC 规范化

print("\n=== MAC 规范化 ===")
check("紧凑格式", LeapAPI.normalizeMac("aabbccddeeff") ?? "nil", "AA:BB:CC:DD:EE:FF")
check("冒号格式", LeapAPI.normalizeMac("aa:bb:cc:dd:ee:ff") ?? "nil", "AA:BB:CC:DD:EE:FF")
check("全零拒绝", "\(LeapAPI.normalizeMac("000000000000") == nil)", "true")
check("全F拒绝", "\(LeapAPI.normalizeMac("FFFFFFFFFFFF") == nil)", "true")
check("非法拒绝", "\(LeapAPI.normalizeMac("xyz") == nil)", "true")
check("长度错误拒绝", "\(LeapAPI.normalizeMac("aabbcc") == nil)", "true")

// ============================================================ 日期

print("\n=== 日期工具 ===")
let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
let ds = LeapDate.string(fixedDate)
check("yyyy-MM-dd 格式长度", "\(ds.count)", "10")
check("包含连字符", ds.contains("-") ? "yes" : "no", "yes")

// ============================================================ 指令表完整性

print("\n=== 指令表完整性 ===")
let allCommands: [(String, ControlCommand)] = [
    ("lock", LeapCommands.lock), ("unlock", LeapCommands.unlock),
    ("trunkOpen", LeapCommands.trunkOpen), ("trunkClose", LeapCommands.trunkClose),
    ("frunkOpen", LeapCommands.frunkOpen), ("frunkClose", LeapCommands.frunkClose),
    ("windowHalf", LeapCommands.windowHalf), ("windowVent", LeapCommands.windowVent),
    ("windowClose", LeapCommands.windowClose), ("sunroofOpen", LeapCommands.sunroofOpen),
    ("sunroofClose", LeapCommands.sunroofClose), ("sunshadeOpen", LeapCommands.sunshadeOpen),
    ("sunshadeClose", LeapCommands.sunshadeClose), ("horn", LeapCommands.horn),
    ("preheatOn", LeapCommands.preheatOn), ("preheatOff", LeapCommands.preheatOff),
    ("acOn", LeapCommands.acOn), ("acOff", LeapCommands.acOff),
    ("quickCool", LeapCommands.quickCool), ("quickHeat", LeapCommands.quickHeat),
    ("defrost", LeapCommands.defrost), ("deodorize", LeapCommands.deodorize),
    ("sentryOn", LeapCommands.sentryOn), ("sentryOff", LeapCommands.sentryOff),
    ("chargeStart", LeapCommands.chargeStart), ("chargeStop", LeapCommands.chargeStop),
    ("unlockCharger", LeapCommands.unlockCharger),
    ("mirrorHeatingOn", LeapCommands.mirrorHeatingOn), ("mirrorHeatingOff", LeapCommands.mirrorHeatingOff)
]
var allValid = true
for (name, cmd) in allCommands {
    if cmd.cmdid.isEmpty || cmd.state.isEmpty || cmd.label.isEmpty {
        print("  无效指令: \(name)")
        allValid = false
    }
    // state 必须是合法 JSON
    if let d = cmd.state.data(using: .utf8),
       (try? JSONSerialization.jsonObject(with: d)) == nil {
        print("  非法 JSON: \(name) -> \(cmd.state)")
        allValid = false
    }
}
check("全部 \(allCommands.count) 条指令合法", "\(allValid)", "true")
checkInt("指令数量", allCommands.count, 29)

// 冰箱指令
let fridgeOn = LeapCommands.fridge(enable: true)
let fridgeOff = LeapCommands.fridge(enable: false)
check("冰箱开 cmdid", fridgeOn.cmdid, "500")
check("冰箱关 cmdid", fridgeOff.cmdid, "500")
if let d = fridgeOn.state.data(using: .utf8),
   let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
    check("冰箱 enable=1", "\(obj["enable"] as? Int ?? -1)", "1")
    check("冰箱 temp 钳制 4", "\(obj["temp"] as? Int ?? -999)", "4")
} else {
    check("冰箱 state 解析", "fail", "ok")
}

// ============================================================ 报告

print("\n" + String(repeating: "=", count: 56))
if failCount == 0 {
    print("  UI 逻辑层全部通过：\(passCount) 项")
} else {
    print("  通过 \(passCount) 项，失败 \(failCount) 项")
}
print(String(repeating: "=", count: 56))
exit(failCount == 0 ? 0 : 1)
