package ru.muzyka.offline;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.drawable.Icon;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaMetadata;
import android.media.MediaPlayer;
import android.media.audiofx.BassBoost;
import android.media.audiofx.Equalizer;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.os.SystemClock;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Плеер своих файлов: очередь, перемешивание, повтор, игра в фоне и с выключенным экраном,
 * уведомление, кнопки наушников и экрана блокировки. Всё, что меняет состояние, — на главном потоке.
 * Очередь и место в треке сохраняются, поэтому после перезапуска можно продолжить с того же места.
 */
final class Engine {
    interface Listener { void onEngineEvent(String name, String json); }

    static final String TAG = "MuzykaEngine";
    static final String CHANNEL = "playback";
    static final int NOTIF_ID = 1001;
    static final String ACT_PLAY = "ru.muzyka.offline.PLAY";
    static final String ACT_PAUSE = "ru.muzyka.offline.PAUSE";
    static final String ACT_NEXT = "ru.muzyka.offline.NEXT";
    static final String ACT_PREV = "ru.muzyka.offline.PREV";
    static final String ACT_STOP = "ru.muzyka.offline.STOP";

    private static Engine inst;

    static synchronized Engine get(Context c) {
        if (inst == null) inst = new Engine(c.getApplicationContext());
        return inst;
    }

    static final class Item {
        final String uri, title, artist, album;
        final double duration;

        Item(JSONObject o) {
            uri = o.optString("uri");
            title = o.optString("title");
            artist = o.optString("artist");
            album = o.optString("album");
            duration = o.optDouble("duration", 0);
        }

        JSONObject json() {
            JSONObject o = new JSONObject();
            try {
                o.put("uri", uri).put("title", title).put("artist", artist).put("album", album).put("duration", duration);
            } catch (Exception ignored) { }
            return o;
        }
    }

    static List<Item> parse(String json) {
        List<Item> out = new ArrayList<>();
        try {
            JSONArray a = new JSONArray(json);
            for (int i = 0; i < a.length(); i++) {
                JSONObject o = a.optJSONObject(i);
                if (o != null && !o.optString("uri").isEmpty()) out.add(new Item(o));
            }
        } catch (Exception e) { Log.w(TAG, "queue", e); }
        return out;
    }

    final Context ctx;
    final Handler main = new Handler(Looper.getMainLooper());
    final MediaSession session;
    private final SharedPreferences prefs;
    private final AudioManager am;
    private final NotificationManager nm;
    private final AudioAttributes attrs;
    private final AudioFocusRequest focus;
    private final ExecutorService bg = Executors.newSingleThreadExecutor();
    private final Random rnd = new Random();

    private final List<Item> queue = new ArrayList<>();
    private int[] order = new int[0];      // порядок игры: по списку или перемешанный
    private int op = -1;                   // место в этом порядке
    volatile String qid = "";
    volatile int index = -1;
    volatile boolean shuffle = false;
    volatile String repeat = "all";        // all | one | off
    volatile boolean wants = false;        // пользователь хочет, чтобы играло
    volatile boolean playing = false;      // звук идёт прямо сейчас
    volatile boolean preparing = false;
    private volatile long anchorPos = 0, anchorAt = 0, durMs = 0;
    private long pendingSeek = 0;
    private MediaPlayer mp;
    private boolean prepared = false;
    private int failures = 0;
    private int audioSession = 0;
    private Equalizer eq;
    private BassBoost boost;
    private int bassDb = 0;
    private boolean resumeOnGain = false, noisyOn = false, notifShown = false;
    private Bitmap art;
    private String artFor = null;
    private long lastSaved = 0;
    volatile Listener listener;

    // 2.5: музыка сайта площадки во встроенном браузере — уведомление показывает её, кнопки идут странице
    volatile boolean siteMode = false;
    volatile boolean delegate = false;     // плейлист с треками площадок: «дальше/назад» решает страница
    private String siteTitle = "", siteArtist = "", siteArtUrl = "";
    private boolean sitePlaying = false;
    private long sitePos = 0, siteDur = 0, siteAt = 0;
    private Bitmap siteArt;

    private final BroadcastReceiver noisy = new BroadcastReceiver() {
        @Override public void onReceive(Context c, Intent i) {
            if (AudioManager.ACTION_AUDIO_BECOMING_NOISY.equals(i.getAction())) pause();   // выдернули наушники
        }
    };

    private final Runnable ticker = new Runnable() {
        @Override public void run() {
            if (mp != null && prepared && playing) {
                try { anchor(mp.getCurrentPosition()); } catch (Exception ignored) { }
            }
            if (SystemClock.elapsedRealtime() - lastSaved > 5000) persist(false);
            if (wants) main.postDelayed(this, 1000);
        }
    };

    private Engine(Context c) {
        ctx = c;
        prefs = c.getSharedPreferences("engine", Context.MODE_PRIVATE);
        am = (AudioManager) c.getSystemService(Context.AUDIO_SERVICE);
        nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        attrs = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build();
        focus = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener(this::onFocus, main)
                .setWillPauseWhenDucked(false)
                .build();
        int sid = am.generateAudioSessionId();
        audioSession = sid > 0 ? sid : 0;

        NotificationChannel ch = new NotificationChannel(CHANNEL, c.getString(R.string.channel_name), NotificationManager.IMPORTANCE_LOW);
        ch.setShowBadge(false);
        ch.setSound(null, null);
        nm.createNotificationChannel(ch);

        session = new MediaSession(c, "Muzyka");
        session.setCallback(new MediaSession.Callback() {
            @Override public void onPlay() { if (siteMode) siteCmd("play", 0); else play(); }
            @Override public void onPause() { if (siteMode) siteCmd("pause", 0); else pause(); }
            @Override public void onStop() { if (siteMode) siteCmd("pause", 0); else pause(); }
            @Override public void onSkipToNext() { skip("next"); }
            @Override public void onSkipToPrevious() { skip("prev"); }
            @Override public void onSeekTo(long pos) { if (siteMode) siteCmd("seek", pos); else seek(pos); }
        }, main);
        session.setSessionActivity(openApp());
        restore();
    }

    // ---------- команды ----------

    void setQueue(String id, List<Item> items, int idx, boolean autoplay, long startMs) {
        if (items.isEmpty()) return;
        siteMode = false;
        synchronized (queue) {
            queue.clear();
            queue.addAll(items);
        }
        qid = id == null || id.isEmpty() ? Long.toString(System.currentTimeMillis(), 36) : id;
        idx = Math.max(0, Math.min(idx, items.size() - 1));
        failures = 0;
        buildOrder(idx);
        if (autoplay) {
            load(idx, true, startMs);
        } else {
            releasePlayer();
            index = idx;
            wants = false;
            durMs = (long) (items.get(idx).duration * 1000);
            anchor(Math.max(0, startMs));
            loadArt(items.get(idx));
            publish();
        }
        persist(true);
    }

    void control(String action, double arg) {
        switch (action == null ? "" : action) {
            case "play": play(); break;
            case "pause": pause(); break;
            case "toggle": if (wants) pause(); else play(); break;
            case "next": next(false); break;
            case "prev": prev(); break;
            case "seek": seek((long) (arg * 1000)); break;
            case "jump": jump((int) arg); break;
            case "stop": stopAll(); break;
            default: break;
        }
    }

    void handleAction(String a) {
        if (ACT_PLAY.equals(a)) { if (siteMode) siteCmd("play", 0); else play(); }
        else if (ACT_PAUSE.equals(a)) { if (siteMode) siteCmd("pause", 0); else pause(); }
        else if (ACT_NEXT.equals(a)) skip("next");
        else if (ACT_PREV.equals(a)) skip("prev");
        else if (ACT_STOP.equals(a)) stopAll();
    }

    /** «Дальше/назад» из уведомления, экрана блокировки и наушников. */
    private void skip(String action) {
        if (siteMode) { siteCmd(action, 0); return; }
        if (delegate && listener != null) { emit("control", "{\"action\":\"" + action + "\"}"); return; }
        if ("next".equals(action)) next(false); else prev();
    }

    private void siteCmd(String action, long posMs) {
        if ("play".equals(action) || "pause".equals(action)) {
            sitePos = sitePosMs(); siteAt = SystemClock.elapsedRealtime();
            sitePlaying = "play".equals(action);
            publish();
        }
        emit("siteControl", "{\"action\":\"" + action + "\",\"pos\":" + (posMs / 1000.0) + "}");
    }

    /** Что играет на сайте (JSON от страницы) или пусто — сайт больше не главный. */
    void setSite(String json) {
        if (json == null || json.isEmpty()) {
            if (!siteMode) return;
            siteMode = false;
            sitePlaying = false;
            if (size() > 0 && (wants || notifShown)) { publish(); return; }
            PlaybackService s = PlaybackService.running;
            if (s != null) s.finish(); else nm.cancel(NOTIF_ID);
            notifShown = false;
            return;
        }
        try {
            JSONObject o = new JSONObject(json);
            siteMode = true;
            siteTitle = o.optString("title");
            siteArtist = o.optString("artist");
            sitePlaying = o.optBoolean("playing");
            sitePos = (long) (o.optDouble("pos", 0) * 1000);
            siteDur = (long) (o.optDouble("dur", 0) * 1000);
            siteAt = SystemClock.elapsedRealtime();
            final String artUrl = o.optString("art");
            if (!artUrl.equals(siteArtUrl)) {
                siteArtUrl = artUrl;
                siteArt = null;
                if (artUrl.startsWith("https://")) {
                    bg.execute(() -> {
                        Bitmap b = download(artUrl);
                        main.post(() -> { if (artUrl.equals(siteArtUrl)) { siteArt = b; publish(); } });
                    });
                }
            }
            publish();
        } catch (Exception e) { Log.w(TAG, "site", e); }
    }

    private long sitePosMs() {
        long p = sitePos + (sitePlaying ? SystemClock.elapsedRealtime() - siteAt : 0);
        if (siteDur > 0) p = Math.min(p, siteDur);
        return Math.max(0, p);
    }

    /** Звук играет или должен играть: свой файл или сайт. */
    boolean active() { return siteMode ? sitePlaying : wants; }

    private static Bitmap download(String url) {
        java.net.HttpURLConnection c = null;
        try {
            c = (java.net.HttpURLConnection) new java.net.URL(url).openConnection();
            c.setConnectTimeout(8000);
            c.setReadTimeout(10000);
            if (c.getResponseCode() != 200) return null;
            try (java.io.InputStream in = c.getInputStream()) {
                byte[] data = Files.readBytes(in, 4 << 20);
                return data == null ? null : Media.decode(data, 512);
            }
        } catch (Exception e) {
            return null;
        } finally {
            if (c != null) c.disconnect();
        }
    }

    void play() {
        if (size() == 0) return;
        wants = true;
        resumeOnGain = false;
        if (mp == null) {
            load(index < 0 ? orderAt(0) : index, true, anchorPos);
            return;
        }
        if (prepared) {
            if (!playing) startNow();
        } else {
            publish();   // ещё открывается — заиграет сразу после
        }
    }

    void pause() {
        wants = false;
        resumeOnGain = false;
        if (mp != null && prepared && playing) {
            try { anchor(mp.getCurrentPosition()); mp.pause(); } catch (Exception ignored) { }
        }
        playing = false;
        registerNoisy(false);
        main.removeCallbacks(ticker);
        publish();
        persist(false);
    }

    void seek(long ms) {
        ms = Math.max(0, ms);
        if (durMs > 0) ms = Math.min(ms, Math.max(0, durMs - 500));
        if (mp != null && prepared) {
            try { mp.seekTo((int) ms); } catch (Exception ignored) { }
        } else {
            pendingSeek = ms;
        }
        anchor(ms);
        publish();
        persist(false);
    }

    /** Дальше. auto — трек доиграл сам. */
    void next(boolean auto) {
        int n = size();
        if (n == 0) return;
        if (auto && "one".equals(repeat) && mp != null && prepared) {
            try { mp.seekTo(0); mp.start(); playing = true; anchor(0); publish(); } catch (Exception e) { load(index, true, 0); }
            return;
        }
        int nop = op + 1;
        if (nop >= n) {
            if (!auto || "all".equals(repeat)) {
                if (shuffle && n > 1) reshuffle();
                nop = 0;
            } else {
                // очередь закончилась: встаём на начало и ждём
                op = 0;
                load(orderAt(0), false, 0);
                emit("queueEnd", "{}");
                return;
            }
        }
        op = nop;
        load(orderAt(op), true, 0);
    }

    /** Назад: если трек играет дольше 3 секунд — в его начало, иначе предыдущий. */
    void prev() {
        int n = size();
        if (n == 0) return;
        if (posMs() > 3000) {
            seek(0);
            if (!wants) play();
            return;
        }
        int nop = op - 1;
        if (nop < 0) nop = "all".equals(repeat) ? n - 1 : 0;
        op = nop;
        load(orderAt(op), true, 0);
    }

    void jump(int idx) {
        if (idx < 0 || idx >= size()) return;
        for (int i = 0; i < order.length; i++) if (order[i] == idx) op = i;
        load(idx, true, 0);
    }

    void setMode(boolean sh, String rep) {
        repeat = "one".equals(rep) ? "one" : ("off".equals(rep) || "none".equals(rep)) ? "off" : "all";
        if (sh != shuffle) {
            shuffle = sh;
            buildOrder(Math.max(0, index));
        }
        persist(false);
        emitState();
    }

    void setBass(int db) {
        bassDb = Math.max(0, Math.min(15, db));
        applyEffects();
        persist(false);
    }

    /** Смахнули уведомление на паузе: закрываем плеер, но очередь и место помним. */
    void stopAll() {
        siteMode = false;
        sitePlaying = false;
        persist(true);
        wants = false;
        playing = false;
        releasePlayer();
        registerNoisy(false);
        main.removeCallbacks(ticker);
        am.abandonAudioFocusRequest(focus);
        session.setActive(false);
        notifShown = false;
        PlaybackService s = PlaybackService.running;
        if (s != null) s.finish();
        nm.cancel(NOTIF_ID);
        emitState();
    }

    void persistNow() { persist(true); }

    boolean hasQueue() { return size() > 0; }

    // ---------- состояние для страницы ----------

    String stateJson() {
        JSONObject o = new JSONObject();
        try {
            o.put("qid", qid).put("length", size()).put("index", index)
                    .put("playing", wants).put("buffering", wants && !playing)
                    .put("pos", posMs() / 1000.0).put("dur", durMs / 1000.0)
                    .put("shuffle", shuffle).put("repeat", repeat);
        } catch (Exception ignored) { }
        return o.toString();
    }

    String queueJson() {
        JSONObject o = new JSONObject();
        JSONArray a = new JSONArray();
        synchronized (queue) {
            for (Item it : queue) a.put(it.json());
        }
        try {
            o.put("qid", qid).put("index", index).put("items", a);
        } catch (Exception ignored) { }
        return o.toString();
    }

    long posMs() {
        long p = anchorPos + (playing ? SystemClock.elapsedRealtime() - anchorAt : 0);
        if (durMs > 0) p = Math.min(p, durMs);
        return Math.max(0, p);
    }

    // ---------- внутреннее ----------

    private int size() {
        synchronized (queue) { return queue.size(); }
    }

    private Item itemAt(int i) {
        synchronized (queue) { return i >= 0 && i < queue.size() ? queue.get(i) : null; }
    }

    private int orderAt(int i) {
        if (order.length == 0) return 0;
        return order[Math.max(0, Math.min(i, order.length - 1))];
    }

    private void buildOrder(int current) {
        int n = size();
        order = new int[n];
        for (int i = 0; i < n; i++) order[i] = i;
        if (shuffle && n > 1) {
            // текущий трек первым, остальные — вперемешку, каждый по разу
            for (int i = n - 1; i > 0; i--) {
                int j = rnd.nextInt(i + 1);
                int t = order[i]; order[i] = order[j]; order[j] = t;
            }
            for (int i = 0; i < n; i++) {
                if (order[i] == current) { order[i] = order[0]; order[0] = current; break; }
            }
            op = 0;
        } else {
            op = Math.max(0, Math.min(current, n - 1));
        }
    }

    /** Новый круг перемешивания: без повтора последнего трека первым. */
    private void reshuffle() {
        int n = order.length, last = index;
        for (int i = n - 1; i > 0; i--) {
            int j = rnd.nextInt(i + 1);
            int t = order[i]; order[i] = order[j]; order[j] = t;
        }
        if (n > 1 && order[0] == last) { int t = order[0]; order[0] = order[1]; order[1] = t; }
    }

    private void anchor(long pos) {
        anchorPos = Math.max(0, pos);
        anchorAt = SystemClock.elapsedRealtime();
    }

    private void releasePlayer() {
        MediaPlayer p = mp;
        mp = null;
        prepared = false;
        preparing = false;
        playing = false;
        if (p != null) {
            try { p.reset(); } catch (Exception ignored) { }
            try { p.release(); } catch (Exception ignored) { }
        }
    }

    private void load(int idx, boolean play, long startMs) {
        Item it = itemAt(idx);
        if (it == null) return;
        releasePlayer();
        index = idx;
        wants = play;
        preparing = true;
        durMs = (long) (it.duration * 1000);
        pendingSeek = Math.max(0, startMs);
        anchor(pendingSeek);
        final MediaPlayer p = new MediaPlayer();
        mp = p;
        try {
            p.setAudioAttributes(attrs);
            if (audioSession > 0) p.setAudioSessionId(audioSession);
            p.setWakeMode(ctx, PowerManager.PARTIAL_WAKE_LOCK);
            p.setOnPreparedListener(x -> { if (x == mp) onPrepared(); });
            p.setOnCompletionListener(x -> { if (x == mp) onCompleted(); });
            p.setOnErrorListener((x, what, extra) -> {
                if (x == mp) onFailed(it, what + "/" + extra);
                return true;
            });
            p.setDataSource(ctx, Uri.parse(it.uri));
            p.prepareAsync();
        } catch (Exception e) {
            Log.w(TAG, "open " + it.uri, e);
            main.post(() -> { if (p == mp) onFailed(it, e.getClass().getSimpleName()); });
        }
        loadArt(it);
        publish();
        persist(false);
    }

    private void onPrepared() {
        prepared = true;
        preparing = false;
        failures = 0;
        try {
            int d = mp.getDuration();
            if (d > 0) durMs = d;
            if (pendingSeek > 0 && (durMs <= 0 || pendingSeek < durMs - 1000)) mp.seekTo((int) pendingSeek);
            else pendingSeek = 0;
        } catch (Exception ignored) { }
        anchor(pendingSeek);
        pendingSeek = 0;
        applyEffects();
        if (wants) startNow();
        else publish();
    }

    private void startNow() {
        if (mp == null || !prepared) return;
        if (am.requestAudioFocus(focus) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            // идёт звонок или другое приложение не отдаёт звук
            wants = false;
            publish();
            return;
        }
        try {
            mp.setVolume(1f, 1f);
            mp.start();
            playing = true;
            anchor(anchorPos);   // место уже известно (перемотка может ещё идти)
        } catch (Exception e) {
            Log.w(TAG, "start", e);
            playing = false;
        }
        session.setActive(true);
        registerNoisy(true);
        main.removeCallbacks(ticker);
        main.postDelayed(ticker, 1000);
        publish();
    }

    private void onCompleted() {
        playing = false;
        anchor(durMs);
        next(true);
    }

    private void onFailed(Item it, String why) {
        Log.w(TAG, "can't play " + it.uri + " (" + why + ")");
        failures++;
        releasePlayer();
        emit("error", "{\"title\":" + JSONObject.quote(it.title) + "}");
        int n = size();
        if (failures >= Math.min(n, 5)) {
            // подряд не открылось несколько файлов — останавливаемся, а не крутимся по кругу
            wants = false;
            failures = 0;
            publish();
            return;
        }
        boolean keep = wants;
        main.postDelayed(() -> {
            if (keep) next(true);
            else publish();
        }, 250);
    }

    private void onFocus(int change) {
        switch (change) {
            case AudioManager.AUDIOFOCUS_LOSS:
                pause();
                break;
            case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
                if (wants) { pause(); resumeOnGain = true; }
                break;
            case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:
                if (mp != null && playing) try { mp.setVolume(0.3f, 0.3f); } catch (Exception ignored) { }
                break;
            case AudioManager.AUDIOFOCUS_GAIN:
                if (mp != null) try { mp.setVolume(1f, 1f); } catch (Exception ignored) { }
                if (resumeOnGain) { resumeOnGain = false; play(); }
                break;
            default:
                break;
        }
    }

    private void registerNoisy(boolean on) {
        try {
            if (on && !noisyOn) {
                IntentFilter f = new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY);
                if (Build.VERSION.SDK_INT >= 33) ctx.registerReceiver(noisy, f, Context.RECEIVER_EXPORTED);
                else ctx.registerReceiver(noisy, f);
                noisyOn = true;
            } else if (!on && noisyOn) {
                ctx.unregisterReceiver(noisy);
                noisyOn = false;
            }
        } catch (Exception e) { Log.w(TAG, "noisy", e); }
    }

    private void applyEffects() {
        if (audioSession <= 0) return;
        try {
            if (bassDb <= 0) {
                if (eq != null) eq.setEnabled(false);
                if (boost != null) boost.setEnabled(false);
                return;
            }
            if (eq == null && boost == null) {
                try { eq = new Equalizer(0, audioSession); } catch (Throwable t) { eq = null; }
                if (eq == null) try { boost = new BassBoost(0, audioSession); } catch (Throwable t) { boost = null; }
            }
            if (eq != null) {
                short[] range = eq.getBandLevelRange();
                short bands = eq.getNumberOfBands();
                for (short b = 0; b < bands; b++) {
                    int hz = eq.getCenterFreq(b) / 1000;
                    double k = hz <= 100 ? 1.0 : hz <= 300 ? 0.6 : hz <= 1000 ? 0.15 : 0;
                    int mb = (int) Math.round(bassDb * 100 * k);
                    eq.setBandLevel(b, (short) Math.max(range[0], Math.min(range[1], mb)));
                }
                eq.setEnabled(true);
            } else if (boost != null) {
                boost.setStrength((short) Math.min(1000, bassDb * 66));
                boost.setEnabled(true);
            }
        } catch (Throwable t) { Log.w(TAG, "fx", t); }
    }

    private void loadArt(Item it) {
        if (it.uri.equals(artFor)) return;
        artFor = it.uri;
        art = null;
        bg.execute(() -> {
            Bitmap b = Media.picture(ctx, it.uri, 512);
            main.post(() -> {
                if (it.uri.equals(artFor)) {
                    art = b;
                    publish();
                }
            });
        });
    }

    // ---------- уведомление, экран блокировки, наушники ----------

    private void publish() {
        if (siteMode) { publishSite(); return; }
        Item it = itemAt(index);
        if (it != null) {
            MediaMetadata.Builder m = new MediaMetadata.Builder()
                    .putString(MediaMetadata.METADATA_KEY_TITLE, it.title)
                    .putString(MediaMetadata.METADATA_KEY_ARTIST, it.artist)
                    .putString(MediaMetadata.METADATA_KEY_ALBUM, it.album)
                    .putLong(MediaMetadata.METADATA_KEY_DURATION, durMs);
            if (art != null) m.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, art);
            session.setMetadata(m.build());
        }
        int st = wants ? (playing ? PlaybackState.STATE_PLAYING : PlaybackState.STATE_BUFFERING) : PlaybackState.STATE_PAUSED;
        session.setPlaybackState(new PlaybackState.Builder()
                .setActions(PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PAUSE | PlaybackState.ACTION_PLAY_PAUSE
                        | PlaybackState.ACTION_SKIP_TO_NEXT | PlaybackState.ACTION_SKIP_TO_PREVIOUS
                        | PlaybackState.ACTION_SEEK_TO | PlaybackState.ACTION_STOP)
                .setState(st, posMs(), playing ? 1f : 0f, SystemClock.elapsedRealtime())
                .build());

        if (it != null) {
            if (wants) session.setActive(true);
            Notification n = buildNotification();
            PlaybackService s = PlaybackService.running;
            if (wants) {
                if (s != null) s.promote(n);
                else startService();
                notifShown = true;
            } else if (s != null) {
                s.demote(n);
                notifShown = true;
            } else if (notifShown) {
                nm.notify(NOTIF_ID, n);
            }
        }
        emitState();
    }

    private void publishSite() {
        MediaMetadata.Builder m = new MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, siteTitle)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, siteArtist)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, siteDur);
        if (siteArt != null) m.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, siteArt);
        session.setMetadata(m.build());
        session.setPlaybackState(new PlaybackState.Builder()
                .setActions(PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PAUSE | PlaybackState.ACTION_PLAY_PAUSE
                        | PlaybackState.ACTION_SKIP_TO_NEXT | PlaybackState.ACTION_SKIP_TO_PREVIOUS | PlaybackState.ACTION_SEEK_TO)
                .setState(sitePlaying ? PlaybackState.STATE_PLAYING : PlaybackState.STATE_PAUSED, sitePosMs(), sitePlaying ? 1f : 0f, SystemClock.elapsedRealtime())
                .build());
        session.setActive(true);
        Notification n = buildNotification();
        PlaybackService s = PlaybackService.running;
        if (sitePlaying) {
            if (s != null) s.promote(n); else startService();
            notifShown = true;
        } else if (s != null) {
            s.demote(n);
        } else if (notifShown) {
            nm.notify(NOTIF_ID, n);
        }
    }

    private void startService() {
        try {
            ctx.startForegroundService(new Intent(ctx, PlaybackService.class));
        } catch (Exception e) {
            // Android не дал запуститься из фона — музыка всё равно играет, просто без «закрепления»
            Log.w(TAG, "service", e);
            nm.notify(NOTIF_ID, buildNotification());
        }
    }

    Notification buildNotification() {
        Item it = itemAt(index);
        boolean on = siteMode ? sitePlaying : wants;
        String title = siteMode ? siteTitle : it != null ? it.title : ctx.getString(R.string.app_name);
        String artist = siteMode ? siteArtist : it != null ? it.artist : "";
        Bitmap big = siteMode ? siteArt : art;
        Notification.Builder b = new Notification.Builder(ctx, CHANNEL)
                .setSmallIcon(R.drawable.ic_notif)
                .setContentTitle(title)
                .setContentText(artist)
                .setContentIntent(openApp())
                .setDeleteIntent(PendingIntent.getBroadcast(ctx, 9, new Intent(ctx, Controls.class).setAction(ACT_STOP),
                        PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT))
                .setOngoing(on)
                .setShowWhen(false)
                .setOnlyAlertOnce(true)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setCategory(Notification.CATEGORY_TRANSPORT)
                .addAction(action(R.drawable.ic_prev, "Назад", ACT_PREV, 1))
                .addAction(on ? action(R.drawable.ic_pause, "Пауза", ACT_PAUSE, 2) : action(R.drawable.ic_play, "Играть", ACT_PLAY, 3))
                .addAction(action(R.drawable.ic_next, "Дальше", ACT_NEXT, 4))
                .setStyle(new Notification.MediaStyle()
                        .setMediaSession(session.getSessionToken())
                        .setShowActionsInCompactView(0, 1, 2));
        if (big != null) b.setLargeIcon(big);
        if (Build.VERSION.SDK_INT >= 31) b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE);
        return b.build();
    }

    private Notification.Action action(int icon, String title, String act, int req) {
        PendingIntent pi = PendingIntent.getForegroundService(ctx, req, new Intent(ctx, PlaybackService.class).setAction(act),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        return new Notification.Action.Builder(Icon.createWithResource(ctx, icon), title, pi).build();
    }

    private PendingIntent openApp() {
        Intent i = new Intent(ctx, MainActivity.class).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(ctx, 0, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    private void emitState() { emit("state", stateJson()); }

    private void emit(String name, String json) {
        Listener l = listener;
        if (l != null) l.onEngineEvent(name, json);
    }

    // ---------- сохранение ----------

    private void persist(boolean withQueue) {
        lastSaved = SystemClock.elapsedRealtime();
        SharedPreferences.Editor e = prefs.edit();
        if (withQueue) {
            JSONArray a = new JSONArray();
            synchronized (queue) {
                for (Item it : queue) a.put(it.json());
            }
            e.putString("queue", a.toString()).putString("qid", qid);
        }
        e.putInt("index", index).putLong("pos", posMs()).putBoolean("shuffle", shuffle)
                .putString("repeat", repeat).putInt("bass", bassDb).apply();
    }

    private void restore() {
        shuffle = prefs.getBoolean("shuffle", false);
        String rep = prefs.getString("repeat", "all");
        repeat = rep == null ? "all" : rep;
        bassDb = prefs.getInt("bass", 0);
        List<Item> items = parse(prefs.getString("queue", "[]"));
        if (items.isEmpty()) return;
        synchronized (queue) {
            queue.addAll(items);
        }
        qid = prefs.getString("qid", "restored");
        index = Math.max(0, Math.min(prefs.getInt("index", 0), items.size() - 1));
        durMs = (long) (items.get(index).duration * 1000);
        anchor(prefs.getLong("pos", 0));
        buildOrder(index);
        artFor = null;
    }
}
