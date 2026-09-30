package ru.muzyka.offline;

import org.json.JSONObject;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Iterator;

/** Запросы к сайтам текстов песен и обложек, к GitHub и к серверу профилей (без ограничений браузера). */
final class Net {
    private Net() { }

    static String get(String url, String headersJson) { return request(url, "GET", headersJson, null); }

    static String request(String url, String method, String headersJson, String body) {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(url).openConnection();
            c.setConnectTimeout(10000);
            c.setReadTimeout(15000);
            c.setInstanceFollowRedirects(true);
            c.setRequestMethod("POST".equals(method) ? "POST" : "GET");
            c.setRequestProperty("User-Agent", "MuzykaOffline/2.5 (Android)");
            c.setRequestProperty("Accept", "application/json, text/plain, */*");
            if (headersJson != null && !headersJson.isEmpty()) {
                JSONObject h = new JSONObject(headersJson);
                Iterator<String> it = h.keys();
                while (it.hasNext()) {
                    String k = it.next();
                    c.setRequestProperty(k, h.optString(k));
                }
            }
            if ("POST".equals(method)) {
                byte[] data = (body == null ? "" : body).getBytes(StandardCharsets.UTF_8);
                c.setDoOutput(true);
                c.setFixedLengthStreamingMode(data.length);
                try (OutputStream o = c.getOutputStream()) { o.write(data); }
            }
            int code = c.getResponseCode();
            InputStream in = code >= 400 ? c.getErrorStream() : c.getInputStream();
            String text = "";
            if (in != null) {
                try (InputStream s = in) { text = Files.readAll(s, 8 << 20); }
            }
            JSONObject o = new JSONObject();
            o.put("status", code);
            o.put("body", text);
            return o.toString();
        } catch (Exception e) {
            return "{\"status\":0,\"body\":\"\"}";
        } finally {
            if (c != null) c.disconnect();
        }
    }
}
