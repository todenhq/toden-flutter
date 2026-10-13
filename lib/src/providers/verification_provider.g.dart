// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'verification_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$verificationConfigHash() => r'3b0c2919123014f7df4acbca4c31be0c2fbfd707';

/// See also [verificationConfig].
@ProviderFor(verificationConfig)
final verificationConfigProvider = Provider<VerificationConfig>.internal(
  verificationConfig,
  name: r'kycConfigProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$verificationConfigHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef VerificationConfigRef = ProviderRef<VerificationConfig>;
String _$kYCNotifierHash() => r'796041b8f77712c6d2e04171714f38b0ec0e5960';

/// See also [VerificationNotifier].
@ProviderFor(VerificationNotifier)
final kYCNotifierProvider = NotifierProvider<VerificationNotifier, VerificationState>.internal(
  VerificationNotifier.new,
  name: r'kYCNotifierProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$kYCNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$VerificationNotifier = Notifier<VerificationState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
