"""Server-side Firebase identity and Google Play purchase verification."""

import datetime
import json
import os

PACKAGE = "dev.admindestekk.vidsave"
PRODUCT = "vidsave_premium_monthly"


class VerificationError(Exception):
    def __init__(self, code, status):
        self.code = code
        self.status = status
        super().__init__(code)


def _service_account():
    raw = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS_JSON", "")
    try:
        info = json.loads(raw)
        if not isinstance(info, dict) or info.get("type") != "service_account":
            raise ValueError()
        if not all(info.get(key) for key in ("project_id", "client_email", "private_key", "token_uri")):
            raise ValueError()
        return info
    except (ValueError, TypeError):
        raise VerificationError("google.config_unavailable", 503) from None


def verify_firebase_token(token):
    import firebase_admin
    from firebase_admin import auth, credentials

    if os.environ.get("FIREBASE_AUTH_EMULATOR_HOST"):
        raise VerificationError("google.config_unavailable", 503)
    info = _service_account()
    project_id = os.environ.get("FIREBASE_PROJECT_ID", "").strip() or info["project_id"]
    try:
        # A separate app avoids coupling to any default Firebase app in the host.
        app_name = "vidsave-" + project_id
        try:
            app = firebase_admin.get_app(app_name)
        except ValueError:
            try:
                app = firebase_admin.initialize_app(
                    credentials.Certificate(info), {"projectId": project_id}, name=app_name
                )
            except ValueError:
                app = firebase_admin.get_app(app_name)
    except Exception:
        raise VerificationError("google.config_unavailable", 503) from None
    try:
        claims = auth.verify_id_token(token, app=app)
    except auth.CertificateFetchError:
        raise VerificationError("google.upstream_unavailable", 502) from None
    except auth.InvalidIdTokenError:
        raise VerificationError("auth.google_token_invalid", 401) from None
    except Exception:
        raise VerificationError("google.upstream_unavailable", 502) from None
    return claims


def verify_play_purchase(token):
    from google.auth.transport.requests import AuthorizedSession
    from google.oauth2 import service_account
    from urllib.parse import quote

    info = _service_account()
    try:
        credentials = service_account.Credentials.from_service_account_info(
            info, scopes=["https://www.googleapis.com/auth/androidpublisher"]
        )
    except Exception:
        raise VerificationError("google.config_unavailable", 503) from None
    url = (
        "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/"
        + PACKAGE + "/purchases/subscriptions/" + PRODUCT + "/tokens/"
        + quote(token, safe="")
    )
    try:
        with AuthorizedSession(credentials) as session:
            response = session.get(url, timeout=15)
    except Exception:
        raise VerificationError("google.upstream_unavailable", 502) from None
    if response.status_code in (400, 404, 410):
        raise VerificationError("purchase.invalid", 400)
    if response.status_code in (401, 403):
        raise VerificationError("google.config_unavailable", 503)
    if response.status_code != 200:
        raise VerificationError("google.upstream_unavailable", 502)
    try:
        data = response.json()
        expiry = datetime.datetime.fromtimestamp(
            int(data["expiryTimeMillis"]) / 1000, datetime.timezone.utc
        )
        if (type(data.get("paymentState")) is not int or data["paymentState"] != 1
                or data.get("cancelReason") == 3
                or expiry <= datetime.datetime.now(datetime.timezone.utc)):
            raise VerificationError("purchase.inactive", 400)
        linked = data.get("linkedPurchaseToken")
        if linked is not None and (not isinstance(linked, str) or not linked):
            raise ValueError()
    except VerificationError:
        raise
    except (ValueError, TypeError, KeyError, AttributeError, OverflowError, OSError):
        raise VerificationError("google.upstream_invalid", 502) from None
    return expiry, linked
