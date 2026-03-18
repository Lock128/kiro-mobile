import 'package:flutter/material.dart';

import 'content_view.dart';
import 'sign_in_view.dart';

/// Non-web (iOS/Android) — returns the native WebView-based views.
/// These are the defaults, so this stub just returns the standard widgets.
Widget buildSignInView() => const SignInView();
Widget buildContentView() => const ContentView();
