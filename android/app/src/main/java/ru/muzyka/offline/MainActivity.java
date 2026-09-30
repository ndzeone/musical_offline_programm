package ru.muzyka.offline;

import android.Manifest;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.util.Log;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.ConsoleMessage;
import android.webkit.CookieManager;
import android.webkit.PermissionRequest;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import org.json.JSONObject;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Окно приложения: общий интерфейс (папка web) во встроенном браузере + мост к Android. */
public class MainActivity extends Activity implements Engine.Listener {
    static final String HOST = "appassets.androidplatform.net";
    static final String START = "https://" + HOST + "/www/index.html";
    private static final int REQ_AUDIO = 11, REQ_EXPORT = 12, REQ_IMPORT = 13;

    FrameLayout root;
    WebView web;
    WebView browser;                 // сайты площадок внутри программы
    private int browserProgress = 0;
    volatile String insetsJson = "";
    private final ExecutorService io = Executors.newFixedThreadPool(2);
    private String pendingScan, pendingExport, pendingImport, exportPayload;
    private int lastTop = -1, lastBottom = -1;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        edgeToEdge(getWindow());
        root = new FrameLayout(this);
        root.setBackgroundColor(0xFF140A22);
        setContentView(root);
        Engine.get(this).listener = this;
        createWeb();
        root.setOnApplyWindowInsetsListener((v, ins) -> {
            applyInsets(ins);
            return ins;
        });
    }

    private void createWeb() {
        web = new WebView(this);
        web.setBackgroundColor(0xFF140A22);
        web.setOverScrollMode(View.OVER_SCROLL_NEVER);
        web.setVerticalScrollBarEnabled(false);
        web.setHorizontalScrollBarEnabled(false);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setTextZoom(100);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        s.setDisplayZoomControls(false);
        s.setUseWideViewPort(true);
        if ((getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0) WebView.setWebContentsDebuggingEnabled(true);
        web.addJavascriptInterface(new Bridge(this), "AndroidNative");
        web.setWebViewClient(new Client());
        web.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onConsoleMessage(ConsoleMessage m) {
                Log.i("MuzykaWeb", m.messageLevel() + " " + m.message() + " @" + m.sourceId() + ":" + m.lineNumber());
                return true;
            }
        });
        root.addView(web, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        web.loadUrl(START);
    }

    // ---------- во весь экран, с отступами под вырез камеры и системные панели ----------

    @SuppressWarnings("deprecation")
    private void edgeToEdge(Window w) {
        if (Build.VERSION.SDK_INT >= 30) {
            w.setDecorFitsSystemWindows(false);
        } else {
            w.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        }
        w.setStatusBarColor(Color.TRANSPARENT);
        w.setNavigationBarColor(Color.TRANSPARENT);
        if (Build.VERSION.SDK_INT >= 29) {
            w.setStatusBarContrastEnforced(false);
            w.setNavigationBarContrastEnforced(false);
        }
        if (Build.VERSION.SDK_INT >= 28) {
            WindowManager.LayoutParams lp = w.getAttributes();
            lp.layoutInDisplayCutoutMode = Build.VERSION.SDK_INT >= 30
                    ? WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                    : WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            w.setAttributes(lp);
        }
    }

    @SuppressWarnings("deprecation")
    private void applyInsets(WindowInsets ins) {
        float d = getResources().getDisplayMetrics().density;
        int top, bottom, left, right, ime;
        if (Build.VERSION.SDK_INT >= 30) {
            android.graphics.Insets s = ins.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            android.graphics.Insets k = ins.getInsets(WindowInsets.Type.ime());
            top = s.top; bottom = s.bottom; left = s.left; right = s.right; ime = k.bottom;
        } else {
            top = ins.getSystemWindowInsetTop();
            bottom = ins.getSystemWindowInsetBottom();
            left = ins.getSystemWindowInsetLeft();
            right = ins.getSystemWindowInsetRight();
            int stable = ins.getStableInsetBottom();
            ime = bottom > stable + 80 * d ? bottom : 0;
            if (ime > 0) bottom = stable;
        }
        // Клавиатура: страница становится ниже, а не прячется под неё
        root.setPadding(left, 0, right, ime);
        int t = Math.round(top / d), b = ime > 0 ? 0 : Math.round(bottom / d);
        insetsJson = "{\"top\":" + t + ",\"bottom\":" + b + "}";
        if (t != lastTop || b != lastBottom) {
            lastTop = t;
            lastBottom = b;
            js("window.__insets && window.__insets(" + t + "," + b + ")");
        }
    }

    // ---------- страница ----------

    private final class Client extends WebViewClient {
        @Override public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest r) {
            Uri u = r.getUrl();
            if (!HOST.equals(u.getHost())) return null;
            String path = u.getPath();
            if (path == null || !path.startsWith("/www/") || path.contains("..")) return missing();
            try {
                InputStream in = getAssets().open(path.substring(1));
                String mime = mime(path);
                WebResourceResponse res = new WebResourceResponse(mime, mime.startsWith("text/") || mime.endsWith("javascript") ? "utf-8" : null, in);
                Map<String, String> h = new HashMap<>();
                h.put("Cache-Control", "no-cache");
                res.setResponseHeaders(h);
                return res;
            } catch (Exception e) {
                return missing();
            }
        }

        @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
            Uri u = r.getUrl();
            if (HOST.equals(u.getHost())) return false;
            openExternal(u.toString());
            return true;
        }

        @Override public boolean onRenderProcessGone(WebView v, RenderProcessGoneDetail detail) {
            // Страницу выгрузили (мало памяти) — создаём заново. Музыка при этом играет дальше.
            if (v == web) {
                root.removeView(web);
                web.destroy();
                web = null;
                lastTop = lastBottom = -1;
                createWeb();
                root.requestApplyInsets();
            }
            return true;
        }
    }

    private static WebResourceResponse missing() {
        return new WebResourceResponse("text/plain", "utf-8", 404, "Not Found", new HashMap<>(), new ByteArrayInputStream(new byte[0]));
    }

    private static String mime(String p) {
        String s = p.toLowerCase();
        if (s.endsWith(".html")) return "text/html";
        if (s.endsWith(".js")) return "application/javascript";
        if (s.endsWith(".css")) return "text/css";
        if (s.endsWith(".json")) return "application/json";
        if (s.endsWith(".png")) return "image/png";
        if (s.endsWith(".jpg") || s.endsWith(".jpeg")) return "image/jpeg";
        if (s.endsWith(".svg")) return "image/svg+xml";
        if (s.endsWith(".woff2")) return "font/woff2";
        if (s.endsWith(".woff")) return "font/woff";
        if (s.endsWith(".ttf")) return "font/ttf";
        if (s.endsWith(".otf")) return "font/otf";
        return "application/octet-stream";
    }

    void js(String code) {
        runOnUiThread(() -> {
            if (web != null) web.evaluateJavascript(code, null);
        });
    }

    void reply(String id, String json) {
        js("window.__nb && window.__nb(" + q(id) + "," + q(json) + ")");
    }

    static String q(String s) {
        return JSONObject.quote(s == null ? "" : s).replace("\u2028", "\\u2028").replace("\u2029", "\\u2029");
    }

    @Override public void onEngineEvent(String name, String json) {
        js("window.__nbEvent && window.__nbEvent(" + q(name) + "," + q(json) + ")");
    }

    // ---------- кнопка «назад»: сначала закрываем окна в приложении, потом сворачиваемся (музыка играет) ----------

    @SuppressWarnings("deprecation")
    @Override public void onBackPressed() {
        if (web == null) { moveTaskToBack(true); return; }
        web.evaluateJavascript("(window.__back && window.__back()) ? 1 : 0", v -> {
            if (!"1".equals(v)) moveTaskToBack(true);
        });
    }

    @Override protected void onPause() {
        if (web != null) {
            web.evaluateJavascript("window.__flush && window.__flush()", null);   // сохранить всё прямо сейчас
            web.onPause();
        }
        Engine.get(this).persistNow();
        super.onPause();
    }

    @Override protected void onResume() {
        super.onResume();
        if (web != null) web.onResume();
    }

    @Override protected void onDestroy() {
        Engine e = Engine.get(this);
        if (e.listener == this) e.listener = null;
        if (browser != null) {
            root.removeView(browser);
            browser.destroy();
            browser = null;
        }
        if (web != null) {
            root.removeView(web);
            web.destroy();
            web = null;
        }
        io.shutdown();
        super.onDestroy();
    }

    // ---------- музыка на телефоне ----------

    private String audioPermission() {
        return Build.VERSION.SDK_INT >= 33 ? Manifest.permission.READ_MEDIA_AUDIO : Manifest.permission.READ_EXTERNAL_STORAGE;
    }

    void scan(String id, boolean ask) {
        if (checkSelfPermission(audioPermission()) == PackageManager.PERMISSION_GRANTED) {
            io.execute(() -> reply(id, Media.scan(this)));
            return;
        }
        if (!ask) {
            reply(id, "{\"ok\":false,\"denied\":true,\"tracks\":[]}");
            return;
        }
        runOnUiThread(() -> {
            pendingScan = id;
            requestPermissions(new String[]{audioPermission()}, REQ_AUDIO);
        });
    }

    @Override public void onRequestPermissionsResult(int req, String[] perms, int[] res) {
        super.onRequestPermissionsResult(req, perms, res);
        if (req != REQ_AUDIO || pendingScan == null) return;
        String id = pendingScan;
        pendingScan = null;
        if (res.length > 0 && res[0] == PackageManager.PERMISSION_GRANTED) {
            io.execute(() -> reply(id, Media.scan(this)));
        } else {
            boolean forever = !shouldShowRequestPermissionRationale(audioPermission());
            reply(id, "{\"ok\":false,\"denied\":true,\"forever\":" + forever + ",\"tracks\":[]}");
        }
    }

    // ---------- копия библиотеки в файл и обратно ----------

    void exportFile(String id, String name, String text) {
        runOnUiThread(() -> {
            pendingExport = id;
            exportPayload = text;
            Intent i = new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("application/json").putExtra(Intent.EXTRA_TITLE, name);
            try {
                startActivityForResult(i, REQ_EXPORT);
            } catch (ActivityNotFoundException e) {
                pendingExport = null;
                exportPayload = null;
                reply(id, "{\"ok\":false}");
            }
        });
    }

    void importFile(String id) {
        runOnUiThread(() -> {
            pendingImport = id;
            Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*");
            try {
                startActivityForResult(i, REQ_IMPORT);
            } catch (ActivityNotFoundException e) {
                pendingImport = null;
                reply(id, "null");
            }
        });
    }

    @Override protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        Uri u = res == RESULT_OK && data != null ? data.getData() : null;
        if (req == REQ_EXPORT && pendingExport != null) {
            String id = pendingExport, text = exportPayload;
            pendingExport = null;
            exportPayload = null;
            if (u == null || text == null) { reply(id, "{\"ok\":false}"); return; }
            io.execute(() -> {
                boolean ok = false;
                for (String mode : new String[]{"wt", "w"}) {
                    try (OutputStream o = getContentResolver().openOutputStream(u, mode)) {
                        if (o == null) continue;
                        o.write(text.getBytes(StandardCharsets.UTF_8));
                        ok = true;
                        break;
                    } catch (Exception ignored) { }
                }
                reply(id, "{\"ok\":" + ok + "}");
            });
        } else if (req == REQ_IMPORT && pendingImport != null) {
            String id = pendingImport;
            pendingImport = null;
            if (u == null) { reply(id, "null"); return; }
            io.execute(() -> {
                try (InputStream in = getContentResolver().openInputStream(u)) {
                    String text = in == null ? "" : Files.readAll(in, 32 << 20);
                    JSONObject o = new JSONObject();
                    o.put("text", text);
                    reply(id, o.toString());
                } catch (Exception e) {
                    reply(id, "null");
                }
            });
        }
    }

    // ---------- браузер внутри программы ----------

    @SuppressWarnings("deprecation")
    private void createBrowser() {
        browser = new WebView(this);
        browser.setBackgroundColor(Color.WHITE);
        WebSettings s = browser.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setUseWideViewPort(true);
        s.setLoadWithOverviewMode(true);
        s.setSupportZoom(true);
        s.setBuiltInZoomControls(true);
        s.setDisplayZoomControls(false);
        s.setSupportMultipleWindows(false);
        // сайты не должны думать, что это «урезанный» встроенный браузер
        s.setUserAgentString(s.getUserAgentString().replace("; wv)", ")"));
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(browser, true);
        browser.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                String u = r.getUrl().toString();
                if (u.startsWith("http://") || u.startsWith("https://")) return false;
                openScheme(u);
                return true;
            }
            @Override public void onPageStarted(WebView v, String url, android.graphics.Bitmap icon) { browserEvent(true); }
            @Override public void onPageFinished(WebView v, String url) { browserEvent(false); }
            @Override public void doUpdateVisitedHistory(WebView v, String url, boolean reload) { browserEvent(null); }
            @Override public boolean onRenderProcessGone(WebView v, RenderProcessGoneDetail d) {
                if (v == browser) {
                    root.removeView(browser);
                    browser.destroy();
                    browser = null;
                    js("window.__nbEvent && window.__nbEvent('browser', {closed: true})");
                }
                return true;
            }
        });
        browser.setWebChromeClient(new WebChromeClient() {
            @Override public void onReceivedTitle(WebView v, String title) { browserEvent(null); }
            @Override public void onProgressChanged(WebView v, int p) {
                if (Math.abs(p - browserProgress) >= 10 || p == 100) { browserProgress = p; browserEvent(p < 100 ? Boolean.TRUE : null); }
            }
            @Override public void onPermissionRequest(PermissionRequest req) {
                // защищённая музыка (как в Spotify) — можно; камера и микрофон — нет
                for (String res : req.getResources()) {
                    if (!PermissionRequest.RESOURCE_PROTECTED_MEDIA_ID.equals(res)) { req.deny(); return; }
                }
                req.grant(req.getResources());
            }
        });
        browser.setDownloadListener((url, ua, cd, mime, len) -> openExternal(url));
        root.addView(browser, new FrameLayout.LayoutParams(1, 1));
    }

    /** Ссылки вида spotify:, vk:, intent:// — в приложения. */
    private void openScheme(String u) {
        try {
            if (u.startsWith("intent:")) {
                Intent i = Intent.parseUri(u, Intent.URI_INTENT_SCHEME);
                try { startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); return; } catch (Exception e) {
                    String fb = i.getStringExtra("browser_fallback_url");
                    if (fb != null && browser != null) browser.loadUrl(fb);
                    return;
                }
            }
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(u)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } catch (Exception ignored) { }
    }

    private void browserEvent(Boolean loading) {
        WebView b = browser;
        if (b == null) return;
        try {
            JSONObject o = new JSONObject();
            o.put("url", b.getUrl() == null ? "" : b.getUrl());
            o.put("title", b.getTitle() == null ? "" : b.getTitle());
            o.put("canBack", b.canGoBack());
            o.put("canFwd", b.canGoForward());
            if (loading != null) o.put("loading", loading.booleanValue());
            o.put("progress", browserProgress / 100.0);
            js("window.__nbEvent && window.__nbEvent('browser'," + q(o.toString()) + ")");
        } catch (Exception ignored) { }
    }

    /** Прямоугольник из страницы (в её точках) → место браузера на экране. */
    private void placeBrowser(String rectJson) {
        if (browser == null || web == null) return;
        try {
            JSONObject r = new JSONObject(rectJson);
            double vw = r.optDouble("vw", 0);
            double k = vw > 0 ? web.getWidth() / vw : getResources().getDisplayMetrics().density;
            FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams((int) Math.round(r.optDouble("w") * k), (int) Math.round(r.optDouble("h") * k));
            lp.leftMargin = (int) Math.round(r.optDouble("x") * k);
            lp.topMargin = (int) Math.round(r.optDouble("y") * k);
            browser.setLayoutParams(lp);
        } catch (Exception ignored) { }
    }

    void browserOpen(String url, String rect) {
        runOnUiThread(() -> {
            if (browser == null) createBrowser();
            placeBrowser(rect);
            browser.setVisibility(View.VISIBLE);
            browser.bringToFront();
            // тот же сайт уже открыт — показываем как есть (музыка и вход сохраняются)
            boolean same = browser.getUrl() != null && url.equals(lastBrowserStart);
            if (!same) browser.loadUrl(url);
            lastBrowserStart = url;
            browserEvent(null);
        });
    }
    private String lastBrowserStart = "";

    void browserBounds(String rect) { runOnUiThread(() -> placeBrowser(rect)); }

    void browserNav(String action) {
        runOnUiThread(() -> {
            if (browser == null) return;
            switch (action == null ? "" : action) {
                case "back": if (browser.canGoBack()) browser.goBack(); break;
                case "forward": if (browser.canGoForward()) browser.goForward(); break;
                case "reload": browser.reload(); break;
                case "stop": browser.stopLoading(); break;
                default: break;
            }
        });
    }

    /** Закрыть — спрятать: страница остаётся (если на сайте играет музыка, она не прервётся). */
    void browserClose() { runOnUiThread(() -> { if (browser != null) browser.setVisibility(View.GONE); }); }

    // ---------- обновление из выпуска на GitHub ----------

    void installUpdate(String url, String name) {
        io.execute(() -> {
            File dir = UpdateFiles.dir(this);
            File f = new File(dir, "update.apk");
            HttpURLConnection c = null;
            try {
                if (!dir.exists() && !dir.mkdirs()) throw new Exception("no dir");
                c = (HttpURLConnection) new URL(url).openConnection();
                c.setConnectTimeout(15000);
                c.setReadTimeout(30000);
                c.setInstanceFollowRedirects(true);
                c.setRequestProperty("User-Agent", "MuzykaOffline (Android)");
                int code = c.getResponseCode();
                if (code != 200) throw new Exception("HTTP " + code);
                long total = c.getContentLengthLong(), done = 0;
                int lastPct = -1;
                try (java.io.InputStream in = c.getInputStream(); FileOutputStream out = new FileOutputStream(f)) {
                    byte[] buf = new byte[65536];
                    int n;
                    while ((n = in.read(buf)) > 0) {
                        out.write(buf, 0, n);
                        done += n;
                        int pct = total > 0 ? (int) (done * 100 / total) : 0;
                        if (pct - lastPct >= 2 || (pct == 100 && lastPct != 100)) {
                            lastPct = pct;
                            js("window.__nbEvent && window.__nbEvent('update', {phase: 'progress', progress: " + (pct / 100.0) + "})");
                        }
                    }
                }
                android.content.pm.PackageInfo pi = getPackageManager().getPackageArchiveInfo(f.getPath(), 0);
                if (pi == null) throw new Exception("not an apk");
                Log.i("MuzykaUpdate", "downloaded " + pi.packageName + " " + pi.versionName + " (" + f.length() + " bytes)");
                js("window.__nbEvent && window.__nbEvent('update', {phase: 'installing', version: " + q(String.valueOf(pi.versionName)) + "})");
                Uri u = Uri.parse("content://" + getPackageName() + ".updates/update.apk");
                Intent i = new Intent(Intent.ACTION_VIEW).setDataAndType(u, "application/vnd.android.package-archive")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                runOnUiThread(() -> {
                    try { startActivity(i); } catch (Exception e) {
                        js("window.__nbEvent && window.__nbEvent('update', {phase: 'error', message: 'Android не открыл установку'})");
                    }
                });
            } catch (Exception e) {
                Log.w("MuzykaUpdate", "download", e);
                js("window.__nbEvent && window.__nbEvent('update', {phase: 'error', message: 'Не получилось скачать обновление. Проверь интернет'})");
            } finally {
                if (c != null) c.disconnect();
            }
        });
    }

    // ---------- разное ----------

    boolean openExternal(String url) {
        try {
            Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    boolean launchApp(String pkg) {
        try {
            Intent i = getPackageManager().getLaunchIntentForPackage(pkg);
            if (i == null) return false;
            startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    void openNotifSettings() {
        Intent i;
        if (Build.VERSION.SDK_INT >= 30) {
            i = new Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                    .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                            new ComponentName(this, MediaListener.class).flattenToString());
            try { startActivity(i); return; } catch (Exception ignored) { }
        }
        try {
            startActivity(new Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS));
        } catch (Exception ignored) { }
    }

    void openAppSettings() {
        try {
            startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", getPackageName(), null)));
        } catch (Exception ignored) { }
    }

    void keepOn(boolean on) {
        if (on) getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        else getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }

    /** Светлая тема — тёмные значки в строке состояния, тёмная — светлые. */
    @SuppressWarnings("deprecation")
    void bars(boolean lightTheme) {
        Window w = getWindow();
        if (Build.VERSION.SDK_INT >= 30) {
            WindowInsetsController c = w.getInsetsController();
            if (c == null) return;
            int mask = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
            c.setSystemBarsAppearance(lightTheme ? mask : 0, mask);
        } else {
            View d = w.getDecorView();
            int f = d.getSystemUiVisibility();
            int mask = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
            d.setSystemUiVisibility(lightTheme ? f | mask : f & ~mask);
        }
    }
}
