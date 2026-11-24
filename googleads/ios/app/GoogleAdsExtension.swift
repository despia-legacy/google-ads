import Foundation
import CoreFoundation
import FirebaseCore
import FirebaseAnalytics

@MainActor
final class GoogleAdsExtension: NativeExtension {
    private var configured = false
    private var enabled = false
    required init() {}
    func didLaunch(_ context: NativeExtContext) {}

    func handle(_ call: NativeExtCall) async -> NativeExtResult {
        do {
            if call.route == "status" {
                return .ok(["configured": configured, "enabled": enabled, "sdk": "13.2.0"])
            }
            if call.route == "configure" {
                if configured { return .ok(["configured": true, "enabled": enabled]) }
                let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist")
                let plist = path.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
                    .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
                if let app = FirebaseApp.app() {
                    if let appID = plist?["GOOGLE_APP_ID"] as? String, app.options.googleAppID != appID {
                        return .error(code: "configuration_conflict", message: "The default Firebase app uses a different Google app ID")
                    }
                } else {
                    guard GoogleAdsConfiguration.isValid(plist, bundleID: Bundle.main.bundleIdentifier),
                          let path, let options = FirebaseOptions(contentsOfFile: path) else {
                        return .error(code: "not_configured", message: "Provide the app's matching GoogleService-Info.plist in the Despia build configuration")
                    }
                    FirebaseApp.configure(options: options)
                }
                configured = true
                return .ok(["configured": true, "enabled": enabled])
            }
            guard configured else { return .error(code: "not_configured", message: "Call configure first") }
            if call.route == "consent" {
                let requested = call.params["enabled"] as? Bool ?? false
                Analytics.setConsent([
                    .analyticsStorage: requested ? .granted : .denied,
                    .adStorage: call.params["ad_storage"] as? Bool == true ? .granted : .denied,
                    .adUserData: call.params["ad_user_data"] as? Bool == true ? .granted : .denied,
                    .adPersonalization: call.params["ad_personalization"] as? Bool == true ? .granted : .denied
                ])
                Analytics.setAnalyticsCollectionEnabled(requested)
                enabled = requested
                return .ok(["enabled": enabled])
            }
            if call.route == "reset" {
                Analytics.resetAnalyticsData()
                return .ok(["accepted": true])
            }
            if call.route == "user", call.params["id"] == nil {
                Analytics.setUserID(nil)
                return .ok(["accepted": true])
            }
            if call.route == "property", call.params["value"] == nil {
                Analytics.setUserProperty(nil, forName: call.params["name"] as? String ?? "")
                return .ok(["accepted": true])
            }
            guard enabled else { return .error(code: "consent_required", message: "Enable adapter event collection first") }
            switch call.route {
            case "event", "purchase":
                var parameters = try GoogleAdsParameters.parse(call.params["properties"] as? String)
                let name: String
                if call.route == "purchase" {
                    name = AnalyticsEventPurchase
                    parameters[AnalyticsParameterValue] = try GoogleAdsParameters.number(call.params["amount"] as? String ?? "")
                    parameters[AnalyticsParameterCurrency] = try GoogleAdsParameters.currency(call.params["currency"] as? String ?? "")
                    parameters[AnalyticsParameterTransactionID] = call.params["transaction_id"] as? String ?? ""
                } else { name = call.params["name"] as? String ?? "" }
                Analytics.logEvent(name, parameters: parameters)
            case "conversion_measurement":
                // Google Ads on-device conversion measurement (FirebaseAnalytics links GoogleAdsOnDeviceConversion).
                // Exactly one identifier: a plain email or E.164 phone, or its SHA-256 digest as 64 hex characters.
                let given = ["email", "phone", "hashed_email", "hashed_phone"].filter { call.params[$0] != nil }
                guard given.count == 1, let value = call.params[given[0]] as? String, !value.isEmpty else { throw GoogleAdsParameters.failure() }
                switch given[0] {
                case "email":
                    guard value.contains("@") else { throw GoogleAdsParameters.failure() }
                    Analytics.initiateOnDeviceConversionMeasurement(emailAddress: value)
                case "phone":
                    guard value.range(of: "^\\+[1-9][0-9]{6,14}$", options: .regularExpression) != nil else { throw GoogleAdsParameters.failure() }
                    Analytics.initiateOnDeviceConversionMeasurement(phoneNumber: value)
                case "hashed_email": Analytics.initiateOnDeviceConversionMeasurement(hashedEmailAddress: try GoogleAdsParameters.digest(value))
                default: Analytics.initiateOnDeviceConversionMeasurement(hashedPhoneNumber: try GoogleAdsParameters.digest(value))
                }
            case "user": Analytics.setUserID(call.params["id"] as? String)
            case "property": Analytics.setUserProperty(call.params["value"] as? String, forName: call.params["name"] as? String ?? "")
            default: return .error(code: "not_registered", message: call.route)
            }
            return .ok(["accepted": true])
        } catch {
            return .error(code: "bad_request", message: "Expected finite numbers, uppercase ISO currency and Firebase event parameters")
        }
    }
}

enum GoogleAdsParameters {
    static func number(_ text: String) throws -> Double {
        guard let amount = Double(text), amount.isFinite else { throw invalid() }
        return amount
    }
    static func currency(_ text: String) throws -> String {
        guard text.count == 3, text.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else { throw invalid() }
        return text
    }
    static func parse(_ text: String?) throws -> [String: Any] {
        guard let text else { return [:] }
        guard let bytes = text.data(using: .utf8),
              let parameters = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw invalid() }
        return try validated(parameters, allowsItems: true)
    }
    private static func validated(_ parameters: [String: Any], allowsItems: Bool) throws -> [String: Any] {
        for (key, parameter) in parameters {
            if parameter is String { continue }
            if let number = parameter as? NSNumber,
               CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite { continue }
            if allowsItems, key == "items", let products = parameter as? [[String: Any]] {
                for product in products { _ = try validated(product, allowsItems: false) }
                continue
            }
            throw invalid()
        }
        return parameters
    }
    /// A SHA-256 digest given as 64 hexadecimal characters, as the 32 bytes Firebase expects.
    static func digest(_ hex: String) throws -> Data {
        guard hex.count == 64, hex.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else { throw invalid() }
        var bytes = Data(capacity: 32); var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { throw invalid() }
            bytes.append(byte); index = next
        }
        return bytes
    }
    static func failure() -> NSError { invalid() }
    private static func invalid() -> NSError { NSError(domain: "googleads", code: 1) }
}

enum GoogleAdsConfiguration {
    static func isValid(_ plist: [String: Any]?, bundleID: String?) -> Bool {
        guard let plist, let appID = plist["GOOGLE_APP_ID"] as? String, isValidAppID(appID),
              let apiKey = plist["API_KEY"] as? String, !apiKey.isEmpty, !apiKey.hasPrefix("REPLACE_"),
              let projectID = plist["PROJECT_ID"] as? String, !projectID.isEmpty, !projectID.hasPrefix("REPLACE_"),
              let configuredBundleID = plist["BUNDLE_ID"] as? String, configuredBundleID == bundleID else { return false }
        return true
    }
    static func isValidAppID(_ appID: String) -> Bool {
        // FirebaseCore validates this before configuring, using an Objective-C exception on failure.
        let scanner = Scanner(string: appID)
        scanner.charactersToBeSkipped = nil
        guard let version = scanner.scanCharacters(from: .decimalDigits), scanner.scanString(":") != nil else { return false }
        if version != "1" { return true }
        var bundleHash: UInt64 = 0
        guard scanner.scanInt() != nil, scanner.scanString(":") != nil,
              scanner.scanUpToString(":") == "ios", scanner.scanString(":") != nil,
              scanner.scanHexInt64(&bundleHash), scanner.isAtEnd else { return false }
        return true
    }
}
