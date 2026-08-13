// test/screens/login_screen_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:basbug_customer_locator/screens/auth/login_screen.dart';

void main() async {
  // 1. TEST ORTAMI GÜVENLİK VE ALTYAPI HAZIRLIKLARI (Önceki testlerdeki gibi)
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({}); 
  await dotenv.load(fileName: ".env");

  group('LoginScreen Arayüz (Widget) Testleri -', () {
    
    testWidgets('Giriş ekranındaki tüm kurumsal logolar ve kutular eksiksiz yüklenmelidir', (WidgetTester tester) async {
      // 2. ACT (Aksiyon): Hayalet kullanıcı uygulamayı sanal olarak Riverpod ile sarmalayıp açar
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // 3. ASSERT (Doğrulama): Ekranda beklediğimiz yazılar ve kutular var mı?
      // findsOneWidget: Ekranda bundan tam olarak 1 tane olmalı demektir.
      expect(find.text('Başbuğ Holding'), findsOneWidget);
      expect(find.text('Müşteri Konum Sistemi'), findsOneWidget);
      
      // TextField (Girdi kutusu) tipinde tam olarak 2 adet widget olmalı (Kullanıcı adı ve Şifre)
      expect(find.byType(TextField), findsNWidgets(2)); 
      
      expect(find.text('Giriş Yap'), findsOneWidget);
    });

    testWidgets('Kullanıcı klavyeden veri girdiğinde arayüz bu yazıları göstermelidir', (WidgetTester tester) async {
      // Uygulamayı tekrar sanal olarak açıyoruz
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Text alanlarını "içindeki ipucu (Label) yazılarına göre" ekranda buluyoruz
      final usernameField = find.widgetWithText(TextField, 'Kullanıcı Adı');
      final passwordField = find.widgetWithText(TextField, 'Şifre');

      // Hayalet kullanıcımız klavyeyi açıp kurumsal bilgilerini giriyor
      await tester.enterText(usernameField, 'omer.ozdemir');
      await tester.enterText(passwordField, '123456');

      // Ekranda değişiklik olduktan sonra (klavye yazımı vb.) UI'ı güncellemek (yenilemek) için pump() çağrılır
      await tester.pump();

      // ASSERT: Yazılan yazılar gerçekten ekranda (TextField içinde) belirdi mi?
      expect(find.text('omer.ozdemir'), findsOneWidget);
      expect(find.text('123456'), findsOneWidget);
    });
  });
}