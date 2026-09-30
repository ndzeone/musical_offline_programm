<?php
/**
 * «Музыка в офлайн» — API профилей.
 *
 * Что хранится: почта, имя, хэш пароля профиля (password_hash), входы с устройств (только SHA-256 от ключа)
 * и отметки по сервисам «есть / нет активации». Пароли и вход в музыкальные сервисы сюда не приходят.
 *
 * Запросы: api.php?action=…
 *   GET  ping                                   — проверка, что сервер жив
 *   POST register {email, name, password, device, agree}
 *   POST login    {email, password, device}
 *   GET  me                                     — профиль и сервисы        (нужен вход)
 *   POST services {device, services: {spotify: true, …}}                 (нужен вход)
 *   POST logout                                                          (нужен вход)
 *   POST delete   {password}                    — удалить профиль и всё   (нужен вход)
 * Вход: заголовок «Authorization: Bearer <ключ>» (или «X-Auth-Token: <ключ>»).
 */
declare(strict_types=1);

const PLATFORMS = ['spotify', 'soundcloud', 'yandex', 'vk'];
const API_VERSION = 1;

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

$configFile = __DIR__ . '/config.php';
if (!is_file($configFile)) fail(500, 'Сервер не настроен: нет config.php');
$config = require $configFile;

cors($config['cors_origins'] ?? []);
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') { http_response_code(204); exit; }

try {
    $db = new PDO($config['dsn'], $config['user'] ?? null, $config['pass'] ?? null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
} catch (Throwable $e) {
    fail(500, 'Нет связи с базой данных');
}

$action = (string)($_GET['action'] ?? '');
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$in = body();

try {
    switch ($action) {
        case 'ping':
            ok(['version' => API_VERSION, 'time' => gmdate('c')]);
        case 'register':
            needPost($method);
            register($db, $config, $in);
        case 'login':
            needPost($method);
            login($db, $config, $in);
        case 'me':
            $u = auth($db);
            ok(['user' => publicUser($u), 'services' => services($db, (int)$u['id'])]);
        case 'services':
            needPost($method);
            $u = auth($db);
            saveServices($db, (int)$u['id'], $in);
            ok(['services' => services($db, (int)$u['id'])]);
        case 'logout':
            needPost($method);
            $u = auth($db);
            $db->prepare('DELETE FROM mo_sessions WHERE id = ?')->execute([$u['session_id']]);
            ok([]);
        case 'delete':
            needPost($method);
            $u = auth($db);
            if (!password_verify((string)($in['password'] ?? ''), $u['pass_hash'])) fail(403, 'Неверный пароль');
            // сервисы и входы удаляются вместе с профилем (ON DELETE CASCADE)
            $db->prepare('DELETE FROM mo_users WHERE id = ?')->execute([$u['id']]);
            ok(['deleted' => true]);
        default:
            fail(404, 'Неизвестное действие');
    }
} catch (Throwable $e) {
    error_log('muzyka api: ' . $e->getMessage());
    fail(500, 'Ошибка сервера, попробуй позже');
}

// ---------- действия ----------

function register(PDO $db, array $config, array $in): void {
    $email = normEmail($in['email'] ?? '');
    $name = mb_substr(trim(strip_tags((string)($in['name'] ?? ''))), 0, 80);
    $pass = (string)($in['password'] ?? '');
    if (!$email) fail(400, 'Проверь почту');
    if (mb_strlen($pass) < 8 || mb_strlen($pass) > 200) fail(400, 'Пароль — от 8 символов');
    if (empty($in['agree'])) fail(400, 'Нужно согласие с условиями хранения данных');
    limit($db, ip(), '#register', 10, 60);
    note($db, ip(), '#register');
    $st = $db->prepare('SELECT id FROM mo_users WHERE email = ?');
    $st->execute([$email]);
    if ($st->fetch()) fail(409, 'Профиль с такой почтой уже есть — войди в него');
    $db->prepare('INSERT INTO mo_users (email, name, pass_hash, created_at, last_login_at) VALUES (?, ?, ?, ?, ?)')
        ->execute([$email, $name, password_hash($pass, PASSWORD_DEFAULT), now(), now()]);
    $id = (int)$db->lastInsertId();
    $token = newSession($db, $config, $id, device($in['device'] ?? ''));
    ok(['token' => $token, 'user' => ['id' => $id, 'email' => $email, 'name' => $name], 'services' => services($db, $id)]);
}

function login(PDO $db, array $config, array $in): void {
    $email = normEmail($in['email'] ?? '');
    $pass = (string)($in['password'] ?? '');
    if (!$email || $pass === '') fail(400, 'Введи почту и пароль');
    limit($db, ip(), '', 30, 60);
    limit($db, '', $email, 8, 15);
    $st = $db->prepare('SELECT * FROM mo_users WHERE email = ?');
    $st->execute([$email]);
    $u = $st->fetch();
    if (!$u || !password_verify($pass, $u['pass_hash'])) {
        note($db, ip(), $email);
        fail(401, 'Неверная почта или пароль');
    }
    if (password_needs_rehash($u['pass_hash'], PASSWORD_DEFAULT)) {
        $db->prepare('UPDATE mo_users SET pass_hash = ? WHERE id = ?')->execute([password_hash($pass, PASSWORD_DEFAULT), $u['id']]);
    }
    $db->prepare('UPDATE mo_users SET last_login_at = ? WHERE id = ?')->execute([now(), $u['id']]);
    $token = newSession($db, $config, (int)$u['id'], device($in['device'] ?? ''));
    ok(['token' => $token, 'user' => publicUser($u), 'services' => services($db, (int)$u['id'])]);
}

function saveServices(PDO $db, int $uid, array $in): void {
    $device = device($in['device'] ?? '');
    $list = $in['services'] ?? null;
    if (!is_array($list)) fail(400, 'Нет списка сервисов');
    $st = $db->prepare('REPLACE INTO mo_services (user_id, platform, device, active, updated_at) VALUES (?, ?, ?, ?, ?)');
    foreach (PLATFORMS as $p) {
        if (!array_key_exists($p, $list)) continue;
        $v = $list[$p];
        $active = is_array($v) ? !empty($v['active']) : !empty($v);
        $st->execute([$uid, $p, $device, $active ? 1 : 0, now()]);
    }
}

/** По каждому сервису: активирован ли хоть где-то и на каких устройствах. */
function services(PDO $db, int $uid): array {
    $out = [];
    foreach (PLATFORMS as $p) $out[$p] = ['active' => false, 'devices' => [], 'updated' => null];
    $st = $db->prepare('SELECT platform, device, active, updated_at FROM mo_services WHERE user_id = ? ORDER BY updated_at DESC');
    $st->execute([$uid]);
    foreach ($st->fetchAll() as $r) {
        $p = $r['platform'];
        if (!isset($out[$p])) continue;
        if (!$out[$p]['updated']) $out[$p]['updated'] = gmdate('c', strtotime($r['updated_at'] . ' UTC'));
        if ((int)$r['active'] === 1) {
            $out[$p]['active'] = true;
            if (!in_array($r['device'], $out[$p]['devices'], true)) $out[$p]['devices'][] = $r['device'];
        }
    }
    return $out;
}

// ---------- вход с устройства ----------

function newSession(PDO $db, array $config, int $uid, string $device): string {
    $token = bin2hex(random_bytes(32));
    $days = max(1, (int)($config['session_days'] ?? 180));
    $db->prepare('INSERT INTO mo_sessions (user_id, token_hash, device, created_at, last_seen_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)')
        ->execute([$uid, hash('sha256', $token), $device, now(), now(), gmdate('Y-m-d H:i:s', time() + $days * 86400)]);
    // старые входы убираем, чтобы база не росла
    $db->prepare('DELETE FROM mo_sessions WHERE expires_at < ?')->execute([now()]);
    return $token;
}

function auth(PDO $db): array {
    $h = $_SERVER['HTTP_AUTHORIZATION'] ?? ($_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '');
    $token = '';
    if (preg_match('/^Bearer\s+([a-f0-9]{64})$/i', trim((string)$h), $m)) $token = $m[1];
    if (!$token && preg_match('/^[a-f0-9]{64}$/i', (string)($_SERVER['HTTP_X_AUTH_TOKEN'] ?? ''))) $token = $_SERVER['HTTP_X_AUTH_TOKEN'];
    if (!$token) fail(401, 'Нужно войти в профиль');
    $st = $db->prepare('SELECT u.*, s.id AS session_id FROM mo_sessions s JOIN mo_users u ON u.id = s.user_id WHERE s.token_hash = ? AND s.expires_at > ?');
    $st->execute([hash('sha256', strtolower($token)), now()]);
    $u = $st->fetch();
    if (!$u) fail(401, 'Вход устарел — войди в профиль снова');
    $db->prepare('UPDATE mo_sessions SET last_seen_at = ? WHERE id = ?')->execute([now(), $u['session_id']]);
    return $u;
}

// ---------- защита от подбора ----------

function limit(PDO $db, string $ip, string $email, int $max, int $minutes): void {
    $since = gmdate('Y-m-d H:i:s', time() - $minutes * 60);
    if ($ip !== '') {
        $st = $db->prepare('SELECT COUNT(*) AS n FROM mo_attempts WHERE ip = ? AND at > ?' . ($email !== '' ? ' AND email = ?' : ''));
        $st->execute($email !== '' ? [$ip, $since, $email] : [$ip, $since]);
    } else {
        $st = $db->prepare('SELECT COUNT(*) AS n FROM mo_attempts WHERE email = ? AND at > ?');
        $st->execute([$email, $since]);
    }
    if ((int)$st->fetch()['n'] >= $max) fail(429, 'Слишком много попыток — попробуй через ' . $minutes . ' минут');
}

function note(PDO $db, string $ip, string $email): void {
    $db->prepare('INSERT INTO mo_attempts (ip, email, at) VALUES (?, ?, ?)')->execute([$ip, $email, now()]);
    if (random_int(1, 50) === 1) $db->prepare('DELETE FROM mo_attempts WHERE at < ?')->execute([gmdate('Y-m-d H:i:s', time() - 86400)]);
}

// ---------- мелочи ----------

function publicUser(array $u): array { return ['id' => (int)$u['id'], 'email' => $u['email'], 'name' => $u['name']]; }

function normEmail($e): string {
    $e = mb_strtolower(trim((string)$e));
    return (mb_strlen($e) <= 190 && filter_var($e, FILTER_VALIDATE_EMAIL)) ? $e : '';
}

function device($d): string {
    $d = preg_replace('/[^\p{L}\p{N} ._-]/u', '', (string)$d);
    $d = mb_substr(trim((string)$d), 0, 40);
    return $d !== '' ? $d : 'Устройство';
}

function ip(): string { return substr((string)($_SERVER['REMOTE_ADDR'] ?? ''), 0, 64); }

function now(): string { return gmdate('Y-m-d H:i:s'); }

function body(): array {
    $raw = file_get_contents('php://input');
    if (!$raw) return [];
    if (strlen($raw) > 65536) fail(413, 'Слишком большой запрос');
    $d = json_decode($raw, true);
    return is_array($d) ? $d : [];
}

function needPost(string $m): void { if ($m !== 'POST') fail(405, 'Нужен POST'); }

function cors(array $origins): void {
    $o = $_SERVER['HTTP_ORIGIN'] ?? '';
    if ($o !== '' && in_array($o, $origins, true)) {
        header('Access-Control-Allow-Origin: ' . $o);
        header('Vary: Origin');
        header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Auth-Token');
        header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    }
}

function ok(array $d): void {
    echo json_encode(['ok' => true] + $d, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function fail(int $code, string $msg): void {
    http_response_code($code);
    echo json_encode(['ok' => false, 'error' => $msg], JSON_UNESCAPED_UNICODE);
    exit;
}
