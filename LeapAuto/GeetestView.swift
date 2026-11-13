//
//  GeetestView.swift
//  极验 v4 人机验证（WKWebView 方案）
//
//  原理：零跑 APK 用内嵌 HTML + WebView 加载 gt4.js，
//  iOS 用 WKWebView 复现同一套逻辑，桥接名保持 AndroidBridge。
//

import SwiftUI
import WebKit
import Foundation

// ============================================================
//  WKWebView 包装
// ============================================================

struct GeetestWebView: UIViewRepresentable {
    let captchaId: String
    let riskType: String
    let onReady: () -> Void
    let onSuccess: (GeetestResult) -> Void
    let onError: (String) -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReady: onReady, onSuccess: onSuccess,
                    onError: onError, onClose: onClose)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "AndroidBridge")
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false

        let html = GeetestPage.html(captchaId: captchaId, riskType: riskType)
        webView.loadHTMLString(html, baseURL: URL(string: "https://static.geetest.com"))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController
            .removeScriptMessageHandler(forName: "AndroidBridge")
        uiView.stopLoading()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onReady: () -> Void
        let onSuccess: (GeetestResult) -> Void
        let onError: (String) -> Void
        let onClose: () -> Void

        init(onReady: @escaping () -> Void,
             onSuccess: @escaping (GeetestResult) -> Void,
             onError: @escaping (String) -> Void,
             onClose: @escaping () -> Void) {
            self.onReady = onReady
            self.onSuccess = onSuccess
            self.onError = onError
            self.onClose = onClose
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                switch type {
                case "ready":
                    self.onReady()
                case "success":
                    if let data = body["data"] as? [String: Any] {
                        self.onSuccess(GeetestResult(raw: data))
                    } else {
                        self.onError("验证结果为空")
                    }
                case "error":
                    self.onError(body["message"] as? String ?? "验证失败")
                case "close":
                    self.onClose()
                default:
                    break
                }
            }
        }
    }
}

// ============================================================
//  验证弹窗
// ============================================================

@MainActor
final class GeetestCoordinator: ObservableObject {
    @Published var isPresented = false
    @Published var isReady = false
    @Published var errorText: String?

    private(set) var captchaId = GeetestPage.defaultCaptchaId
    private(set) var riskType = ""
    private var completion: ((GeetestResult?) -> Void)?

    /// 开始验证；用户取消或失败时回调 nil
    func begin(riskType: String, completion: @escaping (GeetestResult?) -> Void) {
        self.riskType = riskType
        self.captchaId = GeetestPage.captchaId(from: riskType)
        self.completion = completion
        self.isReady = false
        self.errorText = nil
        self.isPresented = true
    }

    func handleSuccess(_ result: GeetestResult) {
        isPresented = false
        let cb = completion
        completion = nil
        cb?(result)
    }

    func handleClose() {
        isPresented = false
        let cb = completion
        completion = nil
        cb?(nil)
    }

    func handleError(_ message: String) {
        errorText = message
        isPresented = false
        let cb = completion
        completion = nil
        cb?(nil)
    }

    func cancel() { handleClose() }
}

/// 验证界面（放进 sheet）
struct GeetestSheet: View {
    @ObservedObject var coordinator: GeetestCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var spinning = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("安全验证")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        coordinator.cancel()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.textDim)
                            .padding(8)
                            .background(Theme.card)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                ZStack {
                    if !coordinator.isReady {
                        VStack(spacing: 14) {
                            ProgressView()
                                .scaleEffect(1.1)
                                .tint(Theme.brand)
                            Text("正在加载验证组件…")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textDim)
                        }
                    }

                    GeetestWebView(
                        captchaId: coordinator.captchaId,
                        riskType: coordinator.riskType,
                        onReady: {
                            coordinator.isReady = true
                        },
                        onSuccess: { result in
                            if result.isValid {
                                coordinator.handleSuccess(result)
                                dismiss()
                            } else {
                                coordinator.handleError("验证结果不完整，请重试")
                                dismiss()
                            }
                        },
                        onError: { message in
                            coordinator.handleError(message)
                            dismiss()
                        },
                        onClose: {
                            coordinator.handleClose()
                            dismiss()
                        }
                    )
                    .opacity(coordinator.isReady ? 1 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .interactiveDismissDisabled()
    }
}
