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
                            .foregroundColor(Theme.textSecondary)
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
                                .foregroundColor(Theme.textSecondary)
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
