//
//  LoginView.swift
//  登录界面：短信登录 / 凭据导入 / 设备信息
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var model: LeapModel
    @State private var mode: LoginMode = .sms
    @State private var showAdvanced = false

    enum LoginMode: Hashable { case sms, raw }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    SegmentedBar(items: [(.sms, "短信登录"), (.raw, "凭据导入")], selection: $mode)
                        .padding(.horizontal, 2)

                    if mode == .sms { smsCard } else { rawCard }

                    deviceCard
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .overlay(alignment: .bottom) { BannerHost() }
        .sheet(isPresented: Binding(
            get: { model.geetest.isPresented },
            set: { model.geetest.isPresented = $0 }
        )) {
            GeetestSheet(coordinator: model.geetest)
        }
    }

    // ---------------------------------------------------------- 头部

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Theme.brand, Theme.brandDark],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 74, height: 74)
                Image(systemName: "car.side.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.black.opacity(0.82))
            }
            .shadow(color: Theme.brand.opacity(0.35), radius: 18, y: 8)

            Text("零跑智控")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Theme.text)
            Text("iOS 移植版 · 车况与远程控制")
                .font(.system(size: 12.5))
                .foregroundColor(Theme.textFaint)
        }
        .padding(.top, 22)
        .padding(.bottom, 6)
    }

    // ---------------------------------------------------------- 短信登录

    private var smsCard: some View {
        Card {
            VStack(spacing: 14) {
                field(icon: "phone.fill", placeholder: "手机号",
                      text: $model.phone, keyboard: .numberPad)

                HStack(spacing: 10) {
                    field(icon: "key.fill", placeholder: "短信验证码",
                          text: $model.smsCode, keyboard: .numberPad)
                    Button {
                        Task { await model.sendSms() }
                    } label: {
                        Text("获取验证码")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.brand)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Theme.brand.opacity(0.14))
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(model.phone.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
                }

                PrimaryButton(title: "登录", icon: "arrow.right.circle.fill",
                              enabled: !model.isBusy
                                  && !model.phone.isEmpty
                                  && !model.smsCode.isEmpty) {
                    Task { await model.loginWithSms() }
                }
            }
        }
    }

    // ---------------------------------------------------------- 凭据导入

    private var rawCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("从 Android 端导出登录凭据后粘贴，可绕过数美设备校验与极验风控。")
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $model.rawAuthText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 132)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.black.opacity(0.28))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )

                Text("支持：完整 JSON / accountId,token[,refreshToken] / 含 token 与 accountId 的任意文本")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textFaint)

                TextField("手机号（可选，用于旧 token 续期）", text: $model.phone)
                    .keyboardType(.numberPad)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )

                PrimaryButton(title: "导入并登录", icon: "square.and.arrow.down.fill",
                              enabled: !model.isBusy
                                  && !model.rawAuthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    Task { await model.importCredentials() }
                }
            }
        }
    }

    // ---------------------------------------------------------- 设备信息

    private var deviceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
                } label: {
                    HStack {
                        Text("设备指纹设置")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textDim)
                        Spacer()
                        Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.textFaint)
                    }
                }
                .buttonStyle(.plain)

                if showAdvanced {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Android 端的 smDeviceId 由数美 SDK 生成，iOS 无法生成。若短信登录被风控拦截，请改用凭据导入。")
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.textFaint)
                            .fixedSize(horizontal: false, vertical: true)

                        TextField("粘贴 Android 端 smDeviceId（可留空）", text: $model.smDeviceIdInput)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Theme.text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )

                        HStack {
                            Text("deviceId")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textFaint)
                            Spacer()
                            Text(model.api.deviceId)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Theme.textDim)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- 页脚

    private var footer: some View {
        VStack(spacing: 5) {
            Text("协议由 Android 原版 4.5.15 逆向移植")
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textFaint)
            Text("仅用于个人车辆管理")
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textFaint.opacity(0.7))
        }
        .padding(.top, 8)
    }

    // ---------------------------------------------------------- 输入框

    private func field(icon: String, placeholder: String,
                       text: Binding<String>,
                       keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Theme.textFaint)
                .frame(width: 18)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .font(.system(size: 15))
                .foregroundColor(Theme.text)
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

// ============================================================ 全局横幅

struct BannerHost: View {
    @EnvironmentObject var model: LeapModel

    var body: some View {
        if let banner = model.banner {
            HStack(spacing: 9) {
                Image(systemName: icon(banner.kind))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color(banner.kind))
                Text(banner.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.cardHi)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(color(banner.kind).opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onTapGesture { model.banner = nil }
        }
    }

    private func icon(_ kind: LeapModel.Banner.Kind) -> String {
        switch kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func color(_ kind: LeapModel.Banner.Kind) -> Color {
        switch kind {
        case .info: return Theme.blue
        case .success: return Theme.green
        case .warning: return Theme.orange
        case .error: return Theme.red
        }
    }
}
