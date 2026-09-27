import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return android;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCO-6bDHFfR-Iz-VVEQhd6QCnYzG-14jy4',
    appId: '1:757149925404:android:7aabb15e68c85037e29fd9',
    messagingSenderId: '757149925404',
    projectId: 'amicupapp-33722',
    storageBucket: 'amicupapp-33722.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAGJCzttZjLx6PlE3orLzEhCSr14pNwbuA',
    appId: '1:757149925404:ios:72650eb6ef38af47e29fd9',
    messagingSenderId: '757149925404',
    projectId: 'amicupapp-33722',
    storageBucket: 'amicupapp-33722.firebasestorage.app',
    iosBundleId: 'com.example.amicupApp',
  );
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'YOUR_MACOS_API_KEY',
    appId: '1:000000000000:macos:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'amicup-app',
    storageBucket: 'amicup-app.appspot.com',
    iosBundleId: 'com.example.amicupApp',
  );
}
