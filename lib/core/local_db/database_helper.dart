// lib/core/local_db/database_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../../models/customer_model.dart';
import '../utils/app_logger.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('CustomerGeo.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    final exists = await databaseExists(path);

    if (!exists) {
      AppLogger.info("Veritabanı kopyalanıyor...");
      try {
        await Directory(dirname(path)).create(recursive: true);
        ByteData data = await rootBundle.load(join('assets/db', filePath));
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
        AppLogger.info("Veritabanı başarıyla kopyalandı.");
      } catch (e) {
        AppLogger.error("Veritabanı kopyalama hatası: $e");
      }
    }

    return await openDatabase(
      path,
      onOpen: (db) async {
        // --- SENİOR DOKUNUŞU: TABLO ŞEMASINI ANALİZ ET ---
        // Bu kod, hazır veritabanındaki sütunları terminale basar ki bir daha kör uçuşu yapmayalım.
        try {
          final tableInfo = await db.rawQuery('PRAGMA table_info(CustomerLocations)');
          AppLogger.info("TABLO ŞEMASI: $tableInfo");
        } catch(e) {
          AppLogger.error("Tablo şeması okunamadı.");
        }

        await db.execute('''
          CREATE TABLE IF NOT EXISTS SyncQueue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customerCode TEXT,
            latitude REAL,
            longitude REAL,
            address TEXT,
            status TEXT
          )
        ''');
        
       // --- 2. GÜVENLİ TEST VERİSİ EKLEME ---
        try {
          final result = await db.query('CustomerLocations', where: 'CustomerCode = ?', whereArgs: ['TEST.01.MERKEZ']);
          if (result.isEmpty) {
            await db.insert('CustomerLocations', {
              'CustomerCode': 'TEST.01.MERKEZ',
              'Title': 'Başbuğ Holding Merkez Test', // DÜZELTME: CustomerName yerine Title!
              'Latitude': 41.0314458, 
              'Longitude': 28.6233605,
              'ResolutionLevel': 2, // DÜZELTME: Metin yerine Tam Sayı (Integer)!
              'GeocodeStatus': 1,    // DÜZELTME: Onay durumu için veritabanındaki gerçek sütun!
              'CreatedDate': DateTime.now().toIso8601String()
            });
            AppLogger.info("Holding Merkez test müşterisi başarıyla eklendi veya zaten mevcut.");
          }
        } catch (e) {
          AppLogger.error(" 🔥 Test müşterisi eklenirken hata: $e");
        }
      },
    );
  }

  // ARAMA (Büyük/Küçük Harf Duyarsız)
  Future<List<CustomerModel>> getCustomersById(String id) async {
    final db = await instance.database;
    try {
      final maps = await db.query(
        'CustomerLocations', 
        where: 'UPPER(CustomerCode) = ?',
        whereArgs: [id.toUpperCase()],
      );
      if (maps.isNotEmpty) {
        return maps.map((e) => CustomerModel.fromMap(e)).toList();
      }
      return [];
    } catch (e) {
      AppLogger.error("VERİTABANI ARAMA HATASI: $e");
      return [];
    }
  }

  // --- 3. MANUEL UPSERT (ÖNCE GÜNCELLE, YOKSA EKLE) ---
  Future<int> updateCustomerLocationLocally(String customerCode, double newLat, double newLng) async {
    final db = await instance.database;
    try {
      int changes = await db.update(
        'CustomerLocations',
        {
          'Latitude': newLat,
          'Longitude': newLng,
          'GeocodeStatus': 1, // Güncellendiğini belirtmek için
        },
        where: 'UPPER(CustomerCode) = ?',
        whereArgs: [customerCode.toUpperCase()],
      );

      if (changes == 0) {
        return await db.insert(
          'CustomerLocations',
          {
            'CustomerCode': customerCode.toUpperCase(),
            'Title': 'Yeni Şube / Müşteri', // DÜZELTME: CustomerName yerine Title!
            'Latitude': newLat,
            'Longitude': newLng,
            'ResolutionLevel': 2, // DÜZELTME: Tam Sayı (Integer)!
            'GeocodeStatus': 1,
            'CreatedDate': DateTime.now().toIso8601String()
          },
        );
      }
      return changes; 
    } catch (e) {
      AppLogger.error("🔥 YEREL DB ÇÖKME SEBEBİ: $e");
      return 0;
    }
  }

  Future<int> insertToSyncQueue(String customerCode, double lat, double lng, String address) async {
    final db = await instance.database;
    return await db.insert('SyncQueue', {
      'customerCode': customerCode.toUpperCase(),
      'latitude': lat,
      'longitude': lng,
      'address': address,
      'status': 'PENDING'
    });
  }

  Future<List<Map<String, dynamic>>> getPendingSyncs() async {
    final db = await instance.database;
    return await db.query('SyncQueue', where: 'status = ?', whereArgs: ['PENDING']);
  }

  Future<int> removeFromSyncQueue(int id) async {
    final db = await instance.database;
    return await db.delete('SyncQueue', where: 'id = ?', whereArgs: [id]);
  }
}