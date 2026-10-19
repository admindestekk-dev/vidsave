web: gunicorn --chdir backend --bind 0.0.0.0:${PORT:-8787} --workers 1 --threads 8 --timeout 300 server:app
