<?php
// Скопируй этот файл в config.php и впиши данные базы с хостинга.
// config.php в репозиторий не попадает (он в .gitignore).
return [
    // MySQL / MariaDB: данные из панели хостинга
    'dsn'  => 'mysql:host=localhost;dbname=muzyka;charset=utf8mb4',
    'user' => 'muzyka',
    'pass' => 'пароль-от-базы',

    // Сколько дней действует вход с устройства
    'session_days' => 180,

    // С каких сайтов можно обращаться к API из браузера (для своего сайта). Программе это не нужно.
    'cors_origins' => ['https://example.ru'],
];
