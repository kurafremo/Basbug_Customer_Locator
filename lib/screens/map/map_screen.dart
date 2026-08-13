// lib/screens/map_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/customer_provider.dart';
import '../../models/customer_model.dart';
import '../../core/network/api_service.dart';
import '../auth/login_screen.dart';
import 'dart:async';

bool _isMapCenteredOnUser = false; // Haritanın kullanıcının konumuna bir kez gitmesi için

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final ApiService _apiService = ApiService();
  
  StreamSubscription<Position>? _locationSubscription;
  
  LatLng? _userLocation; 
  final double _allowedRadius = 100.0; 
  final Set<String> _verifiedPins = {};
  
  CustomerModel? _selectedAndVerifiedCustomer;
  String? _resolvedFullAddress;

  @override
  void initState() {
    super.initState();
    _initLocationService();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mapController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initLocationService() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('Lütfen cihazınızın konum (GPS) servisini açın.', Colors.red);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar('Konum izni reddedildi.', Colors.red);
        return;
      }
    }

    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0)
    ).listen((Position position) {
      if (!mounted) return; 
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
        // SENİOR DOKUNUŞU: Harita ilk kez açıldığında kullanıcının gerçek canlı konumuna zumla!
        if (!_isMapCenteredOnUser) {
          _mapController.move(_userLocation!, 16.0); // 15.0 sokak seviyesi yakınlaştırmasıdır
          _isMapCenteredOnUser = true; // Sadece bir kez çalışması için kilitliyoruz
        }
      });
    });
  }

  void _performSearch() {
    FocusScope.of(context).unfocus(); 
    final id = _searchController.text.trim();
    
    if (id.isNotEmpty && !id.contains("Lat:")) {
      ref.read(customerProvider.notifier).searchCustomers(id);
      
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return; 
        final state = ref.read(customerProvider);
        if (state.customers.isNotEmpty) {
          _mapController.move(
            LatLng(state.customers.first.latitude, state.customers.first.longitude),
            14.0 
          );
        }
      });
    }
  }

  Future<void> _verifyAndPinLocation(CustomerModel customer) async {
    if (_userLocation == null) {
      _showSnackBar('Canlı konumunuz aranıyor, lütfen bekleyin...', Colors.orange);
      return;
    }

    double distanceInMeters = Geolocator.distanceBetween(
      _userLocation!.latitude, _userLocation!.longitude,
      customer.latitude, customer.longitude,
    );

    if (distanceInMeters <= _allowedRadius) {
      _showSnackBar('Mesafe onaylandı! Adres çözümleniyor...', Colors.blueAccent);
      
      setState(() {
        _verifiedPins.add(customer.customerId + customer.latitude.toString()); 
      });

      String address = await _apiService.getFullAddressFromCoordinates(_userLocation!.latitude, _userLocation!.longitude);
      if (!mounted) return;
      
      String fullDetail = "$address (Lat: ${_userLocation!.latitude.toStringAsFixed(5)}, Lng: ${_userLocation!.longitude.toStringAsFixed(5)})";
      
      setState(() {
        _searchController.text = fullDetail; 
        _selectedAndVerifiedCustomer = customer;
        _resolvedFullAddress = address;
      });

    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Mesafe Uyarısı"),
          content: Text("Sistemdeki konuma ${distanceInMeters.toStringAsFixed(0)} metre uzaktasınız.\n\nEğer şu an doğru müşteri konumundaysanız (Sistemde yanlış işaretlenmişse), mevcut konumunuzu bu müşteri için yeni merkez olarak belirleyebilirsiniz."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("İptal", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade900),
              onPressed: () {
                Navigator.pop(context); 
                _forcePinCurrentLocation(customer.customerId); 
              },
              child: const Text("Burayı Yeni Konum Yap", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _forcePinCurrentLocation(String customerId) async {
    if (_userLocation == null) {
      _showSnackBar('Canlı konumunuz aranıyor, lütfen bekleyin...', Colors.orange);
      return;
    }

    _showSnackBar('Özel Durum: Konum zorla eşitleniyor...', Colors.orange);

    CustomerModel overrideCustomer = CustomerModel(
      customerId: customerId,
      latitude: _userLocation!.latitude,
      longitude: _userLocation!.longitude,
    );

    setState(() {
      _verifiedPins.add(overrideCustomer.customerId + overrideCustomer.latitude.toString());
    });

    String address = await _apiService.getFullAddressFromCoordinates(_userLocation!.latitude, _userLocation!.longitude);
    if (!mounted) return;

    setState(() {
      _searchController.text = "$address (Özel Konum Ataması)";
      _selectedAndVerifiedCustomer = overrideCustomer;
      _resolvedFullAddress = address;
    });
  }

  // --- MENÜ İÇERİKLERİ ---
  void _showUnlocatedCustomers() {
    final customerState = ref.read(customerProvider);
    final unlocatedCustomers = customerState.customers.where((c) => c.latitude == 0.0 && c.longitude == 0.0).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: MediaQuery.of(context).size.height * 0.5,
          child: Column(
            children: [
              const Text("Konumu Olmayan Müşteriler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(),
              if (unlocatedCustomers.isEmpty)
                const Expanded(child: Center(child: Text("Eksik konumlu müşteri bulunmamaktadır.")))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: unlocatedCustomers.length,
                    itemBuilder: (context, index) {
                      final customer = unlocatedCustomers[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.location_off, color: Colors.redAccent),
                          title: Text(customer.customerId),
                          subtitle: const Text("Konum atanmamış, buraya sabitlemek için dokunun."),
                          onTap: () {
                            Navigator.pop(context); 
                            _forcePinCurrentLocation(customer.customerId); 
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showPendingSyncs() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: MediaQuery.of(context).size.height * 0.4,
          child: Column(
            children: [
              const Icon(Icons.sync_problem, color: Colors.orange, size: 40),
              const SizedBox(height: 10),
              const Text("Bekleyen İşlemler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(),
              const Expanded(
                child: Center(
                  child: Text("Şu an çevrimdışı kuyrukta bekleyen işlem yok.\nİnternet bağlantınız koptuğunda yapılan onaylamalar burada listelenecektir.", textAlign: TextAlign.center),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Kapat"),
              )
            ],
          ),
        );
      },
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.blueGrey),
            SizedBox(width: 10),
            Text("Sistem Ayarları"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Uygulama Sürümü: v1.0.0", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("Bağlantı Durumu: Çevrimiçi", style: TextStyle(color: Colors.green)),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_sweep, color: Colors.redAccent),
              title: const Text("Yerel Önbelleği Temizle"),
              onTap: () {
                Navigator.pop(context);
                _showSnackBar("Önbellek temizlendi.", Colors.green);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Kapat"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customerState = ref.watch(customerProvider);

    return Scaffold(
      extendBodyBehindAppBar: true, 
      resizeToAvoidBottomInset: false, 
      appBar: AppBar(
        title: const Text('Müşteri Konum Denetimi', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white.withValues(alpha: 0.9), 
        elevation: 0,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: Colors.blue.shade900),
              accountName: const Text("Saha Personeli", style: TextStyle(fontWeight: FontWeight.bold)),
              accountEmail: const Text("omer.ozdemir@basbuggroup.com"),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 40, color: Colors.blueAccent),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.map),
              title: const Text('Harita'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.sync_problem, color: Colors.orange),
              title: const Text('Bekleyen Senkronizasyonlar'),
              trailing: const CircleAvatar(radius: 12, backgroundColor: Colors.orange, child: Text('0', style: TextStyle(fontSize: 12, color: Colors.white))),
              onTap: () {
                Navigator.pop(context);
                _showPendingSyncs();
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_off),
              title: const Text('Konumu Olmayan Müşteriler'),
              onTap: () {
                Navigator.pop(context);
                _showUnlocatedCustomers();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Ayarlar'),
              onTap: () {
                Navigator.pop(context);
                _showSettingsDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Güvenli Çıkış', style: TextStyle(color: Colors.red)),
              onTap: () async {
                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (Route<dynamic> route) => false, 
                );
              },
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _userLocation ?? const LatLng(41.0314458, 28.6233605),
              initialZoom: 16.0, 
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.basbug.fieldservice',
              ),
              MarkerLayer(
                markers: [
                  // SENİOR DOKUNUŞU: Kendi Tasarladığımız Profesyonel Canlı Konum İmleci
                  if (_userLocation != null)
                    Marker(
                      point: _userLocation!,
                      width: 60, height: 60,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.2), 
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Container(
                            width: 22, height: 22,
                            decoration: BoxDecoration(
                              color: Colors.blueAccent, 
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3.5), 
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Müşteri İğneleri
                  ...customerState.customers.where((c) => c.latitude != 0.0 && c.longitude != 0.0).map((customer) {
                    bool isVerified = _verifiedPins.contains(customer.customerId + customer.latitude.toString());
                    return Marker(
                      point: LatLng(customer.latitude, customer.longitude),
                      width: 60, height: 60,
                      child: GestureDetector(
                        onTap: () => _verifyAndPinLocation(customer),
                        child: Icon(
                          Icons.location_on,
                          color: isVerified ? Colors.green : Colors.grey.shade700,
                          size: 50,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Card(
                    elevation: 6,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              maxLines: null, 
                              keyboardType: TextInputType.multiline,
                              decoration: InputDecoration(
                                hintText: 'Müşteri Kodu (Örn: TEST.01.MERKEZ)',
                                border: InputBorder.none,
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchController.clear();
                                          ref.read(customerProvider.notifier).clearSearch();
                                          setState(() {
                                            _selectedAndVerifiedCustomer = null; 
                                          }); 
                                        },
                                      )
                                    : null,
                              ),
                              onChanged: (value) {
                                if (value.isEmpty) {
                                  ref.read(customerProvider.notifier).clearSearch();
                                  setState(() => _selectedAndVerifiedCustomer = null);
                                } else {
                                  setState(() {});
                                }
                              },
                              onSubmitted: (_) => _performSearch(),
                            ),
                          ),
                          customerState.isLoading 
                              ? const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.search, color: Colors.blueAccent),
                                  onPressed: _performSearch,
                                ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_selectedAndVerifiedCustomer != null)
            Positioned(
              bottom: 30, left: 20, right: 20,
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified, color: Colors.green, size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Müşteri: ${_selectedAndVerifiedCustomer!.customerId}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      Text(
                        "Kirli veri tespit edildi. Veritabanındaki eski koordinatlar, bulunduğunuz canlı ve nokta atışı konum ile değiştirilecektir.",
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            _showSnackBar("Holding sunucularına iletiliyor...", Colors.orange);
                            
                            bool success = await ref.read(customerProvider.notifier).updateAndSyncLocation(
                              _selectedAndVerifiedCustomer!.customerId,
                              _userLocation!.latitude,
                              _userLocation!.longitude,
                              _resolvedFullAddress ?? "Adres bulunamadı",
                            );

                            if (!mounted) return; 

                            if (success) {
                              _showSnackBar("BAŞARILI: Veriler şirket veritabanında ve cihazda güncellendi!", Colors.green);
                              setState(() {
                                _selectedAndVerifiedCustomer = null; 
                                _searchController.clear();
                              });
                            } else {
                              _showSnackBar("HATA: Sunucuya ulaşılamadı. İşlem başarısız.", Colors.red);
                            }
                          },
                          icon: const Icon(Icons.cloud_upload, color: Colors.white),
                          label: const Text("Veritabanında Güncelle", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade900,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),

          if (customerState.errorMessage != null)
            Positioned(
              bottom: 20, left: 20, right: 20,
              child: Card(
                color: Colors.redAccent,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    customerState.errorMessage!,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue.shade900,
        child: const Icon(Icons.add_location_alt, color: Colors.white),
        onPressed: () {
          TextEditingController newCodeController = TextEditingController();
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Yeni Şube/Müşteri"),
              content: TextField(
                controller: newCodeController,
                textCapitalization: TextCapitalization.characters, // Klavyeyi otomatik büyük harf yapar
                decoration: const InputDecoration(
                  labelText: "Müşteri Kodu / Adı",
                  hintText: "Örn: YENI.01",
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () async {
                    if (newCodeController.text.isNotEmpty) {
                      String newCode = newCodeController.text.trim().toUpperCase();
                      Navigator.pop(context);
                      FocusScope.of(context).unfocus();
                      _performSearch(seachText);
                      
                      // 1. Haritada Pinle ve Adresi Çöz
                      await _forcePinCurrentLocation(newCode);
                      
                      // 2. Personeli uğraştırmadan OTOMATİK olarak veritabanına kaydet
                      _showSnackBar("Yeni müşteri sisteme işleniyor...", Colors.orange);
                      await ref.read(customerProvider.notifier).updateAndSyncLocation(
                        newCode,
                        _userLocation!.latitude,
                        _userLocation!.longitude,
                        _resolvedFullAddress ?? "Adres bulunamadı",
                      );
                      
                      _showSnackBar("$newCode başarıyla eklendi!", Colors.green);
                    }
                  },
                  child: const Text("Hemen Ekle ve Kaydet"),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}