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

import java.io.ByteArrayOutputStream;
import java.util.HashMap;
import java.util.Map;

/** Музыка на телефоне, обложки из файлов, значки приложений. */
final class Media {
    private Media() { }

    private static final Map<String, String> icons = new HashMap<>();

    static String scan(Context ctx) {
        JSONArray out = new JSONArray();
        Uri coll = Build.VERSION.SDK_INT >= 29
                ? MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
                : MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;
        String[] proj = {
                MediaStore.Audio.Media._ID, MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST,
                MediaStore.Audio.Media.ALBUM, MediaStore.Audio.Media.DURATION, MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.DATE_ADDED
        };
        // только что скопированный файл медиатека ещё не разобрала (is_music пока пусто) — его тоже показываем
        String sel = "(" + MediaStore.Audio.Media.IS_MUSIC + " != 0 OR " + MediaStore.Audio.Media.IS_MUSIC + " IS NULL)";
        try (Cursor c = ctx.getContentResolver().query(coll, proj, sel, null, MediaStore.Audio.Media.TITLE + " COLLATE NOCASE ASC")) {
            if (c != null) {
                while (c.moveToNext()) {
                    long id = c.getLong(0);
                    long dur = c.getLong(4);
                    if (dur > 0 && dur < 15000) continue;        // короткие звуки — не песни
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
            JSONObject r = new JSONObject();
            r.put("ok", true);
            r.put("tracks", out);
            return r.toString();
        } catch (Exception e) {
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
