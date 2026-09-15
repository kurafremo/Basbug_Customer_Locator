// lib/providers/customer_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/local_db/database_helper.dart';
import '../core/network/api_service.dart';
import '../models/customer_model.dart';
import '../core/utils/app_logger.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CustomerState {
  final List<CustomerModel> customers;
  final bool isLoading;
  final String? errorMessage;
  final bool isOffline; 

  CustomerState({
    this.customers = const [],
    this.isLoading = false,
    this.errorMessage,
    this.isOffline = false, 
  });

  CustomerState copyWith({List<CustomerModel>? customers, bool? isLoading, String? errorMessage, bool? isOffline}) {
    return CustomerState(
      customers: customers ?? this.customers,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      isOffline: isOffline ?? this.isOffline,
    );
  }
}

class CustomerNotifier extends Notifier<CustomerState> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ApiService _apiService = ApiService();

  @override
  CustomerState build() {
    checkInternetAndSync(); 
    
    // SENİOR DOKUNUŞU: Arka planda sürekli internet bağlantısını dinle.
    // Bağlantı geri geldiği an kimseye sormadan kuyruktaki verileri Holding'e postala!
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      bool hasInternet = results.contains(ConnectivityResult.mobile) || results.contains(ConnectivityResult.wifi);
      if (hasInternet) {
        checkInternetAndSync(); 
      } else {
        state = state.copyWith(isOffline: true);
      }
    });

    return CustomerState();
  }
  
  // --- GÜNCELLENEN YENİ METOD: HARİTA AÇILDIĞINDA ÇAĞRILACAK ---
  Future<void> fetchMyCustomers() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    // İleride bu değer authProvider'dan (giriş yapan kişinin token'ından) gelecek.
    try {
      const storage = FlutterSecureStorage();
      // Kasadan giriş yapan plasiyerin kodunu oku (Yoksa varsayılan olarak '*' al)
      String mySalDeptCode = await storage.read(key: 'saldept_code') ?? "*"; 
      
      AppLogger.info("Harita Yükleniyor... Plasiyer Kodu: $mySalDeptCode");

      final myCustomers = await _dbHelper.getCustomersBySalDept(mySalDeptCode);
      
      state = state.copyWith(isLoading: false, customers: myCustomers);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: "Plasiyer müşterileri yüklenemedi.");
    }
  }

 // 1. ARAMA İŞLEMİ (SENİOR DOKUNUŞU: Ana Listeyi Asla Bozmaz!)
  // DİKKAT: Artık void değil, Future<CustomerModel?> döndürüyor!
  Future<CustomerModel?> searchCustomers(String customerId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      // 1. ADIM: Zaten indirdiğimiz ana listede var mı?
      final existingCustomers = state.customers.where((c) => c.customerId.toUpperCase() == customerId.toUpperCase().trim()).toList();

      if (existingCustomers.isNotEmpty) {
        state = state.copyWith(isLoading: false);
        return existingCustomers.first; // Haritayı kaydırmak için ilkini döndür
      }

      // 2. ADIM: Listede yoksa Local DB'de ara
      final localCustomers = await _dbHelper.getCustomersById(customerId);

      if (localCustomers.isNotEmpty) {
        // KRİTİK NOKTA: Listeyi ezmiyoruz! Bulunan yeni müşteriyi mevcut listenin ÜZERİNE EKLİYORUZ.
        state = state.copyWith(isLoading: false, customers: [...state.customers, ...localCustomers]);
        return localCustomers.first;
      }

      // 3. ADIM: Hiçbir yerde yoksa API'ye sor
      final apiCustomers = await _apiService.getCustomerLocations(customerId);
      
      if (apiCustomers.isNotEmpty) {
        state = state.copyWith(isLoading: false, customers: [...state.customers, ...apiCustomers]);
        return apiCustomers.first;
      } else {
        state = state.copyWith(isLoading: false, errorMessage: "Müşteri sistemde bulunamadı.");
        return null;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: "Arama sırasında bir hata oluştu.");
      return null;
    }
  }

  // 2. KAYDETME İŞLEMİ (Sadece İnternet Yokken Telefona Kaydet, Çift Kaydı Önle)
  Future<bool> updateAndSyncLocation(CustomerModel oldCustomer, double lat, double lng, String address) async {
    state = state.copyWith(isLoading: true);

    // 1. ÖNCE İNTERNETİ KONTROL ET
    var connectivityResult = await (Connectivity().checkConnectivity());
    bool hasInternet = connectivityResult.contains(ConnectivityResult.mobile) || connectivityResult.contains(ConnectivityResult.wifi);

    bool isOperationSuccessful = false;

    if (hasInternet) {
      // DURUM A: İNTERNET VAR -> Yalnızca Sunucuya (Veritabanına) Kaydet.
      // Yerel telefona (updateCustomerLocationLocally) ASLA kaydetme!
      bool apiSuccess = await _apiService.updateCustomerLocation(oldCustomer.customerId, lat, lng, address);
      
      if (apiSuccess) {
        isOperationSuccessful = true;
      } else {
        // Sunucu anlık çöktüyse mecburen kuyruğa al (Fail-Safe)
        AppLogger.error("Sunucu reddetti! İşlem çevrimdışı kuyruğa alınıyor...");
        await _dbHelper.insertToSyncQueue(oldCustomer.customerId, lat, lng, address);
        isOperationSuccessful = true; 
      }
    } else {
      // DURUM B: İNTERNET YOK -> Sadece Telefona (Bekleyenler Kuyruğuna) Kaydet.
      AppLogger.error("İnternet Yok! Cihaz hafızasında kuyruğa alınıyor...");
      state = state.copyWith(isOffline: true);
      await _dbHelper.insertToSyncQueue(oldCustomer.customerId, lat, lng, address); 
      isOperationSuccessful = true; 
    }

    // 2. RAM OPTİMİZASYONU (SADECE EKRANI GÜNCELLE)
    if (isOperationSuccessful) {
      List<CustomerModel> updatedList = List.from(state.customers);
      
      // Çift kaydı engellemek için listede arıyoruz
      int index = updatedList.indexWhere((c) => c.customerId.toUpperCase() == oldCustomer.customerId.toUpperCase());
      
      if (index != -1) {
        // Zaten listedeyse (Konumu olmayanlardan geldiyse) sadece koordinatları değiştir
        updatedList[index] = CustomerModel(customerId: oldCustomer.customerId, latitude: lat, longitude: lng);
      } else {
        // Yeni eklendiyse listeye sadece BİR KERE dahil et
        updatedList.add(CustomerModel(customerId: oldCustomer.customerId, latitude: lat, longitude: lng));
      }

      state = state.copyWith(isLoading: false, customers: updatedList); 
      return true; 
    } else {
      state = state.copyWith(isLoading: false, errorMessage: "İşlem başarısız oldu.");
      return false;
    }
  }
  // 3. KUYRUK ERİTME İŞLEMİ
  Future<void> checkInternetAndSync() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    bool hasInternet = connectivityResult.contains(ConnectivityResult.mobile) || connectivityResult.contains(ConnectivityResult.wifi);

    if (hasInternet) {
      state = state.copyWith(isOffline: false);
      final pendingTasks = await _dbHelper.getPendingSyncs();
      
      if (pendingTasks.isNotEmpty) {
        AppLogger.info("İnternet geldi! Kuyruktaki ${pendingTasks.length} işlem API'ye aktarılıyor...");
        
        for (var task in pendingTasks) {
          bool apiSuccess = await _apiService.updateCustomerLocation(
            task['customerCode'], task['latitude'], task['longitude'], task['address']
          );
          if (apiSuccess) {
            await _dbHelper.removeFromSyncQueue(task['id']);
          }
        }
      }
    } else {
      state = state.copyWith(isOffline: true);
    }
  }

  void clearSearch() {
    // SENİOR DOKUNUŞU: Bellekteki listeyi (customers) koruyarak sadece hata mesajını temizliyoruz.
    state = state.copyWith(errorMessage: null);
  }
}

final customerProvider = NotifierProvider<CustomerNotifier, CustomerState>(() {
  return CustomerNotifier();
});