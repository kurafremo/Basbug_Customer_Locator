// test/network/api_service_mock_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
// Kendi proje adına göre import yolunu kontrol et
import 'package:basbug_customer_locator/core/network/api_service.dart';

// 1. DÜBLÖR (MOCK) SINIFI OLUŞTURUYORUZ
// Bu sınıf, gerçek ApiService'in tüm yeteneklerine sahiptir ama içinde hiçbir kod çalışmaz.
class MockApiService extends Mock implements ApiService {}

void main() {
  // Testler boyunca kullanacağımız dublör nesnemiz
  late MockApiService mockApiService;

  // setUp: Her bir 'test' bloğu çalışmadan hemen önce otomatik olarak tetiklenir.
  setUp(() {
    // Her testte birbirine karışmaması için dublörü sıfırlıyoruz.
    mockApiService = MockApiService();
  });

  group('ApiService Mock (Taklit) Testleri -', () {
    
    test('Doğru kullanıcı adı ve şifre gönderildiğinde başarılı (true) dönmelidir', () async {
      // 1. ARRANGE (Hazırlık ve Senaryo Yazımı)
      // Dublörümüze diyoruz ki: "Eğer sana admin ve 123456 gelirse, sanki sunucuya gitmişsin de başarılı olmuşsun gibi 'true' cevabı ver."
      when(() => mockApiService.login('admin', '123456'))
          .thenAnswer((_) async => true);

      // 2. ACT (Eyleme Geç)
      // Fonksiyonu sanki uygulamada butona basılmış gibi çalıştırıyoruz.
      final result = await mockApiService.login('admin', '123456');

      // 3. ASSERT (Doğrulama)
      // Gelen cevap gerçekten 'true' mu?
      expect(result, true);
      
      // SENIOR DOKUNUŞU: Bu fonksiyon gerçekten tam olarak bu parametrelerle tam olarak 1 kez çağrıldı mı?
      verify(() => mockApiService.login('admin', '123456')).called(1);
    });

    test('Yanlış şifre gönderildiğinde başarısız (false) dönmelidir', () async {
      // 1. ARRANGE
      // Dublörümüze kasten yanlış bir senaryo veriyoruz.
      when(() => mockApiService.login('admin', 'yanlis_sifre'))
          .thenAnswer((_) async => false);

      // 2. ACT
      final result = await mockApiService.login('admin', 'yanlis_sifre');

      // 3. ASSERT
      // Cevabın 'false' olmasını bekliyoruz.
      expect(result, false);
      
      // Yanlış şifreyle 1 kez denenmiş olduğunu doğruluyoruz.
      verify(() => mockApiService.login('admin', 'yanlis_sifre')).called(1);
    });

  });
}