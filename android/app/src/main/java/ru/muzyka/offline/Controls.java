package ru.muzyka.offline;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Уведомление смахнули — закрываем плеер (очередь и место в треке сохранены). */
public class Controls extends BroadcastReceiver {
    @Override public void onReceive(Context c, Intent i) {
        Engine.get(c).handleAction(i.getAction());
    }
}
