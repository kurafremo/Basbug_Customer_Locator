// test/providers/auth_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:basbug_customer_locator/providers/auth_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async{

    TestWidgetsFlutterBinding.ensureInitialized();
    //Şifreli kasayı test ortamı için sahte (mock) modda çalıştır
    FlutterSecureStorage.setMockInitialValues({});

    // testLoad yerine projenin ana dizinindeki gerçek .env dosyasını belleğe yüklüyoruz
    await dotenv.load(fileName: ".env");
    
    group('AuthProvider State Management Testleri -', () {
    
    // Riverpod'u test ortamında çalıştırmak için bir kapsayıcı (container)
    late ProviderContainer container;

    setUp(() {
      // Her testten önce tertemiz bir Riverpod hafızası oluşturuyoruz
      container = ProviderContainer();
    });

    tearDown(() {
      // Test bitince hafızayı temizle
      container.dispose();
    });

    test('Uygulama ilk açıldığında varsayılan State değerleri doğru olmalıdır', () {
      // 1. ACT (Provider'ı oku)
      final authState = container.read(authProvider);

      // 2. ASSERT (Başlangıç durumlarını doğrula)
      // İlk açılışta yüklenme olmamalı, giriş yapılmamış olmalı ve hata mesajı boş olmalıdır.
      expect(authState.isLoading, false);
      expect(authState.isAuthenticated, false);
      expect(authState.errorMessage, null);
    });

    test('Login işlemi tetiklendiğinde (mocklanmış bekleme süresince) isLoading tetiklenmelidir', () async {
      // Bu testte Riverpod'un asenkron fonksiyonunu dinleyeceğiz
      final notifier = container.read(authProvider.notifier);
      
      // ACT: Login işlemini başlatıyoruz ama 'await' koymuyoruz çünkü o sıradaki durumu (loading) yakalamak istiyoruz.
      final loginFuture = notifier.login('admin', '123456');

      // ASSERT 1: İşlem başladığı an isLoading true olmalı!
      final loadingState = container.read(authProvider);
      expect(loadingState.isLoading, true);

      // ACT: İşlemin bitmesini bekle
      await loginFuture;

      // ASSERT 2: İşlem bittikten sonra isLoading false olmalı ve giriş başarılı sayılmalı
      final finishedState = container.read(authProvider);
      expect(finishedState.isLoading, false);
      expect(finishedState.isAuthenticated, true);
    });
  });
}