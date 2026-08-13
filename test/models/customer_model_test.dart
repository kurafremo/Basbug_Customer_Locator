// test/models/customer_model_test.dart

import 'package:flutter_test/flutter_test.dart';
// Proje ismini 'basbug_customer_locator' olarak varsayıyorum, eğer farklıysa kendi paket isminle değiştir.
import 'package:basbug_customer_locator/models/customer_model.dart'; 

void main() {
  // Testleri mantıksal gruplara ayırıyoruz
  group('CustomerModel Kurumsal Birim Testleri -', () {
    
    test('API\'den gelen doğru JSON verisi, CustomerModel nesnesine hatasız dönüşmelidir', () {
      // 1. ARRANGE (Hazırlık): Sunucudan gelmiş gibi davranan sahte bir JSON verisi
      final Map<String, dynamic> mockJson = {
        'CustomerCode': 'M01.01.6261',
        'Latitude': 41.0082,
        'Longitude': 28.9784,
      };

      // 2. ACT (Eylem): Fabrika metodumuzu (fromMap) çalıştırıyoruz
      final customer = CustomerModel.fromMap(mockJson);

      // 3. ASSERT (Doğrulama): Dönüşen veriler beklediğimiz gibi mi?
      // Eğer burada değerler eşleşmezse, test anında "FAILED" (Başarısız) döner!
      expect(customer.customerId, 'M01.01.6261');
      expect(customer.latitude, 41.0082);
      expect(customer.longitude, 28.9784);
    });

    test('Eksik JSON verisi geldiğinde varsayılan değerler (null/0) atanmalıdır', () {
      // 1. ARRANGE: Yanlış veya eksik gelmiş bir sunucu verisi
      final Map<String, dynamic> mockIncompleteJson = {
        'CustomerCode': 'M02.44.1122',
        // Latitude ve Longitude kasten gönderilmedi
      };

      // 2. ACT
      final customer = CustomerModel.fromMap(mockIncompleteJson);

      // 3. ASSERT: Eksik veriler çökmeye neden olmamalı, varsayılan (fallback) değer almalı
      expect(customer.customerId, 'M02.44.1122');
      expect(customer.latitude, 0.0); // Senin modelindeki fallback yapısına göre null veya 0.0 olmalı
      expect(customer.longitude, 0.0);
    });

  });
}