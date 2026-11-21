import Foundation

@main
struct GoogleAdsParametersTests {
    @MainActor static func main() throws {
        func rejects(_ action: () throws -> Void) {
            do { try action(); fatalError("Accepted invalid Firebase parameter") } catch { return }
        }
        let amount = try GoogleAdsParameters.number("12.50")
        precondition(amount == 12.5)
        for text in ["NaN", "Infinity", "1e999", "invalid"] {
            rejects { _ = try GoogleAdsParameters.number(text) }
        }
        let currency = try GoogleAdsParameters.currency("USD")
        precondition(currency == "USD")
        for text in ["usd", "US", "123", "USD\n"] { rejects { _ = try GoogleAdsParameters.currency(text) } }
        let parameters = try GoogleAdsParameters.parse("{\"coupon\":\"offer\",\"count\":2,\"items\":[{\"item_id\":\"p1\",\"price\":12.5,\"quantity\":1}]}")
        precondition(parameters["coupon"] as? String == "offer")
        precondition((parameters["items"] as? [[String: Any]])?.first?["item_id"] as? String == "p1")
        let empty = try GoogleAdsParameters.parse(nil)
        precondition(empty.isEmpty)
        for text in ["[]", "null", "{\"flag\":true}", "{\"nested\":{}}", "{\"items\":[{\"nested\":{}}]}", "{\"items\":[1]}", "{\"price\":null}"] {
            rejects { _ = try GoogleAdsParameters.parse(text) }
        }
        let valid: [String: Any] = ["GOOGLE_APP_ID": "1:123456:ios:123abc", "API_KEY": "synthetic-public-sdk-setting",
                                    "PROJECT_ID": "synthetic-project", "BUNDLE_ID": "com.despia.test"]
        precondition(GoogleAdsConfiguration.isValid(valid, bundleID: "com.despia.test"))
        precondition(!GoogleAdsConfiguration.isValid(valid, bundleID: "com.despia.other"))
        precondition(!GoogleAdsConfiguration.isValid(nil, bundleID: "com.despia.test"))
        for field in ["GOOGLE_APP_ID", "API_KEY", "PROJECT_ID", "BUNDLE_ID"] {
            var missing = valid; missing.removeValue(forKey: field)
            precondition(!GoogleAdsConfiguration.isValid(missing, bundleID: "com.despia.test"))
            missing[field] = 42
            precondition(!GoogleAdsConfiguration.isValid(missing, bundleID: "com.despia.test"))
            missing[field] = ""
            precondition(!GoogleAdsConfiguration.isValid(missing, bundleID: "com.despia.test"))
        }
        for appID in ["", "REPLACE_WITH_GOOGLE_APP_ID", "1:123:android:abc", "1:123:ios:", "1:123:ios:xyz", "1:123:ios:abc trailing"] {
            precondition(!GoogleAdsConfiguration.isValidAppID(appID))
        }
        // FirebaseCore permits an unknown numeric ID version after its separator.
        precondition(GoogleAdsConfiguration.isValidAppID("2:future-format"))
        print("Google Ads parameter and configuration checks passed")
    }
}
