// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_new_run_form.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MobileNewRunForm)
final mobileNewRunFormProvider = MobileNewRunFormFamily._();

final class MobileNewRunFormProvider
    extends $NotifierProvider<MobileNewRunForm, NewRunDraft> {
  MobileNewRunFormProvider._({
    required MobileNewRunFormFamily super.from,
    required (String, {String? workspaceId}) super.argument,
  }) : super(
         retry: null,
         name: r'mobileNewRunFormProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileNewRunFormHash();

  @override
  String toString() {
    return r'mobileNewRunFormProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileNewRunForm create() => MobileNewRunForm();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NewRunDraft value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NewRunDraft>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileNewRunFormProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileNewRunFormHash() => r'a53555c5dcc16e8faa04a93632cab5a37a969a1c';

final class MobileNewRunFormFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileNewRunForm,
          NewRunDraft,
          NewRunDraft,
          NewRunDraft,
          (String, {String? workspaceId})
        > {
  MobileNewRunFormFamily._()
    : super(
        retry: null,
        name: r'mobileNewRunFormProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileNewRunFormProvider call(String hostId, {String? workspaceId}) =>
      MobileNewRunFormProvider._(
        argument: (hostId, workspaceId: workspaceId),
        from: this,
      );

  @override
  String toString() => r'mobileNewRunFormProvider';
}

abstract class _$MobileNewRunForm extends $Notifier<NewRunDraft> {
  late final _$args = ref.$arg as (String, {String? workspaceId});
  String get hostId => _$args.$1;
  String? get workspaceId => _$args.workspaceId;

  NewRunDraft build(String hostId, {String? workspaceId});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<NewRunDraft, NewRunDraft>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<NewRunDraft, NewRunDraft>,
              NewRunDraft,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, workspaceId: _$args.workspaceId),
    );
  }
}
