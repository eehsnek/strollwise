import 'package:flutter/material.dart';

import '../data/origin_locations.dart';

/// Country and city dropdowns backed by [OriginLocationCatalog].
class OriginLocationPicker extends StatelessWidget {
  const OriginLocationPicker({
    super.key,
    required this.country,
    required this.city,
    required this.onCountryChanged,
    required this.onCityChanged,
    this.dense = false,
  });

  final String country;
  final String city;
  final ValueChanged<String> onCountryChanged;
  final ValueChanged<String> onCityChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final countries = OriginLocationCatalog.countries;
    final cities = OriginLocationCatalog.citiesFor(country);
    final countryValue = countries.contains(country)
        ? country
        : OriginLocationCatalog.defaultCountry;
    final cityValue = cities.contains(city) ? city : cities.first;

    return Column(
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('country-$countryValue'),
          initialValue: countryValue,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Country of origin',
            prefixIcon: const Icon(Icons.public_outlined),
            isDense: dense,
          ),
          items: countries
              .map(
                (name) => DropdownMenuItem(value: name, child: Text(name)),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            onCountryChanged(value);
            final nextCities = OriginLocationCatalog.citiesFor(value);
            if (nextCities.isNotEmpty &&
                !nextCities.contains(city)) {
              onCityChanged(nextCities.first);
            }
          },
        ),
        SizedBox(height: dense ? 8 : 10),
        DropdownButtonFormField<String>(
          key: ValueKey('city-$countryValue-$cityValue'),
          initialValue: cityValue,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'City of origin',
            prefixIcon: const Icon(Icons.location_city_outlined),
            isDense: dense,
          ),
          items: cities
              .map(
                (name) => DropdownMenuItem(value: name, child: Text(name)),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            onCityChanged(value);
          },
        ),
      ],
    );
  }
}
