//
//  ControlView.swift
//  控制页：车锁 / 空调 / 车窗 / 座椅 / 充电 / 冰箱
//

import SwiftUI

struct ControlView: View {
    @EnvironmentObject var model: LeapModel
    @State private var tab: ControlTab = .lock
    @State private var wheelLevel = 0

    enum ControlTab: Hashable { case lock, climate, body, comfort, charge }

    private var s: LeapStatus { model.status }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                pinBar
                SegmentedBar(items: [
                    (.lock, "车锁"),
                    (.climate, "空调"),
                    (.body, "车身"),
                    (.comfort, "座椅"),
                    (.charge, "充电")
                ], selection: $tab)

                switch tab {
                case .lock: lockPanel
                case .climate: climatePanel
                case .body: bodyPanel
                case .comfort: comfortPanel
                case .charge: chargePanel
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    // ---------------------------------------------------------- PIN

    private var pinBar: some View {
        Card(padding: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.brand)
                SecureField("操作密码（控车需要）", text: $model.pin)
                    .keyboardType(.numberPad)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text)
                if !model.pin.isEmpty {
                    Button {
                        model.pin = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ---------------------------------------------------------- 车锁

    private var lockPanel: some View {
        VStack(spacing: 14) {
            Card {
                VStack(spacing: 14) {
                    HStack {
                        Text("车锁")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.text)
                        Spacer()
                        if let locked = s.isLocked {
                            Pill(text: locked ? "已上锁" : "未上锁",
                                 color: locked ? Theme.green : Theme.orange)
                        }
                    }
                    HStack(spacing: 10) {
                        bigButton("上锁", "lock.fill",
                                  color: Theme.green, active: s.isLocked == true) {
                            Task { await model.run(LeapCommands.lock) }
                        }
                        bigButton("解锁", "lock.open.fill",
                                  color: Theme.orange, active: s.isLocked == false) {
                            Task { await model.run(LeapCommands.unlock) }
                        }
                    }
                    bigButton("鸣笛寻车", "light.beacon.max.fill", color: Theme.blue) {
                        Task { await model.run(LeapCommands.horn) }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: "后备箱与前后舱")
                    HStack(spacing: 4) {
                        ActionButton(title: "开后备箱", icon: "car.rear.and.collision.road.lane",
                                     active: s.trunkOpen == true, disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.trunkOpen) }
                        }
                        ActionButton(title: "关后备箱", icon: "car.rear",
                                     disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.trunkClose) }
                        }
                        ActionButton(title: "开前备箱", icon: "car.front.waves.up",
                                     active: s.hoodOpen == true, disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.frunkOpen) }
                        }
                        ActionButton(title: "关前备箱", icon: "car.front.waves.down",
                                     disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.frunkClose) }
                        }
                    }
                }
            }
        }
    }

    private func bigButton(_ title: String, _ icon: String,
                           color: Color, active: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(active ? .black : color)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(active ? color : color.opacity(0.14))
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(model.isBusy)
        .opacity(model.isBusy ? 0.5 : 1)
    }

    // ---------------------------------------------------------- 空调

    private var climatePanel: some View {
        VStack(spacing: 14) {
            Card {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("空调")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.text)
                            Text(s.acOn == true
                                 ? "设定 \(s.acSetting ?? "-")° · 车内 \(s.interiorTemp ?? "-")°"
                                 : "当前已关闭")
                                .font(.system(size: 11.5))
                                .foregroundColor(Theme.textFaint)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { s.acOn == true },
                            set: { newValue in
                                Task { await model.run(newValue ? LeapCommands.acOn : LeapCommands.acOff) }
                            }
                        ))
                        .labelsHidden()
                        .tint(Theme.brand)
                    }

                    HStack(spacing: 4) {
                        ActionButton(title: "开空调", icon: "fan.fill",
                                     active: s.acOn == true, disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.acOn) }
                        }
                        ActionButton(title: "关空调", icon: "fan.slash.fill", disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.acOff) }
                        }
                        ActionButton(title: "极速降温", icon: "snowflake", tint: Theme.blue,
                                     disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.quickCool) }
                        }
                        ActionButton(title: "极速升温", icon: "flame.fill", tint: Theme.orange,
                                     disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.quickHeat) }
                        }
                    }
                    HStack(spacing: 4) {
                        ActionButton(title: "除雾", icon: "windshield.front.and.wiper",
                                     active: s.windshieldDefrost == true, disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.defrost) }
                        }
                        ActionButton(title: "快速除味", icon: "aqi.medium", disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.deodorize) }
                        }
                        ActionButton(title: "电池预热", icon: "bolt.batteryblock.fill",
                                     tint: Theme.purple, disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.preheatOn) }
                        }
                        ActionButton(title: "关预热", icon: "bolt.slash", disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.preheatOff) }
                        }
                    }
                }
            }

            TemperatureCard()

            ScheduledAcCard()
        }
    }

    // ---------------------------------------------------------- 车身

    private var bodyPanel: some View {
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "车窗")
                    HStack(spacing: 4) {
                        ActionButton(title: "半开", icon: "rectangle.compress.vertical",
                                     disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.windowHalf) }
                        }
                        ActionButton(title: "通风", icon: "wind", disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.windowVent) }
                        }
                        ActionButton(title: "全关", icon: "rectangle.portrait.and.arrow.right",
                                     disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.windowClose) }
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "天窗与遮阳帘")
                    HStack(spacing: 4) {
                        ActionButton(title: "开天窗", icon: "sun.max.fill", tint: Theme.blue,
                                     disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.sunroofOpen) }
                        }
                        ActionButton(title: "关天窗", icon: "sun.min", disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.sunroofClose) }
                        }
                        ActionButton(title: "开遮阳帘", icon: "window.casement", disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.sunshadeOpen) }
                        }
                        ActionButton(title: "关遮阳帘", icon: "window.casement.closed",
                                     disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.sunshadeClose) }
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: "后视镜与哨兵")
                    Toggle(isOn: Binding(
                        get: { s.mirrorHeating == true },
                        set: { newValue in Task { await model.setMirrorHeating(newValue) } }
                    )) {
                        Label("后视镜加热", systemImage: "square.split.bottomrightquarter")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textDim)
                    }
                    .tint(Theme.brand)

                    Divider().background(Color.white.opacity(0.07))

                    Toggle(isOn: Binding(
                        get: { s.sentryMode == true },
                        set: { newValue in
                            Task { await model.run(newValue ? LeapCommands.sentryOn : LeapCommands.sentryOff) }
                        }
                    )) {
                        Label("哨兵模式", systemImage: "shield.lefthalf.filled")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textDim)
                    }
                    .tint(Theme.purple)
                }
            }
        }
    }

    // ---------------------------------------------------------- 座椅

    private var comfortPanel: some View {
        VStack(spacing: 14) {
            SeatCard(title: "主驾", heatingKey: "driverSeatHeating",
                     ventKey: "driverSeatVentilation", position: "left_front")
            SeatCard(title: "副驾", heatingKey: "passengerSeatHeating",
                     ventKey: "passengerSeatVentilation", position: "right_front")
            SeatCard(title: "左后", heatingKey: "leftRearSeatHeating",
                     ventKey: "leftRearSeatVentilation", position: "left_rear")
            SeatCard(title: "右后", heatingKey: "rightRearSeatHeating",
                     ventKey: "rightRearSeatVentilation", position: "right_rear")

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "方向盘")
                    LevelSelector(title: "方向盘加热",
                                  level: $wheelLevel,
                                  maxLevel: 2) { lv in
                        Task { await model.setSteeringWheel(lv) }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("车载冰箱", systemImage: "refrigerator")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textDim)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { s.fridgeOn == true },
                            set: { newValue in Task { await model.setFridge(newValue) } }
                        ))
                        .labelsHidden()
                        .tint(Theme.brand)
                    }
                    if let temp = s.fridgeTemp {
                        InfoRow(title: "目标温度", value: "\(temp)°C")
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- 充电

    private var chargePanel: some View {
        VStack(spacing: 14) {
            Card {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("充电")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.text)
                            Text(s.chargeLabel)
                                .font(.system(size: 11.5))
                                .foregroundColor(s.isCharging ? Theme.green : Theme.textFaint)
                        }
                        Spacer()
                        if let soc = s.socPercent {
                            Text("\(soc)%")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.text)
                        }
                    }

                    if let soc = s.socPercent {
                        ProgressBar(value: Double(soc) / 100, color: Theme.green)
                    }

                    HStack(spacing: 4) {
                        ActionButton(title: "开始充电", icon: "bolt.fill", tint: Theme.green,
                                     disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.chargeStart) }
                        }
                        ActionButton(title: "停止充电", icon: "bolt.slash.fill", disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.chargeStop) }
                        }
                        ActionButton(title: "解锁充电枪", icon: "powerplug.fill", disabled: model.isBusy) {
                            Task { await model.run(LeapCommands.unlockCharger) }
                        }
                    }
                }
            }

            HealthyChargingCard()

            ScheduledChargingCard()
        }
    }
}

// ============================================================ 温度快捷

struct TemperatureCard: View {
    @EnvironmentObject var model: LeapModel
    @State private var temperature = 24

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "自定义温度")
                HStack {
                    Button {
                        if temperature > 16 { temperature -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(Theme.textFaint)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                    VStack(spacing: 0) {
                        Text("\(temperature)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.text)
                        Text("°C")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textFaint)
                    }
                    Spacer()

                    Button {
                        if temperature < 32 { temperature += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(Theme.textFaint)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)

                HStack(spacing: 8) {
                    ForEach([18, 22, 26, 30], id: \.self) { preset in
                        Button {
                            temperature = preset
                        } label: {
                            Text("\(preset)°")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(temperature == preset ? .black : Theme.textDim)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(temperature == preset ? Theme.brand : Color.white.opacity(0.07))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                PrimaryButton(title: "按 \(temperature)°C 开启", icon: "fan.fill",
                              enabled: !model.isBusy) {
                    Task { await model.run(LeapCommands.ac(temperature)) }
                }
            }
        }
    }
}

// ============================================================ 座椅卡片

struct SeatCard: View {
    @EnvironmentObject var model: LeapModel
    let title: String
    let heatingKey: String
    let ventKey: String
    let position: String

    @State private var heating = 0
    @State private var vent = 0

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    if heating > 0 { Pill(text: "加热 \(heating)", color: Theme.orange) }
                    if vent > 0 { Pill(text: "通风 \(vent)", color: Theme.blue) }
                }
                LevelSelector(title: "加热",
                              level: $heating,
                              maxLevel: 3) { lv in
                    Task { await model.setSeatHeating(position, level: lv) }
                }
                LevelSelector(title: "通风",
                              level: $vent,
                              maxLevel: 3) { lv in
                    Task { await model.setSeatVentilation(position, level: lv) }
                }
            }
        }
        .onAppear {
            heating = model.status.seatHeating(heatingKey) ?? 0
            vent = model.status.seatVentilation(ventKey) ?? 0
        }
        .onChange(of: model.status.raw.count) { _ in
            heating = model.status.seatHeating(heatingKey) ?? 0
            vent = model.status.seatVentilation(ventKey) ?? 0
        }
    }
}

// ============================================================ 健康充电

struct HealthyChargingCard: View {
    @EnvironmentObject var model: LeapModel
    @State private var enabled = false
    @State private var soc = 80

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("健康充电", systemImage: "heart.text.square.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Toggle("", isOn: $enabled)
                        .labelsHidden()
                        .tint(Theme.brand)
                }
                Text("限制慢充上限以延长电池寿命")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textFaint)

                if enabled {
                    StepSelector(title: "目标电量", value: $soc, range: 50...100, unit: "%")
                }

                PrimaryButton(title: "保存设置", enabled: !model.isBusy) {
                    Task { await model.setHealthyCharging(enabled: enabled, soc: soc) }
                }
            }
        }
        .onAppear {
            enabled = model.status.healthyChargeEnabled ?? false
            soc = model.status.targetSoc ?? 80
        }
    }
}

// ============================================================ 预约充电

struct ScheduledChargingCard: View {
    @EnvironmentObject var model: LeapModel
    @State private var enabled = false
    @State private var startHour = 22
    @State private var endHour = 6
    @State private var soc = 90
    @State private var continueUntilLimit = true

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("预约充电", systemImage: "clock.badge.checkmark.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Toggle("", isOn: $enabled)
                        .labelsHidden()
                        .tint(Theme.brand)
                }

                if enabled {
                    StepSelector(title: "开始时间", value: $startHour, range: 0...23, unit: ":00")
                    StepSelector(title: "结束时间", value: $endHour, range: 0...23, unit: ":00")
                    StepSelector(title: "目标电量", value: $soc, range: 50...100, unit: "%")
                    Toggle(isOn: $continueUntilLimit) {
                        Text("充满后继续补电")
                            .font(.system(size: 13.5))
                            .foregroundColor(Theme.textDim)
                    }
                    .tint(Theme.brand)
                }

                PrimaryButton(title: enabled ? "保存预约" : "关闭预约充电", enabled: !model.isBusy) {
                    Task {
                        await model.setScheduledCharging(
                            enabled: enabled,
                            start: String(format: "%02d:00", startHour),
                            end: String(format: "%02d:00", endHour),
                            soc: soc)
                    }
                }
            }
        }
        .onAppear {
            if let on = model.status.chargeScheduleEnabled { enabled = on }
            if let start = model.status.chargeScheduleStart,
               let h = Int(start.split(separator: ":").first ?? "") { startHour = h }
            if let end = model.status.chargeScheduleEnd,
               let h = Int(end.split(separator: ":").first ?? "") { endHour = h }
            if let target = model.status.targetSoc { soc = target }
        }
    }
}

// ============================================================ 定时空调

struct ScheduledAcCard: View {
    @EnvironmentObject var model: LeapModel
    @State private var plan = ScheduledAcPlan()
    @State private var showEditor = false

    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label("定时空调", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text(plan.enabled
                         ? "\(plan.startTime) · \(plan.temperatureC)°C · \(LeapDays.summary(plan.days))"
                         : "未设置预约")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textFaint)
                }
                Spacer()
                Button("设置") { showEditor = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.brand)
                    .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showEditor) {
            ScheduledAcEditor(plan: $plan)
        }
        .onAppear { plan = model.scheduledAc }
        .onChange(of: model.scheduledAc.enabled) { newValue in
            if plan.enabled != newValue { plan = model.scheduledAc }
        }
    }
}
