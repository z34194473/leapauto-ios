//
//  ScheduledAcEditor.swift
//  定时空调编辑面板
//

import SwiftUI

struct ScheduledAcEditor: View {
    @EnvironmentObject var model: LeapModel
    @Environment(\.dismiss) private var dismiss
    @Binding var plan: ScheduledAcPlan

    @State private var draft = ScheduledAcPlan()
    @State private var hour = 7
    @State private var minute = 30
    @State private var days: Set<Int> = Set(1...7)

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        enableCard
                        if draft.enabled {
                            timeCard
                            dayCard
                            paramCard
                        }
                        saveButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("定时空调")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundColor(Theme.textDim)
                }
            }
        }
        .presentationBackground(Theme.bg)
        .onAppear { load() }
    }

    private func load() {
        draft = plan
        let parts = plan.startTime.split(separator: ":")
        if parts.count >= 2 {
            hour = Int(parts[0]) ?? 7
            minute = Int(parts[1]) ?? 30
        }
        days = LeapDays.parseToDaySet(plan.days)
    }

    // ---------------------------------------------------------- 开关

    private var enableCard: some View {
        Card {
            Toggle(isOn: $draft.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("启用定时空调")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text("按设定时间自动开启空调")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textFaint)
                }
            }
            .tint(Theme.brand)
        }
    }

    // ---------------------------------------------------------- 时间

    private var timeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "开始时间")
                StepSelector(title: "小时", value: $hour, range: 0...23, unit: " 时")
                StepSelector(title: "分钟", value: $minute, range: 0...55, unit: " 分")
                Text("分钟步进 5，当前 \(String(format: "%02d:%02d", hour, minute / 5 * 5))")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textFaint)
            }
        }
        .onChange(of: minute) { newValue in
            minute = (newValue / 5) * 5
        }
    }

    // ---------------------------------------------------------- 星期

    private var dayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "重复日期", trailing: LeapDays.summary(days))
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { d in
                        Button {
                            if days.contains(d) { days.remove(d) } else { days.insert(d) }
                        } label: {
                            Text(weekName(d))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(days.contains(d) ? .black : Theme.textDim)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(days.contains(d) ? Theme.brand : Color.white.opacity(0.07))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    quickDay("工作日", Set(1...5))
                    quickDay("周末", Set([6, 7]))
                    quickDay("每天", Set(1...7))
                }
            }
        }
    }

    private func weekName(_ d: Int) -> String {
        ["一", "二", "三", "四", "五", "六", "日"][d - 1]
    }

    private func quickDay(_ title: String, _ set: Set<Int>) -> some View {
        Button {
            days = set
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.brand)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.brand.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
    }

    // ---------------------------------------------------------- 参数

    private var paramCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "温度与风量")
                StepSelector(title: "温度", value: $draft.temperatureC, range: 16...32, unit: "°C")
                StepSelector(title: "风量", value: $draft.windLevel, range: 1...7, unit: " 档")

                SectionTitle(text: "模式")
                SegmentedBar(items: [
                    ("cold", "制冷"),
                    ("hot", "制热"),
                    ("nohotcold", "自动")
                ], selection: $draft.mode)

                SectionTitle(text: "循环")
                SegmentedBar(items: [
                    ("in", "内循环"),
                    ("out", "外循环")
                ], selection: $draft.circle)

                Toggle(isOn: $draft.windshieldDefogging) {
                    Text("开启前挡除雾")
                        .font(.system(size: 13.5))
                        .foregroundColor(Theme.textDim)
                }
                .tint(Theme.brand)
            }
        }
    }

    // ---------------------------------------------------------- 保存

    private var saveButton: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: draft.enabled ? "保存定时空调" : "关闭定时空调",
                          icon: "checkmark.circle.fill",
                          enabled: !model.isBusy) {
                plan = draft
                plan.startTime = String(format: "%02d:%02d", hour, minute / 5 * 5)
                plan.days = (1...7).map { days.contains($0) ? "1" : "0" }.joined(separator: ",")
                Task {
                    await model.saveScheduledAc(plan)
                    dismiss()
                }
            }
            Text("定时任务由车端执行，需保持车辆联网")
                .font(.system(size: 11))
                .foregroundColor(Theme.textFaint)
        }
    }
}
