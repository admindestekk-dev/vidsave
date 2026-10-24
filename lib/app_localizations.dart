import 'package:flutter/widgets.dart';

/// VidSave çok dilli yerelleştirme (Dictionary / Sözlük) sınıfı.
///
/// Dünyadaki tüm dilleri ve sistem yerellerini destekler.
/// Tanımlı diller (İngilizce, Türkçe, Almanca, İspanyolca, Fransızca, Rusça,
/// Arapça, Farsça, Çince, Japonca, Portekizce, İtalyanca vb.) için zengin çeviri,
/// tanımlanmamış tüm diğer küresel diller için İngilizceye zarif geri dönüş (fallback) sağlar.
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('tr'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// Desteklenen ana diller listesi (MaterialApp.supportedLocales için)
  static const List<Locale> supportedLocales = [
    Locale('tr'), // Türkçe
    Locale('en'), // İngilizce
    Locale('de'), // Almanca
    Locale('es'), // İspanyolca
    Locale('fr'), // Fransızca
    Locale('ru'), // Rusça
    Locale('ar'), // Arapça (RTL)
    Locale('fa'), // Farsça (RTL)
    Locale('ur'), // Urduca (RTL)
    Locale('zh'), // Çince
    Locale('ja'), // Japonca
    Locale('pt'), // Portekizce
    Locale('it'), // İtalyanca
    Locale('hi'), // Hintçe
    Locale('ko'), // Korece
    Locale('id'), // Endonezce
  ];

  /// Dilin sağdan sola yazılan (RTL) bir dil olup olmadığını kontrol eder.
  bool get isRtl {
    const rtlLanguages = {'ar', 'fa', 'ur', 'he', 'ps', 'sd', 'ug', 'yi'};
    return rtlLanguages.contains(locale.languageCode.toLowerCase());
  }

  /// Dil koduna göre sözlük haritası
  static final Map<String, Map<String, String>> _localizedValues = {
    'tr': {
      'app_title': 'VidSave',
      'nav_videos': 'Videolar',
      'nav_music': 'Müzik',
      'nav_download': 'İndir',
      'nav_more': 'Ayarlar',
      'section_which_platform': 'Hangi platformdan indiriyorsunuz?',
      'section_tap_hint': 'Kareye dokunun, bağlantıyı yapıştırıp indirin',
      'section_downloads': 'İNDİRİLENLER',
      'downloads_screen_title': 'İndirilenler',
      'section_downloads_hint':
          'İndirdiğiniz dosyalar türüne göre ayrı kutularda listelenir',
      'cat_video_title': 'Video',
      'cat_video_sub': 'MP4 / hareketli görüntü',
      'cat_audio_title': 'MP3',
      'cat_audio_sub': 'Ses / müzik dosyaları',
      'btn_download': 'İNDİR',
      'btn_search': 'ARA',
      'btn_play': 'Oynat',
      'btn_delete': 'Sil',
      'btn_clear_all': 'Tümünü Temizle',
      'btn_cancel': 'Vazgeç',
      'filter_all': 'Tümü',
      'filter_videos': 'Videolar',
      'filter_music': 'Müzikler (MP3)',
      'empty_downloads_title': 'Henüz İndirilen Dosya Yok',
      'empty_downloads_hint':
          'İndirdiğiniz videolar ve MP3 ses dosyaları kalıcı olarak burada listelenecektir.',
      'status_resolving': 'Çözülüyor…',
      'status_downloading': 'İndiriliyor…',
      'status_downloaded': 'Başarıyla indirildi: ',
      'input_enter_link': 'Bağlantı girin',
      'input_search_or_paste': 'Video ara veya bağlantı yapıştırın',
      'input_music_search':
          'Müzik ara veya Video linki yapıştırın (YouTube, TikTok, IG vb.)',
      'now_playing': 'Şimdi Çalıyor',
      'song_could_not_play': 'Şarkı çalınamadı',
      'music_subtitle': 'VidSave Müzik',
      'video_could_not_play': 'Video açılamadı',
      'video_player_title': 'Video oynatıcı',
      'delete_dialog_title': 'İndirme Kaydını Sil',
      'delete_dialog_content': 'kaydını listeden silmek istiyor musunuz?',
      'clear_dialog_title': 'Tüm Geçmişi Temizle',
      'clear_dialog_content':
          'Tüm indirme kayıtları listeden temizlenecek. Onaylıyor musunuz?',
      'file_not_found': 'Dosya cihaz hafızasında bulunamadı veya taşınmış',
      'record_removed': 'Kayıt listeden kaldırıldı.',
      'all_cleared': 'Tüm indirme geçmişi temizlendi.',
      'platform_mismatch':
          'Bu bağlantı seçilen platforma ait değil! Lütfen doğru bağlantı yapıştırın.',
      'err_download_failed': 'İndirme tamamlanamadı. Lütfen tekrar deneyin.',
      'err_connection_timeout': 'Bağlantı zaman aşımına uğradı. Ağınızı kontrol edin.',
      'err_connection': 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edin.',
      'err_access_denied': 'Erişim engellendi veya içerik korumalı (403 Forbidden).',
      'err_not_found': 'Medya veya sayfa bulunamadı (404 Not Found).',
      'err_server': 'Medya sunucusunda geçici bir hata oluştu.',
      'err_format': 'Medya formatı ayrıştırılamadı.',
    },
    'en': {
      'app_title': 'VidSave',
      'nav_videos': 'Videos',
      'nav_music': 'Music',
      'nav_download': 'Download',
      'nav_more': 'Settings',
      'section_which_platform': 'Which platform are you downloading from?',
      'section_tap_hint': 'Tap a tile, paste the link and download',
      'section_downloads': 'DOWNLOADS',
      'downloads_screen_title': 'Downloads',
      'section_downloads_hint':
          'Downloaded files are neatly categorized by type',
      'cat_video_title': 'Video',
      'cat_video_sub': 'MP4 / Video files',
      'cat_audio_title': 'MP3',
      'cat_audio_sub': 'Audio / Music files',
      'btn_download': 'DOWNLOAD',
      'btn_search': 'SEARCH',
      'btn_play': 'Play',
      'btn_delete': 'Delete',
      'btn_clear_all': 'Clear All',
      'btn_cancel': 'Cancel',
      'filter_all': 'All',
      'filter_videos': 'Videos',
      'filter_music': 'Music (MP3)',
      'empty_downloads_title': 'No Downloaded Files Yet',
      'empty_downloads_hint':
          'Your downloaded videos and MP3 audio files will be saved here permanently.',
      'status_resolving': 'Resolving…',
      'status_downloading': 'Downloading…',
      'status_downloaded': 'Successfully downloaded: ',
      'input_enter_link': 'Enter link',
      'input_search_or_paste': 'Search video or paste link',
      'input_music_search':
          'Search music or paste video link (YouTube, TikTok, IG etc.)',
      'now_playing': 'Now Playing',
      'song_could_not_play': 'Could not play song',
      'music_subtitle': 'VidSave Music',
      'video_could_not_play': 'Could not play video',
      'video_player_title': 'Video Player',
      'delete_dialog_title': 'Delete Download Record',
      'delete_dialog_content': 'Are you sure you want to remove this record?',
      'clear_dialog_title': 'Clear All History',
      'clear_dialog_content':
          'All download history will be cleared. Do you confirm?',
      'file_not_found': 'File was not found on device storage or moved',
      'record_removed': 'Record removed from list.',
      'all_cleared': 'All download history cleared.',
      'platform_mismatch':
          'This link does not belong to the selected platform! Please paste a valid link.',
      'err_download_failed': 'Download failed. Please try again.',
      'err_connection_timeout': 'Connection timed out. Check your network.',
      'err_connection': 'Could not connect to server. Check your internet connection.',
      'err_access_denied': 'Access denied or content is protected (403 Forbidden).',
      'err_not_found': 'Media or page not found (404 Not Found).',
      'err_server': 'Temporary error on the media server.',
      'err_format': 'Media format could not be parsed.',
    },
    'de': {
      'app_title': 'VidSave',
      'nav_videos': 'Videos',
      'nav_music': 'Musik',
      'nav_download': 'Herunterladen',
      'nav_more': 'Einstellungen',
      'section_which_platform': 'Von welcher Plattform laden Sie herunter?',
      'section_tap_hint': 'Kachel antippen, Link einfügen und herunterladen',
      'section_downloads': 'DOWNLOADS',
      'downloads_screen_title': 'Downloads',
      'section_downloads_hint':
          'Heruntergeladene Dateien werden nach Typ sortiert',
      'cat_video_title': 'Video',
      'cat_video_sub': 'MP4 / Videodateien',
      'cat_audio_title': 'MP3',
      'cat_audio_sub': 'Audio / Musikdateien',
      'btn_download': 'LADEN',
      'btn_search': 'SUCHEN',
      'btn_play': 'Abspielen',
      'btn_delete': 'Löschen',
      'btn_clear_all': 'Alles löschen',
      'btn_cancel': 'Abbrechen',
      'filter_all': 'Alle',
      'filter_videos': 'Videos',
      'filter_music': 'Musik (MP3)',
      'empty_downloads_title': 'Noch keine Downloads vorhanden',
      'empty_downloads_hint':
          'Ihre heruntergeladenen Dateien werden hier dauerhaft gespeichert.',
      'status_resolving': 'Wird analysiert…',
      'status_downloading': 'Wird heruntergeladen…',
      'status_downloaded': 'Erfolgreich heruntergeladen: ',
      'input_enter_link': 'Link eingeben',
      'input_search_or_paste': 'Video suchen oder Link einfügen',
      'input_music_search': 'Musik suchen oder Video-Link einfügen',
      'now_playing': 'Aktuelle Wiedergabe',
      'song_could_not_play': 'Titel konnte nicht abgespielt werden',
      'music_subtitle': 'VidSave Musik',
      'video_could_not_play': 'Video konnte nicht abgespielt werden',
      'video_player_title': 'Videoplayer',
      'delete_dialog_title': 'Download-Eintrag löschen',
      'delete_dialog_content': 'Möchten Sie diesen Eintrag wirklich löschen?',
      'clear_dialog_title': 'Verlauf löschen',
      'clear_dialog_content': 'Möchten Sie den gesamten Verlauf leeren?',
      'file_not_found': 'Datei nicht gefunden oder verschoben',
      'record_removed': 'Eintrag wurde entfernt.',
      'all_cleared': 'Download-Verlauf wurde gelöscht.',
      'platform_mismatch':
          'Dieser Link gehört nicht zur ausgewählten Plattform!',
    },
    'es': {
      'app_title': 'VidSave',
      'nav_videos': 'Videos',
      'nav_music': 'Música',
      'nav_download': 'Descargar',
      'nav_more': 'Ajustes',
      'section_which_platform': '¿De qué plataforma estás descargando?',
      'section_tap_hint': 'Toca un cuadro, pega el enlace y descarga',
      'section_downloads': 'DESCARGAS',
      'downloads_screen_title': 'Descargas',
      'section_downloads_hint':
          'Los archivos descargados se ordenan según su tipo',
      'cat_video_title': 'Video',
      'cat_video_sub': 'MP4 / Archivos de video',
      'cat_audio_title': 'MP3',
      'cat_audio_sub': 'Audio / Archivos de música',
      'btn_download': 'DESCARGAR',
      'btn_search': 'BUSCAR',
      'btn_play': 'Reproducir',
      'btn_delete': 'Eliminar',
      'btn_clear_all': 'Borrar todo',
      'btn_cancel': 'Cancelar',
      'filter_all': 'Todos',
      'filter_videos': 'Videos',
      'filter_music': 'Música (MP3)',
      'empty_downloads_title': 'No hay archivos descargados todavía',
      'empty_downloads_hint':
          'Tus videos y canciones descargadas se guardarán aquí permanentemente.',
      'status_resolving': 'Resolviendo…',
      'status_downloading': 'Descargando…',
      'status_downloaded': 'Descargado con éxito: ',
      'input_enter_link': 'Introduce el enlace',
      'input_search_or_paste': 'Buscar video o pegar enlace',
      'input_music_search': 'Buscar música o pegar enlace de video',
      'now_playing': 'Reproduciendo ahora',
      'song_could_not_play': 'No se pudo reproducir la canción',
      'music_subtitle': 'VidSave Música',
      'video_could_not_play': 'No se pudo reproducir el video',
      'video_player_title': 'Reproductor de video',
      'delete_dialog_title': 'Eliminar descarga',
      'delete_dialog_content': '¿Deseas eliminar este registro de la lista?',
      'clear_dialog_title': 'Borrar historial',
      'clear_dialog_content':
          '¿Estás seguro de que deseas borrar todo el historial?',
      'file_not_found': 'El archivo no se encontró en el dispositivo',
      'record_removed': 'Registro eliminado de la lista.',
      'all_cleared': 'Todo el historial de descargas ha sido borrado.',
      'platform_mismatch':
          '¡Este enlace no pertenece a la plataforma seleccionada!',
    },
    'fr': {
      'app_title': 'VidSave',
      'nav_videos': 'Vidéos',
      'nav_music': 'Musique',
      'nav_download': 'Télécharger',
      'nav_more': 'Paramètres',
      'section_which_platform': 'De quelle plateforme téléchargez-vous ?',
      'section_tap_hint': 'Touchez une case, collez le lien et téléchargez',
      'section_downloads': 'TÉLÉCHARGEMENTS',
      'downloads_screen_title': 'Téléchargements',
      'section_downloads_hint':
          'Les fichiers téléchargés sont classés par catégorie',
      'cat_video_title': 'Vidéo',
      'cat_video_sub': 'MP4 / Fichiers vidéo',
      'cat_audio_title': 'MP3',
      'cat_audio_sub': 'Fichiers audio / musique',
      'btn_download': 'TÉLÉCHARGER',
      'btn_search': 'CHERCHER',
      'btn_play': 'Lire',
      'btn_delete': 'Supprimer',
      'btn_clear_all': 'Tout effacer',
      'btn_cancel': 'Annuler',
      'filter_all': 'Tout',
      'filter_videos': 'Vidéos',
      'filter_music': 'Musique (MP3)',
      'empty_downloads_title': 'Aucun fichier téléchargé pour le moment',
      'empty_downloads_hint':
          'Vos fichiers téléchargés seront conservés ici de façon permanente.',
      'status_resolving': 'Résolution en cours…',
      'status_downloading': 'Téléchargement en cours…',
      'status_downloaded': 'Téléchargé avec succès : ',
      'input_enter_link': 'Entrez le lien',
      'input_search_or_paste': 'Rechercher une vidéo ou coller un lien',
      'input_music_search': 'Rechercher de la musique ou coller un lien',
      'now_playing': 'Lecture en cours',
      'song_could_not_play': 'Impossible de lire le morceau',
      'music_subtitle': 'VidSave Musique',
      'video_could_not_play': 'Impossible de lire la vidéo',
      'video_player_title': 'Lecteur vidéo',
      'delete_dialog_title': 'Supprimer le téléchargement',
      'delete_dialog_content': 'Voulez-vous supprimer cet élément ?',
      'clear_dialog_title': 'Effacer l’historique',
      'clear_dialog_content':
          'Tout l’historique sera effacé. Confirmez-vous ?',
      'file_not_found': 'Fichier introuvable sur l’appareil',
      'record_removed': 'Élément retiré de la liste.',
      'all_cleared': 'Historique de téléchargement effacé.',
      'platform_mismatch':
          'Ce lien ne correspond pas à la plateforme sélectionnée !',
    },
    'ru': {
      'app_title': 'VidSave',
      'nav_videos': 'Видео',
      'nav_music': 'Музыка',
      'nav_download': 'Скачать',
      'nav_more': 'Настройки',
      'section_which_platform': 'С какой платформы вы скачиваете?',
      'section_tap_hint': 'Нажмите на плитку, вставьте ссылку и скачайте',
      'section_downloads': 'ЗАГРУЗКИ',
      'downloads_screen_title': 'Загрузки',
      'section_downloads_hint':
          'Загруженные файлы упорядочены по категориям',
      'cat_video_title': 'Видео',
      'cat_video_sub': 'MP4 / Видеофайлы',
      'cat_audio_title': 'MP3',
      'cat_audio_sub': 'Аудио / Музыка',
      'btn_download': 'СКАЧАТЬ',
      'btn_search': 'ПОИСК',
      'btn_play': 'Воспроизвести',
      'btn_delete': 'Удалить',
      'btn_clear_all': 'Очистить всё',
      'btn_cancel': 'Отмена',
      'filter_all': 'Все',
      'filter_videos': 'Видео',
      'filter_music': 'Музыка (MP3)',
      'empty_downloads_title': 'Загруженных файлов пока нет',
      'empty_downloads_hint':
          'Ваши загруженные видео и MP3 будут сохранены здесь.',
      'status_resolving': 'Обработка…',
      'status_downloading': 'Загрузка…',
      'status_downloaded': 'Успешно загружено: ',
      'input_enter_link': 'Введите ссылку',
      'input_search_or_paste': 'Поиск видео или вставьте ссылку',
      'input_music_search': 'Поиск музыки или ссылка на видео',
      'now_playing': 'Сейчас играет',
      'song_could_not_play': 'Не удалось воспроизвести трек',
      'music_subtitle': 'VidSave Музыка',
      'video_could_not_play': 'Не удалось воспроизвести видео',
      'video_player_title': 'Видеоплеер',
      'delete_dialog_title': 'Удалить запись',
      'delete_dialog_content': 'Удалить эту запись из списка?',
      'clear_dialog_title': 'Очистить историю',
      'clear_dialog_content': 'Вы уверены, что хотите очистить всю историю?',
      'file_not_found': 'Файл не найден на устройстве или перемещён',
      'record_removed': 'Запись удалена из списка.',
      'all_cleared': 'Вся история загрузок очищена.',
      'platform_mismatch':
          'Эта ссылка не принадлежит выбранной платформе!',
    },
    'ar': {
      'app_title': 'VidSave',
      'nav_videos': 'فيديوهات',
      'nav_music': 'موسيقى',
      'nav_download': 'تنزيل',
      'nav_more': 'الإعدادات',
      'section_which_platform': 'من أي منصة تريد التنزيل؟',
      'section_tap_hint': 'اضغط على المربع والصق الرابط للبدء بالتنزيل',
      'section_downloads': 'التنزيلات',
      'downloads_screen_title': 'التنزيلات',
      'section_downloads_hint': 'يتم تصنيف الملفات المنزلة حسب النوع',
      'cat_video_title': 'فيديو',
      'cat_video_sub': 'MP4 / ملفات فيديو',
      'cat_audio_title': 'MP3',
      'cat_audio_sub': 'صوتيات / ملفات موسيقى',
      'btn_download': 'تنزيل',
      'btn_search': 'بحث',
      'btn_play': 'تشغيل',
      'btn_delete': 'حذف',
      'btn_clear_all': 'مسح الكل',
      'btn_cancel': 'إلغاء',
      'filter_all': 'الكل',
      'filter_videos': 'فيديوهات',
      'filter_music': 'موسيقى (MP3)',
      'empty_downloads_title': 'لا توجد ملفات تم تنزيلها بعد',
      'empty_downloads_hint':
          'سيتم حفظ مقاطع الفيديو وملفات MP3 الخاصة بك هنا بشكل دائم.',
      'status_resolving': 'جارٍ المعالجة…',
      'status_downloading': 'جارٍ التنزيل…',
      'status_downloaded': 'تم التنزيل بنجاح: ',
      'input_enter_link': 'أدخل الرابط',
      'input_search_or_paste': 'ابحث عن فيديو أو الصق الرابط',
      'input_music_search': 'ابحث عن موسيقى أو الصق رابط الفيديو',
      'now_playing': 'قيد التشغيل الآن',
      'song_could_not_play': 'تعذر تشغيل المقطع الصوتي',
      'music_subtitle': 'VidSave موسيقى',
      'video_could_not_play': 'تعذر تشغيل الفيديو',
      'video_player_title': 'مشغل الفيديو',
      'delete_dialog_title': 'حذف سجل التنزيل',
      'delete_dialog_content': 'هل تريد حذف هذا السجل من القائمة؟',
      'clear_dialog_title': 'مسح السجل بالكامل',
      'clear_dialog_content': 'سيتم مسح جميع التنزيلات، هل أنت متأكد؟',
      'file_not_found': 'الملف غير موجود في ذاكرة الجهاز أو تم نقله',
      'record_removed': 'تمت إزالة السجل من القائمة.',
      'all_cleared': 'تم مسح سجل التنزيلات بالكامل.',
      'platform_mismatch': 'هذا الرابط لا يتبع للمنصة المحددة!',
    },
    'fa': {
      'app_title': 'VidSave',
      'nav_videos': 'ویدیوها',
      'nav_music': 'موسیقی',
      'nav_download': 'دانلود',
      'nav_more': 'تنظیمات',
      'section_which_platform': 'از چه پلتفرمی دانلود می‌کنید؟',
      'section_tap_hint': 'روی کادر بزنید، پیوند را جای‌گذاری و دانلود کنید',
      'section_downloads': 'دانلودها',
      'downloads_screen_title': 'دانلودها',
      'section_downloads_hint':
          'فایل‌های دانلود شده بر اساس نوع دسته‌بندی می‌شوند',
      'cat_video_title': 'ویدیو',
      'cat_video_sub': 'MP4 / فایل‌های ویدیویی',
      'cat_audio_title': 'MP3',
      'cat_audio_sub': 'صوتی / فایل‌های موسیقی',
      'btn_download': 'دانلود',
      'btn_search': 'جستجو',
      'btn_play': 'پخش',
      'btn_delete': 'حذف',
      'btn_clear_all': 'پاک کردن همه',
      'btn_cancel': 'انصراف',
      'filter_all': 'همه',
      'filter_videos': 'ویدیوها',
      'filter_music': 'موسیقی (MP3)',
      'empty_downloads_title': 'هنوز فایلی دانلود نشده است',
      'empty_downloads_hint':
          'ویدیوها و فایل‌های صوتی دانلود شده در اینجا ذخیره می‌شوند.',
      'status_resolving': 'در حال پردازش…',
      'status_downloading': 'در حال دانلود…',
      'status_downloaded': 'با موفقیت دانلود شد: ',
      'input_enter_link': 'پیوند را وارد کنید',
      'input_search_or_paste': 'جستجوی ویدیو یا جای‌گذاری پیوند',
      'input_music_search': 'جستجوی موسیقی یا پیوند ویدیو',
      'now_playing': 'در حال پخش',
      'song_could_not_play': 'پخش آهنگ انجام نشد',
      'music_subtitle': 'VidSave موسیقی',
      'video_could_not_play': 'پخش ویدیو انجام نشد',
      'video_player_title': 'پخش‌کننده ویدیو',
      'delete_dialog_title': 'حذف سابقه دانلود',
      'delete_dialog_content': 'آیا مایل به حذف این مورد هستید؟',
      'clear_dialog_title': 'پاک کردن تاریخچه',
      'clear_dialog_content': 'تمامی تاریخچه دانلود پاک خواهد شد، مطمئنید؟',
      'file_not_found': 'فایل در حافظه دستگاه یافت نشد',
      'record_removed': 'مورد از لیست حذف شد.',
      'all_cleared': 'تمامی تاریخچه دانلود پاک شد.',
      'platform_mismatch': 'این پیوند مربوط به پلتفرم انتخاب شده نیست!',
    },
  };

  /// Anahtar sözcüğü yerel dilde döndürür, yoksa İngilizceye ve Türkçe'ye geri döner.
  String text(String key) {
    final lang = locale.languageCode.toLowerCase();
    if (_localizedValues.containsKey(lang) &&
        _localizedValues[lang]!.containsKey(key)) {
      return _localizedValues[lang]![key]!;
    }
    // Fallback: İngilizce
    if (_localizedValues['en']!.containsKey(key)) {
      return _localizedValues['en']![key]!;
    }
    // Fallback: Türkçe
    return _localizedValues['tr']?[key] ?? key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true; // Dünyadaki tüm dilleri kabul eder!

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
