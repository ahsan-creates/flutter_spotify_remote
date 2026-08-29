#
# Run `pod lib lint flutter_spotify_remote.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_spotify_remote'
  s.version          = '0.0.4'
  s.summary          = 'Flutter plugin for Spotify App Remote SDK'
  s.description      = <<-DESC
    Flutter plugin wrapping the Spotify App Remote SDK for iOS and Android.
    Supports playback control, player state subscription, and OAuth with
    silent token refresh. The SpotifyiOS xcframework (v5.0.1) is vendored,
    so no extra CocoaPods source is required in the host app.
  DESC
  s.homepage         = 'https://github.com/ahsan-creates/flutter_spotify_remote'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Ahsan Khalil' => 'https://github.com/ahsan-creates' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.vendored_frameworks = 'Frameworks/SpotifyiOS.xcframework'
  s.dependency         'Flutter'
  s.platform         = :ios, '14.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_VERSION'  => '5.0',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version    = '5.0'
end
