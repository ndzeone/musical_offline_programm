package ru.muzyka.offline;

import android.app.NotificationManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.MediaSessionManager;
import android.media.session.PlaybackState;
import android.os.Build;
import android.os.SystemClock;
import android.provider.Settings;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Что играет в других приложениях (Spotify, Яндекс Музыка, VK, SoundCloud) и управление ими. */
final class Sessions {
    private Sessions() { }

    private static List<MediaController> cache = Collections.emptyList();
    private static long cacheAt = 0;
    private static final Map<String, String> labels = new HashMap<>();
    private static String artKey = null, artVal = "";

    static boolean hasAccess(Context c) {
        try {
            if (Build.VERSION.SDK_INT >= 27) {
                NotificationManager nm = c.getSystemService(NotificationManager.class);
                return nm != null && nm.isNotificationListenerAccessGranted(new ComponentName(c, MediaListener.class));
            }
            String s = Settings.Secure.getString(c.getContentResolver(), "enabled_notification_listeners");
            return s != null && s.contains(c.getPackageName());
        } catch (Exception e) {
            return false;
        }
    }

    private static synchronized List<MediaController> list(Context c) {
        long now = SystemClock.elapsedRealtime();
        if (now - cacheAt < 400) return cache;
        cacheAt = now;
        try {
            MediaSessionManager m = c.getSystemService(MediaSessionManager.class);
            cache = m == null ? Collections.emptyList() : m.getActiveSessions(new ComponentName(c, MediaListener.class));
        } catch (Exception e) {
            cache = Collections.emptyList();
        }
        return cache;
    }

    private static MediaController find(Context c, String pkg) {
        for (MediaController m : list(c)) if (m.getPackageName().equals(pkg)) return m;
        return null;
    }

    static String json(Context c) {
        JSONArray a = new JSONArray();
        if (!hasAccess(c)) return "[]";
        for (MediaController m : list(c)) {
            try {
                if (m.getPackageName().equals(c.getPackageName())) continue;
                MediaMetadata md = m.getMetadata();
                if (md == null) continue;
                String title = first(md.getString(MediaMetadata.METADATA_KEY_TITLE), md.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE));
                if (title.isEmpty()) continue;
                String artist = first(md.getString(MediaMetadata.METADATA_KEY_ARTIST), md.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST),
                        md.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE));
                PlaybackState st = m.getPlaybackState();
                boolean playing = st != null && (st.getState() == PlaybackState.STATE_PLAYING || st.getState() == PlaybackState.STATE_BUFFERING);
                long pos = st == null ? 0 : st.getPosition();
                if (st != null && st.getState() == PlaybackState.STATE_PLAYING && st.getLastPositionUpdateTime() > 0) {
                    pos += (long) ((SystemClock.elapsedRealtime() - st.getLastPositionUpdateTime()) * st.getPlaybackSpeed());
                }
                long dur = md.getLong(MediaMetadata.METADATA_KEY_DURATION);
                JSONObject o = new JSONObject();
                o.put("pkg", m.getPackageName());
                o.put("app", label(c, m.getPackageName()));
                o.put("title", title);
                o.put("artist", artist);
                o.put("album", first(md.getString(MediaMetadata.METADATA_KEY_ALBUM)));
                o.put("dur", Math.max(0, dur) / 1000.0);
                o.put("pos", Math.max(0, pos) / 1000.0);
                o.put("playing", playing);
                a.put(o);
            } catch (Exception ignored) { }
        }
        return a.toString();
    }

    static synchronized String art(Context c, String pkg) {
        MediaController m = find(c, pkg);
        if (m == null || m.getMetadata() == null) return "";
        MediaMetadata md = m.getMetadata();
        String key = pkg + "|" + md.getString(MediaMetadata.METADATA_KEY_TITLE) + "|" + md.getString(MediaMetadata.METADATA_KEY_ARTIST);
        if (key.equals(artKey)) return artVal;
        Bitmap b = md.getBitmap(MediaMetadata.METADATA_KEY_ART);
        if (b == null) b = md.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART);
        if (b == null) b = md.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON);
        String v = "";
        if (b != null) {
            try { v = Media.dataUrl(Media.fit(b, 400), true); } catch (Exception ignored) { }
        }
        if (!v.isEmpty()) {           // картинка может прийти чуть позже названия — пустое не запоминаем
            artKey = key;
            artVal = v;
        }
        return v;
    }

    static void control(Context c, String pkg, String action, double arg) {
        MediaController m = find(c, pkg);
        if (m == null) return;
        MediaController.TransportControls t = m.getTransportControls();
        switch (action == null ? "" : action) {
            case "play": t.play(); break;
            case "pause": t.pause(); break;
            case "next": t.skipToNext(); break;
            case "prev": t.skipToPrevious(); break;
            case "seek": t.seekTo((long) (arg * 1000)); break;
            default: break;
        }
        synchronized (Sessions.class) { cacheAt = 0; }
    }

    private static synchronized String label(Context c, String pkg) {
        String l = labels.get(pkg);
        if (l != null) return l;
        try {
            PackageManager pm = c.getPackageManager();
            l = pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString();
        } catch (Exception e) {
            l = pkg;
        }
        labels.put(pkg, l);
        return l;
    }

    private static String first(String... v) {
        for (String s : v) if (s != null && !s.trim().isEmpty()) return s.trim();
        return "";
    }
}
