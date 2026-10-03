/// Valid country → city pairs for registration and profile.
class OriginLocationCatalog {
  OriginLocationCatalog._();

  static const String defaultCountry = 'Philippines';
  static const String defaultCity = 'Cebu City';

  static const Map<String, List<String>> _citiesByCountry = {
    'Philippines': [
      'Cebu City',
      'Manila',
      'Quezon City',
      'Davao City',
      'Makati',
      'Taguig',
      'Iloilo City',
      'Bacolod',
      'Cagayan de Oro',
      'Baguio',
      'Angeles City',
      'General Santos',
      'Zamboanga City',
      'Pasig',
      'Mandaue',
    ],
    'United States': [
      'New York',
      'Los Angeles',
      'San Francisco',
      'Chicago',
      'Seattle',
      'Houston',
      'Miami',
      'Boston',
    ],
    'Japan': [
      'Tokyo',
      'Osaka',
      'Kyoto',
      'Nagoya',
      'Fukuoka',
      'Sapporo',
    ],
    'South Korea': [
      'Seoul',
      'Busan',
      'Incheon',
      'Daegu',
    ],
    'China': [
      'Beijing',
      'Shanghai',
      'Shenzhen',
      'Guangzhou',
      'Hong Kong',
    ],
    'Australia': [
      'Sydney',
      'Melbourne',
      'Brisbane',
      'Perth',
    ],
    'United Kingdom': [
      'London',
      'Manchester',
      'Birmingham',
      'Edinburgh',
    ],
    'Canada': [
      'Toronto',
      'Vancouver',
      'Montreal',
      'Calgary',
    ],
    'Singapore': [
      'Singapore',
    ],
    'Germany': [
      'Berlin',
      'Munich',
      'Frankfurt',
      'Hamburg',
    ],
    'France': [
      'Paris',
      'Lyon',
      'Marseille',
    ],
    'Italy': [
      'Rome',
      'Milan',
      'Naples',
    ],
    'Spain': [
      'Madrid',
      'Barcelona',
      'Valencia',
    ],
    'Netherlands': [
      'Amsterdam',
      'Rotterdam',
      'The Hague',
    ],
    'India': [
      'Mumbai',
      'Delhi',
      'Bengaluru',
      'Chennai',
      'Hyderabad',
    ],
    'Indonesia': [
      'Jakarta',
      'Surabaya',
      'Bali (Denpasar)',
      'Bandung',
    ],
    'Malaysia': [
      'Kuala Lumpur',
      'Penang',
      'Johor Bahru',
    ],
    'Thailand': [
      'Bangkok',
      'Chiang Mai',
      'Phuket',
    ],
    'Vietnam': [
      'Ho Chi Minh City',
      'Hanoi',
      'Da Nang',
    ],
    'Taiwan': [
      'Taipei',
      'Kaohsiung',
      'Taichung',
    ],
    'United Arab Emirates': [
      'Dubai',
      'Abu Dhabi',
    ],
    'Saudi Arabia': [
      'Riyadh',
      'Jeddah',
    ],
    'Brazil': [
      'São Paulo',
      'Rio de Janeiro',
      'Brasília',
    ],
    'Mexico': [
      'Mexico City',
      'Guadalajara',
      'Monterrey',
    ],
    'Other': [
      'Other city',
    ],
  };

  static List<String> get countries {
    final names = _citiesByCountry.keys.toList(growable: false);
    names.sort((a, b) {
      if (a == defaultCountry) return -1;
      if (b == defaultCountry) return 1;
      return a.compareTo(b);
    });
    return names;
  }

  static List<String> citiesFor(String country) {
    return List<String>.unmodifiable(
      _citiesByCountry[country] ?? const [],
    );
  }

  static bool isValidPair(String country, String city) {
    final cities = _citiesByCountry[country];
    if (cities == null) return false;
    return cities.contains(city.trim());
  }

  /// Maps common typos (e.g. "Philippine") to a catalog country, or null.
  static String? normalizeCountry(String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final country in _citiesByCountry.keys) {
      if (country.toLowerCase() == q) return country;
    }
    const aliases = <String, String>{
      'philippine': 'Philippines',
      'philippines': 'Philippines',
      'ph': 'Philippines',
      'pinas': 'Philippines',
      'usa': 'United States',
      'us': 'United States',
      'u.s.': 'United States',
      'u.s.a.': 'United States',
      'uk': 'United Kingdom',
      'u.k.': 'United Kingdom',
      'uae': 'United Arab Emirates',
    };
    return aliases[q];
  }

  /// Best-effort city match for a country; null if unknown.
  static String? normalizeCity(String country, String raw) {
    final cities = citiesFor(country);
    if (cities.isEmpty) return null;
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final city in cities) {
      if (city.toLowerCase() == q) return city;
    }
    if (country == defaultCountry) {
      if (q.contains('cebu')) return 'Cebu City';
      if (q.contains('manila')) return 'Manila';
      if (q.contains('davao')) return 'Davao City';
    }
    return null;
  }

  /// Resolved selection for forms (dropdown values).
  static ({String country, String city}) resolveSelection({
    String? country,
    String? city,
  }) {
    final resolvedCountry =
        normalizeCountry(country ?? '') ??
        (countries.contains(country ?? '') ? country! : defaultCountry);
    final cities = citiesFor(resolvedCountry);
    final resolvedCity =
        normalizeCity(resolvedCountry, city ?? '') ??
        (cities.contains(city ?? '') ? city! : cities.first);
    return (country: resolvedCountry, city: resolvedCity);
  }
}
