import datetime
import hashlib
import json
import os
import sqlite3
import sys
import tempfile
import unittest
from contextlib import closing
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import google_verification as google
import server


class GoogleEndpointTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.old_db, self.old_key = server.DB_PATH, server.API_KEY
        server.DB_PATH = str(Path(self.directory.name) / "test.db")
        server.API_KEY = "test-key"
        server._init_db()
        self.client = server.app.test_client()
        self.headers = {"X-Api-Key": "test-key"}
        self.old_limiter = server.limiter.enabled
        server.limiter.enabled = False

    def tearDown(self):
        server.DB_PATH, server.API_KEY = self.old_db, self.old_key
        server.limiter.enabled = self.old_limiter
        self.directory.cleanup()

    def register(self, email):
        data = self.client.post("/api/auth/register", headers=self.headers, json={
            "email": email, "password": "a secure password"
        }).get_json()
        return data, {**self.headers, "Authorization": "Bearer " + data["token"]}

    def test_google_only_uses_verified_claims(self):
        claims = {"uid": "firebase-user", "email": "Real@Example.com", "email_verified": True,
                  "name": "Real", "picture": "https://example.com/real",
                  "firebase": {"sign_in_provider": "google.com"}}
        with patch.object(google, "verify_firebase_token", return_value=claims) as verify:
            response = self.client.post("/api/auth/google", headers=self.headers, json={
                "idToken": "firebase-token", "email": "victim@example.com",
                "name": "Fake", "avatarUrl": "fake",
            })
        self.assertEqual(response.status_code, 200)
        verify.assert_called_once_with("firebase-token")
        user = response.get_json()["user"]
        self.assertEqual((user["email"], user["name"], user["avatarUrl"]),
                         ("real@example.com", "Real", "https://example.com/real"))
        with closing(sqlite3.connect(server.DB_PATH)) as conn:
            conn.execute("INSERT INTO user_subscriptions (user_id, premium_until) VALUES (?, ?)",
                         (user["id"], "2099-01-01T00:00:00+00:00"))
            conn.commit()
        with patch.object(google, "verify_firebase_token", return_value=claims):
            again = self.client.post("/api/auth/google", headers=self.headers, json={"idToken": "x"})
        self.assertFalse(again.get_json()["is_premium"])

    def test_google_rejects_missing_invalid_and_unverified_identity(self):
        self.assertEqual(self.client.post("/api/auth/google", headers=self.headers,
                          json={"email": "victim@example.com"}).status_code, 400)
        with patch.object(google, "verify_firebase_token",
                          side_effect=google.VerificationError("auth.google_token_invalid", 401)):
            self.assertEqual(self.client.post("/api/auth/google", headers=self.headers,
                              json={"idToken": "fake"}).status_code, 401)
        for claims in ({"uid": "u", "email": "x@example.com", "email_verified": False,
                        "firebase": {"sign_in_provider": "google.com"}},
                       {"uid": "u", "email": "x@example.com", "email_verified": True,
                        "firebase": {"sign_in_provider": "password"}}):
            with patch.object(google, "verify_firebase_token", return_value=claims):
                self.assertEqual(self.client.post("/api/auth/google", headers=self.headers,
                                  json={"idToken": "fake"}).status_code, 401)

    def test_google_does_not_link_an_existing_password_account(self):
        self.register("victim@example.com")
        claims = {"uid": "firebase-user", "email": "victim@example.com",
                  "email_verified": True, "firebase": {"sign_in_provider": "google.com"}}
        with patch.object(google, "verify_firebase_token", return_value=claims):
            response = self.client.post("/api/auth/google", headers=self.headers, json={"idToken": "x"})
        self.assertEqual(response.status_code, 409)

    def test_initialization_revokes_unverified_google_sessions(self):
        with closing(sqlite3.connect(server.DB_PATH)) as conn:
            conn.execute("INSERT INTO users (id, email, password_hash, created_at) VALUES (?, ?, ?, ?)",
                         ("legacy", "legacy@example.com", "google_oauth_no_password", 0))
            conn.execute("INSERT INTO auth_sessions (token_hash, user_id, created_at, expires_at) "
                         "VALUES (?, ?, ?, ?)", ("old", "legacy", 0, 9999999999))
            conn.commit()
        server._init_db()
        with closing(sqlite3.connect(server.DB_PATH)) as conn:
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM auth_sessions").fetchone()[0], 0)

    def test_purchase_ownership_replay_and_linked_token(self):
        first, headers = self.register("first@example.com")
        _, second_headers = self.register("second@example.com")
        expiry = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=7)
        with patch.object(google, "verify_play_purchase", return_value=(expiry, None)):
            self.assertEqual(self.client.post("/api/auth/verify-purchase", headers=self.headers,
                             json={"token": "receipt"}).status_code, 401)
            for _ in range(2):
                response = self.client.post("/api/auth/verify-purchase", headers=headers,
                                            json={"token": "receipt"})
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.get_json()["premiumUntil"], expiry.isoformat())
            conflict = self.client.post("/api/auth/verify-purchase", headers=second_headers,
                                        json={"token": "receipt"})
            self.assertEqual(conflict.status_code, 409)
        with patch.object(google, "verify_play_purchase", return_value=(expiry, "receipt")):
            conflict = self.client.post("/api/auth/verify-purchase", headers=second_headers,
                                        json={"token": "replacement"})
            self.assertEqual(conflict.status_code, 409)
            self.assertEqual(self.client.post("/api/auth/verify-purchase", headers=headers,
                             json={"token": "replacement"}).status_code, 200)
        with patch.object(google, "verify_play_purchase", return_value=(expiry, None)):
            self.assertEqual(self.client.post("/api/auth/verify-purchase", headers=headers,
                             json={"token": "receipt"}).status_code, 409)
        with closing(sqlite3.connect(server.DB_PATH)) as conn:
            stored = conn.execute("SELECT premium_until, purchase_token, entitlement_source "
                                  "FROM user_subscriptions WHERE user_id = ?", (first["user"]["id"],)).fetchone()
            claims = conn.execute("SELECT token_hash FROM play_purchase_claims").fetchall()
        self.assertEqual(stored, (expiry.isoformat(), None, "google_play"))
        self.assertIn((hashlib.sha256(b"receipt").hexdigest(),), claims)
        self.assertNotIn(("receipt",), claims)
        with patch.object(google, "verify_play_purchase",
                          side_effect=google.VerificationError("purchase.inactive", 400)):
            self.assertEqual(self.client.post("/api/auth/verify-purchase", headers=headers,
                             json={"token": "replacement"}).status_code, 400)
        with closing(sqlite3.connect(server.DB_PATH)) as conn:
            self.assertEqual(conn.execute("SELECT is_premium, premium_until FROM user_subscriptions "
                                          "WHERE user_id = ?", (first["user"]["id"],)).fetchone(), (0, None))

    def test_purchase_rejects_bad_input_and_surfaces_errors(self):
        _, headers = self.register("first@example.com")
        for data in ({}, {"purchaseId": "not-a-token"}):
            self.assertEqual(self.client.post("/api/auth/verify-purchase",
                             headers=headers, json=data).status_code, 400)
        self.assertEqual(self.client.post("/api/auth/verify-purchase", headers=headers,
                         json={"token": "x", "productId": "wrong"}).status_code, 400)
        for code, status in (("purchase.invalid", 400), ("purchase.inactive", 400),
                             ("google.config_unavailable", 503), ("google.upstream_unavailable", 502)):
            with patch.object(google, "verify_play_purchase", side_effect=google.VerificationError(code, status)):
                response = self.client.post("/api/auth/verify-purchase", headers=headers, json={"token": "secret-token"})
                self.assertEqual(response.status_code, status)
                self.assertEqual(response.get_json()["error"]["code"], code)
                self.assertNotIn("secret-token", response.get_data(as_text=True))
class GoogleVerifierTests(unittest.TestCase):
    def test_firebase_verifier_classifies_invalid_and_upstream(self):
        from firebase_admin import auth
        info = {"type": "service_account", "project_id": "test", "client_email": "a",
                "private_key": "fake", "token_uri": "https://example.com"}
        with patch.dict(os.environ, {"GOOGLE_APPLICATION_CREDENTIALS_JSON": json.dumps(info)}), \
             patch("firebase_admin.get_app", return_value=object()), \
             patch("firebase_admin.auth.verify_id_token") as verify:
            for exception, expected in ((auth.InvalidIdTokenError("invalid"), "auth.google_token_invalid"),
                                        (auth.CertificateFetchError("unavailable", None), "google.upstream_unavailable")):
                verify.side_effect = exception
                with self.assertRaises(google.VerificationError) as caught:
                    google.verify_firebase_token("fake")
                self.assertEqual(caught.exception.code, expected)

    def test_play_verifier_validates_paid_expiry_and_upstream_status(self):
        info = {"type": "service_account", "project_id": "test", "client_email": "a",
                "private_key": "fake", "token_uri": "https://example.com"}
        expiry = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=10)
        response = MagicMock(status_code=200)
        session = MagicMock()
        session.__enter__.return_value.get.return_value = response
        with patch.dict(os.environ, {"GOOGLE_APPLICATION_CREDENTIALS_JSON": json.dumps(info)}), \
             patch("google.oauth2.service_account.Credentials.from_service_account_info"), \
             patch("google.auth.transport.requests.AuthorizedSession", return_value=session):
            response.json.return_value = {"expiryTimeMillis": str(int(expiry.timestamp() * 1000)), "paymentState": 1}
            actual, _ = google.verify_play_purchase("test-token")
            self.assertAlmostEqual(actual.timestamp(), expiry.timestamp(), places=2)
            url = session.__enter__.return_value.get.call_args.args[0]
            self.assertIn(google.PACKAGE + "/purchases/subscriptions/" + google.PRODUCT, url)
            for data in ({"expiryTimeMillis": "0", "paymentState": 1},
                         {"expiryTimeMillis": str(int(expiry.timestamp() * 1000)), "paymentState": 0},
                         {"expiryTimeMillis": str(int(expiry.timestamp() * 1000)), "paymentState": 1, "cancelReason": 3}):
                response.json.return_value = data
                with self.assertRaises(google.VerificationError) as caught:
                    google.verify_play_purchase("test-token")
                self.assertEqual(caught.exception.code, "purchase.inactive")
            for status, code in ((404, "purchase.invalid"), (403, "google.config_unavailable"),
                                 (500, "google.upstream_unavailable")):
                response.status_code = status
                with self.assertRaises(google.VerificationError) as caught:
                    google.verify_play_purchase("test-token")
                self.assertEqual(caught.exception.code, code)
        with patch.dict(os.environ, {"GOOGLE_APPLICATION_CREDENTIALS_JSON": ""}):
            with self.assertRaises(google.VerificationError) as caught:
                google.verify_play_purchase("fake")
            self.assertEqual(caught.exception.code, "google.config_unavailable")
