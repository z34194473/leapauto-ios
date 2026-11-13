//
//  HomeView.swift
//  首页：车辆概览 / 电量续航 / 快捷控制 / 状态卡片
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var model: LeapModel
    @State private var showVehiclePicker = false
    @State private var showPhoto = false

    private var s: LeapStatus { model.status }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                vehicleBar
                if s.hasAnyData {
                    energyCard
                    quickCard
                    if s.isReev { hybridCard }
                    lockCard
                    climateCard
                    tireCard
                    securityCard
                    travelCard
                } else {
                    placeholder
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(Theme.bg.ignoresSafeArea())
        .refreshable { await model.refresh() }
        .sheet(isPresented: $showVehiclePicker) { VehiclePickerSheet() }
        .sheet(isPresented: $showPhoto) { PhotoSheet() }
    }

    // ---------------------------------------------------------- 车辆条

    private var vehicleBar: some View {
        Button {
            showVehiclePicker = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.07)).frame(width: 38, height: 38)
                    Image(systemName: "car.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.brand)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedVehicle?.title ?? "未选择车辆")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text(model.selectedVehicle?.subtitle ?? "点击选择车辆")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textFaint)
                }
                Spacer()
                if s.isCharging {
                    Pill(text: "充电中", color: Theme.green)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.textFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Theme.card)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // ---------------------------------------------------------- 电量与续航

    private var energyCard: some View {
        Card {
            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    BatteryRing(percent: s.socPercent ?? 0, charging: s.isCharging)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(s.isCharging ? "正在充电" : "电量状态")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.textDim)
                            if let temp = s.batteryTemp {
                                Pill(text: "\(temp)°", color: Theme.blue)
                            }
                        }

                        if let range = s.remainingRange {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(range)
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.text)
                                Text("km")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Theme.textDim)
                            }
                            Text(rangeLabel)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textFaint)
                        } else {
                            Text("暂无续航数据")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textFaint)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if s.isCharging || s.chargeState == 4 {
                    Divider().background(Color.white.opacity(0.07))
                    HStack(spacing: 12) {
                        statItem("充电状态", s.chargeLabel)
                        if let power = s.chargePower {
                            statItem("充电功率", power)
                        }
                        if let remaining = s.chargeRemaining {
                            statItem("预计充满", remaining)
                        }
                    }
                }

                if let total = s.totalMileage {
                    Divider().background(Color.white.opacity(0.07))
                    HStack {
                        Image(systemName: "gauge.medium")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textFaint)
                        Text("总里程")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textDim)
                        Spacer()
                        Text("\(total) km")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.text)
                    }
                }
            }
        }
    }

    private var rangeLabel: String {
        switch s.any("rangeMode") as? String {
        case "0": return "标准续航"
        case "1": return "动态续航"
        default: return "剩余续航"
        }
    }

    private func statItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textFaint)
            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ---------------------------------------------------------- 增程信息

    private var hybridCard: some View {
        Card {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "fuelpump.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.orange)
                    Text("增程模式")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textDim)
                    Spacer()
                    if let f = s.fuelSocPercent {
                        Text("油量 \(f)%")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(Theme.orange)
                    }
                }
                HStack(spacing: 12) {
                    if let e = LeapValue.text(s.any("electricRangeStandard")) {
                        statItem("纯电续航", "\(e) km")
                    }
                    if let f = s.fuelRange {
                        statItem("燃油续航", "\(f) km")
                    }
                    if let c = s.combinedRange {
                        statItem("综合续航", "\(c) km")
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- 快捷控制

    private var quickCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "快捷控制")

                HStack(spacing: 4) {
                    ActionButton(title: s.isLocked == true ? "解锁" : "上锁",
                                 icon: s.isLocked == true ? "lock.open.fill" : "lock.fill",
                                 active: s.isLocked == false,
                                 disabled: model.isBusy) {
                        Task {
                            await model.run(s.isLocked == true ? LeapCommands.unlock : LeapCommands.lock)
                        }
                    }

                    ActionButton(title: "后备箱",
                                 icon: "car.rear.and.collision.road.lane",
                                 active: s.trunkOpen == true,
                                 disabled: model.isBusy) {
                        Task {
                            await model.run(s.trunkOpen == true ? LeapCommands.trunkClose : LeapCommands.trunkOpen)
                        }
                    }

                    ActionButton(title: s.acOn == true ? "关空调" : "开空调",
                                 icon: "fan.fill",
                                 active: s.acOn == true,
                                 disabled: model.isBusy) {
                        Task {
                            await model.run(s.acOn == true ? LeapCommands.acOff : LeapCommands.acOn)
                        }
                    }

                    ActionButton(title: "寻车",
                                 icon: "light.beacon.max.fill",
                                 disabled: model.isBusy) {
                        Task { await model.run(LeapCommands.horn) }
                    }

                    ActionButton(title: s.sentryMode == true ? "关哨兵" : "哨兵",
                                 icon: "shield.lefthalf.filled",
                                 active: s.sentryMode == true,
                                 tint: Theme.purple,
                                 disabled: model.isBusy) {
                        Task {
                            await model.run(s.sentryMode == true ? LeapCommands.sentryOff : LeapCommands.sentryOn)
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- 门锁

    private var lockCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: s.isLocked == true ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 13))
                        .foregroundColor(s.isLocked == true ? Theme.green : Theme.orange)
                    Text("车锁状态")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Text(s.isLocked == true ? "已上锁" : (s.isLocked == false ? "未上锁" : "未知"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(s.isLocked == true ? Theme.green : Theme.orange)
                }

                if !s.doors.isEmpty {
                    Divider().background(Color.white.opacity(0.07))
                    HStack(spacing: 0) {
                        ForEach(s.doors) { door in
                            VStack(spacing: 4) {
                                Image(systemName: door.open ? "door.left.hand.open" : "door.left.hand.closed")
                                    .font(.system(size: 15))
                                    .foregroundColor(door.open ? Theme.orange : Theme.textDim)
                                Text(door.name)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(Theme.textFaint)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                if !s.windows.isEmpty {
                    Divider().background(Color.white.opacity(0.07))
                    HStack(spacing: 0) {
                        ForEach(s.windows) { w in
                            VStack(spacing: 4) {
                                Image(systemName: w.open ? "arrow.up.square.fill" : "square.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(w.open ? Theme.orange : Theme.textDim)
                                Text(w.name)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(Theme.textFaint)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- 空调

    private var climateCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 13))
                        .foregroundColor(toneColor)
                    Text("车内环境")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.text)
                    Spacer()
                    if let t = s.interiorTemp {
                        Text("\(t)°")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(toneColor)
                    }
                }

                HStack(spacing: 12) {
                    if let setting = s.acSetting {
                        statItem("设定温度", "\(setting)°")
                    }
                    if let vol = s.acAirVolume {
                        statItem("风量", vol)
                    }
                    statItem("空调", s.acOn == true ? "开启" : "关闭")
                }
            }
        }
    }

    private var toneColor: Color {
        switch s.climateTone {
        case .cooling: return Theme.blue
        case .heating: return Theme.orange
        case .ventilation: return Theme.green
        case .idle: return Theme.textDim
        }
    }

    // ---------------------------------------------------------- 胎压

    private var tireCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textDim)
                    Text("胎压")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.text)
                    Spacer()
                    if s.tires.contains(where: { $0.abnormal }) {
                        Pill(text: "异常", color: Theme.red)
                    } else if !s.tires.isEmpty {
                        Pill(text: "正常", color: Theme.green)
                    }
                }

                if s.tires.isEmpty {
                    Text("暂无胎压数据")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textFaint)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(s.tires) { tire in
                            HStack {
                                Text(tire.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.textDim)
                                Spacer()
                                Text(tire.value ?? "--")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(tire.abnormal ? Theme.red : Theme.text)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- 安防与驻车

    private var securityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "安防与驻车")
                InfoRow(title: "哨兵模式",
                        value: s.sentryMode == true ? "已开启" : "已关闭",
                        color: s.sentryMode == true ? Theme.purple : Theme.textDim,
                        icon: "shield.lefthalf.filled")
                InfoRow(title: "电子手刹",
                        value: s.parkingBrake == true ? "已拉起" : "已释放",
                        color: s.parkingBrake == true ? Theme.green : Theme.textDim,
                        icon: "parkingsign")
                if let mirrors = s.mirrorHeating {
                    InfoRow(title: "后视镜加热",
                            value: mirrors ? "已开启" : "已关闭",
                            color: mirrors ? Theme.orange : Theme.textDim,
                            icon: "square.split.bottomrightquarter")
                }
                Button {
                    showPhoto = true
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textFaint)
                            .frame(width: 18)
                        Text("驻车环视照片")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textDim)
                        Spacer()
                        Text("查看")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.brand)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ---------------------------------------------------------- 行驶信息

    private var travelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "行驶信息")
                if let gear = s.gear {
                    InfoRow(title: "档位", value: gear, icon: "gearshape.fill")
                }
                if let speed = s.speed {
                    InfoRow(title: "车速", value: "\(speed) km/h", icon: "speedometer")
                }
                if let limit = s.speedLimit {
                    InfoRow(title: "限速", value: "\(limit) km/h", icon: "exclamationmark.circle")
                }
                if let c = s.coordinate {
                    InfoRow(title: "位置",
                            value: String(format: "%.4f, %.4f", c.lat, c.lon),
                            icon: "location.fill")
                }
            }
        }
    }

    // ---------------------------------------------------------- 占位

    private var placeholder: some View {
        Card {
            VStack(spacing: 14) {
                EmptyHint(icon: "car.badge.gearshape",
                          text: model.vehicles.isEmpty
                            ? "正在获取车辆信息"
                            : "点击右上角刷新，或下拉获取车况")
                if let last = model.lastRefresh {
                    Text("上次更新 \(timeText(last))")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textFaint)
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

// ============================================================ 车辆选择

struct VehiclePickerSheet: View {
    @EnvironmentObject var model: LeapModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.vehicles) { v in
                    Button {
                        model.selectVehicle(v)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.white.opacity(0.07)).frame(width: 36, height: 36)
                                Image(systemName: "car.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.brand)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Theme.text)
                                Text(v.subtitle)
                                    .font(.system(size: 11.5))
                                    .foregroundColor(Theme.textFaint)
                            }
                            Spacer()
                            if v.vin == model.api.selectedVin {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Theme.brand)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("选择车辆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(Theme.brand)
                }
            }
        }
        .sheetBackgroundCompat(Theme.bg)
    }
}

// ============================================================ 驻车照片

struct PhotoSheet: View {
    @EnvironmentObject var model: LeapModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if loading {
                    ProgressView().tint(Theme.brand)
                } else if let image = image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    }
                } else if let photo = model.chassisPhoto {
                    VStack(spacing: 14) {
                        EmptyHint(icon: "photo.badge.exclamationmark",
                                  text: "图片未加载，可尝试重新获取")
                        Text(photo.fileUrl)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.textFaint)
                            .lineLimit(2)
                        PrimaryButton(title: "加载图片", icon: "arrow.down.circle") {
                            Task { await load(photo.fileUrl) }
                        }
                        .padding(.horizontal, 40)
                    }
                } else {
                    VStack(spacing: 14) {
                        EmptyHint(icon: "camera.metering.unknown",
                                  text: "该车型暂无驻车环视照片")
                        PrimaryButton(title: "重新获取", icon: "arrow.clockwise") {
                            Task {
                                await model.loadChassisPhoto()
                                if let photo = model.chassisPhoto {
                                    await load(photo.fileUrl)
                                }
                            }
                        }
                        .padding(.horizontal, 40)
                    }
                }
            }
            .navigationTitle("驻车环视")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(Theme.brand)
                }
            }
        }
        .sheetBackgroundCompat(Theme.bg)
        .task {
            if model.chassisPhoto == nil { await model.loadChassisPhoto() }
            if let photo = model.chassisPhoto { await load(photo.fileUrl) }
        }
    }

    private func load(_ url: String) async {
        guard let u = URL(string: url) else { return }
        loading = true
        defer { loading = false }
        if let (data, _) = try? await URLSession.shared.data(from: u),
           let img = UIImage(data: data) {
            image = img
        }
    }
}
