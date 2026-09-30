package ru.muzyka.offline;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileNotFoundException;

/** Скачанный установщик обновления для системной установки (только чтение, только папка обновлений). */
public class UpdateFiles extends ContentProvider {
    @Override public boolean onCreate() { return true; }

    static File dir(android.content.Context c) { return new File(c.getCacheDir(), "updates"); }

    private File file(Uri u) {
        String n = u.getLastPathSegment();
        if (n == null || !n.matches("[A-Za-z0-9._-]+") || getContext() == null) return null;
        return new File(dir(getContext()), n);
    }

    @Override public String getType(Uri u) { return "application/vnd.android.package-archive"; }

    @Override public ParcelFileDescriptor openFile(Uri u, String mode) throws FileNotFoundException {
        File f = file(u);
        if (f == null || !f.exists()) throw new FileNotFoundException(String.valueOf(u));
        return ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override public Cursor query(Uri u, String[] projection, String selection, String[] args, String sort) {
        File f = file(u);
        MatrixCursor c = new MatrixCursor(new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE});
        if (f != null && f.exists()) c.addRow(new Object[]{f.getName(), f.length()});
        return c;
    }

    @Override public Uri insert(Uri u, ContentValues v) { return null; }

    @Override public int delete(Uri u, String s, String[] a) { return 0; }

    @Override public int update(Uri u, ContentValues v, String s, String[] a) { return 0; }
}
