import 'package:flutter/material.dart';

import 'content_view_web.dart';
import 'sign_in_view_web.dart';

/// Web platform — returns iframe-based views instead of WebView.
Widget buildSignInView() => const SignInViewWeb();
Widget buildContentView() => const ContentViewWeb();
