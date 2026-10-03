import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainShell extends StatelessWidget {
  const MainShell({required this.child, super.key});

  final Widget child;

  static const _tabs = [
    '/explore',
    '/add-tag',
    '/feed',
    '/trends',
    '/profile',
  ];

  int _currentIndex(String location) {
    final index = _tabs.indexWhere((route) => location.startsWith(route));
    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final hideNavigation = location.startsWith('/add-tag');
    return Scaffold(
      body: child,
      bottomNavigationBar: hideNavigation
          ? null
          : NavigationBar(
              selectedIndex: _currentIndex(location),
              onDestinationSelected: (index) => context.go(_tabs[index]),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.hexagon_outlined),
                  label: 'Explore',
                ),
                NavigationDestination(
                  icon: Icon(Icons.add_location_alt_outlined),
                  label: 'Add Tag',
                ),
                NavigationDestination(
                  icon: Icon(Icons.dynamic_feed_outlined),
                  label: 'Feed',
                ),
                NavigationDestination(
                  icon: Icon(Icons.trending_up_outlined),
                  label: 'Trends',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: 'Profile',
                ),
              ],
            ),
    );
  }
}
