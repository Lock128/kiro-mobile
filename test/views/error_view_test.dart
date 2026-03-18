import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiro_flutter_auth/views/error_view.dart';

void main() {
  group('ErrorView', () {
    testWidgets('displays the error message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ErrorView(message: 'Something went wrong'),
        ),
      );

      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('displays error icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ErrorView(message: 'Error occurred'),
        ),
      );

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows retry button when onRetry is provided', (tester) async {
      var retryCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: ErrorView(
            message: 'Try again',
            onRetry: () => retryCalled = true,
          ),
        ),
      );

      final retryButton = find.text('Retry');
      expect(retryButton, findsOneWidget);

      await tester.tap(retryButton);
      expect(retryCalled, isTrue);
    });

    testWidgets('hides retry button when onRetry is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ErrorView(message: 'No retry'),
        ),
      );

      expect(find.text('Retry'), findsNothing);
    });
  });
}
