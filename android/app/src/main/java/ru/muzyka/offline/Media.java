package ru.muzyka.offline;

import android.content.ContentUris;
import android.content.Context;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import android.util.Base64;
import android.util.Size;

import org.json.JSONArray;
import org.json.JSONObject;

import android.media.MediaScannerConnection;
import android.os.Environment;
import android.os.storage.StorageManager;
import android.os.storage.StorageVolume;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;

/** Музыка на телефоне, обложки из файлов, значки приложений. */
final class Media {
    private Media() { }

    private static final Map<String, String> icons = new HashMap<>();

    static String scan(Context ctx) {
        try {
            JSONObject r = new JSONObject();
            r.put("ok", true);
            r.put("tracks", query(ctx, false, null));
            return r.toString();
        } catch (Exception e) {
            return "{\"ok\":false,\"tracks\":[]}";
        }
    }

    private static Uri collection() {
        return Build.VERSION.SDK_INT >= 29 ? MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL) : MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;
    }

    // Не песни: звонки, диктофон, звуки уведомлений и будильника
    private static final Pattern NOT_SONGS = Pattern.compile("(?i)/(recordings?|call|callrecord|voice ?recorder|notifications|ringtones|alarms|ui)/|voice notes");

    /**
     * Музыка из медиатеки Android. all — вся (и то, что Android не пометил как музыку, если оно длиннее 30 секунд);
     * paths — сюда складываются пути найденных файлов (для проверки после поиска по папкам).
     */
    @SuppressWarnings("deprecation")
    private static JSONArray query(Context ctx, boolean all, java.util.Set<String> paths) throws Exception {
        JSONArray out = new JSONArray();
        Uri coll = collection();
        String[] proj = {
                MediaStore.Audio.Media._ID, MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST,
                MediaStore.Audio.Media.ALBUM, MediaStore.Audio.Media.DURATION, MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.DATE_ADDED, MediaStore.Audio.Media.DATA, MediaStore.Audio.Media.IS_MUSIC
        };
        // только что скопированный файл медиатека ещё не разобрала (is_music пока пусто) — его тоже показываем
        String sel = all ? null : "(" + MediaStore.Audio.Media.IS_MUSIC + " != 0 OR " + MediaStore.Audio.Media.IS_MUSIC + " IS NULL)";
        try (Cursor c = ctx.getContentResolver().query(coll, proj, sel, null, MediaStore.Audio.Media.TITLE + " COLLATE NOCASE ASC")) {
            if (c == null) return out;
            while (c.moveToNext()) {
                long id = c.getLong(0);
                long dur = c.getLong(4);
                String data = c.getString(7);
                boolean music = c.isNull(8) || c.getInt(8) != 0;
                if (dur > 0 && dur < 15000) continue;        // короткие звуки — не песни
                if (all && !music) {
                    if (dur > 0 && dur < 30000) continue;
                    if (data != null && NOT_SONGS.matcher(data).find()) continue;
                }
                if (all && data != null && !new File(data).exists()) continue;   // файла уже нет
                if (paths != null && data != null) paths.add(data);
                String title = clean(c.getString(1));
                String artist = clean(c.getString(2));
                String album = clean(c.getString(3));
                if (title.isEmpty()) {
                    String dn = c.getString(5);
                    title = dn == null ? "Без названия" : dn.replaceFirst("\\.[^.]+$", "");
                }
                // «Исполнитель - Название» в имени файла, если исполнитель не указан
                if (artist.isEmpty()) {
                    int k = title.indexOf(" - ");
                    if (k > 0 && k < title.length() - 3) {
                        artist = title.substring(0, k).trim();
                        title = title.substring(k + 3).trim();
                    }
                }
                JSONObject o = new JSONObject();
                o.put("uri", ContentUris.withAppendedId(coll, id).toString());
                o.put("title", title);
                o.put("artist", artist);
                o.put("album", album);
                o.put("duration", dur / 1000.0);
                o.put("added", c.getLong(6));
                out.put(o);
            }
        }
        return out;
    }

    private static final Pattern AUDIO = Pattern.compile("(?i).+\\.(mp3|m4a|aac|flac|wav|ogg|oga|opus|wma|amr|mid|midi|3gp|mka|aiff?|webm)$");

    /** Все аудиофайлы в памяти телефона и на картах, в любых папках. */
    private static void walk(File dir, int depth, List<String> out) {
        if (depth > 14 || out.size() > 40000) return;
        File[] list = dir.listFiles();
        if (list == null) return;
        for (File f : list) {
            String n = f.getName();
            if (n.startsWith(".")) continue;
            if (f.isDirectory()) {
                if (depth == 0 && "Android".equals(n)) continue;          // данные приложений
                walk(f, depth + 1, out);
            } else if (AUDIO.matcher(n).matches() && f.length() > 100 * 1024) {
                out.add(f.getAbsolutePath());
            }
        }
    }

    private static List<File> roots(Context ctx) {
        List<File> r = new ArrayList<>();
        r.add(Environment.getExternalStorageDirectory());
        if (Build.VERSION.SDK_INT >= 30) {
            try {
                StorageManager sm = (StorageManager) ctx.getSystemService(Context.STORAGE_SERVICE);
                for (StorageVolume v : sm.getStorageVolumes()) {
                    File d = v.getDirectory();
                    if (d != null && !r.contains(d)) r.add(d);
                }
            } catch (Exception ignored) { }
        }
        return r;
    }

    /** Полная проверка: медиатека + все папки. Найденное в папках, но не в медиатеке, добавляется в неё. */
    static String deepScan(Context ctx) {
        try {
            java.util.Set<String> known = new java.util.HashSet<>();
            int before = query(ctx, true, known).length();
            List<String> files = new ArrayList<>();
            for (File root : roots(ctx)) walk(root, 0, files);
            List<String> fresh = new ArrayList<>();
            for (String f : files) if (!known.contains(f)) fresh.add(f);
            if (!fresh.isEmpty()) {
                final CountDownLatch done = new CountDownLatch(fresh.size());
                MediaScannerConnection.scanFile(ctx, fresh.toArray(new String[0]), null, (path, uri) -> done.countDown());
                done.await(Math.min(180, 20 + fresh.size() / 5), TimeUnit.SECONDS);
            }
            JSONArray tracks = query(ctx, true, null);
            int missing = 0;
            // исчезнувшие файлы: медиатека их помнит, а на диске нет — просим Android их забыть
            try (Cursor c = ctx.getContentResolver().query(collection(), new String[]{MediaStore.Audio.Media.DATA}, null, null, null)) {
                if (c != null) {
                    List<String> gone = new ArrayList<>();
                    while (c.moveToNext()) {
                        String d = c.getString(0);
                        if (d != null && !new File(d).exists()) gone.add(d);
                    }
                    missing = gone.size();
                    if (!gone.isEmpty()) MediaScannerConnection.scanFile(ctx, gone.toArray(new String[0]), null, null);
                }
            }
            JSONObject stats = new JSONObject();
            stats.put("found", tracks.length());
            stats.put("fresh", Math.max(0, tracks.length() - before));
            stats.put("files", files.size());
            stats.put("missing", missing);
            JSONObject r = new JSONObject();
            r.put("ok", true);
            r.put("tracks", tracks);
            r.put("stats", stats);
            return r.toString();
        } catch (Exception e) {
            android.util.Log.w("MuzykaMedia", "deepScan", e);
            return "{\"ok\":false,\"tracks\":[]}";
        }
    }

    private static String clean(String s) {
        if (s == null) return "";
        s = s.trim();
        return "<unknown>".equals(s) ? "" : s;
    }

    static String embeddedArt(Context ctx, String uri) {
        Bitmap b = picture(ctx, uri, 400);
        String art = b == null ? null : dataUrl(b, true);
        try {
            JSONObject o = new JSONObject();
            o.put("art", art == null ? JSONObject.NULL : art);
            return o.toString();
        } catch (Exception e) {
            return "{\"art\":null}";
        }
    }

    /** Картинка из самого файла, а если её нет — обложка альбома из медиатеки. */
    static Bitmap picture(Context ctx, String uri, int max) {
        if (uri == null || uri.isEmpty()) return null;
        MediaMetadataRetriever r = new MediaMetadataRetriever();
        try {
            r.setDataSource(ctx, Uri.parse(uri));
            byte[] pic = r.getEmbeddedPicture();
            if (pic != null) {
                Bitmap b = decode(pic, max);
                if (b != null) return b;
            }
        } catch (Exception ignored) {
        } finally {
            try { r.release(); } catch (Exception ignored) { }
        }
        if (Build.VERSION.SDK_INT >= 29 && uri.startsWith("content://")) {
            try {
                return ctx.getContentResolver().loadThumbnail(Uri.parse(uri), new Size(max, max), null);
            } catch (Exception ignored) { }
        }
        return null;
    }

    static Bitmap decode(byte[] data, int max) {
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(data, 0, data.length, o);
        int s = 1;
        while (o.outWidth / (s * 2) >= max && o.outHeight / (s * 2) >= max) s *= 2;
        BitmapFactory.Options d = new BitmapFactory.Options();
        d.inSampleSize = s;
        Bitmap b = BitmapFactory.decodeByteArray(data, 0, data.length, d);
        if (b == null) return null;
        return fit(b, max);
    }

    static Bitmap fit(Bitmap b, int max) {
        int w = b.getWidth(), h = b.getHeight();
        if (w <= max && h <= max) return b;
        float k = (float) max / Math.max(w, h);
        return Bitmap.createScaledBitmap(b, Math.max(1, Math.round(w * k)), Math.max(1, Math.round(h * k)), true);
    }

    static String dataUrl(Bitmap b, boolean jpeg) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        b.compress(jpeg ? Bitmap.CompressFormat.JPEG : Bitmap.CompressFormat.PNG, 86, out);
        return (jpeg ? "data:image/jpeg;base64," : "data:image/png;base64,") + Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP);
    }

    /** Значок установленного приложения (Spotify, Яндекс Музыка…) или пустая строка. */
    static synchronized String appIcon(Context ctx, String pkg) {
        if (pkg == null || pkg.isEmpty()) return "";
        String c = icons.get(pkg);
        if (c != null) return c;
        String res = "";
        try {
            Drawable d = ctx.getPackageManager().getApplicationIcon(pkg);
            Bitmap b = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888);
            Canvas cv = new Canvas(b);
            d.setBounds(0, 0, 96, 96);
            d.draw(cv);
            res = dataUrl(b, false);
        } catch (Exception ignored) { }
        icons.put(pkg, res);
        return res;
    }
}
