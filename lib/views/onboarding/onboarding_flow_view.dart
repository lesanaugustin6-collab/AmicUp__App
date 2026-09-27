import 'dart:io';

import 'package:flutter/material.dart';
import '../../widgets/brand_wordmark.dart';
import '../../widgets/avatar_preview.dart';
import '../../theme/app_theme.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../utils/profile_field_codec.dart';
import '../main_navigation_view.dart';

class BrandedBackground extends StatelessWidget {
  const BrandedBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppTheme.of(context).canvas),
      child: child,
    );
  }
}

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );
      return;
    }

    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your password.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = Supabase.instance.client.auth;
      final response = await auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw StateError('Invalid login credentials.');
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavigationView()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Login failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BrandedBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: BrandWordmark()),
                        const SizedBox(height: 16),
                        Text(
                          'Welcome back',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.of(context).ink,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: AppTheme.of(context).violet,
                            foregroundColor: AppTheme.of(context).onAccent,
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.of(context).onAccent,
                                  ),
                                )
                              : const Text('Log In'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const OnboardingFlowView(),
                              ),
                            );
                          },
                          child: const Text("Don't have an account? Sign Up"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingFlowView extends StatefulWidget {
  const OnboardingFlowView({super.key, this.initialPage = 0});

  final int initialPage;

  @override
  State<OnboardingFlowView> createState() => _OnboardingFlowViewState();
}

class _OnboardingFlowViewState extends State<OnboardingFlowView> {
  late final PageController _pageController = PageController(initialPage: 0);
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  String? _selectedCountry;
  final List<TextEditingController> _icebreakerControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];

  final List<String> _lifestyleOptions = [
    'Gym / Fitness',
    'Running',
    'Hiking',
    'Reading',
    'Coffee & Brunch',
    'Cooking',
    'Travel',
    'Photography',
    'Gaming',
    'Movies / TV',
    'Music',
    'Art / Painting',
    'Yoga',
    'Cycling',
    'Dog Parent',
    'Nightlife',
  ];

  final List<String> _socialOptions = [
    'Outgoing',
    'Easygoing',
    'Talkative',
    'Thoughtful',
    'Funny',
    'Calm',
    'Curious',
    'Adventurous',
    'Warm',
    'Independent',
    'Supportive',
    'Creative',
    'Spontaneous',
    'Grounded',
    'Optimistic',
    'Introverted',
  ];

  // ignore: unused_field
  final List<String> _sportsOptions = [
    'Basketball',
    'Football',
    'Running',
    'Gym',
    'Swimming',
    'Cycling',
    'Volleyball',
    'Tennis',
    'Hiking',
    'Yoga',
    'Climbing',
    'Pickleball',
  ];

  // ignore: unused_field
  final List<String> _hobbyOptions = [
    'Reading',
    'Cooking',
    'Photography',
    'Travel',
    'Art',
    'Gaming',
    'Music',
    'Movies',
    'Coffee Shops',
    'Brunch',
    'Hiking',
    'Board Games',
  ];

  // ignore: unused_field
  final List<String> _musicOptions = [
    'Pop',
    'Rock',
    'Hip Hop',
    'R&B',
    'Indie',
    'Electronic',
    'Jazz',
    'Country',
    'Classical',
    'Latin',
  ];

  final List<String> _languageOptions = AppConstants.languages;

  // ignore: unused_field
  final List<String> _matchIntentOptions = [
    'Friendship',
    'Networking',
    'Hanging Out',
    'Activities',
    'Coffee / Brunch',
  ];

  // ignore: unused_field
  final List<String> _availabilityOptions = [
    'Weeknights',
    'Weekends',
    'Evenings',
    'Mornings',
    'Afternoons',
    'Flexible',
  ];

  List<String> _selectedSports = [];
  List<String> _selectedHobbies = [];
  List<String> _selectedMusic = [];
  List<String> _selectedLifestyle = [];
  List<String> _selectedSocialVibe = [];
  List<String> _selectedLanguages = [];
  List<String> _selectedMatchIntent = [];
  List<String> _selectedAvailability = [];
  List<Map<String, String>> _icebreakers = [];
  final int _totalSteps = 10;
  final List<XFile> _galleryPhotos = [];
  final List<XFile> _selectedGalleryFiles = [];
  final List<String> _uploadedPhotoUrls = [];
  String? _avatarPublicUrl;
  XFile? _avatarFile;
  XFile? _profileImage;
  String? _registeredUserId;
  DateTime? _dob;
  String? _selectedGender;
  int _currentStep = 0;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSubmitting = false;
  bool _isPicking = false;
  bool _isLoginMode = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    for (final controller in _icebreakerControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _goToPreviousStep() async {
    await _pageController.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildScrollableStep({required List<Widget> children}) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  void _syncIcebreakers() {
    _icebreakers = [
      {
        'question': "I'm looking for a friend who...",
        'answer': _icebreakerControllers[0].text.trim(),
      },
      {
        'question': 'My ideal way to spend a free afternoon with friends is...',
        'answer': _icebreakerControllers[1].text.trim(),
      },
      {
        'question': 'The fastest way to become my friend is...',
        'answer': _icebreakerControllers[2].text.trim(),
      },
    ];
  }

  Future<void> _validateAndNext() async {
    String? errorMessage;

    switch (_currentStep) {
      case 0:
        if (_emailController.text.trim().isEmpty) {
          errorMessage = 'Please enter an email.';
        } else if (_passwordController.text.trim().isEmpty) {
          errorMessage = 'Please enter a password.';
        } else if (!_isLoginMode && _passwordController.text.length < 6) {
          errorMessage = 'Password must be at least 6 characters.';
        } else if (!_isLoginMode &&
            _passwordController.text != _confirmPasswordController.text) {
          errorMessage = 'Passwords do not match.';
        }
        break;
      case 1:
        if (_firstNameController.text.trim().isEmpty) {
          errorMessage = 'Please enter your first name.';
        } else if (_selectedCountry == null ||
            _selectedCountry!.trim().isEmpty) {
          errorMessage = 'Please select your country.';
        }
        break;
      case 2:
        if (_selectedSports.length < 2) {
          errorMessage = 'Please select at least 2 sports.';
        }
        break;
      case 3:
        if (_selectedHobbies.length < 2) {
          errorMessage = 'Please select at least 2 hobbies.';
        }
        break;
      case 4:
        if (_selectedMusic.length < 2) {
          errorMessage = 'Please select at least 2 music genres.';
        }
        break;
      case 5:
        if (_selectedLifestyle.length < 2) {
          errorMessage = 'Please select at least 2 lifestyle options.';
        } else if (_selectedSocialVibe.length < 2) {
          errorMessage = 'Please select at least 2 social vibe options.';
        }
        break;
      case 6:
        if (_selectedLanguages.isEmpty) {
          errorMessage = 'Please select at least 1 language.';
        } else if (_selectedAvailability.isEmpty) {
          errorMessage = 'Please select at least 1 availability option.';
        }
        break;
      case 7:
        if (_selectedMatchIntent.isEmpty) {
          errorMessage = 'Please choose at least one reason to join.';
        }
        break;
      case 8: // Step 9: Icebreakers
        _syncIcebreakers();
        final answeredCount = _icebreakerControllers
            .where((c) => c.text.trim().isNotEmpty)
            .length;
        if (answeredCount < 2) {
          errorMessage = 'Please answer at least 2 icebreakers to continue.';
        }
        break;
      case 9:
        if (_avatarFile == null && _avatarPublicUrl == null) {
          errorMessage = 'Please upload a main profile picture.';
        } else if (_selectedGalleryFiles.length < 2) {
          errorMessage = 'Please upload at least 2 gallery photos.';
        }
        break;
    }

    if (errorMessage != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_currentStep == 0) {
      await _handleAuthStep();
      return;
    }

    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep++);
    } else {
      _submitFinalProfile();
    }
  }

  Future<void> _handleAuthStep() async {
    final supabase = Supabase.instance.client;
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() => _isSubmitting = true);

    try {
      if (_isLoginMode) {
        await supabase.auth.signOut();

        final response = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (response.user == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid login credentials'),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }

        try {
          final profile = await supabase
              .from('profiles')
              .select()
              .eq('id', response.user!.id)
              .maybeSingle();

          if (profile != null && profile['first_name'] != null) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const MainNavigationView(),
              ),
            );
            return;
          }

          if (!mounted) return;
          _pageController.nextPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          setState(() => _currentStep = 1);
          return;
        } on PostgrestException catch (e) {
          if (e.code == 'PGRST303' || e.message.contains('JWT')) {
            await supabase.auth.signOut();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Time synchronization issue. Please try tapping Log In again.',
                ),
                backgroundColor: Colors.orangeAccent,
              ),
            );
            return;
          }
          rethrow;
        }
      }

      final response = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to create account.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      _registeredUserId = response.user!.id;

      if (!mounted) return;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep = 1);
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message.isNotEmpty ? error.message : 'Authentication failed',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<ImageSource?> _showPhotoSourceBottomSheet(BuildContext context) async {
    return await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipSelector({
    required String title,
    required List<String> options,
    required List<String> selectedList,
    required Function(List<String>) onChanged,
    int maxSelections = 6,
    int minSelections = 2,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          "Choose $minSelections to $maxSelections · ${selectedList.length} selected",
          style: TextStyle(color: AppTheme.of(context).muted, height: 1.4),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final isSelected = selectedList.contains(option);
            return FilterChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (selected) {
                final updated = List<String>.from(selectedList);
                if (selected) {
                  if (updated.length < maxSelections) updated.add(option);
                } else {
                  updated.remove(option);
                }
                onChanged(updated);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _showLanguagePickerBottomSheet() async {
    final searchController = TextEditingController();
    final filteredLanguages = List<String>.from(_languageOptions);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final query = searchController.text.trim().toLowerCase();
            final visibleLanguages = query.isEmpty
                ? filteredLanguages
                : filteredLanguages.where((language) {
                    return language.toLowerCase().contains(query);
                  }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.75,
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppTheme.of(context).line,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          'Select Languages (${_selectedLanguages.length} chosen)',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: searchController,
                          onChanged: (_) => setSheetState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Search languages',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: visibleLanguages.length,
                          itemBuilder: (context, index) {
                            final language = visibleLanguages[index];
                            final isSelected = _selectedLanguages.contains(
                              language,
                            );

                            return CheckboxListTile(
                              value: isSelected,
                              title: Text(language),
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (selected) {
                                final updated = List<String>.from(
                                  _selectedLanguages,
                                );
                                if (selected == true) {
                                  updated.add(language);
                                } else {
                                  updated.remove(language);
                                }
                                setState(() => _selectedLanguages = updated);
                                setSheetState(() {});
                              },
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.of(context).violet,
                              foregroundColor: AppTheme.of(context).onAccent,
                            ),
                            child: const Text('Done'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickAvatarImage() async {
    if (_isPicking) return;
    _isPicking = true;

    try {
      final source = await _showPhotoSourceBottomSheet(context);
      if (source == null) return;

      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 90);

      if (picked == null || !mounted) return;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop profile picture',
            toolbarColor: AppTheme.of(context).violet,
            toolbarWidgetColor: AppTheme.of(context).onAccent,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: 'Crop profile picture',
            aspectRatioLockEnabled: true,
          ),
        ],
      );

      if (croppedFile != null) {
        setState(() {
          _profileImage = XFile(croppedFile.path);
          _avatarFile = _profileImage;
        });
      }
    } catch (error) {
      debugPrint('Avatar pick error: $error');
      _showSnack('Unable to pick and crop a profile photo.');
    } finally {
      _isPicking = false;
    }
  }

  Future<void> _pickGalleryImage() async {
    if (_isPicking || _galleryPhotos.length >= 6) {
      if (_galleryPhotos.length >= 6) {
        _showSnack('You can add up to 6 profile photos.');
      }
      return;
    }
    _isPicking = true;

    try {
      final source = await _showPhotoSourceBottomSheet(context);
      if (source == null) return;

      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 82);

      if (picked != null) {
        setState(() {
          _selectedGalleryFiles.add(picked);
          _galleryPhotos.clear();
          _galleryPhotos.addAll(_selectedGalleryFiles);
        });
      }
    } catch (error) {
      debugPrint('Gallery photo pick error: $error');
      _showSnack('Unable to add a photo.');
    } finally {
      _isPicking = false;
    }
  }

  void _removeGalleryPhoto(int index) {
    if (_galleryPhotos.length <= 2) {
      _showSnack('Keep at least 2 profile photos.');
      return;
    }
    setState(() {
      _galleryPhotos.removeAt(index);
      _selectedGalleryFiles
        ..clear()
        ..addAll(_galleryPhotos);
    });
  }

  Future<void> _replaceGalleryPhoto(int index) async {
    if (_isPicking) return;
    _isPicking = true;

    try {
      final source = await _showPhotoSourceBottomSheet(context);
      if (source == null) return;

      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 82);

      if (picked != null) {
        setState(() {
          _selectedGalleryFiles[index] = picked;
          _galleryPhotos.clear();
          _galleryPhotos.addAll(_selectedGalleryFiles);
        });
      }
    } catch (error) {
      debugPrint('Gallery replacement error: $error');
      _showSnack('Unable to replace photo.');
    } finally {
      _isPicking = false;
    }
  }

  int _calculateAge(DateTime date) {
    final now = DateTime.now();
    var age = now.year - date.year;
    if (now.month < date.month ||
        (now.month == date.month && now.day < date.day)) {
      age--;
    }
    return age;
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final maxDate = DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? maxDate,
      firstDate: DateTime(1900),
      lastDate: maxDate,
    );

    if (picked != null) {
      setState(() => _dob = picked);
    }
  }

  Future<void> _pickCountry() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final queryController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = AppConstants.worldCountries
                .where(
                  (country) => country.toLowerCase().contains(
                    queryController.text.toLowerCase(),
                  ),
                )
                .toList();

            return AlertDialog(
              title: const Text('Choose your country'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: queryController,
                      decoration: const InputDecoration(
                        hintText: 'Search country',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final country = filtered[index];
                          return ListTile(
                            title: Text(country),
                            onTap: () =>
                                Navigator.of(dialogContext).pop(country),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected != null) {
      setState(() => _selectedCountry = selected);
    }
  }

  Future<void> _submitFinalProfile() async {
    final email = _emailController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final username = _usernameController.text.trim();
    final bio = _bioController.text.trim();

    if (email.isEmpty ||
        firstName.isEmpty ||
        lastName.isEmpty ||
        username.isEmpty ||
        bio.isEmpty ||
        _dob == null ||
        _selectedGender == null ||
        _selectedGender!.isEmpty ||
        _selectedCountry == null ||
        _selectedCountry!.trim().isEmpty) {
      _showSnack('Please complete all profile details before submitting.');
      return;
    }

    if (_profileImage == null &&
        _avatarFile == null &&
        _avatarPublicUrl == null) {
      _showSnack('Please upload a profile photo to continue.');
      return;
    }

    final sourceGallery = _selectedGalleryFiles.isNotEmpty
        ? _selectedGalleryFiles
        : _galleryPhotos;
    if (sourceGallery.isEmpty) {
      _showSnack('Please add at least 1 gallery photo.');
      return;
    }

    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id ?? _registeredUserId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Session expired. Please re-enter your email and password in Step 1.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String? uploadedAvatarUrl;
      final avatarFile = _profileImage ?? _avatarFile;
      if (avatarFile != null) {
        final bytes = await avatarFile.readAsBytes();
        final fileExt = avatarFile.path.split('.').last;
        final fileName =
            'avatars/${userId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

        await client.storage
            .from('profiles')
            .uploadBinary(
              fileName,
              bytes,
              fileOptions: FileOptions(
                contentType: 'image/$fileExt',
                upsert: true,
              ),
            );

        uploadedAvatarUrl = client.storage
            .from('profiles')
            .getPublicUrl(fileName);
        _avatarPublicUrl = uploadedAvatarUrl;
      }

      final galleryUrls = <String>[];
      for (int i = 0; i < sourceGallery.length; i++) {
        final photo = sourceGallery[i];
        final fileName =
            '$userId/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';

        try {
          await client.storage
              .from('profiles')
              .upload(
                fileName,
                File(photo.path),
                fileOptions: const FileOptions(upsert: true),
              );

          final publicUrl = client.storage
              .from('profiles')
              .getPublicUrl(fileName);
          galleryUrls.add(publicUrl);
        } catch (e) {
          debugPrint('UPLOAD ERROR for file: $e');
        }
      }

      _uploadedPhotoUrls.clear();
      _uploadedPhotoUrls.addAll(galleryUrls);

      _syncIcebreakers();
      final prompts = _icebreakers;

      final Map<String, dynamic> profileData = {
        'id': userId,
        'email': client.auth.currentUser?.email ?? email,
        'first_name': firstName,
        'last_name': lastName,
        'username': username,
        'birth_date':
            '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
        'gender': _selectedGender,
        'bio': bio,
        'country': _selectedCountry,
        'avatar_url': uploadedAvatarUrl,
        'prompts': prompts,
        'gallery_photos': encodeProfileList(galleryUrls),
        'sports': encodeProfileList(_selectedSports),
        'hobbies': encodeProfileList(_selectedHobbies),
        'music': encodeProfileList(_selectedMusic),
        'lifestyle': encodeProfileList(_selectedLifestyle),
        'social_vibe': encodeProfileList(_selectedSocialVibe),
        'languages': encodeProfileList(_selectedLanguages),
        'availability': List<String>.from(_selectedAvailability),
        'match_intent': _selectedMatchIntent,
      };

      await client.from('profiles').upsert(profileData, onConflict: 'id');

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavigationView()),
        (route) => false,
      );
    } catch (error) {
      debugPrint('Submit profile error: $error');
      if (!mounted) return;
      _showSnack('Could not save your profile: $error');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildSignUpStep() {
    return _buildScrollableStep(
      children: [
        const SizedBox(height: 18),
        Text(
          _isLoginMode ? 'Welcome back' : 'Create account',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppTheme.of(context).ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your people. Your plans. Start here.',
          style: TextStyle(color: AppTheme.of(context).muted, fontSize: 15),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
              ),
            ),
          ),
        ),
        if (!_isLoginMode) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              labelText: 'Confirm password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                ),
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _validateAndNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.of(context).violet,
              foregroundColor: AppTheme.of(context).onAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isSubmitting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.of(context).onAccent,
                    ),
                  )
                : Text(_isLoginMode ? 'Log In' : 'Create Account & Continue'),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _isLoginMode = !_isLoginMode),
            child: Text(
              _isLoginMode
                  ? 'Need an account? Sign Up'
                  : 'Already have an account? Log In',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBasicInfoStep() {
    return _buildScrollableStep(
      children: [
        const SizedBox(height: 18),
        Text(
          'Basic info',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppTheme.of(context).ink,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _firstNameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'First Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _lastNameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Last Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: 'Username',
            hintText: '@yourname',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        InkWell(
          onTap: _pickDob,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.of(context).muted),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _dob == null
                      ? 'Date of Birth'
                      : '${_dob!.day}/${_dob!.month}/${_dob!.year} (${_calculateAge(_dob!)} years)',
                ),
                const Icon(Icons.calendar_month),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _selectedGender,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Gender',
            hintText: 'How do you identify?',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Male', child: Text('Male')),
            DropdownMenuItem(value: 'Female', child: Text('Female')),
            DropdownMenuItem(value: 'Non-Binary', child: Text('Non-Binary')),
            DropdownMenuItem(
              value: 'Prefer not to say',
              child: Text('Prefer not to say'),
            ),
          ],
          onChanged: (value) {
            setState(() => _selectedGender = value);
          },
        ),
        const SizedBox(height: 14),
        InkWell(
          onTap: _pickCountry,
          borderRadius: BorderRadius.circular(18),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Country',
              hintText: 'Select your country',
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.public),
            ),
            child: Text(
              _selectedCountry ?? 'Select your country',
              style: TextStyle(
                color: _selectedCountry == null
                    ? AppTheme.of(context).muted
                    : AppTheme.of(context).ink,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _bioController,
          maxLength: 250,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Bio',
            hintText: 'Tell people a little about yourself...',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _goToPreviousStep,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _validateAndNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.of(context).violet,
                  foregroundColor: AppTheme.of(context).onAccent,
                ),
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSportsStep() {
    return _buildScrollableStep(
      children: [
        const SizedBox(height: 18),
        _buildChipSelector(
          title: 'Sports',
          options: _sportsOptions,
          selectedList: _selectedSports,
          onChanged: (val) => setState(() => _selectedSports = val),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _goToPreviousStep,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _validateAndNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.of(context).violet,
                  foregroundColor: AppTheme.of(context).onAccent,
                ),
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHobbiesStep() {
    return _buildScrollableStep(
      children: [
        const SizedBox(height: 18),
        _buildChipSelector(
          title: 'Hobbies',
          options: _hobbyOptions,
          selectedList: _selectedHobbies,
          onChanged: (val) => setState(() => _selectedHobbies = val),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _goToPreviousStep,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _validateAndNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.of(context).violet,
                  foregroundColor: AppTheme.of(context).onAccent,
                ),
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMusicStep() {
    return _buildScrollableStep(
      children: [
        const SizedBox(height: 18),
        _buildChipSelector(
          title: 'Music',
          options: _musicOptions,
          selectedList: _selectedMusic,
          onChanged: (val) => setState(() => _selectedMusic = val),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _goToPreviousStep,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _validateAndNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.of(context).violet,
                  foregroundColor: AppTheme.of(context).onAccent,
                ),
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLifestyleAndSocialStep() {
    return _buildScrollableStep(
      children: [
        const SizedBox(height: 18),
        _buildChipSelector(
          title: 'Lifestyle',
          options: _lifestyleOptions,
          selectedList: _selectedLifestyle,
          onChanged: (val) => setState(() => _selectedLifestyle = val),
        ),
        const SizedBox(height: 22),
        _buildChipSelector(
          title: 'Social vibe',
          options: _socialOptions,
          selectedList: _selectedSocialVibe,
          onChanged: (val) => setState(() => _selectedSocialVibe = val),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _goToPreviousStep,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _validateAndNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.of(context).violet,
                  foregroundColor: AppTheme.of(context).onAccent,
                ),
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLanguagesAndAvailabilityStep() {
    return _buildScrollableStep(
      children: [
        const SizedBox(height: 18),
        Text(
          'Languages',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _showLanguagePickerBottomSheet,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.of(context).muted),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedLanguages.isEmpty
                        ? 'Select Languages'
                        : 'Select Languages (${_selectedLanguages.length} selected)',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_selectedLanguages.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedLanguages.map((language) {
              return Chip(
                label: Text(language),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () => setState(() {
                  _selectedLanguages.remove(language);
                }),
              );
            }).toList(),
          ),
        const SizedBox(height: 22),
        _buildChipSelector(
          title: 'Availability',
          options: _availabilityOptions,
          selectedList: _selectedAvailability,
          onChanged: (val) => setState(() => _selectedAvailability = val),
          minSelections: 1,
          maxSelections: 6,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _goToPreviousStep,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _validateAndNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.of(context).violet,
                  foregroundColor: AppTheme.of(context).onAccent,
                ),
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMatchIntentStep() {
    return _buildScrollableStep(
      children: [
        const SizedBox(height: 18),
        _buildChipSelector(
          title: 'What brings you here?',
          options: _matchIntentOptions,
          selectedList: _selectedMatchIntent,
          onChanged: (val) => setState(() => _selectedMatchIntent = val),
          minSelections: 1,
          maxSelections: 5,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _goToPreviousStep,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _validateAndNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.of(context).violet,
                  foregroundColor: AppTheme.of(context).onAccent,
                ),
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep9Icebreakers() {
    final prompts = [
      "I'm looking for a friend who...",
      'My ideal way to spend a free afternoon with friends is...',
      'The fastest way to become my friend is...',
    ];

    return _buildScrollableStep(
      children: [
        const SizedBox(height: 18),
        Text(
          'Icebreakers / Prompts',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppTheme.of(context).ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Answer at least 2 prompts to help others get to know you.',
          style: TextStyle(color: AppTheme.of(context).muted),
        ),
        const SizedBox(height: 20),
        ...List.generate(prompts.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Prompt ${index + 1}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _icebreakerControllers[index],
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: prompts[index],
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _goToPreviousStep,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _validateAndNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.of(context).violet,
                  foregroundColor: AppTheme.of(context).onAccent,
                ),
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGalleryStep() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 18),
            Text(
              'Put a face to your name',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppTheme.of(context).ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start with a profile photo, then add 2–6 moments that feel like you.',
              style: TextStyle(color: AppTheme.of(context).muted),
            ),
            const SizedBox(height: 20),
            Center(
              child: GestureDetector(
                onTap: () {
                  final photo = _profileImage ?? _avatarFile;
                  if (photo == null) {
                    _pickAvatarImage();
                  } else {
                    showAvatarPreview(context, FileImage(File(photo.path)));
                  }
                },
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: AppTheme.of(context).surfaceMuted,
                      backgroundImage: _profileImage != null
                          ? FileImage(File(_profileImage!.path))
                          : (_avatarFile != null
                                ? FileImage(File(_avatarFile!.path))
                                : null),
                      child: (_profileImage == null && _avatarFile == null)
                          ? Icon(
                              Icons.person_outline_rounded,
                              size: 46,
                              color: AppTheme.of(context).violetStrong,
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: _pickAvatarImage,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.of(context).violet,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            size: 18,
                            color: AppTheme.of(context).onAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Profile photos',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.of(context).ink,
                  ),
                ),
                Text(
                  '${_galleryPhotos.length}/6',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.of(context).muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Add 2–6 photos. You can replace or remove them anytime.',
              style: TextStyle(color: AppTheme.of(context).muted),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 0.82,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: List.generate(6, (index) {
                final hasPhoto = index < _galleryPhotos.length;
                return GestureDetector(
                  onTap: () async {
                    if (hasPhoto) {
                      await _replaceGalleryPhoto(index);
                    } else {
                      await _pickGalleryImage();
                    }
                  },
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.of(context).surfaceMuted,
                          border: Border.all(color: AppTheme.of(context).line),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: hasPhoto
                            ? Image.file(
                                File(_galleryPhotos[index].path),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              )
                            : Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add_photo_alternate_outlined,
                                      size: 28,
                                      color: AppTheme.of(context).violetStrong,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Add photo',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.of(
                                          context,
                                        ).violetStrong,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      if (hasPhoto)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Remove photo ${index + 1}',
                              onPressed: () => _removeGalleryPhoto(index),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _goToPreviousStep,
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _validateAndNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.of(context).violet,
                      foregroundColor: AppTheme.of(context).onAccent,
                    ),
                    child: _isSubmitting
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.of(context).onAccent,
                            ),
                          )
                        : const Text('Complete Profile'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BrandedBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    if (_currentStep > 0)
                      IconButton(
                        onPressed: _goToPreviousStep,
                        icon: Icon(
                          Icons.arrow_back,
                          color: AppTheme.of(context).ink,
                        ),
                      )
                    else
                      const SizedBox(width: 48),
                    Expanded(
                      child: Column(
                        children: [
                          const BrandWordmark(),
                          const SizedBox(height: 2),
                          Text(
                            'Step ${_currentStep + 1} of $_totalSteps',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.of(context).muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: (_currentStep + 1) / _totalSteps,
                  minHeight: 4,
                  backgroundColor: AppTheme.of(context).surfaceMuted,
                  color: AppTheme.of(context).violet,
                  borderRadius: BorderRadius.circular(999),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (value) =>
                        setState(() => _currentStep = value),
                    children: [
                      _buildSignUpStep(),
                      _buildBasicInfoStep(),
                      _buildSportsStep(),
                      _buildHobbiesStep(),
                      _buildMusicStep(),
                      _buildLifestyleAndSocialStep(),
                      _buildLanguagesAndAvailabilityStep(),
                      _buildMatchIntentStep(),
                      _buildStep9Icebreakers(),
                      _buildGalleryStep(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
