import 'dart:io';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:image_picker/image_picker.dart';

class BasicProfileStepView extends StatelessWidget {
  const BasicProfileStepView({
    super.key,
    required this.firstNameController,
    required this.lastNameController,
    required this.usernameController,
    required this.bioController,
    required this.dateOfBirth,
    required this.onPickDate,
    required this.onPickAvatar,
    required this.onNext,
    required this.onBack,
    required this.avatarFile,
    required this.calculateAge,
  });

  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController usernameController;
  final TextEditingController bioController;
  final DateTime? dateOfBirth;
  final VoidCallback onPickDate;
  final VoidCallback onPickAvatar;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final XFile? avatarFile;
  final int Function(DateTime) calculateAge;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Profile essentials',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          Center(
            child: GestureDetector(
              onTap: onPickAvatar,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: AppTheme.of(context).line,
                    backgroundImage: avatarFile != null
                        ? FileImage(File(avatarFile!.path))
                        : null,
                    child: avatarFile == null
                        ? const Icon(
                            Icons.person,
                            size: 48,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        color: AppTheme.of(context).onAccent,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: firstNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'First Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: lastNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Last Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: usernameController,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              labelText: 'Username',
              hintText: '@username',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onPickDate,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dateOfBirth != null
                          ? 'Born: ${dateOfBirth!.day.toString().padLeft(2, '0')}/${dateOfBirth!.month.toString().padLeft(2, '0')}/${dateOfBirth!.year} (${calculateAge(dateOfBirth!)} years old)'
                          : 'Select Date of Birth',
                    ),
                    const Icon(Icons.calendar_month),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: bioController,
            minLines: 3,
            maxLines: 5,
            maxLength: 250,
            decoration: const InputDecoration(
              labelText: 'Bio',
              hintText: 'Write a short intro about yourself...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              OutlinedButton(onPressed: onBack, child: const Text('Back')),
              const Spacer(),
              ElevatedButton(onPressed: onNext, child: const Text('Next')),
            ],
          ),
        ],
      ),
    );
  }
}
