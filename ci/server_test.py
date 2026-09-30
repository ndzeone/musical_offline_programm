#!/usr/bin/env python3
"""Проверка API профилей (server/api.php) на настоящих PHP и MySQL. Запуск: python3 ci/server_test.py http://127.0.0.1:8088/api.php"""
import json
import sys
import urllib.error
import urllib.request

API = sys.argv[1]
failed = 0


def call(action, body=None, token=None, method=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + '?action=' + action, data=data, method=method or ('POST' if data is not None else 'GET'))
    req.add_header('Content-Type', 'application/json')
    if token:
        req.add_header('Authorization', 'Bearer ' + token)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, json.loads(r.read() or b'null')
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b'null')


def check(name, ok, info=''):
    global failed
    print(('PASS ' if ok else 'FAIL ') + name + (' — ' + str(info) if info else ''))
    if not ok:
        failed += 1


s, d = call('ping')
check('ping', s == 200 and d['ok'], d)

s, d = call('register', {'email': 'bad', 'password': '12345678', 'agree': True})
check('register: wrong email rejected', s == 400, d)
s, d = call('register', {'email': 'test@example.com', 'password': '123', 'agree': True})
check('register: short password rejected', s == 400, d)
s, d = call('register', {'email': 'test@example.com', 'password': 'пароль-надёжный', 'name': 'Тест'})
check('register: consent required', s == 400, d)
s, d = call('register', {'email': 'Test@Example.com', 'password': 'пароль-надёжный', 'name': 'Тест <b>', 'device': 'Mac', 'agree': True})
check('register', s == 200 and len(d.get('token', '')) == 64 and d['user']['email'] == 'test@example.com', d)
tok = d.get('token')
check('name is stored without HTML', d.get('user', {}).get('name') == 'Тест', d.get('user'))
s, d = call('register', {'email': 'test@example.com', 'password': 'другой-пароль', 'agree': True})
check('register: same email twice → 409', s == 409, d)

s, d = call('me', token=tok)
check('me', s == 200 and d['user']['name'] == 'Тест' and not d['services']['spotify']['active'], d)
s, d = call('me', token='0' * 64)
check('me: wrong token → 401', s == 401, d)
s, d = call('me')
check('me: no token → 401', s == 401, d)

s, d = call('services', {'device': 'Mac', 'services': {'spotify': True, 'yandex': False, 'hacker': True}}, tok)
check('services: Mac has Spotify', s == 200 and d['services']['spotify']['active'] and d['services']['spotify']['devices'] == ['Mac']
      and not d['services']['yandex']['active'] and 'hacker' not in d['services'], d)

s, d = call('login', {'email': 'test@example.com', 'password': 'неверный'})
check('login: wrong password → 401', s == 401, d)
s, d = call('login', {'email': 'TEST@example.com', 'password': 'пароль-надёжный', 'device': 'Android'})
check('login from a second device', s == 200 and len(d['token']) == 64 and d['services']['spotify']['active'], d)
tok2 = d['token']
s, d = call('services', {'device': 'Android', 'services': {'spotify': True, 'vk': True}}, tok2)
check('services from both devices', s == 200 and sorted(d['services']['spotify']['devices']) == ['Android', 'Mac'] and d['services']['vk']['devices'] == ['Android'], d)
s, d = call('services', {'device': 'Mac', 'services': {'spotify': False}}, tok)
check('service turned off on one device stays on the other', d['services']['spotify']['devices'] == ['Android'], d)

s, d = call('logout', {}, tok2)
check('logout', s == 200, d)
s, d = call('me', token=tok2)
check('token is invalid after logout', s == 401, d)

for i in range(9):
    s, d = call('login', {'email': 'test@example.com', 'password': 'подбор-%d' % i})
check('password guessing is limited', s == 429, d)

s, d = call('delete', {'password': 'неверный'}, tok)
check('delete: wrong password rejected', s == 403, d)
s, d = call('delete', {'password': 'пароль-надёжный'}, tok)
check('delete profile', s == 200 and d.get('deleted'), d)
s, d = call('me', token=tok)
check('everything is gone after delete', s == 401, d)

print('FAILED: %d' % failed if failed else 'ALL PASSED')
sys.exit(1 if failed else 0)
