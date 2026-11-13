//
//  LeapAPI.swift
//  云端接口层：登录 / 网关签名 / 车辆 / 车况 / 控车 / 预约 / 蓝牙钥匙证书
//  与 LeapmotorApi.kt 与 CF.smali 逐行对齐
//

import Foundation

#if canImport(FoundationNetworking)
// 非 Apple 平台（Linux / Windows）需单独导入网络模块；
// Apple 平台的 URLSession 已在 Foundation 中。
import FoundationNetworking
#endif

// ============================================================ 端点常量

enum LeapHost {
    static let global = "https://app-gw-global-master.leapmotor.com"
    static let gateway = "https://appgateway.leapmotor.com"
    static let user = "https://appuser.leapmotor.cn"
    static let iov = "https://iov-api.leapmotor.com"

    static let appVersion = "1.23.00"
    static let subVersion = "3.24.5-1"

    // 旧链路
    static let sendSms = "/app-user/applogin/compliance/sendmessagecode"
    static let smsLogin = "/app-user/applogin/check_login_with_phone"
    static let refreshOldToken = "/app-user/appuseroperate/getnewtoken"
    static let bluetoothCertificate = "/carownerservice/v3/api/bluetoothkey/combine/syncBluetoothKeys"
    static let bluetoothUploadRecords = "/carownerservice/v3/api/bluetoothkey/uploadRecords"

    // 新网关
    static let gatewayLogin = "/base/base-user/account/v1/login"
    static let gatewayRefresh = "/base/base-user/token/v1/refresh"
    static let vehicleList = "/app/app-global-service/v1/vehicle/list"
    static let carRoute = "/app/app-global-service/v1/vehicle/getCarRoute"
    static let signalQuery = "/app/app-signal-service/signal/info/query"
    static let commonConfig = "/carownerservice/v3/api/vehicleinfo/commonConfig"
    static let remoteControl = "/app/app-control-service/v3/api/appremotectl"
    static let remoteControlQuery = "/app/app-control-service/v3/api/appremotectl/query"
    static let appointment = "/carownerservice/v3/api/appremotectl/appointment"
    static let getAppointment = "/carownerservice/v3/api/appremotectl/getappointment"
    static let themeList = "/carownerservice/v3/api/theme/listThemeList"
    static let healthyChargingControl = "/carownerservice/v3/api/healthyCharging/control"
    static let healthyChargingState = "/carownerservice/v3/api/healthyCharging/queryPushState"
    static let mileageEnergy = "/carownerservice/v3/api/drivingrecord/mileage/energy/detail"
    static let chassisQuery = "/carownerservice/v3/api/chassis/query"
    static let bluetoothConfig = "/app/app-global-service/v3/api/commoninfo/transparent/conf/upload"
    static let bluetoothCalibration = "/app/app-global-service/v3/api/bluetoothkey/uploadAutonomyCalibrateParams"
}

// ============================================================ 数据模型

struct OldAuth: Codable, Equatable {
    var accountId: String
    var token: String
    var refreshToken: String
    var tokenExpired: String
    var tokenObtainedAt: Int64
}

struct NewAuth: Codable, Equatable {
    var accountId: String
    var accessToken: String
    var refreshToken: String
    var signKeyBase64: String
    var accessTokenExpiresAt: Int64

    var signKey: Data { Data(base64Encoded: signKeyBase64) ?? Data() }
}

struct RouteData: Codable, Equatable {
    var appRegion: String
    var appCenter: String
}

struct Vehicle: Identifiable, Hashable {
    let vin: String
    let carType: String
    let nickname: String
    let year: String
    let color: String
    let isShared: Bool

    var id: String { vin }
    var title: String { nickname.isEmpty ? String(vin.suffix(6)) : nickname }
    var subtitle: String {
        var parts: [String] = []
        if !carType.isEmpty { parts.append(carType) }
        if !year.isEmpty { parts.append(year) }
        parts.append(String(vin.suffix(6)))
        return parts.joined(separator: " · ")
    }
    var isReev: Bool {
        let t = carType.uppercased()
        return t.contains("REEV") || carType.contains("增程")
    }
}

struct ControlResult {
    let msgID: String
    let raw: [String: Any]
}

struct ScheduledPreheatPlan {
    var enabled: Bool
    var startTime: String
    var days: String
}

struct ChassisPhoto {
    let fileUrl: String
    let uploadTimeMs: Int64
}

// ============================================================ 错误

struct LeapAPIError: LocalizedError {
    let message: String
    let httpStatus: Int?
    let stage: String

    init(_ message: String, httpStatus: Int? = nil, stage: String = "") {
        self.message = message
        self.httpStatus = httpStatus
        self.stage = stage
    }

    var errorDescription: String? { message }
}

// ============================================================ API

/// 网络与签名层。所有方法均为线程安全的纯函数式调用（除会话状态），
/// 不标注 @MainActor，由调用方（LeapModel 在主线程）串行驱动。
final class LeapAPI: @unchecked Sendable {

    // 会话状态
    private(set) var deviceId: String
    private(set) var smDeviceId: String
    private(set) var phone: String
    private(set) var oldAuth: OldAuth?
    private(set) var newAuth: NewAuth?
    private(set) var route: RouteData?
    private(set) var selectedVin: String
    private(set) var selectedCarType: String
    private(set) var selectedNickname: String
    private(set) var selectedYear: String

    /// 每次登录/切车递增，用于作废过期的异步回调
    private(set) var generation: Int = 0

    private let storeKey = "leap.session.v2"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 45
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)

        let d = UserDefaults.standard.dictionary(forKey: storeKey) ?? [:]
        deviceId = (d["deviceId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? LeapSign.randomDeviceId()
        smDeviceId = d["smDeviceId"] as? String ?? ""
        phone = d["phone"] as? String ?? ""
        selectedVin = d["selectedVin"] as? String ?? ""
        selectedCarType = d["selectedCarType"] as? String ?? ""
        selectedNickname = d["selectedNickname"] as? String ?? ""
        selectedYear = d["selectedYear"] as? String ?? ""
        oldAuth = (d["oldAuth"] as? Data).flatMap { try? JSONDecoder().decode(OldAuth.self, from: $0) }
        newAuth = (d["newAuth"] as? Data).flatMap { try? JSONDecoder().decode(NewAuth.self, from: $0) }
        route = (d["route"] as? Data).flatMap { try? JSONDecoder().decode(RouteData.self, from: $0) }
    }

    // ---------------------------------------------------------- 持久化

    func persist() {
        var d: [String: Any] = [
            "deviceId": deviceId,
            "smDeviceId": smDeviceId,
            "phone": phone,
            "selectedVin": selectedVin,
            "selectedCarType": selectedCarType,
            "selectedNickname": selectedNickname,
            "selectedYear": selectedYear
        ]
        if let o = oldAuth, let b = try? JSONEncoder().encode(o) { d["oldAuth"] = b }
        if let n = newAuth, let b = try? JSONEncoder().encode(n) { d["newAuth"] = b }
        if let r = route, let b = try? JSONEncoder().encode(r) { d["route"] = b }
        UserDefaults.standard.set(d, forKey: storeKey)
    }

    func reset() {
        oldAuth = nil
        newAuth = nil
        route = nil
        selectedVin = ""
        selectedCarType = ""
        selectedNickname = ""
        selectedYear = ""
        generation += 1
        persist()
    }

    func setSmDeviceId(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        smDeviceId = trimmed
        persist()
    }

    /// 更换设备 ID（风控换环境用）
    func setDeviceId(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        deviceId = trimmed
        persist()
    }

    /// 生成并应用一个全新的随机 deviceId（32 位小写 hex）
    @discardableResult
    func rotateDeviceId() -> String {
        let hex = "0123456789abcdef"
        let fresh = String((0..<32).map { _ in hex.randomElement()! })
        deviceId = fresh
        persist()
        return fresh
    }

    func setPhone(_ value: String) {
        phone = value.trimmingCharacters(in: .whitespaces)
        persist()
    }

    func selectVehicle(_ v: Vehicle) {
        selectedVin = v.vin
        selectedCarType = v.carType
        selectedNickname = v.nickname
        selectedYear = v.year
        route = nil
        generation += 1
        persist()
    }

    var isLoggedIn: Bool { newAuth != nil && oldAuth != nil }
    var hasOldAuth: Bool { oldAuth != nil }

    // ---------------------------------------------------------- 签名助手

    private func oldAppHeaders(withToken: Bool) -> [String: String] {
        var h: [String: String] = [
            "User-Agent": "okhttp/4.9.3",
            "APPPlatform": "Android",
            "APPVersion": LeapHost.appVersion,
            "APPImei": deviceId,
            "C-VERSIONS": "APP",
            "XFX-CDN-VRS": "v4"
        ]
        if withToken, let old = oldAuth { h["XFX-CDN-CROSS-NODE"] = old.token }
        return h
    }

    /// 旧链路签名：timespan/nonce/deviceID/token 参与 md5Short，签完剔除 token
    func oldSignedParams(_ params: [String: String],
                         withRefreshToken: Bool = false,
                         includeTimespan: Bool = true) throws -> [String: String] {
        guard let old = oldAuth else { throw LeapAPIError("未登录（缺少旧 token）") }
        var map: [String: String?] = [:]
        if includeTimespan { map["timespan"] = String(Int64(Date().timeIntervalSince1970 * 1000)) }
        map["nonce"] = LeapSign.randomNonce()
        map["deviceID"] = deviceId
        if withRefreshToken { map["refreshtoken"] = old.refreshToken } else { map["token"] = old.token }
        for (k, v) in params { map[k] = v }

        let signStr = LeapSign.md5Short(LeapSign.sortAndConcat(map))
        map.removeValue(forKey: withRefreshToken ? "refreshtoken" : "token")

        var out: [String: String] = [:]
        for (k, v) in map where v != nil { out[k] = v }
        out["signStr"] = signStr
        return out
    }

    /// 新网关签名头
    func newGatewayHeaders(_ params: [String: String?] = [:], needLogin: Bool = true) throws -> [String: String] {
        let nonce = LeapSign.randomNonce()
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        var h: [String: String] = [
            "source": "leapmotor",
            "channel": "1",
            "acceptLanguage": "zh-CN",
            "x-region": "CN",
            "x-api-signature-version": "2.0",
            "digest": "",
            "version": LeapHost.appVersion,
            "deviceType": "android",
            "nonce": nonce,
            "timestamp": timestamp,
            "deviceId": deviceId,
            "userId": newAuth?.accountId ?? oldAuth?.accountId ?? "",
            "carvin": selectedVin,
            "cartype": selectedCarType,
            "x-subversion": LeapHost.subVersion
        ]
        let signHeaders: [String: String?] = [
            "acceptLanguage": "zh-CN",
            "channel": "1",
            "deviceId": deviceId,
            "deviceType": "android",
            "nonce": nonce,
            "source": "leapmotor",
            "timestamp": timestamp,
            "version": LeapHost.appVersion
        ]
        let signBase = LeapSign.sortAndConcat(signHeaders, params)
        if needLogin {
            guard let auth = newAuth else { throw LeapAPIError("未完成网关登录") }
            h["token"] = auth.accessToken
            h["userId"] = auth.accountId
            h["sign"] = LeapSign.hmacSHA256Hex(key: auth.signKey, signBase)
        } else {
            h["sign"] = LeapSign.sha256Hex(signBase)
        }
        return h
    }

    /// 旧头 +（有网关会话时）网关头
    func combinedHeaders(_ params: [String: String?] = [:], needLogin: Bool = true) throws -> [String: String] {
        var h = oldAppHeaders(withToken: true)
        if newAuth != nil {
            for (k, v) in try newGatewayHeaders(params, needLogin: needLogin) { h[k] = v }
        }
        return h
    }

    private func optionalMap(_ m: [String: String]) -> [String: String?] {
        var out: [String: String?] = [:]
        for (k, v) in m { out[k] = v }
        return out
    }

    // ---------------------------------------------------------- HTTP 底层

    private enum Body {
        case none
        case json(Any)
        case form([String: String])
        case empty
    }

    private func perform(_ url: String,
                         method: String = "GET",
                         headers: [String: String] = [:],
                         query: [String: String]? = nil,
                         body: Body = .none) async throws -> (status: Int, text: String) {
        var target = url
        if let q = query, !q.isEmpty {
            let qs = q.map { "\(LeapSign.formEncode($0.key))=\(LeapSign.formEncode($0.value))" }
                .joined(separator: "&")
            target += (url.contains("?") ? "&" : "?") + qs
        }
        guard let finalURL = URL(string: target) else {
            throw LeapAPIError("URL 非法: \(target.prefix(120))")
        }

        var req = URLRequest(url: finalURL)
        req.httpMethod = method
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        switch body {
        case .none:
            break
        case .json(let obj):
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: obj, options: [])
        case .form(let form):
            req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            let text = form.map { "\(LeapSign.formEncode($0.key))=\(LeapSign.formEncode($0.value))" }
                .joined(separator: "&")
            req.httpBody = Data(text.utf8)
        case .empty:
            req.httpBody = Data()
        }

        #if canImport(FoundationNetworking)
        // 非 Apple 平台：Foundation 尚无 async data(for:)，用 completion 包装
        return try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: req) { data, resp, error in
                if let error = error {
                    continuation.resume(throwing: LeapAPIError("网络请求失败，请检查网络后重试",
                                                              stage: "network: \(error.localizedDescription)"))
                    return
                }
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                continuation.resume(returning: (status, text))
            }.resume()
        }
        #else
        do {
            let (data, resp) = try await session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return (status, String(data: data, encoding: .utf8) ?? "")
        } catch {
            throw LeapAPIError("网络请求失败，请检查网络后重试", stage: "network")
        }
        #endif
    }

    private func requestJSON(_ url: String,
                             method: String = "GET",
                             headers: [String: String] = [:],
                             query: [String: String]? = nil,
                             body: Body = .none,
                             stage: String = "") async throws -> [String: Any] {
        let (status, text) = try await perform(url, method: method, headers: headers, query: query, body: body)
        guard status == 200 else {
            throw LeapAPIError("请求失败，HTTP \(status)", httpStatus: status, stage: stage)
        }
        guard !text.isEmpty else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw LeapAPIError("服务端响应格式异常", httpStatus: status, stage: stage)
        }
        return obj
    }

    // ---------------------------------------------------------- 响应工具

    func scalar(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    func businessResult(_ resp: [String: Any]) -> String? {
        for key in ["result", "code"] where resp[key] != nil && !(resp[key] is NSNull) {
            return scalar(resp[key])
        }
        return nil
    }

    func isSuccessCode(_ resp: [String: Any]) -> Bool {
        guard let code = businessResult(resp) else { return true }
        return code == "0" || code == "200"
    }

    func errorMessage(_ resp: [String: Any]) -> String {
        let raw = (resp["msg"] as? String) ?? (resp["message"] as? String) ?? ""
        if raw.contains("临时管制") { return "登录触发安全风控临时管制，请稍后重试" }
        if raw.contains("疑似高风险") {
            return "当前网络环境被风控拦截，请换用移动数据（4G/5G）或等待 10 分钟后重试"
        }
        if raw.contains("验证码") && (raw.contains("过期") || raw.contains("失效")) { return "验证码已失效，请重新获取" }
        if raw.contains("验证码") { return "验证码错误，请检查后重试" }
        if raw.contains("频繁") { return "请求过于频繁，请稍后重试" }
        return raw.isEmpty ? "服务端拒绝请求" : raw
    }

    func isAuthFailure(_ resp: [String: Any]) -> Bool {
        let code = (resp["code"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (resp["result"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (resp["status"] as? String) ?? ""
        if code == "401" || code == "403" { return true }
        let msg = ((resp["msg"] as? String ?? "") + (resp["message"] as? String ?? "")
            + (resp["error"] as? String ?? "")).lowercased()
        let hasAuth = msg.contains("token") || msg.contains("登录") || msg.contains("鉴权") || msg.contains("认证")
        let hasExpire = msg.contains("expire") || msg.contains("invalid")
            || msg.contains("过期") || msg.contains("失效") || msg.contains("无效") || msg.contains("重新登录")
        return hasAuth && hasExpire
    }

    func isOldAuthFailure(_ resp: [String: Any]) -> Bool {
        if let result = scalar(resp["result"]), result == "39" { return true }
        let msg = (resp["msg"] as? String ?? "") + (resp["message"] as? String ?? "")
        for pattern in ["信息校验失败", "第三方TOKEN失效", "token.*失效", "鉴权失败"] {
            if msg.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        }
        return false
    }

    func findObject(_ root: Any?, where predicate: ([String: Any]) -> Bool) -> [String: Any]? {
        guard let root = root else { return nil }
        if let d = root as? [String: Any] {
            if predicate(d) { return d }
            for k in d.keys {
                if let f = findObject(d[k], where: predicate) { return f }
            }
        } else if let a = root as? [Any] {
            for v in a {
                if let f = findObject(v, where: predicate) { return f }
            }
        }
        return nil
    }

    func collectObjects(_ root: Any?, where predicate: ([String: Any]) -> Bool) -> [[String: Any]] {
        var out: [[String: Any]] = []
        func walk(_ node: Any?) {
            guard let node = node else { return }
            if let d = node as? [String: Any] {
                if predicate(d) { out.append(d) }
                for k in d.keys { walk(d[k]) }
            } else if let a = node as? [Any] {
                for v in a { walk(v) }
            }
        }
        walk(root)
        return out
    }

    // ---------------------------------------------------------- 登录：短信

    @discardableResult
    func sendSms(phone rawPhone: String) async throws -> [String: Any] {
        let target = rawPhone.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { throw LeapAPIError("手机号不能为空") }
        let cipher = try LeapSign.rsaEncryptPhone(target)
        let resp = try await requestJSON(LeapHost.user + LeapHost.sendSms,
                                         headers: oldAppHeaders(withToken: false),
                                         query: ["phoneNo": cipher],
                                         stage: "sendmessagecode")
        guard isSuccessCode(resp) else {
            throw LeapAPIError("发送验证码失败: \(errorMessage(resp))", stage: "sendmessagecode")
        }
        return resp
    }

    /// 短信登录结果：可能是成功，也可能需要人机验证
    enum SmsLoginOutcome {
        /// 需要极验验证，携带 risk_type（内含 captchaId）
        case needCaptcha(riskType: String)
        /// 登录成功
        case success(OldAuth)
    }

    func loginWithSms(phone rawPhone: String,
                      code rawCode: String,
                      captcha: GeetestResult? = nil) async throws -> SmsLoginOutcome {
        let target = rawPhone.trimmingCharacters(in: .whitespaces)
        let smsCode = rawCode.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, !smsCode.isEmpty else {
            throw LeapAPIError("手机号和验证码不能为空")
        }
        let cipher = try LeapSign.rsaEncryptPhone(target)

        var query: [String: String] = [
            "phoneNoCiphertext": cipher,
            "smsCode": smsCode,
            "deviceID": deviceId,
            "smDeviceId": smDeviceId.isEmpty ? deviceId : smDeviceId,
            "os": "android",
            "pageUrl": ""
        ]
        // 极验凭据（服务端要求时才有）
        if let c = captcha, c.isValid {
            for (k, v) in c.queryItems { query[k] = v }
        }

        let resp = try await requestJSON(LeapHost.user + LeapHost.smsLogin,
                                         method: "POST",
                                         headers: oldAppHeaders(withToken: false),
                                         query: query,
                                         body: .empty,
                                         stage: "check_login_with_phone")

        // 服务端下发 risk_type → 需要人机验证
        if let data = resp["data"] as? [String: Any],
           let risk = data["risk_type"] as? String,
           GeetestPage.needsCaptcha(risk) {
            return .needCaptcha(riskType: risk)
        }

        let auth = try parseOldAuth(resp)
        phone = target
        oldAuth = auth
        generation += 1
        persist()
        try await exchangeNewGateway()
        return .success(auth)
    }


    private func parseOldAuth(_ resp: [String: Any]) throws -> OldAuth {
        let data = resp["data"] as? [String: Any]
        let auth = (data?["appLoginVO"] as? [String: Any])
            ?? (data?["appOneLoginVO"] as? [String: Any])
            ?? findObject(resp) { $0["accountId"] != nil && $0["token"] != nil }
        guard let a = auth,
              let accountId = scalar(a["accountId"]), !accountId.isEmpty,
              let token = a["token"] as? String, !token.isEmpty else {
            throw LeapAPIError("登录响应缺少有效账号或凭据: \(errorMessage(resp))",
                               stage: "check_login_with_phone")
        }
        return OldAuth(accountId: accountId,
                       token: token,
                       refreshToken: a["refreshToken"] as? String ?? "",
                       tokenExpired: scalar(a["tokenExpired"]) ?? "21600",
                       tokenObtainedAt: Int64(Date().timeIntervalSince1970 * 1000))
    }

    // ---------------------------------------------------------- 登录：凭据导入

    func loginWithRawAuth(_ rawText: String, phone inputPhone: String = "") async throws {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LeapAPIError("导入内容不能为空") }

        var accountId = ""
        var token = ""
        var refreshToken = ""
        var tokenExpired = "21600"
        var phoneValue = inputPhone.trimmingCharacters(in: .whitespaces)

        if text.hasPrefix("{"),
           let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
            let data = obj["data"] as? [String: Any]
            let auth = (obj["appLoginVO"] as? [String: Any])
                ?? (obj["appOneLoginVO"] as? [String: Any])
                ?? (data?["appLoginVO"] as? [String: Any])
                ?? (data?["appOneLoginVO"] as? [String: Any])
                ?? findObject(obj) { $0["accountId"] != nil && $0["token"] != nil }
            let src = auth ?? obj
            accountId = (src["accountId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (src["identifier"] as? String) ?? ""
            token = (src["token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (src["security"] as? String) ?? ""
            refreshToken = src["refreshToken"] as? String ?? ""
            tokenExpired = scalar(src["tokenExpired"]) ?? "21600"

            let dev = Self.firstNonEmptyString(obj, keys: ["deviceID", "deviceId", "deviceid", "appimei"])
            if !dev.trimmingCharacters(in: .whitespaces).isEmpty {
                deviceId = dev.trimmingCharacters(in: .whitespaces)
            }
            let sm = Self.firstNonEmptyString(obj, keys: ["smDeviceId", "smdeviceid", "sm_device_id"])
            if !sm.trimmingCharacters(in: .whitespaces).isEmpty {
                smDeviceId = sm.trimmingCharacters(in: .whitespaces)
            }
            if phoneValue.isEmpty { phoneValue = obj["phone"] as? String ?? "" }
        } else if text.contains(","), !text.contains("\n") {
            let parts = text.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else {
                throw LeapAPIError("逗号分隔格式需为 accountId,token[,refreshToken]")
            }
            accountId = parts[0]
            token = parts[1]
            if parts.count > 2 { refreshToken = parts[2] }
        } else {
            token = firstGroup(#"(?:token|security|XFX-CDN-CROSS-NODE)["':=\s]+([a-zA-Z0-9_-]{16,})"#, text) ?? ""
            accountId = firstGroup(#"(?:accountId|identifier|userId|account_id)["':=\s]+([a-zA-Z0-9_-]+)"#, text) ?? ""
            refreshToken = firstGroup(#"(?:refreshToken|XFX-CDN-CROSS-REFRESH-NODE)["':=\s]+([a-zA-Z0-9_-]{16,})"#, text) ?? ""
            if let dev = firstGroup(#"(?:deviceID|deviceId|deviceid|appimei)["':=\s]+([a-zA-Z0-9_-]{16,})"#, text) {
                deviceId = dev.trimmingCharacters(in: .whitespaces)
            }
            if let sm = firstGroup(#"(?:smDeviceId|smdeviceid|sm_device_id)["':=\s]+([a-zA-Z0-9_%/+=.-]{16,})"#, text) {
                smDeviceId = sm.trimmingCharacters(in: .whitespaces)
            }
        }

        guard !accountId.isEmpty, !token.isEmpty else {
            throw LeapAPIError("未能解析出有效的 accountId 和 token")
        }
        if !phoneValue.isEmpty { phone = phoneValue }
        oldAuth = OldAuth(accountId: accountId, token: token, refreshToken: refreshToken,
                          tokenExpired: tokenExpired,
                          tokenObtainedAt: Int64(Date().timeIntervalSince1970 * 1000))
        generation += 1
        persist()
        try await exchangeNewGateway()
    }

    private func firstGroup(_ pattern: String, _ text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    // ---------------------------------------------------------- 网关会话

    func exchangeNewGateway() async throws {
        guard let old = oldAuth else { throw LeapAPIError("未登录") }
        let payload: [String: Any] = [
            "identifier": old.accountId,
            "identifierType": "1",
            "security": old.token
        ]
        let signParams: [String: String?] = [
            "identifier": old.accountId,
            "identifierType": "1",
            "security": old.token
        ]
        let headers = try newGatewayHeaders(signParams, needLogin: false)
        let resp = try await requestJSON(LeapHost.global + LeapHost.gatewayLogin,
                                         method: "POST", headers: headers,
                                         body: .json(payload), stage: "gateway_login")
        newAuth = try extractNewAuth(resp)
        persist()
    }

    private func extractNewAuth(_ resp: [String: Any]) throws -> NewAuth {
        let data = (resp["data"] as? [String: Any])
            ?? findObject(resp) { $0["accessToken"] != nil && $0["signParam"] != nil }
        guard let d = data else {
            throw LeapAPIError("网关登录响应缺少 accessToken/signParam: \(errorMessage(resp))",
                               stage: "gateway_login")
        }
        guard let accessToken = d["accessToken"] as? String, !accessToken.isEmpty,
              let signParam = d["signParam"] as? [String: Any],
              let r2 = signParam["r2"] as? String, !r2.isEmpty,
              let r3 = signParam["r3"] as? String, !r3.isEmpty else {
            throw LeapAPIError("网关登录响应缺少 signParam.r2/r3", stage: "gateway_login")
        }
        let signKey = try LeapSign.deriveSignKey(accessToken: accessToken, r2: r2, r3: r3)

        // 网关 token 绑定 deviceId，签名必须换用它
        if let bound = LeapSign.jwtDeviceId(accessToken), !bound.isEmpty {
            deviceId = bound
        }

        var expiry = LeapSign.jwtExpiryMs(accessToken)
        if expiry <= 0, let t = (d["tokenExpireTime"] as? NSNumber)?.int64Value, t > 0 {
            expiry = Int64(Date().timeIntervalSince1970 * 1000) &+ t &* 1000
        }
        return NewAuth(accountId: oldAuth?.accountId ?? (d["accountId"] as? String ?? ""),
                       accessToken: accessToken,
                       refreshToken: d["refreshToken"] as? String ?? "",
                       signKeyBase64: signKey.base64EncodedString(),
                       accessTokenExpiresAt: expiry)
    }

    func refreshGatewayToken() async throws {
        guard let auth = newAuth else { throw LeapAPIError("未登录") }
        guard !auth.refreshToken.isEmpty else { throw LeapAPIError("缺少 refreshToken，无法自动续期") }
        let payload: [String: Any] = ["refreshToken": auth.refreshToken]
        let params: [String: String?] = ["refreshToken": auth.refreshToken]
        let headers = try newGatewayHeaders(params, needLogin: true)
        let resp = try await requestJSON(LeapHost.global + LeapHost.gatewayRefresh,
                                         method: "POST", headers: headers,
                                         body: .json(payload), stage: "gateway_refresh")
        newAuth = try extractNewAuth(resp)
        persist()
    }

    /// 旧 token 续期（需手机号）
    func refreshOldToken() async throws {
        guard let old = oldAuth else { throw LeapAPIError("未登录") }
        guard !phone.isEmpty else { throw LeapAPIError("旧 token 续期需要手机号，请重新登录") }
        let cipher = try LeapSign.rsaEncryptPhone(phone)
        let signed = try oldSignedParams(["accountId": old.accountId, "accountNumber": cipher],
                                         withRefreshToken: true)
        var headers = oldAppHeaders(withToken: true)
        headers["XFX-CDN-CROSS-REFRESH-NODE"] = old.refreshToken

        let resp = try await requestJSON(LeapHost.user + LeapHost.refreshOldToken,
                                         headers: headers, query: signed,
                                         stage: "appuseroperate")
        let data = (resp["data"] as? [String: Any]) ?? resp
        guard let token = data["token"] as? String, !token.isEmpty else {
            throw LeapAPIError("旧 token 续期失败: \(errorMessage(resp))", stage: "appuseroperate")
        }
        let code = (resp["code"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (resp["result"] as? String) ?? ""
        let ok = code == "200" || code == "0" || (resp["success"] as? Bool == true)
        guard ok else {
            throw LeapAPIError("旧 token 续期失败: \(errorMessage(resp))", stage: "appuseroperate")
        }

        let newRefresh = (data["refreshToken"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? old.refreshToken
        oldAuth = OldAuth(accountId: old.accountId, token: token,
                          refreshToken: newRefresh,
                          tokenExpired: scalar(data["tokenExpired"]) ?? old.tokenExpired,
                          tokenObtainedAt: Int64(Date().timeIntervalSince1970 * 1000))
        persist()
        // 换新网关会话
        try? await exchangeNewGateway()
    }

    private func ensureFreshAccessToken() async {
        guard let auth = newAuth else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if auth.accessTokenExpiresAt > 0, auth.accessTokenExpiresAt - now <= 300_000 {
            do {
                try await refreshGatewayToken()
            } catch {
                try? await refreshOldToken()
            }
        }
    }

    /// 旧 token 剩余不足 60 秒时续期
    func ensureFreshOldToken() async {
        guard let old = oldAuth else { return }
        let expiredSeconds = Int64(old.tokenExpired) ?? 21600
        let expiresAt = old.tokenObtainedAt &+ expiredSeconds &* 1000
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if expiresAt > old.tokenObtainedAt, expiresAt - now <= 60_000 {
            try? await refreshOldToken()
        }
    }

    // ---------------------------------------------------------- 网关请求（带自动续期）

    private func gatewayFetch(_ url: String,
                              method: String = "GET",
                              params: [String: String?] = [:],
                              query: [String: String]? = nil,
                              jsonBody: Any? = nil,
                              formBody: [String: String]? = nil,
                              stage: String = "") async throws -> [String: Any] {
        await ensureFreshAccessToken()
        let q = query ?? (method == "GET" ? params.compactMapValues { $0 } : nil)

        func attempt() async throws -> [String: Any] {
            let headers = try newGatewayHeaders(params, needLogin: true)
            let body: Body
            if let json = jsonBody {
                body = .json(json)
            } else if let form = formBody {
                body = .form(form)
            } else {
                body = .none
            }
            return try await requestJSON(url, method: method, headers: headers,
                                         query: q, body: body, stage: stage)
        }

        var resp = try await attempt()
        if isAuthFailure(resp) {
            do {
                try await refreshGatewayToken()
            } catch {
                try? await refreshOldToken()
            }
            resp = try await attempt()
        }
        return resp
    }

    private func requireVin() throws {
        guard !selectedVin.isEmpty else { throw LeapAPIError("还没有选择车辆 VIN") }
    }

    // ---------------------------------------------------------- 车辆

    func listVehicles() async throws -> [Vehicle] {
        let resp = try await gatewayFetch(LeapHost.global + LeapHost.vehicleList,
                                          stage: "vehiclelist")
        let objects = collectObjects(resp) { obj in
            guard let vin = obj["vin"] as? String else { return false }
            return vin.count >= 8
        }
        var seen = Set<String>()
        var out: [Vehicle] = []
        for obj in objects {
            guard let vin = obj["vin"] as? String, !vin.isEmpty, !seen.contains(vin) else { continue }
            seen.insert(vin)

            let model = obj["modelParam"] as? [String: Any]
            var carType = Self.firstNonEmptyString(obj, keys: ["carType", "cartype"])
            if carType.isEmpty, let m = model?["carType"] as? String { carType = m }

            let nickname = Self.firstNonEmptyString(
                obj, keys: ["vehicleName", "carName", "licensePlate", "nickName", "nickname"])

            var year = Self.firstNonEmptyString(obj, keys: ["year", "modelYear", "carYear"])
            if year.isEmpty, let m = model?["year"] as? String { year = m }

            let color = Self.firstNonEmptyString(obj, keys: ["outColor", "color"])

            let rightList = (obj["rightList"] as? String) ?? ""
            var isShared = false
            if (obj["isShare"] as? Bool) == true { isShared = true }
            else if (obj["isShared"] as? Bool) == true { isShared = true }
            else if (obj["share"] as? Bool) == true { isShared = true }
            else if scalar(obj["bindType"]) == "2" { isShared = true }
            else if scalar(obj["userType"]) == "2" { isShared = true }
            else if scalar(obj["shareType"]) == "1" { isShared = true }
            else if scalar(obj["isMaster"]) == "0" { isShared = true }
            else if (obj["isOwner"] as? Bool) == false { isShared = true }
            else if !rightList.isEmpty && carType.uppercased().contains("REEV") { isShared = true }

            out.append(Vehicle(vin: vin, carType: carType, nickname: nickname,
                               year: year, color: color, isShared: isShared))
        }

        if selectedVin.isEmpty, let first = out.first {
            selectedVin = first.vin
            selectedCarType = first.carType
            selectedNickname = first.nickname
            selectedYear = first.year
            route = nil
            persist()
        } else if let selected = out.first(where: { $0.vin == selectedVin }) {
            if selectedCarType.isEmpty { selectedCarType = selected.carType }
            selectedNickname = selected.nickname
            selectedYear = selected.year
            persist()
        }
        return out
    }

    func getCarRoute() async throws -> RouteData {
        try requireVin()
        let params: [String: String?] = ["vin": selectedVin]
        let resp = try await gatewayFetch(LeapHost.global + LeapHost.carRoute,
                                          params: params,
                                          query: ["vin": selectedVin],
                                          stage: "getCarRoute")
        let data = (resp["data"] as? [String: Any])
            ?? findObject(resp) { $0["appRegion"] != nil || $0["appCenter"] != nil }
        guard let d = data,
              let region = d["appRegion"] as? String, !region.isEmpty else {
            throw LeapAPIError("车辆路由响应缺少 appRegion", stage: "getCarRoute")
        }
        let r = RouteData(appRegion: region, appCenter: d["appCenter"] as? String ?? "")
        route = r
        persist()
        return r
    }

    private func ensureRoute() async throws -> RouteData {
        if let r = route, !r.appRegion.isEmpty { return r }
        return try await getCarRoute()
    }

    // ---------------------------------------------------------- 车况

    func getVehicleStateRaw() async throws -> [String: Any] {
        try requireVin()
        let r = try await ensureRoute()
        return try await gatewayFetch(r.appRegion + LeapHost.signalQuery,
                                      method: "POST",
                                      params: ["vin": selectedVin],
                                      jsonBody: ["vin": selectedVin],
                                      stage: "signalinquiry")
    }

    func getVehicleState() async throws -> [String: Any] {
        let raw = try await getVehicleStateRaw()
        let signal = LeapAPI.extractSignalMap(raw)
        guard !signal.isEmpty else {
            throw LeapAPIError("车况接口未返回 signalMap")
        }
        var decoded = LeapSignalTable.decode(signal)

        // 合并 config.3 充电计划
        let config = (raw["data"] as? [String: Any])?["config"] as? [String: Any]
            ?? raw["config"] as? [String: Any]
        if let plan = config?["3"] as? [String: Any] {
            if decoded["chargeScheduleEnabled"] == nil, let v = plan["isEnable"] { decoded["chargeScheduleEnabled"] = v }
            if decoded["chargeScheduleStart"] == nil, let v = plan["beginTime"] { decoded["chargeScheduleStart"] = v }
            if decoded["chargeScheduleEnd"] == nil, let v = plan["endTime"] { decoded["chargeScheduleEnd"] = v }
            if decoded["chargeScheduleCycles"] == nil, let v = plan["cycles"] { decoded["chargeScheduleCycles"] = v }
            if decoded["chargeScheduleCirculation"] == nil, let v = plan["circulation"] { decoded["chargeScheduleCirculation"] = v }
            if decoded["chargeScheduleRecharge"] == nil, let v = plan["recharge"] { decoded["chargeScheduleRecharge"] = v }
            if decoded["chargesocSetting"] == nil, let v = plan["percent"] { decoded["chargesocSetting"] = v }
        }
        return decoded
    }

    static func extractSignalMap(_ resp: [String: Any]) -> [String: Any] {
        if let m = resp["signalMap"] as? [String: Any], !m.isEmpty { return m }
        if let d = resp["data"] as? [String: Any] {
            if let m = d["signalMap"] as? [String: Any], !m.isEmpty { return m }
            if let inner = d["data"] as? [String: Any],
               let m = inner["signalMap"] as? [String: Any], !m.isEmpty { return m }
        }
        if let found = findStatic(resp, where: { $0["signalMap"] is [String: Any] }),
           let m = found["signalMap"] as? [String: Any] {
            return m
        }
        return [:]
    }

    private static func findStatic(_ root: Any?, where predicate: ([String: Any]) -> Bool) -> [String: Any]? {
        guard let root = root else { return nil }
        if let d = root as? [String: Any] {
            if predicate(d) { return d }
            for k in d.keys {
                if let f = findStatic(d[k], where: predicate) { return f }
            }
        } else if let a = root as? [Any] {
            for v in a {
                if let f = findStatic(v, where: predicate) { return f }
            }
        }
        return nil
    }

    /// 驻车环视照片
    func getChassisPhoto() async throws -> ChassisPhoto? {
        try requireVin()
        let signed = try oldSignedParams(["vin": selectedVin])
        let headers = try combinedHeaders(optionalMap(signed), needLogin: true)
        let r = try? await ensureRoute()
        var candidates = [
            LeapHost.iov + LeapHost.chassisQuery,
            LeapHost.gateway + LeapHost.chassisQuery
        ]
        if let region = r?.appRegion, !region.isEmpty {
            candidates.append(region + LeapHost.chassisQuery)
        }
        for url in candidates {
            guard let resp = try? await requestJSON(url, method: "GET", headers: headers,
                                                    query: signed, stage: "chassisquery"),
                  let data = resp["data"] as? [String: Any],
                  let fileUrl = data["fileUrl"] as? String, !fileUrl.isEmpty else { continue }
            return ChassisPhoto(fileUrl: fileUrl,
                                uploadTimeMs: (data["uploadTime"] as? NSNumber)?.int64Value ?? 0)
        }
        return nil
    }

    // ---------------------------------------------------------- 控车

    /// 用于加密操作密码的 token：优先网关 accessToken，回退旧 token
    func operationPasswordToken() throws -> String {
        if let t = newAuth?.accessToken, !t.isEmpty { return t }
        if let t = oldAuth?.token, !t.isEmpty { return t }
        throw LeapAPIError("未登录（缺少用于加密操作密码的 Token）")
    }

    /// 下发控车指令
    func sendControl(_ cmd: ControlCommand, pin: String) async throws -> ControlResult {
        try requireVin()
        var params: [String: String] = [
            "cmdid": cmd.cmdid,
            "state": cmd.state,
            "carvin": selectedVin
        ]
        if !pin.trimmingCharacters(in: .whitespaces).isEmpty {
            params["oppwd"] = try LeapSign.encryptOperationPassword(pin, token: operationPasswordToken())
        }
        let signedBody = try oldSignedParams(params)
        let headers = try combinedHeaders(optionalMap(signedBody), needLogin: true)

        let r = try? await ensureRoute()
        var candidates = [LeapHost.gateway + LeapHost.remoteControl]
        if let region = r?.appRegion, !region.isEmpty {
            candidates.append(region + LeapHost.remoteControl)
        }

        var last: Error?
        for url in candidates {
            do {
                let resp = try await requestJSON(url, method: "POST", headers: headers,
                                                 body: .form(signedBody), stage: "appremotectl")
                try checkControlResult(resp)
                return ControlResult(msgID: extractMsgID(resp), raw: resp)
            } catch {
                last = error
            }
        }
        throw last ?? LeapAPIError("控车请求发送失败")
    }

    func queryControlResult(msgID: String) async throws -> [String: Any] {
        guard !msgID.isEmpty else { throw LeapAPIError("msgID 为空") }
        try requireVin()
        let signed = try oldSignedParams(["msgID": msgID])
        let headers = try combinedHeaders(optionalMap(signed), needLogin: true)
        let r = try? await ensureRoute()
        var candidates = [LeapHost.gateway + LeapHost.remoteControlQuery]
        if let region = r?.appRegion, !region.isEmpty {
            candidates.append(region + LeapHost.remoteControlQuery)
        }
        var last: Error?
        for url in candidates {
            do {
                return try await requestJSON(url, method: "GET", headers: headers,
                                            query: signed, stage: "appremotectlquery")
            } catch { last = error }
        }
        throw last ?? LeapAPIError("控车结果查询失败")
    }

    private func checkControlResult(_ resp: [String: Any]) throws {
        let value = scalar(resp["result"] ?? resp["code"])
        guard let v = value else { return }
        if v != "0" && v != "200" {
            throw LeapAPIError("控车失败(\(v)): \(errorMessage(resp))")
        }
    }

    private func extractMsgID(_ resp: [String: Any]) -> String {
        if let obj = findObject(resp, where: { $0["msgID"] != nil || $0["msgId"] != nil || $0["eventId"] != nil }) {
            for key in ["msgID", "msgId", "eventId"] {
                if let s = obj[key] as? String, !s.isEmpty { return s }
            }
        }
        if let d = resp["data"], !(d is NSNull), !(d is [String: Any]), !(d is [Any]) {
            return String(describing: d)
        }
        return ""
    }

    // ---------------------------------------------------------- 预约充电 / 预热 / 空调

    func setScheduledCharging(enabled: Bool, startTime: String, endTime: String,
                              targetSoc: Int = 80, pin: String = "",
                              continueUntilLimit: Bool = true) async throws -> [String: Any] {
        try requireVin()
        let route = try await ensureRoute()
        let soc = min(max(targetSoc, 50), 100)
        let state: [String: Any] = [
            "chargeEnable": enabled ? 1 : 0,
            "chargesoc": soc,
            "circulation": enabled ? 1 : 0,
            "cycles": enabled ? "1,1,1,1,1,1,1" : "",
            "starttime": startTime,
            "endtime": endTime,
            "recharge": continueUntilLimit ? 1 : 0
        ]
        let stateText = jsonString(state)

        var params: [String: String] = ["cmdid": "190", "state": stateText, "carvin": selectedVin]
        if !pin.trimmingCharacters(in: .whitespaces).isEmpty {
            params["oppwd"] = try LeapSign.encryptOperationPassword(pin, token: operationPasswordToken())
        }
        let signedBody = try oldSignedParams(params)
        let headers = try combinedHeaders(optionalMap(signedBody), needLogin: true)

        // 1. 车控核心通道
        if let resp = try? await requestJSON(route.appRegion + LeapHost.remoteControl,
                                             method: "POST", headers: headers,
                                             body: .form(signedBody), stage: "schedule"),
           isSuccessCode(resp) {
            return resp
        }
        // 2. 预约通道
        let host = route.appCenter.isEmpty ? route.appRegion : route.appCenter
        if let resp = try? await requestJSON(host + LeapHost.appointment,
                                             method: "POST", headers: headers,
                                             body: .form(signedBody), stage: "appointment"),
           isSuccessCode(resp) {
            return resp
        }
        // 3. 日程服务兜底
        let model = selectedCarType.isEmpty ? "C16" : selectedCarType
        let sched: [String: String?] = [
            "carvin": selectedVin, "vin": selectedVin, "model": model, "type": "1",
            "state": enabled ? "1" : "0", "status": enabled ? "1" : "0",
            "startTime": startTime, "endTime": endTime,
            "repeat": "1,2,3,4,5,6,7", "cycle": "1,2,3,4,5,6,7",
            "continueCharge": continueUntilLimit ? "1" : "0",
            "continueUntilFull": continueUntilLimit ? "1" : "0"
        ]
        return try await gatewayFetch(route.appRegion + "/carownerservice/v3/api/schedule/operate",
                                      method: "POST", params: sched,
                                      formBody: sched.compactMapValues { $0 },
                                      stage: "scheduleoperate")
    }

    func setScheduledPreheat(enabled: Bool, startTime: String, pin: String = "",
                             days: [Int] = [1, 2, 3, 4, 5, 6, 0]) async throws -> [String: Any] {
        try requireVin()
        let route = try await ensureRoute()
        let today = Self.dateString(Date())
        let fullStart = startTime.count == 5 ? "\(today) \(startTime):00" : startTime
        var state: [String: Any] = [:]
        if enabled {
            state["controls"] = [[
                "on": "1",
                "set_id": "ptc_set_\(Int64(Date().timeIntervalSince1970 * 1000))",
                "start_time": fullStart,
                "update_time": String(Int64(Date().timeIntervalSince1970 * 1000)),
                "days": days
            ]]
        } else {
            state["controls"] = [[String: Any]]()
        }

        var params: [String: String] = ["cmdid": "161", "state": jsonString(state), "carvin": selectedVin]
        if !pin.trimmingCharacters(in: .whitespaces).isEmpty {
            params["oppwd"] = try LeapSign.encryptOperationPassword(pin, token: operationPasswordToken())
        }
        let signedBody = try oldSignedParams(params)
        let headers = try combinedHeaders(optionalMap(signedBody), needLogin: true)
        return try await requestJSON(route.appRegion + LeapHost.remoteControl,
                                     method: "POST", headers: headers,
                                     body: .form(signedBody), stage: "preheat")
    }

    func setScheduledAirConditioning(_ plan: ScheduledAcPlan, pin: String = "") async throws -> [String: Any] {
        try requireVin()
        let route = try await ensureRoute()
        let cmd = LeapCommands.buildScheduledAc(plan: plan, deviceId: deviceId)
        var params: [String: String] = ["cmdid": cmd.cmdid, "state": cmd.state, "carvin": selectedVin]
        if !pin.trimmingCharacters(in: .whitespaces).isEmpty {
            params["oppwd"] = try LeapSign.encryptOperationPassword(pin, token: operationPasswordToken())
        }
        let signedBody = try oldSignedParams(params)
        let headers = try combinedHeaders(optionalMap(signedBody), needLogin: true)
        let host = route.appCenter.isEmpty ? route.appRegion : route.appCenter
        var candidates = [LeapHost.gateway + LeapHost.appointment, host + LeapHost.appointment]
        var seen = Set<String>()
        candidates = candidates.filter { !$0.isEmpty && seen.insert($0).inserted }

        var last: Error?
        for url in candidates {
            do {
                let resp = try await requestJSON(url, method: "POST", headers: headers,
                                                 body: .form(signedBody), stage: "scheduledac")
                try checkControlResult(resp)
                return resp
            } catch { last = error }
        }
        throw last ?? LeapAPIError("定时空调设置失败")
    }

    func getScheduledAirConditioning() async throws -> (has: Bool, plan: ScheduledAcPlan)? {
        try requireVin()
        let route = try await ensureRoute()
        let params = try oldSignedParams(["cmdid": "171", "carvin": selectedVin])
        let headers = try combinedHeaders(optionalMap(params), needLogin: true)
        let host = route.appCenter.isEmpty ? route.appRegion : route.appCenter
        var candidates = [LeapHost.gateway + LeapHost.getAppointment, host + LeapHost.getAppointment]
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0).inserted }

        for url in candidates {
            guard let resp = try? await requestJSON(url, method: "GET", headers: headers,
                                                    query: params, stage: "getappointment") else { continue }
            if let result = scalar(resp["result"]), result != "0" { continue }
            return LeapCommands.parseScheduledAc(resp["data"])
        }
        return nil
    }

    // ---------------------------------------------------------- 能耗 / 主题 / 健康充电

    func getMileageEnergy(recentSevenDays: Bool = true) async throws -> [String: Any] {
        try requireVin()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var params: [String: String] = ["vin": selectedVin]
        if recentSevenDays {
            params["begintime"] = String(now - 7 * 86_400_000)
            params["endtime"] = String(now)
        }
        let signed = try oldSignedParams(params)
        let headers = try combinedHeaders(optionalMap(signed), needLogin: true)
        let path = LeapHost.mileageEnergy

        for host in [LeapHost.gateway, LeapHost.iov] {
            if let resp = try? await requestJSON(host + path, method: "GET", headers: headers,
                                                 query: signed, stage: "mileageenergy") {
                if let data = resp["data"] as? [String: Any], !data.isEmpty { return resp }
            }
        }
        // 回退：仅 vin
        let simple = try oldSignedParams(["vin": selectedVin])
        let simpleHeaders = try combinedHeaders(optionalMap(simple), needLogin: true)
        return try await requestJSON(LeapHost.gateway + path, method: "GET",
                                     headers: simpleHeaders, query: simple, stage: "mileageenergy")
    }

    func listThemes() async throws -> [[String: Any]] {
        try requireVin()
        let resp = try await gatewayFetch(LeapHost.gateway + LeapHost.themeList,
                                          method: "POST",
                                          params: ["vin": selectedVin],
                                          jsonBody: ["vin": selectedVin],
                                          stage: "themelist")
        guard let data = resp["data"] as? [String: Any],
              let list = data["list"] as? [Any] else { return [] }
        return list.compactMap { $0 as? [String: Any] }
    }

    func setHealthyCharging(enabled: Bool, targetSoc: Int) async throws -> [String: Any] {
        try requireVin()
        let route = try await ensureRoute()
        let soc = min(max(targetSoc, 50), 100)
        let params: [String: String] = [
            "carvin": selectedVin, "vin": selectedVin,
            "state": enabled ? "1" : "0",
            "soc": String(soc), "targetSoc": String(soc)
        ]
        return try await gatewayFetch(route.appRegion + LeapHost.healthyChargingControl,
                                      method: "POST",
                                      params: optionalMap(params),
                                      jsonBody: params,
                                      formBody: params,
                                      stage: "healthycharging")
    }

    // ---------------------------------------------------------- 蓝牙钥匙证书

    /// POST {appCenter}/carownerservice/v3/api/bluetoothkey/combine/syncBluetoothKeys
    func fetchBluetoothCertificate() async throws -> BleKeyCertificate {
        guard let old = oldAuth, !old.token.isEmpty, !old.accountId.isEmpty else {
            throw LeapAPIError("请先登录后同步蓝牙钥匙", stage: "ble_certificate")
        }
        guard !deviceId.isEmpty, !selectedVin.isEmpty else {
            throw LeapAPIError("请先选择车辆并确认设备信息", stage: "ble_certificate")
        }
        await ensureFreshOldToken()
        let r = try await ensureRoute()
        guard !r.appCenter.isEmpty,
              let center = URL(string: r.appCenter),
              let scheme = center.scheme, scheme == "https",
              let host = center.host,
              host.hasSuffix(".leapmotor.cn") || host.hasSuffix(".leapmotor.com") else {
            throw LeapAPIError("缺少车辆蓝牙钥匙服务路由", stage: "ble_certificate")
        }
        var url = r.appCenter
        if url.hasSuffix("/") { url.removeLast() }
        url += LeapHost.bluetoothCertificate

        let signed = try oldSignedParams(["vin": selectedVin])
        let headers = oldAppHeaders(withToken: true)
        let resp = try await requestJSON(url, method: "POST", headers: headers,
                                         body: .form(signed), stage: "ble_certificate")
        do {
            return try BleKeyCertificate.fromResponse(resp, expectedVin: selectedVin)
        } catch let error as BleKeyCertificate.ParseError {
            throw LeapAPIError(error.localizedDescription, stage: "ble_certificate")
        }
    }

    /// 云端蓝牙配置（commonConfig → config.4）
    func fetchBluetoothMetadata() async throws -> (address: String, version: String)? {
        try requireVin()
        let r = try await ensureRoute()
        let params: [String: String?] = [
            "appVersion": LeapHost.appVersion,
            "osType": "Android",
            "vin": selectedVin
        ]
        let resp = try await gatewayFetch(LeapHost.gateway + LeapHost.commonConfig,
                                          params: params,
                                          query: params.compactMapValues { $0 },
                                          stage: "commonConfig")
        guard let data = resp["data"] as? [String: Any],
              let config = data["config"] as? [String: Any],
              let bt = config["4"] as? [String: Any] else { return nil }
        guard let raw = bt["mac"] as? String,
              let normalized = Self.normalizeMac(raw),
              let version = bt["version"] as? String, !version.isEmpty else { return nil }
        _ = r
        return (normalized, version)
    }

    /// 上传蓝牙配置偏好（云端保存，不代表车端已生效）
    func uploadBluetoothConfiguration(_ configuration: BlePassiveConfiguration) async throws {
        try requireVin()
        let conf: [String: Any] = [
            "bleKeySwitch": configuration.enabled,
            "bleKeyUnlock": configuration.autoUnlock,
            "bleKeyLock": configuration.autoLock,
            "bleKeyBtn": configuration.buttonEnabled
        ]
        let params: [String: String] = ["vin": selectedVin, "conf": jsonString(conf)]
        let signed = try oldSignedParams(params)
        let headers = try combinedHeaders(optionalMap(signed), needLogin: true)
        _ = try await requestJSON(LeapHost.global + LeapHost.bluetoothConfig,
                                  method: "POST", headers: headers,
                                  body: .form(signed), stage: "ble_cloud_configuration")
    }

    /// 上报蓝牙控车上锁/解锁记录
    func uploadBluetoothRecord(action: BleLockAction) async {
        guard !selectedVin.isEmpty, !deviceId.isEmpty, oldAuth != nil else { return }
        let record: [String: Any] = [
            "devType": "Android",
            "list": [[
                "optDesc": action == .lock ? "1" : "0",
                "optResult": "0",
                "optTime": String(Int64(Date().timeIntervalSince1970 * 1000)),
                "optType": "1",
                "sendType": "4",
                "vin": selectedVin
            ]]
        ]
        guard let signed = try? oldSignedParams(["records": jsonString(record)]) else { return }
        guard let headers = try? newGatewayHeaders(optionalMap(signed), needLogin: true) else { return }
        _ = try? await requestJSON(LeapHost.gateway + LeapHost.bluetoothUploadRecords,
                                   method: "POST", headers: headers,
                                   body: .form(signed), stage: "bluetoothRecords")
    }

    // ---------------------------------------------------------- 工具

    /// 按顺序取第一个非空字符串（用于兼容多种字段名拼写）
    static func firstNonEmptyString(_ dict: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let s = dict[key] as? String, !s.isEmpty { return s }
        }
        return ""
    }

    /// 按顺序取第一个非空字符串，含可选字典
    static func firstNonEmptyString(_ dict: [String: Any]?, keys: [String]) -> String {
        guard let dict = dict else { return "" }
        return firstNonEmptyString(dict, keys: keys)
    }

    func jsonString(_ obj: Any) -> String {        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    static func normalizeMac(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let compact: String
        if trimmed.count == 12, trimmed.allSatisfy({ $0.isHexDigit }) {
            compact = trimmed.uppercased()
        } else if trimmed.count == 17, trimmed.enumerated().allSatisfy({ idx, c in
            idx % 3 == 2 ? c == ":" : c.isHexDigit
        }) {
            compact = trimmed.replacingOccurrences(of: ":", with: "").uppercased()
        } else {
            return nil
        }
        guard compact != "000000000000", compact != "FFFFFFFFFFFF" else { return nil }
        var parts: [String] = []
        var idx = compact.startIndex
        while idx < compact.endIndex {
            let next = compact.index(idx, offsetBy: 2)
            parts.append(String(compact[idx..<next]))
            idx = next
        }
        return parts.joined(separator: ":")
    }

    static func dateString(_ date: Date) -> String { LeapDate.string(date) }
}
