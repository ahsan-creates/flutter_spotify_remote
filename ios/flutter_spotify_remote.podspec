#
# Run `pod lib lint flutter_spotify_remote.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_spotify_remote'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for Spotify App Remote SDK'
  s.description      = <<-DESC
    Flutter plugin wrapping Spotify App Remote SDK for iOS and Android.
    Supports playback control and player state subscription.
    Uses CocoaPods for the SpotifyiOS framework — no bundled xcframework.
  DESC
  s.homepage         = 'https://github.com/ahsan-creates/flutter_spotify_remote'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Your Name' => 'you@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency         'Flutter'
  # Pull SpotifyiOS from CocoaPods — avoids the xcframework conflict in spotify_sdk
  s.dependency         'SpotifyiOS', '~> 5.0.1'
  s.platform         = :ios, '14.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_VERSION'  => '5.0',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version    = '5.0'
end
