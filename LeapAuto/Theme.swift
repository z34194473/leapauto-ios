//
//  Theme.swift
//  设计系统：颜色 / 卡片 / 通用组件
//

import SwiftUI

enum Theme {
    // 主品牌色（接近零跑官方绿）
    static let brand = Color(red: 0.18, green: 0.72, blue: 0.55)
    static let brandDark = Color(red: 0.10, green: 0.55, blue: 0.42)

    static let bg = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let card = Color(red: 0.12, green: 0.13, blue: 0.16)
    static let cardHi = Color(red: 0.16, green: 0.18, blue: 0.21)

    static let text = Color.white
    static let textDim = Color.white.opacity(0.62)
    static let textFaint = Color.white.opacity(0.38)

    static let green = Color(red: 0.28, green: 0.85, blue: 0.55)
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.20)
    static let red = Color(red: 0.96, green: 0.34, blue: 0.34)
    static let blue = Color(red: 0.36, green: 0.66, blue: 1.0)
    static let purple = Color(red: 0.68, green: 0.52, blue: 1.0)

    static let radius: CGFloat = 18
}

// ============================================================ 卡片容器

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textDim)
            Spacer()
            if let trailing = trailing {
                Text(trailing)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textFaint)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
}

// ============================================================ 状态徽标

struct Pill: View {
    let text: String
    var color: Color = Theme.green

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(0.16))
            )
    }
}

// ============================================================ 信息行

struct InfoRow: View {
    let title: String
    let value: String
    var color: Color = Theme.text
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textFaint)
                    .frame(width: 18)
            }
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(Theme.textDim)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
    }
}

// ============================================================ 圆形操作按钮

struct ActionButton: View {
    let title: String
    let icon: String
    var active: Bool = false
    var tint: Color = Theme.brand
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(active ? tint.opacity(0.22) : Color.white.opacity(0.07))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(active ? tint : Theme.text.opacity(0.9))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(active ? tint : Theme.textDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.38 : 1)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// ============================================================ 主按钮

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var enabled: Bool = true
    var color: Color = Theme.brand
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon = icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(enabled ? .black : Theme.textFaint)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(enabled ? color : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(!enabled)
    }
}

// ============================================================ 电量环形

struct BatteryRing: View {
    let percent: Int
    let charging: Bool
    var size: CGFloat = 92

    private var ringColor: Color {
        if charging { return Theme.green }
        if percent <= 15 { return Theme.red }
        if percent <= 30 { return Theme.orange }
        return Theme.brand
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.09), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                .stroke(
                    AngularGradient(colors: [ringColor.opacity(0.65), ringColor],
                                    center: .center),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: percent)

            VStack(spacing: 1) {
                Text("\(percent)")
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                Text("%")
                    .font(.system(size: size * 0.11, weight: .semibold))
                    .foregroundColor(Theme.textDim)
            }
        }
        .frame(width: size, height: size)
    }
}

// ============================================================ 横向进度条

struct ProgressBar: View {
    let value: Double          // 0...1
    var color: Color = Theme.brand
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.09))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

// ============================================================ 空状态

struct EmptyHint: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundColor(Theme.textFaint)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Theme.textFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

// ============================================================ 分段控件

struct SegmentItem<T: Hashable>: Identifiable {
    let value: T
    let title: String
    var id: T { value }
}

struct SegmentedBar<T: Hashable>: View {
    let items: [SegmentItem<T>]
    @Binding var selection: T

    init(items: [SegmentItem<T>], selection: Binding<T>) {
        self.items = items
        self._selection = selection
    }

    /// 便捷构造：[(值, 标题)]
    init(items: [(T, String)], selection: Binding<T>) {
        self.items = items.map { SegmentItem(value: $0.0, title: $0.1) }
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selection = item.value }
                } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(selection == item.value ? .black : Theme.textDim)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(selection == item.value ? Theme.brand : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

// ============================================================ 步进选择器

struct StepSelector: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var unit: String = ""

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(Theme.textDim)
            Spacer()
            HStack(spacing: 0) {
                stepButton("minus") {
                    if value > range.lowerBound { value -= 1 }
                }
                Text("\(value)\(unit)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.text)
                    .frame(minWidth: 54)
                stepButton("plus") {
                    if value < range.upperBound { value += 1 }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
        }
        .padding(.vertical, 4)
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.textDim)
                .frame(width: 36, height: 34)
        }
        .buttonStyle(.plain)
    }
}

// ============================================================ 档位选择（0-3）

struct LevelSelector: View {
    let title: String
    @Binding var level: Int
    var maxLevel: Int = 3
    var onCommit: (Int) -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(Theme.textDim)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0...maxLevel, id: \.self) { lv in
                    Button {
                        level = lv
                        onCommit(lv)
                    } label: {
                        Text(lv == 0 ? "关" : "\(lv)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(level == lv ? .black : Theme.textDim)
                            .frame(width: 34, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(level == lv ? Theme.brand : Color.white.opacity(0.07))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
