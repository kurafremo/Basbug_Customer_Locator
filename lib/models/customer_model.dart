// lib/models/customer_model.dart

class CustomerModel {
  final String customerId;
  final double latitude;   // Değişkenler her zaman küçük harfle başlar
  final double longitude;

  CustomerModel({
    required this.customerId,
    required this.latitude,
    required this.longitude,
  });

  factory CustomerModel.fromMap(Map<String, dynamic> map) {
    return CustomerModel(
      // toString() hayat kurtarır: Veri integer bile gelse çökmeyi engeller ve metne çevirir
      customerId: map['CustomerCode']?.toString().trim() ?? '', 
      
      // Null gelme ihtimaline karşı varsayılan olarak 0.0 atıyoruz
      latitude: double.tryParse(map['Latitude']?.toString() ?? '0.0') ?? 0.0,
      longitude: double.tryParse(map['Longitude']?.toString() ?? '0.0') ?? 0.0,
    );
  }
}