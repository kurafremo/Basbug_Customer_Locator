// lib/screens/customers/located_customers_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/customer_provider.dart';
import 'dart:async';

class LocatedCustomersScreen extends ConsumerStatefulWidget {
  const LocatedCustomersScreen({super.key});

  @override
  ConsumerState<LocatedCustomersScreen> createState() => _LocatedCustomersScreenState();
}

class _LocatedCustomersScreenState extends ConsumerState<LocatedCustomersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customerState = ref.watch(customerProvider);
    
    // FİLTRE: Koordinatları 0 olmayanlar (Kayıtlılar)
    final locatedList = customerState.customers.where((c) {
      final isLocated = c.latitude != 0.0 && c.longitude != 0.0;
      final matchesSearch = c.customerId.toLowerCase().contains(_searchQuery.toLowerCase());
      return isLocated && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Kayıtlı Müşteriler', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        elevation: 1,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Kayıtlı Müşteri Ara...",
                prefixIcon: const Icon(Icons.search, color: Colors.green),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = "");
                          FocusScope.of(context).unfocus();
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              // SENİOR DOKUNUŞU: Arama kasmalarını önleyen geciktirici mantık
              onChanged: (value) {
                // Eğer kullanıcı yazmaya devam ediyorsa eski sayacı iptal et
                if (_debounce?.isActive ?? false) {
                  _debounce!.cancel();
                }
                
                // Kullanıcı klavyeden elini çektikten tam 300 milisaniye sonra aramayı tetikle
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  setState(() {
                    _searchQuery = value.trim();
                  });
                });
              },
            ),
          ),
          
          Expanded(
            child: locatedList.isEmpty
                ? const Center(child: Text("Eşleşen kayıtlı müşteri bulunamadı.", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: locatedList.length,
                    itemBuilder: (context, index) {
                      final customer = locatedList[index];
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.shade100,
                            child: const Icon(Icons.verified, color: Colors.green),
                          ),
                          title: Text(customer.customerId, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("Lat: ${customer.latitude.toStringAsFixed(4)}\nLng: ${customer.longitude.toStringAsFixed(4)}", style: const TextStyle(fontSize: 12)),
                          trailing: const Icon(Icons.map, color: Colors.blueAccent),
                          onTap: () {
                            // Tıklandığında Haritada bu müşteriye gitmesi için ID'yi geri gönderir
                            Navigator.pop(context, customer.customerId);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}