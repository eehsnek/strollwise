import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/colors.dart';
import '../../../shared/data/origin_locations.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/origin_location_picker.dart';

const _kUserTypeChoices = <(String value, String label)>[
  ('local_resident', 'Local resident'),
  ('international_visitor', 'International visitor'),
  ('domestic_traveler', 'Domestic traveler'),
];

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  AuthMode _mode = AuthMode.login;
  bool _obscurePassword = true;
  bool _acceptedResearchConsent = false;
  String _userTypeValue = 'local_resident';
  String _countryOfOrigin = OriginLocationCatalog.defaultCountry;
  String _cityOfOrigin = OriginLocationCatalog.defaultCity;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email and password are required.')),
      );
      return;
    }
    if (_mode == AuthMode.register && password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 8 characters.'),
        ),
      );
      return;
    }
    if (_mode == AuthMode.register && !_acceptedResearchConsent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please accept the privacy and research consent notice.',
          ),
        ),
      );
      return;
    }
    if (_mode == AuthMode.register) {
      final displayName = _displayNameController.text.trim();
      if (displayName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Display name is required.')),
        );
        return;
      }
      if (!OriginLocationCatalog.isValidPair(
        _countryOfOrigin,
        _cityOfOrigin,
      )) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Choose a valid country and city from the lists.'),
          ),
        );
        return;
      }
    }
    if (_mode == AuthMode.login &&
        email.toLowerCase() == 'demo@strollwise.local' &&
        (password == 'demo12345' || password.toLowerCase() == 'demo')) {
      ref.read(authActionProvider.notifier).loginDemoUser();
      if (!mounted) return;
      context.go('/explore');
      return;
    }
    try {
      await ref
          .read(authActionProvider.notifier)
          .submit(
            mode: _mode,
            email: email,
            password: password,
            displayName: _displayNameController.text,
            countryOfOrigin: _countryOfOrigin,
            cityOfOrigin: _cityOfOrigin,
            userType: _userTypeValue,
            acceptedResearchConsent: _acceptedResearchConsent,
          );
      if (!mounted) return;
      context.go('/explore');
    } catch (error) {
      if (!mounted) return;
      final message = _authErrorMessage(error, mode: _mode);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _authErrorMessage(Object error, {required AuthMode mode}) {
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'Cannot reach the server. Start the backend and run the app with '
            '--dart-define=API_URL=http://127.0.0.1:8000';
      }
      final status = error.response?.statusCode;
      final detail = error.response?.data;
      if (detail is Map && detail['detail'] != null) {
        final msg = detail['detail'].toString();
        if (status == 409 && mode == AuthMode.register) {
          return 'This email is already registered. Switch to Sign in.';
        }
        return msg;
      }
    }
    return mode == AuthMode.login
        ? 'Login failed. Check your credentials.'
        : 'Registration failed. Try a different email.';
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authActionProvider);
    final isLoading = authState.isLoading;
    final isRegister = _mode == AuthMode.register;
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFEAF4FA),
                  Color(0xFFF8FAFC),
                  Color(0xFFFFFEF5),
                ],
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Opacity(
                opacity: 0.08,
                child: Image.asset(
                  'lib/app/theme/strollwiselogo.jpg',
                  width: 320,
                  height: 320,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 20,
                  ),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x180F172A),
                          blurRadius: 24,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.asset(
                                'lib/app/theme/strollwiselogo.jpg',
                                width: 36,
                                height: 36,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'StrollWise',
                              style: TextStyle(
                                color: AppColors.primaryText,
                                fontSize: 36 / 2,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 34,
                          height: 3,
                          decoration: BoxDecoration(
                            color: AppColors.secondaryAction,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isRegister ? 'Create your account' : 'Welcome back',
                          style: const TextStyle(
                            color: AppColors.primaryText,
                            fontSize: 34 / 2,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Sign in or register to personalize your zone feed.',
                          style: TextStyle(
                            color: AppColors.secondaryText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (isRegister) ...[
                          TextField(
                            controller: _displayNameController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              hintText: 'Display name',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            hintText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                        ),
                        if (isRegister) ...[
                          const SizedBox(height: 10),
                          OriginLocationPicker(
                            country: _countryOfOrigin,
                            city: _cityOfOrigin,
                            onCountryChanged: (value) =>
                                setState(() => _countryOfOrigin = value),
                            onCityChanged: (value) =>
                                setState(() => _cityOfOrigin = value),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _userTypeValue,
                            decoration: const InputDecoration(
                              labelText: 'User type',
                              prefixIcon: Icon(Icons.groups_outlined),
                            ),
                            items: _kUserTypeChoices
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.$1,
                                    child: Text(e.$2),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _userTypeValue = v);
                            },
                          ),
                        ],
                        if (isRegister) ...[
                          const SizedBox(height: 12),
                          _ResearchConsentCard(
                            value: _acceptedResearchConsent,
                            onChanged: (value) => setState(
                              () => _acceptedResearchConsent = value ?? false,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: isLoading ? null : _submit,
                            child: Text(
                              isLoading
                                  ? 'Please wait...'
                                  : (isRegister ? 'Register' : 'Log in'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(
                                'or continue with',
                                style: TextStyle(
                                  color: AppColors.mutedText.withValues(
                                    alpha: 0.9,
                                  ),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: null,
                                icon: const Text('G'),
                                label: const Text('Google'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.apple),
                                label: const Text('Apple'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: isLoading
                                ? null
                                : () {
                                    ref
                                        .read(authActionProvider.notifier)
                                        .loginDemoUser();
                                    context.go('/explore');
                                  },
                            child: const Text('Use Demo Login (offline mode)'),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              isRegister
                                  ? 'Already have an account?'
                                  : 'Need an account?',
                              style: const TextStyle(
                                color: AppColors.secondaryText,
                              ),
                            ),
                            TextButton(
                              onPressed: isLoading
                                  ? null
                                  : () => setState(
                                      () {
                                        _mode = isRegister
                                            ? AuthMode.login
                                            : AuthMode.register;
                                        if (_mode == AuthMode.login) {
                                          _acceptedResearchConsent = false;
                                        }
                                      },
                                    ),
                              child: Text(isRegister ? 'Log in' : 'Register'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResearchConsentCard extends StatelessWidget {
  const _ResearchConsentCard({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(value: value, onChanged: onChanged),
          const SizedBox(width: 6),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Privacy + research consent',
                  style: TextStyle(
                    color: AppColors.primaryText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'I agree that my submitted tags may be converted into aggregated H3 zone signals for thesis research. Exact GPS is not shown publicly; StrollWise displays zone-level behavior patterns.',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    height: 1.35,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
