from __future__ import annotations

import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import server


class AuthEndpointTests(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.original_db_path = server.DB_PATH
        self.original_api_key = server.API_KEY
        server.DB_PATH = str(Path(self.temporary_directory.name) / "auth-test.db")
        server.API_KEY = ""
        server._init_db()

    def tearDown(self):
        server.DB_PATH = self.original_db_path
        server.API_KEY = self.original_api_key
        self.temporary_directory.cleanup()

    def register(self, email="person@example.com", password="correct horse battery staple"):
        return self.client.post(
            "/api/auth/register", json={"email": email, "password": password}
        )

    def test_register_hashes_password_and_returns_authenticated_session(self):
        response = self.register(" PERSON@example.com ")
        self.assertEqual(response.status_code, 201)
        data = response.get_json()
        self.assertEqual(data["user"]["email"], "person@example.com")
        self.assertTrue(data["token"])

        with closing(sqlite3.connect(server.DB_PATH)) as conn:
            stored_hash = conn.execute(
                "SELECT password_hash FROM users WHERE id = ?",
                (data["user"]["id"],),
            ).fetchone()[0]
        self.assertNotEqual(stored_hash, "correct horse battery staple")
        self.assertIn("scrypt", stored_hash)

        me = self.client.get(
            "/api/auth/me",
            headers={"Authorization": f"Bearer {data['token']}"},
        )
        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.get_json()["user"], data["user"])

    def test_register_rejects_invalid_email_and_weak_password(self):
        invalid_email = self.register("not-an-email")
        self.assertEqual(invalid_email.status_code, 400)
        self.assertEqual(
            invalid_email.get_json()["error"]["code"], "auth.email_invalid"
        )

        weak_password = self.register("valid@example.com", "short")
        self.assertEqual(weak_password.status_code, 400)
        self.assertEqual(
            weak_password.get_json()["error"]["code"], "auth.password_invalid"
        )

    def test_register_rejects_duplicate_email_case_insensitively(self):
        self.assertEqual(self.register().status_code, 201)
        duplicate = self.register("PERSON@example.com")
        self.assertEqual(duplicate.status_code, 409)
        self.assertEqual(duplicate.get_json()["error"]["code"], "auth.email_in_use")

    def test_login_uses_generic_invalid_credentials_and_locks_after_five_failures(self):
        self.assertEqual(self.register().status_code, 201)

        for attempt in range(5):
            response = self.client.post(
                "/api/auth/login",
                json={"email": "person@example.com", "password": "wrong password"},
            )
            self.assertEqual(response.status_code, 401 if attempt < 4 else 429)
            expected = "auth.invalid_credentials" if attempt < 4 else "auth.rate_limited"
            self.assertEqual(response.get_json()["error"]["code"], expected)

        locked = self.client.post(
            "/api/auth/login",
            json={"email": "person@example.com", "password": "correct horse battery staple"},
        )
        self.assertEqual(locked.status_code, 429)

    def test_login_and_logout_revoke_the_session(self):
        self.assertEqual(self.register().status_code, 201)
        response = self.client.post(
            "/api/auth/login",
            json={"email": "person@example.com", "password": "correct horse battery staple"},
        )
        self.assertEqual(response.status_code, 200)
        token = response.get_json()["token"]
        headers = {"Authorization": f"Bearer {token}"}

        logged_out = self.client.post("/api/auth/logout", headers=headers)
        self.assertEqual(logged_out.status_code, 200)
        self.assertEqual(self.client.get("/api/auth/me", headers=headers).status_code, 401)

    def test_subscription_uses_authenticated_identity_not_body_identity(self):
        registered = self.register().get_json()
        response = self.client.post(
            "/api/auth/subscribe-monthly",
            headers={"Authorization": f"Bearer {registered['token']}"},
            json={
                "lang": "tr",
                "userId": "22222222-2222-4222-8222-222222222222",
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["subscription"]["userId"], registered["user"]["id"])

        unauthenticated = self.client.post(
            "/api/auth/subscribe-monthly",
            json={"lang": "tr", "userId": registered["user"]["id"]},
        )
        self.assertEqual(unauthenticated.status_code, 401)
        self.assertEqual(
            unauthenticated.get_json()["error"]["code"], "auth.required"
        )

    def test_delete_account_requires_session_and_deletes_only_session_user(self):
        first = self.register("first@example.com").get_json()
        second = self.register("second@example.com").get_json()
        with closing(sqlite3.connect(server.DB_PATH)) as conn:
            for user in (first["user"], second["user"]):
                conn.execute(
                    "INSERT INTO user_subscriptions (user_id) VALUES (?)",
                    (user["id"],),
                )
                conn.execute(
                    "INSERT INTO subscriptions (id, user_id, lang, amount, currency, status) "
                    "VALUES (?, ?, 'tr', 9.99, 'TRY', 'verified')",
                    (f"invoice-{user['id']}", user["id"]),
                )
            conn.commit()

        unauthenticated = self.client.post(
            "/api/auth/delete-account", json={"userId": first["user"]["id"]}
        )
        self.assertEqual(unauthenticated.status_code, 401)

        deleted = self.client.post(
            "/api/auth/delete-account",
            headers={"Authorization": f"Bearer {first['token']}"},
            json={"userId": second["user"]["id"]},
        )
        self.assertEqual(deleted.status_code, 200)
        self.assertEqual(
            self.client.get(
                "/api/auth/me",
                headers={"Authorization": f"Bearer {first['token']}"},
            ).status_code,
            401,
        )
        self.assertEqual(
            self.client.get(
                "/api/auth/me",
                headers={"Authorization": f"Bearer {second['token']}"},
            ).status_code,
            200,
        )
        with closing(sqlite3.connect(server.DB_PATH)) as conn:
            remaining = conn.execute(
                "SELECT user_id FROM user_subscriptions"
            ).fetchall()
            remaining_users = conn.execute("SELECT id FROM users").fetchall()
        self.assertEqual(remaining, [(second["user"]["id"],)])
        self.assertEqual(remaining_users, [(second["user"]["id"],)])


if __name__ == "__main__":
    unittest.main()

    def test_google_auth_creates_or_finds_user_and_returns_session(self):
        # 1. New Google user registration
        res1 = self.client.post(
            "/api/auth/google",
            json={
                "email": "googleuser@gmail.com",
                "name": "Google User",
                "avatarUrl": "https://lh3.googleusercontent.com/photo.jpg",
            },
        )
        self.assertEqual(res1.status_code, 200)
        data1 = res1.get_json()
        self.assertTrue(data1["success"])
        self.assertTrue(data1["token"])
        self.assertFalse(data1["is_premium"])
        self.assertEqual(data1["user"]["email"], "googleuser@gmail.com")
        self.assertEqual(data1["user"]["name"], "Google User")
        self.assertEqual(data1["user"]["avatarUrl"], "https://lh3.googleusercontent.com/photo.jpg")

        # 2. Same Google user logging in again
        res2 = self.client.post(
            "/api/auth/google",
            json={
                "email": "googleuser@gmail.com",
                "name": "Google User Updated",
                "avatarUrl": "https://lh3.googleusercontent.com/photo2.jpg",
            },
        )
        self.assertEqual(res2.status_code, 200)
        data2 = res2.get_json()
        self.assertEqual(data2["user"]["id"], data1["user"]["id"])
        self.assertEqual(data2["user"]["name"], "Google User Updated")
        self.assertEqual(data2["user"]["avatarUrl"], "https://lh3.googleusercontent.com/photo2.jpg")

        # 3. Check me endpoint works with returned token
        me = self.client.get(
            "/api/auth/me",
            headers={"Authorization": f"Bearer {data2['token']}"},
        )
        self.assertEqual(me.status_code, 200)
        me_user = me.get_json()["user"]
        self.assertEqual(me_user["email"], "googleuser@gmail.com")
        self.assertEqual(me_user["name"], "Google User Updated")
