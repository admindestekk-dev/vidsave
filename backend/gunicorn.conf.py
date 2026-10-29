import os

# Dynamic Render PORT binding (Render sets $PORT, default to 8787 if not set)
port = os.environ.get("PORT", "8787")
bind = f"0.0.0.0:{port}"

# Concurrency and timeout configuration
workers = 1
threads = 8
timeout = 300
keepalive = 5
accesslog = "-"
errorlog = "-"
