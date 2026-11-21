package despia.ext.googleads;

import android.os.Bundle;
import com.google.firebase.analytics.FirebaseAnalytics;
import org.json.*;
import java.util.Iterator;

final class GoogleAdsParameters {
    static double number(String text) {
        double amount = Double.parseDouble(text);
        if (!Double.isFinite(amount)) throw new IllegalArgumentException("Finite number required");
        return amount;
    }
    static String currency(String text) {
        if (!text.matches("[A-Z]{3}")) throw new IllegalArgumentException("Uppercase ISO currency required");
        return text;
    }
    static Bundle parse(String text) throws JSONException {
        return bundle(new JSONObject(text == null ? "{}" : text), true);
    }
    private static Bundle bundle(JSONObject parameters, boolean allowsItems) throws JSONException {
        Bundle bundle = new Bundle();
        Iterator<String> names = parameters.keys();
        while (names.hasNext()) {
            String name = names.next();
            Object parameter = parameters.get(name);
            if (parameter instanceof String) bundle.putString(name, (String)parameter);
            else if (parameter instanceof Integer || parameter instanceof Long) bundle.putLong(name, ((Number)parameter).longValue());
            else if (parameter instanceof Number && Double.isFinite(((Number)parameter).doubleValue())) bundle.putDouble(name, ((Number)parameter).doubleValue());
            else if (allowsItems && name.equals(FirebaseAnalytics.Param.ITEMS) && parameter instanceof JSONArray) {
                JSONArray products = (JSONArray)parameter;
                Bundle[] entries = new Bundle[products.length()];
                for (int i = 0; i < entries.length; i++) entries[i] = bundle(products.getJSONObject(i), false);
                bundle.putParcelableArray(name, entries);
            } else throw new IllegalArgumentException("Expected Firebase string, number or items array");
        }
        return bundle;
    }
}
