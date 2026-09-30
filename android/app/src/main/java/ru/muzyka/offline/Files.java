package ru.muzyka.offline;

import android.content.Context;
import android.util.Log;

import org.json.JSONTokener;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/**
 * Настройки и библиотека. Запись всегда целиком во временный файл и подмена одним шагом,
 * поэтому файл не может остаться «наполовину записанным». Раз в 10 минут — запасная копия.
 * Если файл всё-таки испорчен, он откладывается в сторону, а читается запасная копия.
 */
final class Files {
    private Files() { }

    private static String safe(String name) {
        String s = name == null ? "" : name.replaceAll("[^A-Za-z0-9._-]", "_");
        return s.isEmpty() ? "data.json" : s;
    }

    static synchronized String read(Context c, String name) {
        File dir = c.getFilesDir();
        File f = new File(dir, safe(name)), bak = new File(dir, safe(name) + ".bak");
        String s = readFile(f);
        if (valid(s)) return s;
        if (s != null && !s.trim().isEmpty()) {
            File broken = new File(dir, safe(name) + ".broken-" + System.currentTimeMillis());
            if (!f.renameTo(broken)) Log.w("MuzykaFiles", "can't move aside " + f);
        }
        String b = readFile(bak);
        return valid(b) ? b : "";
    }

    static synchronized boolean write(Context c, String name, String text) {
        if (text == null) return false;
        File dir = c.getFilesDir();
        File f = new File(dir, safe(name)), tmp = new File(dir, safe(name) + ".tmp"), bak = new File(dir, safe(name) + ".bak");
        try (FileOutputStream o = new FileOutputStream(tmp)) {
            o.write(text.getBytes(StandardCharsets.UTF_8));
            o.getFD().sync();
        } catch (IOException e) {
            Log.w("MuzykaFiles", "write " + name, e);
            return false;
        }
        boolean oldBackup = !bak.exists() || System.currentTimeMillis() - bak.lastModified() > 10 * 60 * 1000;
        if (f.exists() && oldBackup && valid(readFile(f))) {
            if (bak.exists() && !bak.delete()) Log.w("MuzykaFiles", "can't drop old backup");
            if (!f.renameTo(bak)) Log.w("MuzykaFiles", "can't keep backup");
        }
        if (tmp.renameTo(f)) return true;
        // на всякий случай: переименование не удалось — пишем напрямую
        try (FileOutputStream o = new FileOutputStream(f)) {
            o.write(text.getBytes(StandardCharsets.UTF_8));
            o.getFD().sync();
            return true;
        } catch (IOException e) {
            return false;
        }
    }

    static boolean valid(String s) {
        if (s == null || s.trim().isEmpty()) return false;
        try {
            new JSONTokener(s).nextValue();
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    static String readFile(File f) {
        if (!f.exists()) return null;
        try (InputStream in = new FileInputStream(f)) {
            return readAll(in, 64 << 20);
        } catch (IOException e) {
            return null;
        }
    }

    static String readAll(InputStream in, int limit) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[16384];
        int n, total = 0;
        while ((n = in.read(buf)) > 0) {
            total += n;
            if (total > limit) break;
            out.write(buf, 0, n);
        }
        return new String(out.toByteArray(), StandardCharsets.UTF_8);
    }
}
