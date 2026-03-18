import 'package:flutter/material.dart';

import 'home_view.dart';
import 'sign_in_view.dart';

/// Non-web (iOS/Android) — returns the native views.
Widget buildSignInView() => const SignInView();
Widget buildContentView() => const HomeView();
