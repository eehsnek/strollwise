import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../app/theme/colors.dart';
import '../../../shared/data/origin_locations.dart';
import '../../../shared/location/cebu_place_geocode.dart';
import '../../../shared/widgets/origin_location_picker.dart';
import '../../../shared/models/report.dart';
import '../../../shared/models/user_contributions.dart';
import '../../../shared/models/visit_pin.dart';
import '../../../shared/models/user_me.dart';
import '../../../shared/models/zone.dart';
import '../../../shared/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/user_manual_map_location.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final token = ref.read(authTokenProvider);
      if (token == null || token == 'demo-token-local') return;
      ref.invalidate(userMeProvider);
      unawaited(ref.read(userContributionsProvider.notifier).refresh());
    });
  }

  void _openVisitOnMap(VisitPinModel pin) {
    final location = LatLng(pin.latitude, pin.longitude);
    ref.read(selectedZoneProvider.notifier).state = null;
    ref.read(mapSearchFocusProvider.notifier).state = location;
    ref.read(mapSearchPlaceTitleProvider.notifier).state =
        pin.label ?? 'Visited spot';
    ref.read(exploreFocusLocationProvider.notifier).state = location;
    ref.invalidate(currentZoneOverviewProvider);
    context.go('/explore');
  }

  Future<void> _refreshProfileData() async {
    final token = ref.read(authTokenProvider);
    if (token == null || token == 'demo-token-local') return;
    ref.invalidate(userMeProvider);
    ref.invalidate(savedZonesProfileProvider);
    ref.invalidate(ownVisitHistoryProvider);
    await ref.read(userContributionsProvider.notifier).refresh();
    try {
      await ref.read(userMeProvider.future);
    } catch (_) {}
    try {
      await ref.read(savedZonesProfileProvider.future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authUserEmailProvider);
    final token = ref.watch(authTokenProvider);
    final isDemo = token == null || token == 'demo-token-local';
    final userMe = ref.watch(userMeProvider);
    final contributions = ref.watch(userContributionsProvider);
    final savedZones = ref.watch(savedZonesProfileProvider);

    final displayName = userMe.maybeWhen(
      data: (u) =>
          (u?.displayName != null && u!.displayName!.trim().isNotEmpty)
              ? u.displayName!.trim()
              : _displayNameFromEmail(u?.email ?? email),
      orElse: () => _displayNameFromEmail(email),
    );

    final travelerLabel = isDemo
        ? 'Demo session — stats below are placeholders until you register.'
        : userMe.maybeWhen(
            data: (u) =>
                u == null ? 'Loading profile…' : _contributorProfileLine(u),
            loading: () => 'Loading profile…',
            orElse: () => 'Loading profile…',
          );

    final stats = contributions.maybeWhen(
      data: (c) => c?.stats,
      orElse: () => null,
    );
    final contributorLabel = isDemo
        ? '—'
        : contributions.maybeWhen(
            data: (c) => c?.contributorLabel ?? 'New to sharing',
            loading: () => 'Loading…',
            orElse: () => 'Loading…',
          );
    final recent = contributions.maybeWhen(
      data: (c) => c?.recentReports ?? const <ReportModel>[],
      orElse: () => const <ReportModel>[],
    );
    final badges = contributions.maybeWhen(
      data: (c) => c?.badges ?? const <ProfileBadgeModel>[],
      orElse: () => const <ProfileBadgeModel>[],
    );

    final submitted = stats?.submitted ?? 0;
    final approved = stats?.approved ?? 0;
    final pending = stats?.pending ?? 0;
    final progress = approved > 0 ? (approved / 25).clamp(0.0, 1.0) : 0.0;

    final showVerified = userMe.maybeWhen(
      data: (u) => u?.isAdmin == true || u?.acceptedResearchConsent == true,
      orElse: () => false,
    );

    final savedList = savedZones.maybeWhen(
      data: (z) => z,
      orElse: () => const <ZoneModel>[],
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryAction,
          onRefresh: _refreshProfileData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: _ProfilePageHeader(
                    onRefreshTap: _refreshProfileData,
                  ),
                ),
              ),
              if (isDemo)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: _DemoSessionCallout(
                      onSignIn: () {
                        if (context.mounted) context.go('/auth');
                      },
                    ),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(20, isDemo ? 12 : 16, 20, 88),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProfileIdentityBanner(
                        displayName: displayName,
                        subtitle: travelerLabel,
                        contributorLabel: contributorLabel,
                        showVerified: showVerified,
                        onEdit: () => _editProfile(context, ref),
                        onLogout: () => _logout(context, ref),
                      ),
                      const SizedBox(height: 14),
                      _ContributionsSummaryCard(
                        taggedCount: submitted,
                        approvedCount: approved,
                        pendingCount: pending,
                        progress: progress,
                      ),
                      const SizedBox(height: 14),
                      _ProfileSectionCard(
                        icon: Icons.edit_location_alt_rounded,
                        title: 'Map location',
                        subtitle:
                            'Set where you explore without sharing live GPS',
                        child: _LocationPreferenceTile(
                          onSetManual: () =>
                              _setManualLocationFromProfile(context, ref),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _ProfileSectionCard(
                        icon: Icons.workspace_premium_outlined,
                        title: 'Badges',
                        subtitle: 'Earned when your tags are approved',
                        child: _BadgesWrap(badges: badges),
                      ),
                      const SizedBox(height: 14),
                      _ProfileSectionCard(
                        icon: Icons.history_rounded,
                        title: 'Recent tags',
                        subtitle: 'Your latest submissions',
                        child: _RecentContributionsList(contributions: recent),
                      ),
                      const SizedBox(height: 14),
                      _ProfileSectionCard(
                        icon: Icons.hiking_rounded,
                        title: 'Places you\'ve been',
                        subtitle:
                            'Private pins only you see — add tags to grow this map',
                        child: _VisitHistoryList(
                          visits: ref.watch(ownVisitHistoryProvider),
                          onOpenVisit: _openVisitOnMap,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _ProfileSectionCard(
                        icon: Icons.visibility_outlined,
                        title: 'Privacy',
                        subtitle: 'How your tags appear on the map',
                        child: const _TagVisibilityFootnote(),
                      ),
                      const SizedBox(height: 14),
                      _ProfileSectionCard(
                        icon: Icons.bookmark_outline_rounded,
                        title: 'Saved zones',
                        subtitle: savedList.isEmpty
                            ? null
                            : '${savedList.length} on your list',
                        child: _SavedZonesFromApi(zones: savedList),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editProfile(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final token = ref.read(authTokenProvider);
    if (token == null || token == 'demo-token-local') {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in with a full account to edit your profile.'),
        ),
      );
      return;
    }
    UserMeModel? user = ref.read(cachedUserMeProvider);
    user ??= await ref.read(userMeProvider.future);
    if (!context.mounted) return;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load profile. Pull to refresh.')),
      );
      return;
    }
    final u = user;
    final result = await showDialog<_ProfileEditResult>(
      context: context,
      builder: (_) => _EditProfileDialog(
        initialName: u.displayName?.trim().isNotEmpty == true
            ? u.displayName!.trim()
            : _displayNameFromEmail(u.email),
        initialCountry: u.countryOfOrigin ?? '',
        initialCity: u.cityOfOrigin ?? '',
        initialUserType: u.userType ?? 'local_resident',
      ),
    );
    if (!context.mounted) return;
    if (result == null) return;
    final name = result.displayName.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Display name is required.')),
      );
      return;
    }
    if (!OriginLocationCatalog.isValidPair(result.country, result.city)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a valid country and city from the lists.'),
        ),
      );
      return;
    }
    try {
      await ref.read(dioProvider).patch(
        '/users/me',
        data: {
          'display_name': name,
          'country_of_origin': result.country.trim(),
          'city_of_origin': result.city.trim(),
          'user_type': result.userType,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      await Future<void>.delayed(Duration.zero);
      if (!context.mounted) return;
      ref.invalidate(userMeProvider);
      try {
        await ref.read(userMeProvider.future);
      } catch (_) {}
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update profile. Try again.')),
        );
      }
    }
  }

  Future<void> _setManualLocationFromProfile(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final queryController = TextEditingController();
    var busy = false;

    Future<void> tryApply(
      BuildContext dialogCtx,
      void Function(void Function()) setLocal,
    ) async {
      final q = queryController.text.trim();
      if (q.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Enter an area, street, or landmark.'),
            ),
          );
        }
        return;
      }
      setLocal(() => busy = true);
      try {
        final found = await geocodeCebuPlace(ref.read(dioProvider), q);
        if (!dialogCtx.mounted) return;
        if (found == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No match in greater Cebu. Try another spelling or a shorter name.',
                ),
              ),
            );
          }
          if (dialogCtx.mounted) {
            setLocal(() => busy = false);
          }
          return;
        }
        Navigator.of(dialogCtx).pop(found);
        // Avoid setLocal after pop — route is disposing (framework assertions).
      } catch (_) {
        if (dialogCtx.mounted) {
          setLocal(() => busy = false);
        }
      }
    }

    LatLng? result;
    try {
      result = await showDialog<LatLng>(
        context: context,
        builder: (dialogCtx) => StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: const Text('Search map location'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Search for a place in greater Cebu — neighborhood, '
                      'street, mall, campus, or landmark.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.mutedText.withValues(alpha: 0.95),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: queryController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Place or street',
                        hintText: 'e.g. Ayala Center, Colon Street, USPF',
                      ),
                      onSubmitted: (_) {
                        if (!busy) unawaited(tryApply(ctx, setLocal));
                      },
                    ),
                    if (busy) ...[
                      const SizedBox(height: 16),
                      const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: busy ? null : () => unawaited(tryApply(ctx, setLocal)),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      queryController.dispose();
    }

    if (result == null) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final token = ref.read(authTokenProvider);
    final isDemo = token == null || token == 'demo-token-local';
    if (!isDemo) {
      final saved = await persistUserManualMapLocation(ref, result);
      if (!context.mounted) return;
      if (!saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save location to your account. Check your connection.',
            ),
          ),
        );
        return;
      }
    }
    ref.read(currentUserLocationProvider.notifier).state = result;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isDemo
              ? 'Saved on this device for Explore and nearby picks.'
              : 'Saved to your account. Explore and feeds will use this place.',
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        title: const Text('Log out'),
        content: const Text('End your current StrollWise session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (shouldLogout != true || !context.mounted) return;
    ref.read(authActionProvider.notifier).logout();
    if (!context.mounted) return;
    context.go('/auth');
  }

  String _displayNameFromEmail(String? email) {
    if (email == null || email.isEmpty || email == 'demo@strollwise.local') {
      return 'New Explorer';
    }
    return email.split('@').first.replaceAll('.', ' ');
  }

  String _contributorProfileLine(UserMeModel u) {
    final type = _userTypeLabel(u.userType, u.travelerType);
    final bits = <String>[];
    final city = u.cityOfOrigin?.trim();
    final country = u.countryOfOrigin?.trim();
    if (city != null && city.isNotEmpty) bits.add(city);
    if (country != null && country.isNotEmpty) bits.add(country);
    if (bits.isEmpty) return '$type · not shown on the public map';
    return '$type · ${bits.join(', ')} (private to you)';
  }

  String _userTypeLabel(String? userType, String travelerType) {
    switch ((userType ?? '').toLowerCase()) {
      case 'local_resident':
        return 'Local resident';
      case 'international_visitor':
        return 'International visitor';
      case 'domestic_traveler':
        return 'Domestic traveler';
      default:
        return _travelerLabel(travelerType);
    }
  }

  String _travelerLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'local':
        return 'Local traveler';
      case 'international':
        return 'International visitor';
      case 'mixed':
      default:
        return 'Mixed traveler';
    }
  }
}

class _ProfileEditResult {
  const _ProfileEditResult({
    required this.displayName,
    required this.country,
    required this.city,
    required this.userType,
  });

  final String displayName;
  final String country;
  final String city;
  final String userType;
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({
    required this.initialName,
    required this.initialCountry,
    required this.initialCity,
    required this.initialUserType,
  });

  final String initialName;
  final String initialCountry;
  final String initialCity;
  final String initialUserType;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  static const _userTypeChoices = <(String, String)>[
    ('local_resident', 'Local resident'),
    ('international_visitor', 'International visitor'),
    ('domestic_traveler', 'Domestic traveler'),
  ];

  late final TextEditingController _nameController;
  late String _country;
  late String _city;
  late String _userType;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    final resolved = OriginLocationCatalog.resolveSelection(
      country: widget.initialCountry,
      city: widget.initialCity,
    );
    _country = resolved.country;
    _city = resolved.city;
    _userType = widget.initialUserType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      title: const Text('Edit profile'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Display name',
                helperText: 'Saved to your StrollWise account',
              ),
            ),
            const SizedBox(height: 12),
            OriginLocationPicker(
              dense: true,
              country: _country,
              city: _city,
              onCountryChanged: (value) => setState(() => _country = value),
              onCityChanged: (value) => setState(() => _city = value),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _userTypeChoices.any((e) => e.$1 == _userType)
                  ? _userType
                  : 'local_resident',
              decoration: const InputDecoration(
                labelText: 'User type',
              ),
              items: _userTypeChoices
                  .map(
                    (e) => DropdownMenuItem(value: e.$1, child: Text(e.$2)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _userType = v);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _ProfileEditResult(
              displayName: _nameController.text,
              country: _country,
              city: _city,
              userType: _userType,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ProfilePageHeader extends StatelessWidget {
  const _ProfilePageHeader({required this.onRefreshTap});

  final Future<void> Function() onRefreshTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Profile',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryText,
                    letterSpacing: -0.4,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your StrollWise account',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedText.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ),
          ),
          _ProfileHeaderIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onTap: () => unawaited(onRefreshTap()),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeaderIconButton extends StatelessWidget {
  const _ProfileHeaderIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Icon(icon, size: 22, color: AppColors.primaryText),
        ),
      ),
    );
    final message = tooltip;
    if (message == null || message.isEmpty) return child;
    return Tooltip(message: message, child: child);
  }
}

class _DemoSessionCallout extends StatelessWidget {
  const _DemoSessionCallout({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.travel_explore_rounded,
                size: 22,
                color: AppColors.transportAccent.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Demo session: sign in with a full StrollWise account to '
                  'load your tags, badges, and saved zones.',
                  style: TextStyle(
                    color: AppColors.secondaryText.withValues(alpha: 0.98),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: onSignIn,
              child: const Text('Sign in or register'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileIdentityBanner extends StatelessWidget {
  const _ProfileIdentityBanner({
    required this.displayName,
    required this.subtitle,
    required this.contributorLabel,
    required this.showVerified,
    required this.onEdit,
    required this.onLogout,
  });

  final String displayName;
  final String subtitle;
  final String contributorLabel;
  final bool showVerified;
  final VoidCallback onEdit;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.mapInk, Color(0xFF0A4A6B)],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -28,
                  top: -36,
                  child: Icon(
                    Icons.hexagon_outlined,
                    size: 168,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primaryAction.withValues(alpha: 0.85),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.22),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 34,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.14),
                          child: const Icon(
                            Icons.directions_walk_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    displayName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                if (showVerified) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.verified_rounded,
                                    color: AppColors.secondaryAction
                                        .withValues(alpha: 0.95),
                                    size: 22,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                contributorLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: onEdit,
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text('Edit name'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withValues(alpha: 0.45),
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: onLogout,
                                  icon: const Icon(Icons.logout_rounded, size: 18),
                                  label: const Text('Log out'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFFFFB4A8),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContributionsSummaryCard extends StatelessWidget {
  const _ContributionsSummaryCard({
    required this.taggedCount,
    required this.approvedCount,
    required this.pendingCount,
    required this.progress,
  });

  final int taggedCount;
  final int approvedCount;
  final int pendingCount;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.localFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.analytics_outlined,
                  color: AppColors.localAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Contributions',
                style: TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _ContributionStatCell(
                    value: '$taggedCount',
                    label: 'Submitted',
                    icon: Icons.add_location_alt_outlined,
                    accent: AppColors.primaryDark,
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppColors.border.withValues(alpha: 0.9),
                ),
                Expanded(
                  child: _ContributionStatCell(
                    value: '$approvedCount',
                    label: 'Approved',
                    icon: Icons.verified_outlined,
                    accent: AppColors.lagoon,
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppColors.border.withValues(alpha: 0.9),
                ),
                Expanded(
                  child: _ContributionStatCell(
                    value: '$pendingCount',
                    label: 'Pending',
                    icon: Icons.hourglass_top_rounded,
                    accent: const Color(0xFFD97706),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Text(
            'Community mapper — $approvedCount approved / 25 toward the next badge',
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: AppColors.border,
              color: AppColors.primaryAction,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(
                color: AppColors.primaryText,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContributionStatCell extends StatelessWidget {
  const _ContributionStatCell({
    required this.value,
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.mutedText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSectionCard extends StatelessWidget {
  const _ProfileSectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.backgroundAlt,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.mapInk, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: AppColors.mutedText.withValues(alpha: 0.95),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _LocationPreferenceTile extends StatelessWidget {
  const _LocationPreferenceTile({required this.onSetManual});

  final VoidCallback onSetManual;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Use this when you do not want to share your device location. '
          'Explore and nearby picks will use the place you choose in '
          'greater Cebu instead of live GPS.',
          style: TextStyle(
            color: AppColors.secondaryText.withValues(alpha: 0.98),
            fontWeight: FontWeight.w600,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          onPressed: onSetManual,
          icon: const Icon(Icons.search_rounded, size: 20),
          label: const Text('Search place on map'),
          style: FilledButton.styleFrom(
            foregroundColor: AppColors.mapInk,
            backgroundColor: AppColors.secondaryAction.withValues(alpha: 0.35),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}

class _BadgesWrap extends StatelessWidget {
  const _BadgesWrap({required this.badges});

  final List<ProfileBadgeModel> badges;

  static (Color bg, Color fg, IconData icon) _styleFor(String key) {
    return switch (key) {
      'food_finder' => (
          const Color(0xFFFFF4E5),
          const Color(0xFFB7791F),
          Icons.restaurant_rounded,
        ),
      'transport_helper' => (
          const Color(0xFFF2EEFF),
          const Color(0xFF6B46C1),
          Icons.directions_bus_outlined,
        ),
      'local_guide' => (
          const Color(0xFFEEF5FF),
          const Color(0xFF3B82F6),
          Icons.star_border_rounded,
        ),
      'safety_reporter' => (
          const Color(0xFFFFF0F6),
          const Color(0xFFB83280),
          Icons.shield_outlined,
        ),
      _ => (
          const Color(0xFFE9F8EF),
          const Color(0xFF2F855A),
          Icons.place_outlined,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) {
      return const Text(
        'No badges yet. Submit tags that get approved to unlock badges here.',
        style: TextStyle(
          color: AppColors.mutedText,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: badges.map((b) {
        final s = _styleFor(b.key);
        return _TagChip(
          label: b.label,
          background: s.$1,
          foreground: s.$2,
          icon: s.$3,
        );
      }).toList(),
    );
  }
}

class _VisitHistoryList extends StatelessWidget {
  const _VisitHistoryList({
    required this.visits,
    required this.onOpenVisit,
  });

  final AsyncValue<List<VisitPinModel>> visits;
  final void Function(VisitPinModel pin) onOpenVisit;

  @override
  Widget build(BuildContext context) {
    return visits.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, _) => const Text(
        'Could not load your visit map.',
        style: TextStyle(
          color: AppColors.mutedText,
          fontWeight: FontWeight.w700,
        ),
      ),
      data: (pins) {
        if (pins.isEmpty) {
          return const Text(
            'No visits saved yet. On Explore, tap the hiking icon to mark where you\'ve been, or add a tag — each tag adds a private pin only you see.',
            style: TextStyle(
              color: AppColors.mutedText,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < pins.length; i++) ...[
              _VisitHistoryRow(
                pin: pins[i],
                onTap: () => onOpenVisit(pins[i]),
              ),
              if (i < pins.length - 1)
                const Divider(height: 16, color: AppColors.border),
            ],
          ],
        );
      },
    );
  }
}

class _VisitHistoryRow extends StatelessWidget {
  const _VisitHistoryRow({
    required this.pin,
    required this.onTap,
  });

  final VisitPinModel pin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = pin.label ?? 'Visited spot';
    final when = _formatVisitDate(pin.lastVisitedAt);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const Text('🧦', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pin.visitCount > 1
                          ? '$when · ${pin.visitCount} visits'
                          : when,
                      style: const TextStyle(
                        color: AppColors.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'View on map',
                      style: TextStyle(
                        color: AppColors.secondaryAction,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.mutedText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatVisitDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.month}/${local.day}/${local.year}';
  }
}

class _RecentContributionsList extends StatelessWidget {
  const _RecentContributionsList({required this.contributions});

  final List<ReportModel> contributions;

  @override
  Widget build(BuildContext context) {
    if (contributions.isEmpty) {
      return const Text(
        'No contributions yet. Add your first zone tag from the Add Tag tab.',
        style: TextStyle(
          color: AppColors.mutedText,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Column(
      children: [
        for (int i = 0; i < contributions.length; i++) ...[
          _ContributionRow(report: contributions[i]),
          if (i < contributions.length - 1)
            const Divider(height: 16, color: AppColors.border),
        ],
      ],
    );
  }
}

class _ContributionRow extends StatelessWidget {
  const _ContributionRow({required this.report});

  final ReportModel report;

  @override
  Widget build(BuildContext context) {
    final approved = report.isApprovedVisible;
    final statusColor = approved
        ? const Color(0xFF2F855A)
        : const Color(0xFFB7791F);
    final title = report.tags.isNotEmpty
        ? report.tags.take(2).join(' • ')
        : report.category.toUpperCase();
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: statusColor.withValues(alpha: 0.14),
          child: Icon(
            _iconForCategory(report.category),
            size: 17,
            color: statusColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${report.category}  ·  ${report.h3Index.substring(0, 7)}',
                style: const TextStyle(
                  color: AppColors.mutedText,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            approved ? 'Approved' : 'Pending validation',
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right_rounded, color: AppColors.mutedText),
      ],
    );
  }

  IconData _iconForCategory(String category) {
    final key = category.toLowerCase();
    if (key.contains('food')) return Icons.restaurant_rounded;
    if (key.contains('transport')) return Icons.directions_bus_outlined;
    if (key.contains('safety')) return Icons.shield_outlined;
    if (key.contains('crowd')) return Icons.groups_rounded;
    return Icons.pin_drop_outlined;
  }
}

class _TagVisibilityFootnote extends StatelessWidget {
  const _TagVisibilityFootnote();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Each tag uses the visibility you pick when you submit it. '
      'Exact GPS is never shown publicly; signals roll up into map zones.',
      style: TextStyle(
        color: AppColors.mutedText,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SavedZonesFromApi extends StatelessWidget {
  const _SavedZonesFromApi({required this.zones});

  final List<ZoneModel> zones;

  @override
  Widget build(BuildContext context) {
    if (zones.isEmpty) {
      return const Text(
        'No saved zones yet. Open a zone on the map and save it to your list.',
        style: TextStyle(
          color: AppColors.mutedText,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: zones
          .map(
            (z) => Chip(
              avatar: Icon(
                Icons.hexagon_outlined,
                size: 16,
                color: AppColors.primaryAction.withValues(alpha: 0.85),
              ),
              label: Text(
                z.displayName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.background,
    required this.foreground,
    required this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: AppColors.border),
    boxShadow: const [
      BoxShadow(color: Color(0x0F0F172A), blurRadius: 12, offset: Offset(0, 4)),
    ],
  );
}
