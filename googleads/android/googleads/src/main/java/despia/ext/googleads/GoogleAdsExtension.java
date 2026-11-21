package despia.ext.googleads;

import android.os.Bundle;
import com.despia.nativeext.*;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.analytics.FirebaseAnalytics;
import org.json.*;
import java.util.EnumMap;

public final class GoogleAdsExtension implements NativeExtension {
    private ExtContext context;
    private FirebaseAnalytics analytics;
    private boolean configured, enabled;

    @Override public void onCreate(ExtContext context) { this.context = context; }

    @Override public void handle(ExtCall call, ExtResult.Callback reply) {
        try {
            if (call.route.equals("status")) {
                reply.reply(ExtResult.ok(state().put("sdk", "BOM34.11.0"))); return;
            }
            if (call.route.equals("configure")) {
                if (configured) { reply.reply(ExtResult.ok(state())); return; }
                FirebaseOptions options = FirebaseOptions.fromResource(context.app());
                FirebaseApp app = null;
                for (FirebaseApp candidate : FirebaseApp.getApps(context.app())) {
                    if (candidate.getName().equals(FirebaseApp.DEFAULT_APP_NAME)) { app = candidate; break; }
                }
                if (app == null) {
                    if (options == null || placeholder(options.getApplicationId()) || placeholder(options.getApiKey()) || placeholder(options.getProjectId())) {
                        reply.reply(ExtResult.error("not_configured", "Provide matching Firebase Android resources before approval")); return;
                    }
                    app = FirebaseApp.initializeApp(context.app(), options);
                } else if (options != null && !placeholder(options.getApplicationId()) && !app.getOptions().getApplicationId().equals(options.getApplicationId())) {
                    reply.reply(ExtResult.error("configuration_conflict", "The default Firebase app uses a different Google app ID")); return;
                }
                if (placeholder(app.getOptions().getApplicationId()) || placeholder(app.getOptions().getApiKey()) || placeholder(app.getOptions().getProjectId())) {
                    reply.reply(ExtResult.error("not_configured", "Replace placeholder Firebase Android resources before approval")); return;
                }
                analytics = FirebaseAnalytics.getInstance(context.app());
                configured = true;
                reply.reply(ExtResult.ok(state())); return;
            }
            if (!configured) { reply.reply(ExtResult.error("not_configured", "Call configure first")); return; }
            if (call.route.equals("consent")) {
                boolean requested = Boolean.TRUE.equals(call.params.get("enabled"));
                EnumMap<FirebaseAnalytics.ConsentType, FirebaseAnalytics.ConsentStatus> consent = new EnumMap<>(FirebaseAnalytics.ConsentType.class);
                consent.put(FirebaseAnalytics.ConsentType.ANALYTICS_STORAGE, consent(requested));
                consent.put(FirebaseAnalytics.ConsentType.AD_STORAGE, consent(Boolean.TRUE.equals(call.params.get("ad_storage"))));
                consent.put(FirebaseAnalytics.ConsentType.AD_USER_DATA, consent(Boolean.TRUE.equals(call.params.get("ad_user_data"))));
                consent.put(FirebaseAnalytics.ConsentType.AD_PERSONALIZATION, consent(Boolean.TRUE.equals(call.params.get("ad_personalization"))));
                analytics.setConsent(consent);
                analytics.setAnalyticsCollectionEnabled(requested);
                enabled = requested;
                reply.reply(ExtResult.ok(new JSONObject().put("enabled", enabled))); return;
            }
            if (call.route.equals("reset")) {
                analytics.resetAnalyticsData(); reply.reply(accepted()); return;
            }
            if (call.route.equals("user") && !call.params.containsKey("id")) {
                analytics.setUserId(null); reply.reply(accepted()); return;
            }
            if (call.route.equals("property") && !call.params.containsKey("value")) {
                analytics.setUserProperty((String)call.params.get("name"), null); reply.reply(accepted()); return;
            }
            if (!enabled) { reply.reply(ExtResult.error("consent_required", "Enable adapter event collection first")); return; }
            switch (call.route) {
                case "event": case "purchase": {
                    Bundle parameters = GoogleAdsParameters.parse((String)call.params.get("properties"));
                    String name = (String)call.params.get("name");
                    if (call.route.equals("purchase")) {
                        name = FirebaseAnalytics.Event.PURCHASE;
                        parameters.putDouble(FirebaseAnalytics.Param.VALUE, GoogleAdsParameters.number((String)call.params.get("amount")));
                        parameters.putString(FirebaseAnalytics.Param.CURRENCY, GoogleAdsParameters.currency((String)call.params.get("currency")));
                        parameters.putString(FirebaseAnalytics.Param.TRANSACTION_ID, (String)call.params.get("transaction_id"));
                    }
                    analytics.logEvent(name, parameters); break;
                }
                case "user": analytics.setUserId((String)call.params.get("id")); break;
                case "property": analytics.setUserProperty((String)call.params.get("name"), (String)call.params.get("value")); break;
                default: reply.reply(ExtResult.error("not_registered", call.route)); return;
            }
            reply.reply(accepted());
        } catch (JSONException | IllegalArgumentException exception) {
            reply.reply(ExtResult.error("bad_request", "Expected finite numbers, uppercase ISO currency and Firebase event parameters"));
        } catch (IllegalStateException exception) {
            reply.reply(ExtResult.error("sdk_error", "Firebase could not use the app configuration"));
        }
    }
    private static boolean placeholder(String setting) { return setting == null || setting.isEmpty() || setting.startsWith("REPLACE_"); }
    private static FirebaseAnalytics.ConsentStatus consent(boolean allowed) {
        return allowed ? FirebaseAnalytics.ConsentStatus.GRANTED : FirebaseAnalytics.ConsentStatus.DENIED;
    }
    private JSONObject state() throws JSONException { return new JSONObject().put("configured", configured).put("enabled", enabled); }
    private static ExtResult accepted() throws JSONException { return ExtResult.ok(new JSONObject().put("accepted", true)); }
}
