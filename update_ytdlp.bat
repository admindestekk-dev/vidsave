@echo off
chcp 65001 >nul
title VidSave - yt-dlp Güncelleyici
echo ========================================================
echo         VidSave: yt-dlp Kütüphanesi Güncelleniyor
echo ========================================================
echo.

python -m pip install --upgrade yt-dlp curl-cffi

echo.
echo Güncel yt-dlp sürümü:
python -m yt_dlp --version

echo.
echo Backend servisi yeniden başlatılıyor...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$conn = Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue; if ($conn) { Stop-Process -Id $conn.OwningProcess -Force }; Start-Process -FilePath powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File backend\start_backend.ps1' -WindowStyle Hidden"

echo.
echo ========================================================
echo İşlem tamamlandı! Pencereyi kapatabilirsiniz.
echo ========================================================
pause
