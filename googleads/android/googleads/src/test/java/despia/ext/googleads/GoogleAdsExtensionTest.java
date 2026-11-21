package despia.ext.googleads;

import com.despia.nativeext.*;
import org.junit.Test;
import java.util.Collections;
import static org.junit.Assert.*;

public class GoogleAdsExtensionTest {
    private ExtResult call(GoogleAdsExtension extension, String route) {
        final ExtResult[] answer = new ExtResult[1];
        extension.handle(new ExtCall("googleads", route, Collections.emptyMap(), null), response -> {
            assertNull("one answer per call", answer[0]); answer[0] = response;
        });
        assertNotNull(answer[0]); return answer[0];
    }
    @Test public void configurationPrecedesSdkOperations() throws Exception {
        GoogleAdsExtension extension = new GoogleAdsExtension();
        assertFalse(call(extension, "status").data().getBoolean("configured"));
        for (String route : new String[]{"event", "purchase", "consent", "user", "property", "reset"}) {
            assertEquals("not_configured", call(extension, route).code());
        }
    }
    @Test public void finiteAmounts() {
        assertEquals(12.5, GoogleAdsParameters.number("12.50"), 0.0);
        for (String text : new String[]{"NaN", "Infinity", "1e999", "invalid"}) {
            try { GoogleAdsParameters.number(text); fail("accepted " + text); }
            catch (IllegalArgumentException expected) { assertNotNull(expected); }
        }
    }
    @Test public void uppercaseCurrency() {
        assertEquals("USD", GoogleAdsParameters.currency("USD"));
        for (String text : new String[]{"usd", "US", "123", "USD\n"}) {
            try { GoogleAdsParameters.currency(text); fail("accepted " + text); }
            catch (IllegalArgumentException expected) { assertNotNull(expected); }
        }
    }
}
