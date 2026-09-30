package ru.muzyka.offline;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

/** Держит приложение живым, пока играет музыка (в фоне и с выключенным экраном). */
public class PlaybackService extends Service {
    static volatile PlaybackService running;
    private boolean foreground = false;

    @Override public void onCreate() {
        super.onCreate();
        running = this;
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        Engine e = Engine.get(this);
        // Система ждёт уведомление сразу после запуска — показываем его до всего остального
        promote(e.buildNotification());
        String a = intent != null ? intent.getAction() : null;
        if (a != null) e.handleAction(a);
        if (Engine.ACT_STOP.equals(a) || !e.hasQueue()) {
            finish();
            return START_NOT_STICKY;
        }
        if (!e.wants) demote(e.buildNotification());
        return START_NOT_STICKY;
    }

    void promote(Notification n) {
        try {
            if (Build.VERSION.SDK_INT >= 29) startForeground(Engine.NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
            else startForeground(Engine.NOTIF_ID, n);
            foreground = true;
        } catch (Exception ex) {
            Log.w(Engine.TAG, "foreground", ex);
            nm().notify(Engine.NOTIF_ID, n);
        }
    }

    /** На паузе уведомление остаётся, но его можно смахнуть. */
    void demote(Notification n) {
        if (foreground) {
            stopForeground(STOP_FOREGROUND_DETACH);
            foreground = false;
        }
        nm().notify(Engine.NOTIF_ID, n);
    }

    void finish() {
        stopForeground(STOP_FOREGROUND_REMOVE);
        foreground = false;
        nm().cancel(Engine.NOTIF_ID);
        stopSelf();
    }

    @Override public void onTaskRemoved(Intent rootIntent) {
        // Приложение смахнули из недавних: если музыка играет — пусть играет, иначе закрываемся
        Engine e = Engine.get(this);
        e.persistNow();
        if (!e.wants) e.stopAll();
        super.onTaskRemoved(rootIntent);
    }

    @Override public void onDestroy() {
        if (running == this) running = null;
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) { return null; }

    private NotificationManager nm() { return (NotificationManager) getSystemService(NOTIFICATION_SERVICE); }
}
