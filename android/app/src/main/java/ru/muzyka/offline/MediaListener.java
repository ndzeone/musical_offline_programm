package ru.muzyka.offline;

import android.service.notification.NotificationListenerService;

/**
 * Нужен только для разрешения «Доступ к уведомлениям»: с ним Android показывает,
 * что играет в Spotify, Яндекс Музыке, VK и SoundCloud, и даёт ими управлять.
 * Сами уведомления приложение не читает.
 */
public class MediaListener extends NotificationListenerService { }
