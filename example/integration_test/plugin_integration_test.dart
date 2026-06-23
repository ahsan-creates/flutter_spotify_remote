import 'package:flutter_spotify_remote/flutter_spotify_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FlutterSpotifyRemote instance is accessible',
      (WidgetTester tester) async {
    final plugin = FlutterSpotifyRemote.instance;
    expect(plugin, isNotNull);
  });
}
