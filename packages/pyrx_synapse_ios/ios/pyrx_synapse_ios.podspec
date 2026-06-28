#
# pyrx_synapse_ios.podspec — CocoaPods spec for the iOS implementation of
# the PYRX Synapse Flutter SDK.
#
# Customers never edit this file directly. `flutter pub get` resolves
# `pyrx_synapse` → `pyrx_synapse_ios`, which causes Flutter's iOS tooling
# to add this Pod to the customer's Podfile automatically.
#
# Dependency policy per plan D2: pin a minimum on the published
# PYRXSynapse 0.1.x line. Allow patch and minor bumps within 0.1.x but
# pin major to avoid surprise breakage when PYRXSynapse goes to 1.0.
#
Pod::Spec.new do |s|
  s.name             = 'pyrx_synapse_ios'
  s.version          = '0.1.0'
  s.summary          = 'iOS implementation of the PYRX Synapse Flutter SDK.'
  s.description      = <<-DESC
Bridges Dart calls in the PYRX Synapse Flutter plugin to the PYRXSynapse
Swift SDK from CocoaPods Trunk, and forwards the SDK's AsyncStream observer
surface to Dart through Pigeon-generated event channels.
                       DESC
  s.homepage         = 'https://github.com/PYRX-Tech/pyrx-synapse-flutter'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'PYRX Tech' => 'sdk@pyrx.tech' }
  s.source           = { :path => '.' }

  s.source_files     = 'Classes/**/*.{swift,h,m}'
  s.public_header_files = 'Classes/**/*.h'
  s.swift_version    = '5.9'

  s.dependency 'Flutter'
  # Pin to >= 0.1.2 (the Phase 9.2.1 observer-surface release) and below 1.0.
  s.dependency 'PYRXSynapse', '>= 0.1.2', '< 1.0.0'

  s.ios.deployment_target = '14.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
