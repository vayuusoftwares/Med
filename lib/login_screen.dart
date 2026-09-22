import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'app_config.dart';
import 'home_screen.dart';
import 'models/user_model.dart';
import 'services/auth_service.dart';
import 'services/storage_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  // Login Controllers
  final TextEditingController _salesEmailController = TextEditingController();
  final TextEditingController _salesPasswordController = TextEditingController();
  final TextEditingController _adminEmailController = TextEditingController();
  final TextEditingController _adminPasswordController = TextEditingController();

  // Step 5: Dynamic Sales Reps list for dropdown
  List<Map<String, dynamic>> _registeredSalesReps = [];
  String? _selectedSalesEmail;
  bool _loadingSalesReps = false;

  // Registration Controllers
  final TextEditingController _salesRegisterNameController = TextEditingController();
  final TextEditingController _salesRegisterEmailController = TextEditingController();
  final TextEditingController _salesRegisterPhoneController = TextEditingController();
  final TextEditingController _salesRegisterPasswordController = TextEditingController();
  final TextEditingController _salesRegisterConfirmPasswordController = TextEditingController();

  final TextEditingController _adminRegisterNameController = TextEditingController();
  final TextEditingController _adminRegisterEmailController = TextEditingController();
  final TextEditingController _adminRegisterPhoneController = TextEditingController();
  final TextEditingController _adminRegisterPasswordController = TextEditingController();
  final TextEditingController _adminRegisterConfirmPasswordController = TextEditingController();

  final _salesFormKey = GlobalKey<FormState>();
  final _adminFormKey = GlobalKey<FormState>();
  final _salesRegisterFormKey = GlobalKey<FormState>();
  final _adminRegisterFormKey = GlobalKey<FormState>();

  // Page Controller for swiping
  late PageController _pageController;

  // Video Controller
  late VideoPlayerController _videoController;

  // Role Toggle State: false = Sales, true = Admin
  bool _isAdmin = false;

  // Mode Toggle State: false = Login, true = Register
  bool _isRegister = false;

  // UI state
  bool _obscurePassword = true;
  bool _obscureRegisterPassword = true;
  bool _obscureRegisterConfirmPassword = true;
  bool _isLoading = false;

  // Medical Emerald Accent (From User Screenshot)
  static const _emeraldPrimary = Color(0xFF00A86B);
  static const _emeraldDark = Color(0xFF047857);

  // Dark Charcoal Typography (From User Screenshot)
  static const _darkText = Color(0xFF1E293B);
  static const _darkSubtext = Color(0xFF334155);

  // Animation
  late AnimationController _animController;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  // ── Step 5: Dynamically fetch registered Sales Reps for login dropdown ─────
  Future<void> _fetchSalesReps() async {
    setState(() => _loadingSalesReps = true);
    for (final host in AppConfig.allHosts) {
      try {
        final url = Uri.parse('$host/backend/get_all_sales_reps.php');
        final response = await http.get(url, headers: AppConfig.headers).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          if (data['success'] == true) {
            final rawList = data['reps'] as List? ?? [];
            final reps = rawList.cast<Map<String, dynamic>>();
            if (mounted) {
              setState(() {
                _registeredSalesReps = reps;
                _loadingSalesReps = false;
                if (_selectedSalesEmail == null && reps.isNotEmpty) {
                  _selectedSalesEmail = reps.first['email'] as String?;
                  _salesEmailController.text = _selectedSalesEmail ?? '';
                }
              });
            }
            return;
          }
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _loadingSalesReps = false);
    }
  }

  @override
  void initState() {
    super.initState();

    _fetchSalesReps();

    _pageController = PageController(initialPage: _isAdmin ? 1 : 0);

    // Start video initialization immediately
    _videoController = VideoPlayerController.asset('assets/videos/background.mp4')
      ..setLooping(true)
      ..setVolume(0.0)
      ..initialize().then((_) {
        if (mounted) {
          _videoController.play();
          setState(() {});
        }
      }).catchError((e) {
        debugPrint('Video initialization error: $e');
      });

    // Entrance animation for login card
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _animController.forward();
  }

  @override
  void dispose() {
    _salesEmailController.dispose();
    _salesPasswordController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    _salesRegisterNameController.dispose();
    _salesRegisterEmailController.dispose();
    _salesRegisterPhoneController.dispose();
    _salesRegisterPasswordController.dispose();
    _salesRegisterConfirmPasswordController.dispose();
    _adminRegisterNameController.dispose();
    _adminRegisterEmailController.dispose();
    _adminRegisterPhoneController.dispose();
    _adminRegisterPasswordController.dispose();
    _adminRegisterConfirmPasswordController.dispose();
    _pageController.dispose();
    _animController.dispose();
    _videoController.dispose();
    super.dispose();
  }

  // Services
  final _authService = AuthService();
  final _storageService = StorageService();

  // ── DEV BYPASS — remove before production ─────────────────────────────────
  static const _devEmail = 'medsafelifescience@gmail.com';
  static const _devPassword = 'medsafelifescience';
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _handleLogin(bool isAdmin) async {
    final formKey = isAdmin ? _adminFormKey : _salesFormKey;
    if (!formKey.currentState!.validate()) return;

    final email = isAdmin
        ? _adminEmailController.text.trim()
        : (_selectedSalesEmail ?? _salesEmailController.text.trim());
    final password =
        isAdmin ? _adminPasswordController.text : _salesPasswordController.text;
    final role = isAdmin ? 'admin' : 'sales_rep';

    // ── DEV BYPASS ──────────────────────────────────────────
    if ((email == _devEmail && password == _devPassword) ||
        (email == 'medsafelifescience' && password == 'Med@2026')) {
      final devUser = User(
        id: 0,
        name: 'Dev User',
        email: _devEmail,
        phone: '0000000000',
        role: isAdmin ? 'admin' : 'sales_rep',
        roleLabel: isAdmin ? 'Administrator' : 'Sales Representative',
        isActive: true,
        createdAt: DateTime.now().toIso8601String(),
      );
      await _storageService.saveToken('dev_token');
      await _storageService.saveUser(devUser);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => HomeScreen(user: devUser, token: 'dev_token'),
        ),
      );
      return;
    }
    // ──────────────────────────────────────────────────────

    setState(() => _isLoading = true);

    // Try WAMP (local MySQL) login first
    AuthResult result = await _authService.wampLogin(
      email: email,
      password: password,
      role: role,
    );

    // Fall back to ngrok/Laravel if WAMP fails
    if (!result.success) {
      result = await _authService.login(
        email: email,
        password: password,
        role: role,
      );
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success && result.user != null && result.token != null) {
      await _storageService.saveToken(result.token!);
      await _storageService.saveUser(result.user!);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: _emeraldPrimary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) =>
              HomeScreen(user: result.user!, token: result.token!),
        ),
      );
    } else {
      final errorMsg = result.fieldErrors.isNotEmpty
          ? result.fieldErrors.values.expand((e) => e).join('\n')
          : result.message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _handleRegister(bool isAdmin) async {
    final formKey = isAdmin ? _adminRegisterFormKey : _salesRegisterFormKey;
    if (!formKey.currentState!.validate()) return;

    final name = isAdmin
        ? _adminRegisterNameController.text.trim()
        : _salesRegisterNameController.text.trim();
    final email = isAdmin
        ? _adminRegisterEmailController.text.trim()
        : _salesRegisterEmailController.text.trim();
    final phone = isAdmin
        ? _adminRegisterPhoneController.text.trim()
        : _salesRegisterPhoneController.text.trim();
    final password = isAdmin
        ? _adminRegisterPasswordController.text
        : _salesRegisterPasswordController.text;
    final confirm = isAdmin
        ? _adminRegisterConfirmPasswordController.text
        : _salesRegisterConfirmPasswordController.text;
    final role = isAdmin ? 'admin' : 'sales_rep';

    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Passwords do not match.'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Try WAMP (local MySQL) register first
    AuthResult result = await _authService.wampRegister(
      name: name,
      email: email,
      phone: phone,
      password: password,
      role: role,
    );

    // Fall back to ngrok/Laravel if WAMP fails
    if (!result.success && result.message.contains('connect')) {
      result = await _authService.register(
        name: name,
        email: email,
        phone: phone,
        password: password,
        passwordConfirmation: confirm,
        role: role,
      );
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      if (isAdmin) {
        _adminEmailController.text = email;
        _adminPasswordController.clear();
      } else {
        _salesEmailController.text = email;
        _salesPasswordController.clear();
      }

      _salesRegisterNameController.clear();
      _salesRegisterEmailController.clear();
      _salesRegisterPhoneController.clear();
      _salesRegisterPasswordController.clear();
      _salesRegisterConfirmPasswordController.clear();
      _adminRegisterNameController.clear();
      _adminRegisterEmailController.clear();
      _adminRegisterPhoneController.clear();
      _adminRegisterPasswordController.clear();
      _adminRegisterConfirmPasswordController.clear();

      setState(() => _isRegister = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Registration successful! Please log in with your new account.',
          ),
          backgroundColor: _emeraldPrimary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      final errorMsg = result.fieldErrors.isNotEmpty
          ? result.fieldErrors.entries
              .map((e) => '${e.key}: ${e.value.join(', ')}')
              .join('\n')
          : result.message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE2E8F0),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // ── Thematic Map Background Fallback ──
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFCBD5E1),
                    Color(0xFFE2E8F0),
                    Color(0xFFD1D5DB),
                  ],
                ),
              ),
            ),
          ),

          // ── Video Background ──
          if (_videoController.value.isInitialized)
            Positioned.fill(
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoController.value.size.width,
                    height: _videoController.value.size.height,
                    child: VideoPlayer(_videoController),
                  ),
                ),
              ),
            ),

          // ── Transparent Glassmorphism Login/Register Card ──
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: SlideTransition(
                    position: _slideUp,
                    child: _buildGlassCard(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(75),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withAlpha(160),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(20),
                blurRadius: 28,
                spreadRadius: 0,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Top Bar (Back Button + Centered Medical Badge) ──
              Stack(
                alignment: Alignment.center,
                children: [
                  if (_isRegister)
                    Positioned(
                      left: 0,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _darkText, size: 20),
                        onPressed: () {
                          setState(() {
                            _isRegister = false;
                          });
                        },
                      ),
                    ),
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _emeraldPrimary,
                      boxShadow: [
                        BoxShadow(
                          color: _emeraldPrimary.withAlpha(90),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isAdmin ? Icons.admin_panel_settings_rounded : Icons.medical_services_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Role Toggle Switch ──
              _buildRoleToggleSwitch(),
              const SizedBox(height: 20),

              // ── Title & Subtitle ──
              Text(
                _isRegister ? 'Create Account' : 'MedSafe Life Science',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: _darkText,
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  _isRegister
                      ? 'Join the AI-Powered Medical Representative Monitoring & Field Force System'
                      : 'AI-Powered Medical Representative Monitoring & Field Force Automation System',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _darkSubtext,
                    height: 1.35,
                    letterSpacing: 0.1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),

              // ── Swipeable Forms with Smooth Animated Height ──
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: _isRegister ? 525 : 340,
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _isAdmin = index == 1;
                    });
                  },
                  children: _isRegister
                      ? [
                          _buildSalesRegisterForm(),
                          _buildAdminRegisterForm(),
                        ]
                      : [
                          _buildSalesLoginForm(),
                          _buildAdminLoginForm(),
                        ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSalesRepDropdown() {
    final hasValidSelection = _selectedSalesEmail != null &&
        _registeredSalesReps.any((r) => r['email'] == _selectedSalesEmail);
    final selectedValue = hasValidSelection
        ? _selectedSalesEmail
        : (_registeredSalesReps.isNotEmpty ? _registeredSalesReps.first['email'] as String? : null);

    return DropdownButtonFormField<String>(
      value: selectedValue,
      dropdownColor: Colors.white,
      isExpanded: true,
      isDense: true,
      borderRadius: BorderRadius.circular(18),
      style: const TextStyle(
        color: _darkText,
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _darkText),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please select a Sales Rep';
        }
        return null;
      },
      hint: Text(
        _loadingSalesReps ? 'Loading Sales Reps...' : 'Select Sales Rep',
        style: const TextStyle(
          color: _darkText,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.person_outline_rounded, color: _darkText, size: 20),
        filled: true,
        fillColor: const Color(0xFF9EACB7).withAlpha(85),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _emeraldPrimary, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2.0),
        ),
        errorStyle: const TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.bold),
      ),
      items: _registeredSalesReps.map((rep) {
        final repName = (rep['name'] ?? 'Sales Rep').toString();
        final repEmail = (rep['email'] ?? '').toString();
        return DropdownMenuItem<String>(
          value: repEmail,
          child: Text(
            repName,
            style: const TextStyle(color: _darkText, fontWeight: FontWeight.bold, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (val) {
        setState(() {
          _selectedSalesEmail = val;
          _salesEmailController.text = val ?? '';
        });
      },
    );
  }

  Widget _buildSalesLoginForm() {
    return Form(
      key: _salesFormKey,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSalesRepDropdown(),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _salesPasswordController,
              hint: 'Password',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscurePassword,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: _darkText,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
            ),
            const SizedBox(height: 20),
            _buildSubmitButton(isAdmin: false, isRegister: false),
            const SizedBox(height: 22),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminLoginForm() {
    return Form(
      key: _adminFormKey,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTextField(
              controller: _adminEmailController,
              hint: 'Admin Email / ID',
              icon: Icons.person_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your admin ID';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _adminPasswordController,
              hint: 'Password',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscurePassword,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: _darkText,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
            ),
            const SizedBox(height: 20),
            _buildSubmitButton(isAdmin: true, isRegister: false),
            const SizedBox(height: 22),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesRegisterForm() {
    return Form(
      key: _salesRegisterFormKey,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTextField(
              controller: _salesRegisterNameController,
              hint: 'Full Name',
              icon: Icons.person_outline_rounded,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your name';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _salesRegisterEmailController,
              hint: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _salesRegisterPhoneController,
              hint: 'Phone Number',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your phone number';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _salesRegisterPasswordController,
              hint: 'Password',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscureRegisterPassword,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureRegisterPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: _darkText,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscureRegisterPassword = !_obscureRegisterPassword);
                },
              ),
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _salesRegisterConfirmPasswordController,
              hint: 'Confirm Password',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscureRegisterConfirmPassword,
              validator: (value) {
                if (value != _salesRegisterPasswordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureRegisterConfirmPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: _darkText,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscureRegisterConfirmPassword = !_obscureRegisterConfirmPassword);
                },
              ),
            ),
            const SizedBox(height: 14),
            _buildSubmitButton(isAdmin: false, isRegister: true),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _isRegister = false;
                  });
                },
                child: const Text(
                  'Already have an account? Check In',
                  style: TextStyle(
                    color: _emeraldDark,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminRegisterForm() {
    return Form(
      key: _adminRegisterFormKey,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTextField(
              controller: _adminRegisterNameController,
              hint: 'Admin Full Name',
              icon: Icons.person_outline_rounded,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your name';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _adminRegisterEmailController,
              hint: 'Admin Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _adminRegisterPhoneController,
              hint: 'Admin Mobile Number',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your mobile number';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _adminRegisterPasswordController,
              hint: 'Password',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscureRegisterPassword,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureRegisterPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: _darkText,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscureRegisterPassword = !_obscureRegisterPassword);
                },
              ),
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _adminRegisterConfirmPasswordController,
              hint: 'Confirm Password',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscureRegisterConfirmPassword,
              validator: (value) {
                if (value != _adminRegisterPasswordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureRegisterConfirmPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: _darkText,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscureRegisterConfirmPassword = !_obscureRegisterConfirmPassword);
                },
              ),
            ),
            const SizedBox(height: 14),
            _buildSubmitButton(isAdmin: true, isRegister: true),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _isRegister = false;
                  });
                },
                child: const Text(
                  'Already have an account? Check In',
                  style: TextStyle(
                    color: _emeraldDark,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildSubmitButton({required bool isAdmin, required bool isRegister}) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: _emeraldPrimary,
          boxShadow: [
            BoxShadow(
              color: _emeraldPrimary.withAlpha(110),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _isLoading
              ? null
              : () => isRegister ? _handleRegister(isAdmin) : _handleLogin(isAdmin),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  isRegister
                      ? (isAdmin ? 'Register as Admin' : 'Register as Sales Rep')
                      : (isAdmin ? 'Check In as Admin' : 'Check In as Sales Rep'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: const [
        Text(
          'Powered by ',
          style: TextStyle(
            color: _darkSubtext,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          'MedSafe LS',
          style: TextStyle(
            color: _emeraldDark,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// ── Role Toggle Switch Widget (Sales vs Admin) ──
  Widget _buildRoleToggleSwitch() {
    return Container(
      width: double.infinity,
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF9EACB7).withAlpha(90),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withAlpha(140),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          // ── Sales Segment ──
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_isAdmin) {
                  _pageController.animateToPage(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  color: !_isAdmin ? _emeraldPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: !_isAdmin
                      ? [
                          BoxShadow(
                            color: _emeraldPrimary.withAlpha(90),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.badge_outlined,
                          size: 16,
                          color: !_isAdmin ? Colors.white : _darkText,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isRegister ? 'Sales Register' : 'Sales Check In',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: !_isAdmin ? Colors.white : _darkText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Admin Segment ──
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!_isAdmin) {
                  _pageController.animateToPage(
                    1,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  color: _isAdmin ? _emeraldPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: _isAdmin
                      ? [
                          BoxShadow(
                            color: _emeraldPrimary.withAlpha(90),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 16,
                          color: _isAdmin ? Colors.white : _darkText,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isRegister ? 'Admin Register' : 'Admin Check In',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _isAdmin ? Colors.white : _darkText,
                          ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: const TextStyle(
        color: _darkText,
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
      cursorColor: _emeraldPrimary,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: _darkText,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(icon, color: _darkText, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFF9EACB7).withAlpha(85),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _emeraldPrimary, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2.0),
        ),
        errorStyle: const TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
