import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_spotify_remote_example/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const SpotifyExampleApp());
    expect(find.byType(SpotifyExampleApp), findsOneWidget);
  });
}
