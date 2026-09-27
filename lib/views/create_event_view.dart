import 'dart:io';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../viewmodels/events_view_model.dart';

class CreateEventView extends StatefulWidget {
  const CreateEventView({super.key, this.eventToEdit});

  final EventModel? eventToEdit;

  @override
  State<CreateEventView> createState() => _CreateEventViewState();
}

class _CreateEventViewState extends State<CreateEventView> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _maxAttendeesController = TextEditingController();
  final _registrationLinkController = TextEditingController();
  final _imagePicker = ImagePicker();

  File? _selectedImage;
  String _category = 'Hangout';
  DateTime _startTime = DateTime.now().add(const Duration(hours: 1));
  DateTime? _endTime;
  bool _isUploading = false;

  bool get _isEditing => widget.eventToEdit != null;

  @override
  void initState() {
    super.initState();
    final event = widget.eventToEdit;
    if (event == null) return;
    _titleController.text = event.title;
    _locationController.text = event.locationName;
    _descriptionController.text = event.description;
    _maxAttendeesController.text = event.maxAttendees?.toString() ?? '';
    _registrationLinkController.text = event.registrationLink ?? '';
    _category = event.category;
    _startTime = event.startTime;
    _endTime = event.endTime;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _maxAttendeesController.dispose();
    _registrationLinkController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1920,
    );
    if (image == null || !mounted) return;
    setState(() => _selectedImage = File(image.path));
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart
        ? _startTime
        : (_endTime ?? _startTime.add(const Duration(hours: 2)));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isStart) {
        _startTime = selected;
        if (_endTime != null && _endTime!.isBefore(selected)) {
          _endTime = selected.add(const Duration(hours: 1));
        }
      } else {
        _endTime = selected;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_endTime != null && !_endTime!.isAfter(_startTime)) {
      _showMessage('End time must be after the start time.');
      return;
    }
    final viewModel = context.read<EventsViewModel>();
    String? coverImageUrl = widget.eventToEdit?.coverImageUrl;
    if (_selectedImage != null) {
      setState(() => _isUploading = true);
      coverImageUrl = await viewModel.uploadCoverImage(_selectedImage!);
      if (!mounted) return;
      setState(() => _isUploading = false);
      if (coverImageUrl == null) {
        _showMessage(viewModel.errorMessage ?? 'Unable to upload cover image.');
        return;
      }
    }
    final event = widget.eventToEdit;
    final success = event == null
        ? await viewModel.createEvent(
            title: _titleController.text,
            category: _category,
            locationName: _locationController.text,
            description: _descriptionController.text,
            coverImageUrl: coverImageUrl,
            maxAttendees: int.tryParse(_maxAttendeesController.text.trim()),
            registrationLink: _registrationLinkController.text,
            startTime: _startTime,
            endTime: _endTime,
          )
        : await viewModel.updateEvent(
            eventId: event.id,
            title: _titleController.text,
            category: _category,
            locationName: _locationController.text,
            description: _descriptionController.text,
            coverImageUrl: coverImageUrl,
            maxAttendees: int.tryParse(_maxAttendeesController.text.trim()),
            registrationLink: _registrationLinkController.text,
            startTime: _startTime,
            endTime: _endTime,
          );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      _showMessage(viewModel.errorMessage ?? 'Unable to save event.');
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final saving = context.watch<EventsViewModel>().isCreating || _isUploading;
    return Scaffold(
      backgroundColor: AppTheme.of(context).canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _isEditing ? 'Edit event' : 'Create event',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            children: [
              Text(
                _isEditing ? 'Keep the plan fresh' : 'Bring people together',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.of(context).ink,
                ),
              ),
              const SizedBox(height: 20),
              _CoverPicker(
                localImage: _selectedImage,
                imageUrl: widget.eventToEdit?.coverImageUrl,
                onTap: saving ? null : _pickCoverImage,
              ),
              const SizedBox(height: 18),
              _field(
                controller: _titleController,
                label: 'Title',
                icon: Icons.title_rounded,
                validator: (value) => value == null || value.trim().length < 3
                    ? 'Enter an event title.'
                    : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: _decoration('Category', Icons.category_outlined),
                items: const ['Party', 'Sports', 'Networking', 'Hangout']
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: saving
                    ? null
                    : (value) => setState(() => _category = value!),
              ),
              const SizedBox(height: 14),
              _field(
                controller: _registrationLinkController,
                label: 'Registration Link (Optional)',
                hintText: 'Registration Link (Optional)',
                icon: Icons.link,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 14),
              _field(
                controller: _locationController,
                label: 'Location name',
                icon: Icons.location_on_outlined,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a location.'
                    : null,
              ),
              const SizedBox(height: 14),
              _field(
                controller: _descriptionController,
                label: 'Description',
                icon: Icons.notes_rounded,
                maxLines: 4,
                validator: (value) => value == null || value.trim().length < 10
                    ? 'Add a little more detail.'
                    : null,
              ),
              const SizedBox(height: 14),
              _field(
                controller: _maxAttendeesController,
                label: 'Max attendees (optional)',
                icon: Icons.groups_outlined,
                keyboardType: TextInputType.number,
                validator: _validateMaxAttendees,
              ),
              const SizedBox(height: 20),
              _dateTile(
                'Starts',
                _startTime,
                () => _pickDateTime(isStart: true),
              ),
              const SizedBox(height: 10),
              _dateTile(
                'Ends (optional)',
                _endTime,
                () => _pickDateTime(isStart: false),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: saving ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.of(context).violet,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: saving
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.of(context).surface,
                        ),
                      )
                    : Text(
                        _isEditing ? 'Save Changes' : 'Create Event',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _validateMaxAttendees(String? value) {
    if (value == null || value.isEmpty) return null;
    final maximum = int.tryParse(value);
    return maximum == null || maximum < 1 ? 'Enter a positive number.' : null;
  }

  Widget _dateTile(
    String label,
    DateTime? value,
    VoidCallback onTap,
  ) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(24),
    child: Ink(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.of(context).line),
        borderRadius: BorderRadius.circular(24),
        color: AppTheme.of(context).surface,
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_month_outlined,
            color: AppTheme.of(context).violetStrong,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.of(context).muted,
                  ),
                ),
                Text(
                  value == null
                      ? 'Select date and time'
                      : '${MaterialLocalizations.of(context).formatFullDate(value)}, ${TimeOfDay.fromDateTime(value).format(context)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hintText,
    required IconData icon,
    String? Function(String?)? validator,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) => TextFormField(
    controller: controller,
    validator: validator,
    maxLines: maxLines,
    keyboardType: keyboardType,
    decoration: _decoration(label, icon).copyWith(hintText: hintText),
  );
  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    filled: true,
    fillColor: AppTheme.of(context).surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(color: AppTheme.of(context).line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(color: AppTheme.of(context).line),
    ),
  );
}

class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.localImage,
    required this.imageUrl,
    required this.onTap,
  });
  final File? localImage;
  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        decoration: BoxDecoration(
          color: AppTheme.of(context).surfaceMuted,
          borderRadius: BorderRadius.circular(24),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (localImage != null)
                Image.file(localImage!, fit: BoxFit.cover)
              else if (imageUrl != null && imageUrl!.isNotEmpty)
                Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _CoverPlaceholder(),
                )
              else
                const _CoverPlaceholder(),
              Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xDD211A30),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 17,
                        color: AppTheme.of(context).surface,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Change Image',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          AppTheme.of(context).coverStart,
          AppTheme.of(context).coverEnd,
        ],
      ),
    ),
    child: Center(
      child: Icon(
        Icons.add_photo_alternate_outlined,
        size: 48,
        color: AppTheme.of(context).surface,
      ),
    ),
  );
}
