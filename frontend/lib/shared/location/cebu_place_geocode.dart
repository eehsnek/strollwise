import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../traveler_gradient.dart';

const double cebuServiceAreaRadiusM = 120000;
const LatLng cebuServiceAreaCenter = LatLng(10.3157, 123.8854);

const Map<String, LatLng> cebuKnownPlaces = {
  'ayala': LatLng(10.3173, 123.9058),
  'ayala center': LatLng(10.3173, 123.9058),
  'it park': LatLng(10.3304, 123.9072),
  'cebu it park': LatLng(10.3304, 123.9072),
  'colon': LatLng(10.2966, 123.8986),
  'colon street': LatLng(10.2966, 123.8986),
  'carbon market': LatLng(10.2954, 123.8994),
  'magellan': LatLng(10.2930, 123.9029),
  'magellan cross': LatLng(10.2930, 123.9029),
  'basilica': LatLng(10.2942, 123.9022),
  'santo nino': LatLng(10.2942, 123.9022),
  'fort san pedro': LatLng(10.2922, 123.9058),
  'fuente': LatLng(10.3094, 123.8931),
  'fuente osmena': LatLng(10.3094, 123.8931),
  'mango': LatLng(10.3109, 123.8953),
  'mango avenue': LatLng(10.3109, 123.8953),
  'escario': LatLng(10.3155, 123.8965),
  'escario street': LatLng(10.3155, 123.8965),
  'capitol site': LatLng(10.3172, 123.8958),
  'ramon duterte': LatLng(10.3145, 123.8868),
  'vicente rama': LatLng(10.3162, 123.8885),
  'south bus': LatLng(10.3002, 123.8931),
  'south bus terminal': LatLng(10.3002, 123.8931),
  'sm city': LatLng(10.3112, 123.9187),
  'sm seaside': LatLng(10.2816, 123.8810),
  'pier': LatLng(10.3003, 123.9122),
  'port area': LatLng(10.3003, 123.9122),
  'j solon': LatLng(10.3181, 123.9021),
  'usc': LatLng(10.3006, 123.8989),
  'university of san carlos': LatLng(10.3006, 123.8989),
  'uspf': LatLng(10.3382, 123.9014),
  'university of southern philippines foundation': LatLng(10.3382, 123.9014),
  'salinas drive': LatLng(10.3370, 123.9025),
  'salinas': LatLng(10.3370, 123.9025),
  'jy square': LatLng(10.3359, 123.9023),
  'jy square lahug': LatLng(10.3359, 123.9023),
  'jy': LatLng(10.3359, 123.9023),
  'cebu doctors': LatLng(10.3099, 123.8916),
  'winland tower': LatLng(10.31873, 123.89346),
  'winland': LatLng(10.31873, 123.89346),
  'landmark premier': LatLng(10.3170, 123.9050),
  'robinsons galleria': LatLng(10.3170, 123.9170),
};

/// Cebu metro viewbox for Nominatim (west,south,east,north).
const _nominatimViewbox = '123.70,10.15,124.15,10.50';

class CebuPlaceSearchHit {
  const CebuPlaceSearchHit({
    required this.title,
    required this.subtitle,
    required this.location,
  });

  final String title;
  final String subtitle;
  final LatLng location;
}

bool cebuPlaceWithinServiceArea(LatLng location) {
  return Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        cebuServiceAreaCenter.latitude,
        cebuServiceAreaCenter.longitude,
      ) <=
      cebuServiceAreaRadiusM;
}

LatLng? lookupCebuPlaceLocal(String query) {
  final normalized = query.toLowerCase().trim();
  if (normalized.isEmpty) return null;
  for (final place in cebuKnownPlaces.entries) {
    final key = place.key;
    if (normalized.contains(key) || key.contains(normalized)) {
      return place.value;
    }
  }
  return null;
}

/// Search malls, streets, landmarks, and buildings in greater Cebu.
Future<List<CebuPlaceSearchHit>> searchCebuPlaces(
  Dio dio,
  String rawQuery, {
  int maxResults = 8,
}) async {
  final query = rawQuery.trim();
  if (query.length < 2) return const [];

  final q = query.toLowerCase();
  final seen = <String>{};
  final hits = <CebuPlaceSearchHit>[];

  void add(CebuPlaceSearchHit hit) {
    if (hits.length >= maxResults) return;
    final key = '${hit.location.latitude.toStringAsFixed(5)}-'
        '${hit.location.longitude.toStringAsFixed(5)}';
    if (!seen.add(key)) return;
    hits.add(hit);
  }

  for (final place in cebuKnownPlaces.entries) {
    if (!_matchesQuery(place.key, q)) continue;
    add(
      CebuPlaceSearchHit(
        title: _titleCase(place.key),
        subtitle: 'Cebu landmark',
        location: place.value,
      ),
    );
  }

  await ZoneCatalog.ensureLoaded();
  for (final entry in ZoneCatalog.entries) {
    final hay = '${entry.zoneName} ${entry.city}'.toLowerCase();
    if (!_matchesQuery(hay, q)) continue;
    add(
      CebuPlaceSearchHit(
        title: entry.zoneName,
        subtitle: '${entry.city} · ${TravelerGradient.dominanceLabel(entry.defaultLocalRatio)}',
        location: LatLng(entry.centerLat, entry.centerLng),
      ),
    );
  }

  final remote = await _nominatimHits(dio, query, limit: maxResults - hits.length);
  for (final hit in remote) {
    add(hit);
  }

  return hits;
}

/// Resolves a free-text place (street, mall, landmark) inside greater Cebu.
Future<LatLng?> geocodeCebuPlace(Dio dio, String query) async {
  final hits = await searchCebuPlaces(dio, query, maxResults: 1);
  return hits.isEmpty ? null : hits.first.location;
}

Future<List<CebuPlaceSearchHit>> _nominatimHits(
  Dio dio,
  String query, {
  required int limit,
}) async {
  if (limit <= 0) return const [];
  try {
    final response = await dio.getUri(
      Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'json',
        'limit': limit.clamp(1, 8).toString(),
        'addressdetails': '1',
        'countrycodes': 'ph',
        'viewbox': _nominatimViewbox,
        'bounded': '0',
        'q': '$query, Cebu, Philippines',
      }),
      options: Options(
        headers: const {
          'User-Agent': 'StrollWise/1.0 (Cebu place search)',
        },
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final results = response.data;
    if (results is! List) return const [];

    final hits = <CebuPlaceSearchHit>[];
    for (final raw in results) {
      if (raw is! Map) continue;
      final lat = double.tryParse(raw['lat']?.toString() ?? '');
      final lng = double.tryParse(raw['lon']?.toString() ?? '');
      if (lat == null || lng == null) continue;
      final loc = LatLng(lat, lng);
      if (!cebuPlaceWithinServiceArea(loc)) continue;

      final display = (raw['display_name'] ?? query).toString();
      final parts = display.split(',');
      final title = parts.isNotEmpty ? parts.first.trim() : query;
      hits.add(
        CebuPlaceSearchHit(
          title: title,
          subtitle: _nominatimSubtitle(raw, parts),
          location: loc,
        ),
      );
    }
    return hits;
  } catch (_) {
    return const [];
  }
}

String _nominatimSubtitle(Map raw, List<String> parts) {
  final type = (raw['type'] ?? raw['class'] ?? '').toString();
  final category = (raw['category'] ?? '').toString();
  if (type.isNotEmpty && category.isNotEmpty) {
    return '${_titleCase(category)} · ${_titleCase(type)}';
  }
  if (parts.length >= 2) {
    return parts.sublist(1, parts.length.clamp(1, 3)).join(', ').trim();
  }
  return 'Street or building in Cebu';
}

bool _matchesQuery(String haystack, String query) {
  final terms = query.split(RegExp(r'\s+')).where((t) => t.length >= 2);
  return terms.every(haystack.contains);
}

String _titleCase(String value) {
  return value
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
