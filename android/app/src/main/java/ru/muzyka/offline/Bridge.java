package ru.muzyka.offline;

import android.content.Context;
import android.webkit.JavascriptInterface;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Команды, которые страница вызывает как window.AndroidNative.*.
 * Долгие (сеть, поиск музыки, файлы) отвечают позже через window.__nb(id, json).
 */
final class Bridge {
    private static final String[][] PLATFORM_APPS = {
            {"com.spotify.music", "Spotify"}, {"ru.yandex.music", "Яндекс Музыка"}, {"com.uma.musicvk", "VK Музыка"},
            {"com.vkontakte.android", "VK"}, {"com.soundcloud.android", "SoundCloud"}
    };

    private final MainActivity a;
    private final Context app;
    private final ExecutorService pool = Executors.newFixedThreadPool(4);

    Bridge(MainActivity a) {
        this.a = a;
        this.app = a.getApplicationContext();
    }

    private Engine engine() { return Engine.get(app); }

    @JavascriptInterface public String version() {
        try {
            return app.getPackageManager().getPackageInfo(app.getPackageName(), 0).versionName;
        } catch (Exception e) {
            return "2.3";
        }
    }

    // ---------- сеть и файлы ----------

    @JavascriptInterface public void http(String id, String url, String headers) {
        pool.execute(() -> a.reply(id, Net.get(url, headers)));
    }

    @JavascriptInterface public String readFile(String name) { return Files.read(app, name); }

    @JavascriptInterface public boolean writeFile(String name, String text) { return Files.write(app, name, text); }

    @JavascriptInterface public void scanMusic(String id, boolean ask) { a.scan(id, ask); }

    @JavascriptInterface public void exportText(String id, String name, String text) { a.exportFile(id, name, text); }

    @JavascriptInterface public void importText(String id) { a.importFile(id); }

    @JavascriptInterface public void embeddedArt(String id, String uri) {
        pool.execute(() -> a.reply(id, Media.embeddedArt(app, uri)));
    }

    // ---------- свой плеер ----------

    @JavascriptInterface public void setQueue(String qid, String items, int index, boolean autoplay, double startSec) {
        List<Engine.Item> list = Engine.parse(items);
        Engine e = engine();
        e.main.post(() -> e.setQueue(qid, list, index, autoplay, (long) (startSec * 1000)));
    }

    @JavascriptInterface public void control(String action, double arg) {
        Engine e = engine();
        e.main.post(() -> e.control(action, arg));
    }

    @JavascriptInterface public String playbackState() { return engine().stateJson(); }

    @JavascriptInterface public String queueState() { return engine().queueJson(); }

    @JavascriptInterface public void setMode(boolean shuffle, String repeat) {
        Engine e = engine();
        e.main.post(() -> e.setMode(shuffle, repeat));
    }

    @JavascriptInterface public void setBass(double db) {
        Engine e = engine();
        e.main.post(() -> e.setBass((int) Math.round(db)));
    }

    // ---------- другие приложения ----------

    @JavascriptInterface public boolean hasNotifAccess() { return Sessions.hasAccess(app); }

    @JavascriptInterface public void openNotifAccess() { a.runOnUiThread(a::openNotifSettings); }

    @JavascriptInterface public String sessions() { return Sessions.json(app); }

    @JavascriptInterface public String sessionArt(String pkg) { return Sessions.art(app, pkg); }

    @JavascriptInterface public void sessionControl(String pkg, String action, double arg) {
        pool.execute(() -> Sessions.control(app, pkg, action, arg));
    }

    @JavascriptInterface public String appIcon(String pkg) { return Media.appIcon(app, pkg); }

    @JavascriptInterface public String installedApps() {
        JSONArray out = new JSONArray();
        for (String[] p : PLATFORM_APPS) {
            try {
                app.getPackageManager().getPackageInfo(p[0], 0);
                out.put(new JSONObject().put("pkg", p[0]).put("name", p[1]));
            } catch (Exception ignored) { }
        }
        return out.toString();
    }

    @JavascriptInterface public boolean openLink(String url) { return a.openExternal(url); }

    @JavascriptInterface public boolean launchApp(String pkg) { return a.launchApp(pkg); }

    @JavascriptInterface public void openAppSettings() { a.runOnUiThread(a::openAppSettings); }

    // ---------- окно ----------

    @JavascriptInterface public void keepScreenOn(boolean on) { a.runOnUiThread(() -> a.keepOn(on)); }

    @JavascriptInterface public void systemBars(boolean lightTheme) { a.runOnUiThread(() -> a.bars(lightTheme)); }

    @JavascriptInterface public String insets() { return a.insetsJson; }

    @JavascriptInterface public void ready() { a.runOnUiThread(() -> a.root.requestApplyInsets()); }
}
