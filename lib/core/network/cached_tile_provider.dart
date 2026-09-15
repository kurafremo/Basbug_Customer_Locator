import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cached_network_image/cached_network_image.dart';

// SENİOR DOKUNUŞU: Harita parçalarını anlık indirmek yerine cihaz hafızasına kazıyan motor.
class CachedTileProvider extends TileProvider {
   CachedTileProvider();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    // Harita resminin URL'sini alıyoruz
    final tileUrl = getTileUrl(coordinates, options);
    
    // Resmi indir ve cihazın fiziksel önbelleğine (Cache) kaydet
    return CachedNetworkImageProvider(tileUrl);
  }
}