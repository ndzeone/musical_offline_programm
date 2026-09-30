package ru.muzyka.offline;

import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.net.Uri;
import android.os.Message;
import android.os.SystemClock;
import android.util.Log;
import android.view.MotionEvent;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import org.json.JSONObject;

import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Сайты площадок внутри программы: у каждой вкладки своя страница, вход (cookies) общий.
 * Скрытые вкладки продолжают играть. Ссылки «открыть в приложении» остаются здесь же —
 * ничего не уходит во внешний браузер и не требует ставить приложения.
 */
final class SiteTabs {
    private static final String TAG = "MuzykaSites";
    private final MainActivity a;
    private final Map<String, WebView> tabs = new LinkedHashMap<>();
    private final Map<String, WebView> popups = new HashMap<>();
    private final Map<String, Boolean> injected = new HashMap<>();
    private String shown = null;
    private JSONObject lastRect = null;
    private String agent = null;
    private String mobileUA = null, desktopUA = null;

    SiteTabs(MainActivity a) { this.a = a; }

    // ---------- площадки ----------

    static String platformOf(String url) {
        String h = Uri.parse(url == null ? "" : url).getHost();
        h = h == null ? "" : h.toLowerCase();
        if (h.matches("(.*\\.)?spotify\\.com")) return "spotify";
        if (h.matches("(.*\\.)?soundcloud\\.com")) return "soundcloud";
        if (h.matches("(.*\\.)?yandex\\.(ru|com|by|kz|uz)") || h.matches("(.*\\.)?ya\\.ru")) return "yandex";
        if (h.matches("(.*\\.)?(vk\\.(ru|com|me)|vkontakte\\.ru)")) return "vk";
        return "";
    }

    /** Spotify и SoundCloud играют музыку только в «компьютерной» версии сайта, Яндекс и VK — и в телефонной. */
    private String uaFor(WebView w, String url) {
        if (mobileUA == null) {
            String def = w.getSettings().getUserAgentString();
            mobileUA = def.replace("; wv)", ")").replaceAll("\\sVersion/\\d+(\\.\\d+)*", "");
            Matcher m = Pattern.compile("Chrome/([\\d.]+)").matcher(def);
            String ver = m.find() ? m.group(1).replaceAll("^(\\d+).*", "$1") + ".0.0.0" : "130.0.0.0";
            desktopUA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/" + ver + " Safari/537.36";
        }
        String p = platformOf(url);
        return "spotify".equals(p) || "soundcloud".equals(p) ? desktopUA : mobileUA;
    }

    private String agentJs() {
        if (agent != null) return agent;
        try (InputStream in = a.getAssets().open("www/agent/site-agent.js")) {
            agent = Files.readAll(in, 1 << 20);
        } catch (Exception e) {
            Log.w(TAG, "agent", e);
            agent = "";
        }
        return agent;
    }

    private void inject(WebView w) { String js = agentJs(); if (!js.isEmpty()) w.evaluateJavascript(js, null); }

    // ---------- создание вкладки ----------

    private final class Post {
        final String tab;
        Post(String tab) { this.tab = tab; }
        @JavascriptInterface public void post(String data) {
            if (data == null || data.length() > 65536) return;
            a.js("window.__nbEvent && window.__nbEvent('siteMsg', {tab: " + MainActivity.q(tab) + ", data: " + MainActivity.q(data) + "})");
        }
    }

    @SuppressWarnings("SetJavaScriptEnabled")
    private void setup(WebView w, String tab, String url) {
        w.setBackgroundColor(Color.WHITE);
        WebSettings s = w.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setUseWideViewPort(true);
        s.setLoadWithOverviewMode(true);
        s.setSupportZoom(true);
        s.setBuiltInZoomControls(true);
        s.setDisplayZoomControls(false);
        s.setSupportMultipleWindows(true);
        s.setJavaScriptCanOpenWindowsAutomatically(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setUserAgentString(uaFor(w, url));
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(w, true);
        w.addJavascriptInterface(new Post(tab), "MuzykaSite");
        w.setDownloadListener((u, ua, cd, mime, len) -> { });
    }

    private WebView create(String tab, String url) {
        WebView w = new WebView(a);
        setup(w, tab, url);
        w.setWebViewClient(new Client(tab));
        w.setWebChromeClient(new Chrome(tab));
        w.setVisibility(View.INVISIBLE);
        a.root.addView(w, params(lastRect));
        tabs.put(tab, w);
        return w;
    }

    private final class Client extends WebViewClient {
        final String tab;
        Client(String tab) { this.tab = tab; }

        @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
            String u = r.getUrl().toString();
            if (u.startsWith("http://") || u.startsWith("https://")) {
                if (!r.isForMainFrame()) return false;
                String ua = uaFor(v, u);
                if (!ua.equals(v.getSettings().getUserAgentString())) {
                    v.getSettings().setUserAgentString(ua);
                    v.loadUrl(u);
                    return true;
                }
                return false;
            }
            scheme(v, u);
            return true;
        }

        @Override public void onPageStarted(WebView v, String url, Bitmap icon) {
            injected.put(tab, false);
            inject(v);
            event(tab, true);
        }

        @Override public void onPageFinished(WebView v, String url) {
            inject(v);
            injected.put(tab, true);
            event(tab, false);
        }

        @Override public void doUpdateVisitedHistory(WebView v, String url, boolean reload) { event(tab, null); }

        @Override public boolean onRenderProcessGone(WebView v, RenderProcessGoneDetail d) {
            WebView w = tabs.remove(tab);
            if (w != null) { a.root.removeView(w); w.destroy(); }
            closePopup(tab);
            if (tab.equals(shown)) shown = null;
            a.js("window.__nbEvent && window.__nbEvent('siteGone', {tab: " + MainActivity.q(tab) + "})");
            return true;
        }
    }

    private final class Chrome extends WebChromeClient {
        final String tab;
        int progress = 0;
        Chrome(String tab) { this.tab = tab; }

        @Override public void onReceivedTitle(WebView v, String title) { event(tab, null); }

        @Override public void onProgressChanged(WebView v, int p) {
            if (p >= 30 && !Boolean.TRUE.equals(injected.get(tab))) { inject(v); injected.put(tab, true); }
            if (Math.abs(p - progress) >= 10 || p == 100) { progress = p; progressOf.put(tab, p); event(tab, p < 100 ? Boolean.TRUE : null); }
        }

        @Override public void onPermissionRequest(PermissionRequest req) {
            // защищённая музыка (Spotify) — можно; камера и микрофон — нет
            for (String res : req.getResources()) {
                if (!PermissionRequest.RESOURCE_PROTECTED_MEDIA_ID.equals(res)) { req.deny(); return; }
            }
            req.grant(req.getResources());
        }

        /** Окно входа (Google, VK ID, Яндекс ID…) — поверх вкладки, внутри программы. */
        @Override public boolean onCreateWindow(WebView v, boolean dialog, boolean user, Message msg) {
            closePopup(tab);
            WebView p = new WebView(a);
            setup(p, tab, v.getUrl());
            p.getSettings().setUserAgentString(v.getSettings().getUserAgentString());
            p.setWebViewClient(new WebViewClient() {
                @Override public boolean shouldOverrideUrlLoading(WebView pv, WebResourceRequest r) {
                    String u = r.getUrl().toString();
                    if (u.startsWith("http://") || u.startsWith("https://")) return false;
                    scheme(pv, u);
                    return true;
                }
            });
            p.setWebChromeClient(new WebChromeClient() {
                @Override public void onCloseWindow(WebView w) { closePopup(tab); event(tab, null); }
            });
            WebView base = tabs.get(tab);
            a.root.addView(p, base != null ? base.getLayoutParams() : params(lastRect));
            p.setVisibility(base != null && base.getVisibility() == View.VISIBLE ? View.VISIBLE : View.INVISIBLE);
            popups.put(tab, p);
            WebView.WebViewTransport t = (WebView.WebViewTransport) msg.obj;
            t.setWebView(p);
            msg.sendToTarget();
            return true;
        }

        @Override public void onCloseWindow(WebView w) { }
    }
    private final Map<String, Integer> progressOf = new HashMap<>();

    /** Ссылки вида intent://, spotify:, vk: — остаются в программе: берём веб-адрес, если он есть. */
    private void scheme(WebView v, String u) {
        try {
            if (u.startsWith("intent:")) {
                Intent i = Intent.parseUri(u, Intent.URI_INTENT_SCHEME);
                String fb = i.getStringExtra("browser_fallback_url");
                if (fb != null && (fb.startsWith("https://") || fb.startsWith("http://")) && !fb.contains("play.google.com")) v.loadUrl(fb);
                return;
            }
            if (u.startsWith("mailto:") || u.startsWith("tel:")) {
                a.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(u)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            }
            // market:, spotify:, vk:, yandexmusic: и т. п. — не уводим из программы
        } catch (Exception ignored) { }
    }

    private void closePopup(String tab) {
        WebView p = popups.remove(tab);
        if (p != null) { a.root.removeView(p); p.destroy(); }
    }

    // ---------- события для страницы программы ----------

    void event(String tab, Boolean loading) {
        WebView b = tabs.get(tab);
        if (b == null) return;
        try {
            JSONObject o = new JSONObject();
            o.put("tab", tab);
            o.put("url", b.getUrl() == null ? "" : b.getUrl());
            o.put("title", b.getTitle() == null ? "" : b.getTitle());
            o.put("canBack", b.canGoBack() || popups.containsKey(tab));
            o.put("canFwd", b.canGoForward());
            if (loading != null) o.put("loading", loading.booleanValue());
            Integer p = progressOf.get(tab);
            o.put("progress", (p == null ? 0 : p) / 100.0);
            a.js("window.__nbEvent && window.__nbEvent('site'," + MainActivity.q(o.toString()) + ")");
        } catch (Exception ignored) { }
    }

    // ---------- место на экране ----------

    /** Прямоугольник из страницы (в её точках) → место на экране. */
    private FrameLayout.LayoutParams params(JSONObject r) {
        if (r == null || a.web == null) return new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
        double vw = r.optDouble("vw", 0);
        double k = vw > 0 && a.web.getWidth() > 0 ? a.web.getWidth() / vw : a.getResources().getDisplayMetrics().density;
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams((int) Math.round(r.optDouble("w") * k), (int) Math.round(r.optDouble("h") * k));
        lp.leftMargin = (int) Math.round(r.optDouble("x") * k);
        lp.topMargin = (int) Math.round(r.optDouble("y") * k);
        return lp;
    }

    private void remember(String rect) {
        try { if (rect != null && !rect.isEmpty() && !"{}".equals(rect)) lastRect = new JSONObject(rect); } catch (Exception ignored) { }
    }

    private void place(String tab) {
        FrameLayout.LayoutParams lp = params(lastRect);
        WebView w = tabs.get(tab);
        if (w != null) w.setLayoutParams(lp);
        WebView p = popups.get(tab);
        if (p != null) p.setLayoutParams(params(lastRect));
    }

    // ---------- команды ----------

    void open(String tab, String url, String rect, boolean show) {
        remember(rect);
        WebView w = tabs.get(tab);
        if (w == null) w = create(tab, url);
        w.getSettings().setUserAgentString(uaFor(w, url));
        w.loadUrl(url);
        if (show) show(tab, null); else place(tab);
    }

    void show(String tab, String rect) {
        remember(rect);
        for (Map.Entry<String, WebView> e : tabs.entrySet()) {
            boolean on = e.getKey().equals(tab);
            e.getValue().setVisibility(on ? View.VISIBLE : View.INVISIBLE);
            WebView p = popups.get(e.getKey());
            if (p != null) p.setVisibility(on ? View.VISIBLE : View.INVISIBLE);
        }
        shown = tabs.containsKey(tab) ? tab : null;
        if (shown == null) return;
        place(tab);
        tabs.get(tab).bringToFront();
        WebView p = popups.get(tab);
        if (p != null) p.bringToFront();
        event(tab, null);
    }

    void hide() {
        shown = null;
        for (WebView w : tabs.values()) w.setVisibility(View.INVISIBLE);
        for (WebView w : popups.values()) w.setVisibility(View.INVISIBLE);
    }

    void close(String tab) {
        closePopup(tab);
        WebView w = tabs.remove(tab);
        if (w != null) {
            a.root.removeView(w);
            w.loadUrl("about:blank");
            w.destroy();
        }
        if (tab.equals(shown)) shown = null;
    }

    void bounds(String rect) {
        remember(rect);
        if (shown != null) place(shown);
    }

    void nav(String tab, String action) {
        WebView w = tabs.get(tab);
        if (w == null) return;
        WebView p = popups.get(tab);
        switch (action == null ? "" : action) {
            case "back":
                if (p != null) { if (p.canGoBack()) p.goBack(); else closePopup(tab); }
                else if (w.canGoBack()) w.goBack();
                break;
            case "forward": if (w.canGoForward()) w.goForward(); break;
            case "reload": w.reload(); break;
            case "stop": w.stopLoading(); break;
            default: break;
        }
        event(tab, null);
    }

    void load(String tab, String url) {
        WebView w = tabs.get(tab);
        if (w == null) { open(tab, url, null, false); return; }
        closePopup(tab);
        w.getSettings().setUserAgentString(uaFor(w, url));
        w.loadUrl(url);
    }

    void eval(String id, String tab, String js) {
        WebView w = tabs.get(tab);
        if (w == null) { a.reply(id, "null"); return; }
        w.evaluateJavascript(js, v -> a.reply(id, v == null ? "null" : v));
    }

    /** Настоящее нажатие пальцем в точку страницы (сайт считает его нажатием человека). */
    void press(String tab, double x, double y, double vw, double vh) {
        WebView w = tabs.get(tab);
        if (w == null || w.getVisibility() != View.VISIBLE || vw <= 0 || w.getWidth() <= 0) return;
        float k = (float) (w.getWidth() / vw);
        float px = (float) (x * k), py = (float) (y * k);
        long t = SystemClock.uptimeMillis();
        MotionEvent down = MotionEvent.obtain(t, t, MotionEvent.ACTION_DOWN, px, py, 0);
        MotionEvent up = MotionEvent.obtain(t, t + 60, MotionEvent.ACTION_UP, px, py, 0);
        w.dispatchTouchEvent(down);
        w.dispatchTouchEvent(up);
        down.recycle();
        up.recycle();
    }

    // ---------- вход в аккаунты ----------

    private static final String[][] LOGIN = {
            {"spotify", "https://open.spotify.com", "sp_dc"},
            {"soundcloud", "https://soundcloud.com", "oauth_token"},
            {"yandex", "https://music.yandex.ru", "Session_id"},
            {"vk", "https://vk.ru", "remixsid|remixnsid"},
            {"vk", "https://vk.com", "remixsid|remixnsid"}
    };

    static String logins() {
        JSONObject o = new JSONObject();
        CookieManager cm = CookieManager.getInstance();
        try {
            for (String[] l : LOGIN) {
                String c = cm.getCookie(l[1]);
                boolean on = false;
                if (c != null) {
                    for (String part : c.split(";")) {
                        String name = part.trim().split("=", 2)[0];
                        String val = part.contains("=") ? part.substring(part.indexOf('=') + 1).trim() : "";
                        if (name.matches(l[2]) && !val.isEmpty() && !"deleted".equals(val)) on = true;
                    }
                }
                if (on || !o.has(l[0])) o.put(l[0], on || o.optBoolean(l[0]));
            }
        } catch (Exception ignored) { }
        return o.toString();
    }

    /** Выйти из площадки: стираем её cookies на этом устройстве. */
    static boolean logout(String platform) {
        CookieManager cm = CookieManager.getInstance();
        List<String> urls = new ArrayList<>();
        switch (platform == null ? "" : platform) {
            case "spotify": urls.add("https://open.spotify.com"); urls.add("https://accounts.spotify.com"); urls.add("https://spotify.com"); break;
            case "soundcloud": urls.add("https://soundcloud.com"); urls.add("https://secure.soundcloud.com"); break;
            case "yandex": urls.add("https://music.yandex.ru"); urls.add("https://passport.yandex.ru"); urls.add("https://yandex.ru"); break;
            case "vk": urls.add("https://vk.ru"); urls.add("https://vk.com"); urls.add("https://id.vk.com"); urls.add("https://login.vk.com"); break;
            default: return false;
        }
        for (String u : urls) {
            String c = cm.getCookie(u);
            if (c == null) continue;
            String host = Uri.parse(u).getHost();
            String parent = host != null && host.split("\\.").length > 2 ? host.substring(host.indexOf('.') + 1) : host;
            for (String part : c.split(";")) {
                String name = part.trim().split("=", 2)[0];
                if (name.isEmpty()) continue;
                String gone = name + "=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/";
                cm.setCookie(u, gone);
                cm.setCookie(u, gone + "; Domain=" + host);
                cm.setCookie(u, gone + "; Domain=." + parent);
            }
        }
        cm.flush();
        return true;
    }

    void destroy() {
        for (String t : new ArrayList<>(tabs.keySet())) close(t);
    }
}
