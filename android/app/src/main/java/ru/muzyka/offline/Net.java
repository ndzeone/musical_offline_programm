package ru.muzyka.offline;

import org.json.JSONObject;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Iterator;

/** Запросы к сайтам текстов песен и обложек (без ограничений браузера). */
final class Net {
    private Net() { }

    static String get(String url, String headersJson) {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(url).openConnection();
            c.setConnectTimeout(10000);
            c.setReadTimeout(15000);
            c.setInstanceFollowRedirects(true);
            c.setRequestProperty("User-Agent", "MuzykaOffline/2.3 (Android)");
            c.setRequestProperty("Accept", "application/json, text/plain, */*");
            if (headersJson != null && !headersJson.isEmpty()) {
                JSONObject h = new JSONObject(headersJson);
                Iterator<String> it = h.keys();
                while (it.hasNext()) {
                    String k = it.next();
                    c.setRequestProperty(k, h.optString(k));
                }
            }
            int code = c.getResponseCode();
            InputStream in = code >= 400 ? c.getErrorStream() : c.getInputStream();
            String body = "";
            if (in != null) {
                try (InputStream s = in) { body = Files.readAll(s, 8 << 20); }
            }
            JSONObject o = new JSONObject();
            o.put("status", code);
            o.put("body", body);
            return o.toString();
        } catch (Exception e) {
            return "{\"status\":0,\"body\":\"\"}";
        } finally {
            if (c != null) c.disconnect();
        }
    }
}
