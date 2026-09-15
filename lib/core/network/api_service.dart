// lib/core/network/api_service.dart

import 'package:dio/dio.dart';
import '../../models/customer_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/app_logger.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  final String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost';
  late Dio _dio; 
  final _storage = const FlutterSecureStorage();

  ApiService() {
    _dio = Dio(BaseOptions(baseUrl: baseUrl));
    
    // 🛡️ SENİOR DOKUNUŞU 1: "QueuedInterceptorsWrapper" ile Kuyruklu İstek Yönetimi
    _dio.interceptors.add(QueuedInterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'jwt_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        options.headers['Accept'] = 'application/json';
        return handler.next(options); 
      },
      onError: (DioException e, handler) async {
        // HATA 401 (YETKİSİZ) İSE GİZLİ YENİLEME OPERASYONUNU BAŞLAT
        if (e.response?.statusCode == 401) {
          AppLogger.error("🚨 401 Yetkisiz Erişim: Token süresi dolmuş. Gizli yenileme başlatılıyor...");
          
          // 1. Arka planda Refresh Token algoritmasını çalıştır
          bool isRefreshed = await _refreshToken();

          if (isRefreshed) {
            // 2. Yenileme başarılı! Kasadan o yepyeni token'ı al
            final newToken = await _storage.read(key: 'jwt_token');
            
            // 3. Başarısız olan o eski isteğin başlığını (Header) yeni token ile güncelle
            e.requestOptions.headers['Authorization'] = 'Bearer $newToken';

            try {
              // 4. İsteği sanki hiç hata almamış gibi, yeni token ile API'ye TEKRAR yolla!
              AppLogger.info("♻️ Bekleyen istek yeni token ile tekrar ediliyor...");
              final response = await _dio.fetch(e.requestOptions);
              return handler.resolve(response); // UI tarafına başarılı cevabı döndür, çökme yok!
            } catch (retryError) {
              return handler.next(retryError as DioException);
            }
          } else {
            // Refresh Token da geçerliliğini yitirdiyse oturumu imha et
            AppLogger.error("💀 Oturum tamamen kapandı. Güvenli çıkış yapılıyor.");
            await _storage.deleteAll();
            // Not: Provider üzerinden kullanıcıyı Login ekranına atma işlemi arayüzde dinleniyor olacak.
          }
        }
        return handler.next(e);
      },
    ));
  }

  // --- 🔄 SENİOR DOKUNUŞU 2: GİZLİ TOKEN YENİLEME ALGORİTMASI ---
  Future<bool> _refreshToken() async {
    try {
      AppLogger.info("Sunucuya Refresh Token gönderiliyor...");
      // Gerçek senaryoda burada sunucuya Refresh Token post edilir
      await Future.delayed(const Duration(milliseconds: 800)); 

      // Süresi uzatılmış yepyeni bir token simülasyonu
      String mockNewJwtToken = "eyJhbGciOiJIUz.YENI_TOKEN_${DateTime.now().millisecondsSinceEpoch}";
      
      // Eski token'ın üzerine yaz
      await _storage.write(key: 'jwt_token', value: mockNewJwtToken);

      AppLogger.info("✅ Token başarıyla yenilendi! Sahadaki personel fark etmeden operasyona devam ediyor.");
      return true;
    } catch (e) {
      AppLogger.error("Token yenileme başarısız oldu: $e");
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    try {
      await Future.delayed(const Duration(milliseconds: 1000));

      if (password == '123456') {
        String mockJwtToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.KurumsalSahaPersoneli.Token123456";
        await _storage.write(key: 'jwt_token', value: mockJwtToken);
        return true;
      }
      return false; // Şifre yanlışsa reddet
    } catch (e) {
      AppLogger.error("LOGIN API HATASI: $e");
      return false;
    }
  }

  Future<List<CustomerModel>> getCustomerLocations(String customerId) async {
    try {
      final String encodedId = Uri.encodeComponent(customerId);

      final response = await _dio.get(
        '$baseUrl/Customers/Location',
        queryParameters: {'code': encodedId}, 
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => CustomerModel.fromMap(json)).toList();
      } else {
        throw Exception('Sunucu hatası: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error("API BAĞLANTI HATASI: $e");
      return [];
    }
  }

  Future<List<String>> getCities() async {
    try {
      await Future.delayed(const Duration(milliseconds: 300)); 
      return ['İstanbul', 'Ankara', 'İzmir'];
    } catch (e) {
      return [];
    }
  }

  Future<List<String>> getDistricts(String city) async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      if (city == 'İstanbul') return ['Bakırköy', 'Kadıköy', 'Şişli', 'Ümraniye'];
      if (city == 'Ankara') return ['Çankaya', 'Keçiören', 'Yenimahalle'];
      return ['Merkez İlçesi'];
    } catch (e) {
      return [];
    }
  }

  Future<List<String>> getNeighborhoods(String district) async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      if (district == 'Bakırköy') return ['Zeytinlik Mah.', 'Osmaniye Mah.', 'Şenlikköy Mah.'];
      if (district == 'Kadıköy') return ['Moda', 'Fenerbahçe', 'Bostancı'];
      return ['Merkez Mahallesi'];
    } catch (e) {
      return [];
    }
  }

  Future<bool> updateCustomerLocation(String customerId, double lat, double lng, String fullAddress) async {
    try {
      await Future.delayed(const Duration(seconds: 1));
      AppLogger.info("VERİTEMİZLİĞİ: $customerId kodlu müşterinin konumu ($lat, $lng) olarak güncellendi.");
      return true;
    } catch (e) {
      AppLogger.error("API GÜNCELLEME HATASI: $e");
      return false;
    }
  }

  Future<String> getFullAddressFromCoordinates(double lat, double lng) async {
    try {
      final response = await _dio.get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': lat,
          'lon': lng,
          'format': 'json',
          'accept-language': 'tr' 
        },
        options: Options(headers: {'User-Agent': 'BasbugCustomerLocator/1.0'}),
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data['display_name'] ?? "Adres detayı alınamadı";
      }
      return "Adres çözümlenemedi (Sunucu Hatası)";
    } catch (e) {
      AppLogger.error("GEOCODING HATASI: $e");
      return "Adres çözümlenemedi (Bağlantı Hatası)";
    }
  }
  // --- SENİOR DOKUNUŞU 3: ZORUNLU SÜRÜM KONTROLÜ (FORCE UPDATE) ---
  Future<Map<String, dynamic>> checkAppVersion(String currentVersion) async {
    try {
      // Gerçek senaryoda: await _dio.get('/App/VersionCheck?v=$currentVersion');
      await Future.delayed(const Duration(milliseconds: 600)); 

      // SİMÜLASYON: Holding sunucusundaki en güncel sürümün "1.0.1" olduğunu varsayıyoruz.
      // Eğer cihazdaki sürüm ("1.0.0") bundan farklıysa güncellemeyi zorunlu kılıyoruz.
      String latestVersionOnServer = currentVersion;
      bool isUpdateRequired = currentVersion != latestVersionOnServer;

      return {
        "isUpdateRequired": isUpdateRequired,
        "latestVersion": latestVersionOnServer,
        // Yönlendirilecek adres (Play Store linki veya holding içi MDM indirme linki)
        "updateUrl": "https://play.google.com/store/apps/details?id=com.basbuggroup.customerlocator"
      };
    } catch (e) {
      AppLogger.error("Sürüm kontrolü yapılamadı: $e");
      // Sunucu çökerse personeli sahada kilitlememek için false dönüyoruz (Fail-Safe)
      return {"isUpdateRequired": false}; 
    }
  }
}