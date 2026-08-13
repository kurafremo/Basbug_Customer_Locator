# basbug_customer_locator

# 🏢 Başbuğ Holding - Saha Operasyon ve Müşteri Konumlandırma Sistemi

Bu proje, Başbuğ Holding saha personellerinin müşteri lokasyon verilerini yüksek hassasiyetle toplaması, yönetmesi ve harita üzerinde görselleştirmesi amacıyla geliştirilmiş **Kurumsal Sınıf (Enterprise-Grade)** bir mobil uygulamadır. 

Proje, çevrimdışı (offline) ortamlarda dahi veri kaybını önleyen **Offline-First** mimarisi ve yüksek güvenlik standartlarıyla tasarlanmıştır.

## 🚀 Öne Çıkan Mimari Özellikler ve Kurumsal Standartlar

### 1. 📡 Çevrimdışı Öncelikli (Offline-First) Senkronizasyon Kuyruğu
Saha operasyonlarında internet bağlantısının kopması durumunda veri kaybını sıfıra indirmek için **SQLite** tabanlı bir yerel veritabanı kullanılmıştır. 
* Personel interneti kapalıyken bile müşteri konumunu güncelleyebilir.
* İnternet bağlantısı geri geldiğinde (Network Connectivity dinleyicisi ile), yerel kuyrukta (Sync Queue) bekleyen veriler otomatik olarak .NET REST API'ye arka planda push edilir.

### 2. 🔐 Üst Düzey Ağ Güvenliği ve Token Yönetimi
* **Sessiz Token Yenileme (Silent Refresh):** API katmanında `QueuedInterceptorsWrapper` kullanılarak gelişmiş bir ajan mimarisi kurulmuştur. JWT token'ın süresi dolduğunda, uygulama 401 hatasını yakalar, istekleri kuyruğa alır, arka planda token'ı yeniler ve başarısız olan istekleri kullanıcıya hiçbir şey hissettirmeden (hata ekranı göstermeden) tekrar ateşler.
* **Şifreli Kasa (Secure Storage):** Kimlik bilgileri ve JWT tokenlar standart önbellekte değil, işletim sisteminin şifreli güvenlik katmanında (`flutter_secure_storage`) saklanmaktadır.
* **Çevre Değişkenleri İzolasyonu:** API endpoint'leri kod içerisine hardcoded yazılmamış, `.env` yapılandırmasıyla dışarıdan izole edilmiştir.

### 3. 🛡️ Uygulama Yaşam Döngüsü ve Sürüm Kontrolü
* **Zorunlu Güncelleme (Force Update):** Uygulama başlatıldığında `SplashScreen` (Açılış Ekranı) üzerinden sunucuyla versiyon doğrulaması (Handshake) yapılır. Sürüm uyumsuzluğu durumunda personel eski versiyonla sahaya çıkamaz; ekran kilitlenir ve güvenli indirme bağlantısına yönlendirilir.
* **Auto-Login (Beni Hatırla):** Geçerli bir oturum varsa Login ekranı atlanarak operasyon süresi hızlandırılır.

### 4. 🗺️ Tersine Coğrafi Kodlama (Reverse Geocoding) Entegrasyonu
Harita üzerinde atılan pinlerin sadece koordinat (Enlem/Boylam) olarak kalmaması için Nominatim API entegrasyonu sağlanmıştır. Sistem, bırakılan iğnenin konumunu anlık olarak analiz edip tam adres, mahalle ve sokak detaylarına dönüştürerek (Reverse Geocoding) müşteri verisini zenginleştirir.

### 5. 🏗️ Katmanlı Mimari ve State Management
* Projede **Riverpod** state management kullanılarak UI (Arayüz) ile İş Mantığı (Business Logic) birbirinden tamamen soyutlanmıştır.
* Kod blokları Modeller (`models/`), Ağ Servisleri (`network/`), Sağlayıcılar (`providers/`) ve Arayüzler (`screens/`) olarak Clean Architecture prensiplerine uygun şekilde modülerleştirilmiştir.

### 6. 🔒 Siber Güvenlik ve Kod Gizleme (Obfuscation)
Uygulamanın AAB/APK derleme süreçleri, tersine mühendisliği (Reverse Engineering) imkansız kılmak adına **R8/ProGuard Sıkıştırması** ve Flutter yerleşik **Code Obfuscation** komutlarıyla şifrelenmiştir.

---
**Geliştirme Ortamı:** Flutter & Dart, Android Studio, VS Code, Git
**Backend Entegrasyonu:** ASP.NET Core REST API
**Veritabanı:** SQLite (Local), SQL Server (Remote)
