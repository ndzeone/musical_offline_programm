-- «Музыка в офлайн»: база профилей (MySQL 5.7+ / MariaDB 10.3+).
-- Храним только: почту, имя, хэш пароля профиля и отметки «есть / нет активации» по сервисам.
-- Пароли и вход в Spotify, Яндекс Музыку, VK и SoundCloud сюда не попадают никогда.

CREATE TABLE IF NOT EXISTS mo_users (
  id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  email         VARCHAR(190) NOT NULL,
  name          VARCHAR(80)  NOT NULL DEFAULT '',
  pass_hash     VARCHAR(255) NOT NULL,
  created_at    DATETIME     NOT NULL,
  last_login_at DATETIME     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Входы с устройств: в базе лежит только SHA-256 от ключа, сам ключ знает лишь устройство
CREATE TABLE IF NOT EXISTS mo_sessions (
  id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id      INT UNSIGNED NOT NULL,
  token_hash   CHAR(64)     NOT NULL,
  device       VARCHAR(40)  NOT NULL DEFAULT '',
  created_at   DATETIME     NOT NULL,
  last_seen_at DATETIME     NOT NULL,
  expires_at   DATETIME     NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_token (token_hash),
  KEY ix_user (user_id),
  CONSTRAINT fk_sess_user FOREIGN KEY (user_id) REFERENCES mo_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Отметка по сервису на каждом устройстве: активирован или нет. Больше ничего.
CREATE TABLE IF NOT EXISTS mo_services (
  user_id    INT UNSIGNED NOT NULL,
  platform   VARCHAR(20)  NOT NULL,
  device     VARCHAR(40)  NOT NULL,
  active     TINYINT(1)   NOT NULL DEFAULT 0,
  updated_at DATETIME     NOT NULL,
  PRIMARY KEY (user_id, platform, device),
  CONSTRAINT fk_svc_user FOREIGN KEY (user_id) REFERENCES mo_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Защита от подбора пароля: неудачные попытки за последний час
CREATE TABLE IF NOT EXISTS mo_attempts (
  id  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  ip  VARCHAR(64)  NOT NULL,
  email VARCHAR(190) NOT NULL DEFAULT '',
  at  DATETIME     NOT NULL,
  PRIMARY KEY (id),
  KEY ix_ip_at (ip, at),
  KEY ix_email_at (email, at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
