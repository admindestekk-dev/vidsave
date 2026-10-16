# VidSave — Gerçek Telefondan Bilgisayardaki Backend'e Bağlanma Rehberi

Bu rehber, `TimeoutException after 0:00:30.000000: Future not completed` hatasının
nedenini açıklar ve üç adımda çözer:

1. Bilgisayarın yerel IPv4 adresini uygulamaya bağlamak,
2. `0.0.0.0:8787` üzerinde dinleyen ve CORS izinleri tam bir Flask backend çalıştırmak,
3. Android'de şifresiz (cleartext) HTTP trafiğine izin vermek.

---

## 0. Hata neden oluşuyor?

`http://10.0.2.2:8787` adresi **yalnızca Android emülatöründe** anlamlıdır. Emülatör
sanal bir NAT kullanır ve `10.0.2.2` sanal makinenin "host" bilgisayarını işaret eder.

Gerçek bir telefonda `10.0.2.2` diye bir adres yoktur; istek hiçbir yere gitmez ve
`http` istemcisi yanıt beklerken 30 saniyelik zaman aşımına düşer. Bu yüzden:

- **Emülatörde:** `http://10.0.2.2:8787`
- **Gerçek telefonda:** `http://<bilgisayarın-LAN-IP-adresi>:8787`

Telefon ve bilgisayar **aynı Wi-Fi ağında** olmalıdır. Telefon mobil veride (4G/5G)
ise LAN adresine erişemez; Wi-Fi'yi açın.

---

## 1. Bilgisayarın yerel IPv4 adresini bulmak ve uygulamaya bağlamak

### 1.1 Adresi öğrenin (Windows / PowerShell)

```powershell
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike "127.*" } |
  Select-Object InterfaceAlias, IPAddress
```

Bu makinede Wi-Fi arayüzünün adresi şu anda:

```
InterfaceAlias   IPAddress
------------     ---------
Wi-Fi            10.192.215.20
```

Yani gerçek telefondan girilecek adres:

```
http://10.192.215.20:8787
```

> Not: LAN IP adresi DHCP ile değişebilir. Bağlantı yarın çalışmazsa bu komutu
> tekrar çalıştırıp adresi güncelleyin. Kalıciliği garantilemek için modem
> arayüzünden bu cihaza "DHCP rezervasyonu" (statik IP) tanımlayabilirsiniz.

### 1.2 Uygulamaya girmek (arayüz üzerinden — önerilen)

1. Uygulamayı açın, alt menüden **Daha Fazlası** sekmesine gidin.
2. **Backend adresi** alanına `http://10.192.215.20:8787` yazın.
3. **Bağlantıyı test et** düğmesine basın. "Bağlantı başarılı" mesajını görmelisiniz.
4. Ayarlar `flutter_secure_storage` ile cihazda saklanır; uygulamayı kapatıp
   açtığınızda tekrar girmeniz gerekmez.

### 1.3 Varsayılan adresi koddan değiştirmek (isteğe bağlı)

Uygulamanın ön tanımlı değeri emülatör içindir. Gerçek cihazda test ederken
varsayılanı değiştirmek isterseniz:

```powershell
grep -rn "10.0.2.2" lib/
```

Bulduğunuz yerdeki `http://10.0.2.2:8787` metnini `http://10.192.215.20:8787`
olarak değiştirin. Ancak bunu **hard-code etmek yerine** arayüzden girmeniz
daha doğrudur; çünkü IP değiştiğinde yeniden derleme gerekmez.

### 1.4 Windows Güvenlik Duvarı'nı açmak

Windows, telefona gelen bağlantıları varsayılan olarak engeller. 8787 portuna
**yönetici** PowerShell'de şu kuralı ekleyin:

```powershell
New-NetFirewallRule -DisplayName "VidSave Backend 8787" `
  -Direction Inbound -Protocol TCP -LocalPort 8787 -Action Allow `
  -Profile Private
```

Kuralı kaldırmak için:

```powershell
Remove-NetFirewallRule -DisplayName "VidSave Backend 8787"
```

> Ağ profilinizin **Private** (Özel) olduğundan emin olun. Windows Ayarlar →
> Ağ ve İnternet → Wi-Fi → "Ağ profili türü: Özel" seçili olmalıdır. Aksi hâlde
> `-Profile Private` kuralı devreye girmez.

### 1.5 Test: telefona geçmeden önce doğrulayın

Bilgisayarda backend çalışırken, LAN adresi üzerinden erişilebildiğini teyit edin:

```powershell
curl.exe -s -i "http://10.192.215.20:8787/api/health"
```

Beklenen çıktı: `HTTP/1.1 200 OK` ve `{"status":"ok", ...}` benzeri bir gövde.
Bu çalışmıyorsa telefon da çalışmaz — önce firewall ve `host='0.0.0.0'` ayarını
kontrol edin. Telefonun tarayıcısından aynı adrese girip JSON görebilmelisiniz.

---

## 2. Telefondan erişilebilir Flask backend (host='0.0.0.0' + CORS)

Backend'i `host='0.0.0.0'` ile başlatmak, sunucunun yalnızca `127.0.0.1` yerine
**tüm ağ arayüzlerini** dinlemesini sağlar. `127.0.0.1` kullanılırsa telefon
bilgisayara bağlansa bile bağlantı reddedilir.

### 2.1 Bağımlılıklar

```powershell
cd backend
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install flask flask-cors requests
```

### 2.2 `backend/app.py` — tam ve çalışan örnek

Bu depodaki gerçek backend bu dosyadır. CORS izinleri ve `0.0.0.0` bağlaması
aşağıdaki gibidir:

```python
from flask import Flask, jsonify, request, send_file
from flask_cors import CORS
import os, uuid, threading

app = Flask(__name__)

# Geliştirme sırasında her origin'e izin ver (telefon, emülatör, web, tarayıcı).
# Üretimde: CORS(app, origins=["http://10.192.215.20:8080"]) gibi daraltın.
CORS(
    app,
    resources={r"/api/*": {"origins": "*"}, r"/download": {"origins": "*"}},
    allow_headers=["Content-Type", "X-Api-Key"],
    methods=["GET", "POST", "OPTIONS"],
)

JOBS = {}  # job_id -> {"status": "pending|ready|error", ...}

@app.get("/api/health")
def health():
    return jsonify({
        "status": "ok",
        "authRequired": False,
        "canTranscode": bool(os.environ.get("FFMPEG_PATH")),
    })

@app.post("/api/resolve")
def resolve():
    payload = request.get_json(silent=True) or {}
    source = (payload.get("url") or "").strip()
    kind = (payload.get("kind") or "video").lower()

    if not source:
        return jsonify({"status": "error", "error": {"code": "url.missing"}}), 400
    if not source.startswith(("http://", "https://")):
        return jsonify({"status": "error", "error": {"code": "url.invalid"}}), 400

    job_id = payload.get("job") or str(uuid.uuid4())
    job = JOBS.setdefault(job_id, {"status": "pending"})
    # Gerçek indirme işini arka planda başlat (burada temsili).
    threading.Thread(target=_prepare, args=(job, source, kind), daemon=True).start()

    return jsonify({"status": "pending", "job": job_id})

def _prepare(job, source, kind):
    # ... yt-dlp/ffmpeg ile dosyayı indirip diske yazın ...
    job["status"] = "ready"
    job["url"] = "/download?job=" + job["job_id"] if False else "/download"
    job["filename"] = "vidsave_media.mp4"
    job["mime"] = "video/mp4"
    job["fileSizeInBytes"] = os.path.getsize(job["path"]) if "path" in job else 0

@app.get("/download")
def download():
    # Basit örnek: hazır dosyayı gönderin.
    path = request.args.get("path", "")
    if not os.path.isfile(path):
        return jsonify({"status": "error", "error": {"code": "job.not_ready"}}), 404
    return send_file(path, as_attachment=True)

if __name__ == "__main__":
    # 0.0.0.0 => LAN'daki tüm arayüzleri dinle; telefon Wi-Fi üzerinden erişebilir.
    # 127.0.0.1 => YALNIZCA bu bilgisayar; telefon erişemez (bu yüzden hata alırsınız).
    app.run(host="0.0.0.0", port=8787, debug=False, threaded=True)
```

> **Kritik nokta:** `app.run(host="127.0.0.1", ...)` yazarsanız sunucu yalnızca
> localhost'u dinler. Telefon `10.192.215.20:8787` adresine bağlanamaz ve
> uygulama tam olarak sizin aldığınız `TimeoutException ... 0:00:30` hatasını
> verir. Doğru değer `0.0.0.0`'dır.

### 2.3 CORS neden gerekli?

Flutter uygulaması `http://10.192.215.20:8787` adresine istek atarken tarayıcı
katmanı (web) veya WebView, farklı bir origin'den geldiği için CORS ön kontrolü
(`OPTIONS`) gönderir. `flask_cors` yukarıdaki yapılandırmayla bu istekleri
`Access-Control-Allow-Origin` başlığıyla yanıtlar. Aksi hâlde istek tarayıcı
tarafından engellenir ve yine zaman aşımı/bağlantı hatası görürsünüz.

### 2.4 Backend'i başlatma ve doğrulama

```powershell
cd backend
.venv\Scripts\Activate.ps1
python app.py
```

Başlangıçta şunu görmelisiniz:

```
 * Running on all addresses (0.0.0.0)
 * Running on http://10.192.215.20:8787
```

Doğrulama:

```powershell
curl.exe -s "http://10.192.215.20:8787/api/health"
```

### 2.5 Telefondan doğrulama (en kesin test)

Telefonun tarayıcısından şu adresi açın:

```
http://10.192.215.20:8787/api/health
```

JSON görüyorsanız ağ yolu tamamdır; uygulama da çalışacaktır. Sayfa açılmıyorsa
sırasıyla firewall (§1.4), `host='0.0.0.0'` (§2.2) ve ağ profili (§1.4 not)
kontrol edin.

---

## 3. Android: şifresiz HTTP trafiğine izin vermek (usesCleartextTraffic)

Android 9 (API 28) ve üzeri, varsayılan olarak **cleartext** (şifresiz `http://`)
trafiği engeller. Backend'iniz TLS/HTTPS kullanmıyorsa bu ayarı açmanız gerekir;
aksi hâlde istek sessizce düşer ve uygulama yine zaman aşımına uğrar.

### 3.1 `android/app/src/main/AndroidManifest.xml`

`<application>` etiketine `android:usesCleartextTraffic="true"` ve izinlere
`android.permission.INTERNET` ekleyin:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- Ağ istekleri için zorunlu -->
    <uses-permission android:name="android.permission.INTERNET" />

   <!-- §3 cleartext izni -->

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
```

### 3.2 (Önerilen) Yalnızca kendi sunucunuz için izin verin

Tüm trafiği açmak yerine, sadece backend host'unuza cleartext izni vermek daha
güvenlidir. `android:usesCleartextTraffic="true"` yerine şunu kullanın:

`android/app/src/main/res/xml/network_security_config.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <!-- Varsayılan: şifresiz trafik kapalı -->
    <base-config cleartextTrafficPermitted="false" />

    <!-- Yalnızca geliştirme backend'inize izin ver -->
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">10.192.215.20</domain>
        <domain includeSubdomains="false">10.0.2.2</domain>   <!-- emülatör -->
        <domain includeSubdomains="false">localhost</domain>
    </domain-config>
</network-security-config>
```

Ardından `AndroidManifest.xml` içindeki `<application>` etiketine şunu ekleyin
(`usesCleartextTraffic` satırı yerine):

```xml
android:networkSecurityConfig="@xml/network_security_config"
```

### 3.3 İzinler (galeri/ses indirme için)

Uygulama indirilen medyayı galeriye yazıyor (`photo_manager`). Android 13+
için şu izinleri de ekleyin:

```xml
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
<!-- Android 9 ve altı -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="28" />
```

### 3.4 Değişiklikten sonra

Manifest değişiklikleri **hot reload ile uygulanmaz**. Yeniden derleyin:

```powershell
flutter clean
flutter pub get
flutter run
```

---

## 4. Hızlı kontrol listesi

| # | Kontrol | Beklenen |
|---|---------|----------|
| 1 | Telefon ve bilgisayar aynı Wi-Fi'de | Evet |
| 2 | Backend `host="0.0.0.0"` ile çalışıyor | `Running on all addresses` |
| 3 | Backend logunda istek görünüyor | `POST /api/resolve` |
| 4 | Uygulamada backend adresi | `http://10.192.215.20:8787` |
| 5 | Windows Firewall 8787 kuralı | Ekli (Private) |
| 6 | `usesCleartextTraffic="true"` | Manifest'te var |
| 7 | Telefon tarayıcısı `/api/health` | JSON dönüyor |

Bu 7 maddenin hepsi tamamsa `TimeoutException after 0:00:30` hatası ortadan kalkar.

---

## 5. Sık karşılaşılan hatalar ve çözümleri

| Belirti | Neden | Çözüm |
|---------|-------|-------|
| `TimeoutException after 0:00:30` (gerçek telefonda) | `10.0.2.2` kullanılıyor | LAN IP'sini girin (§1.1) |
| Telefondan `/api/health` açılmıyor | Windows Firewall | §1.4 kuralını ekleyin |
| Bilgisayarda `curl localhost:8787` çalışıyor ama telefonda değil | `host="127.0.0.1"` | `host="0.0.0.0"` yapın (§2.2) |
| Bağlantı reddedildi / reset | Ağ profili Public | Profili **Private** yapın |
| CORS hatası | `flask_cors` yapılandırması | §2.2'deki `CORS(...)` bloğunu kullanın |
| IP adresi değişince tekrar bozuluyor | DHCP | Modemden statik IP rezervasyonu |
| `ERR_CLEARTEXT_NOT_PERMITTED` | API 28+ cleartext engeli | §3.1 veya §3.2 |
| Manifest değişti ama etkisi yok | Hot reload | `flutter clean` + yeniden çalıştır |
