import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Where a user stands on consent, in the terms the rest of the app asks about.
@immutable
class AdConsentResult {
  const AdConsentResult({
    required this.canRequestAds,
    required this.status,
    required this.privacyOptionsRequired,
    this.formShown = false,
    this.error,
  });

  /// Google's own gate, asked of the SDK rather than inferred: false until the
  /// consent state has been established.
  final bool canRequestAds;

  final ConsentStatus status;

  /// True when the "privacy options" entry point has to stay reachable, which
  /// is the case exactly where consent was gathered at all.
  final bool privacyOptionsRequired;

  /// Whether a form was put in front of the user during this call.
  final bool formShown;

  /// Why the update did not complete, when it did not. Never fatal: ads simply
  /// do not load.
  final String? error;
}

/// The consent half of AdMob.
///
/// Google requires a consent form before an ad is requested from someone in the
/// EEA, the UK or Switzerland, and requires that the choice stays changeable
/// afterwards. Both are what this wraps: [gather] for the form at startup,
/// [showPrivacyOptions] for the row in Settings that opens it again.
///
/// Nothing here decides whether to *show* an ad. It answers one question the ad
/// manager asks — `canRequestAds` — and every failure path answers no, because
/// the safe reading of "we could not reach the consent SDK" is not "assume the
/// user agreed".
class AdConsent {
  AdConsent._();

  static final AdConsent instance = AdConsent._();

  /// A second call this soon after the first would be another round trip for an
  /// answer that cannot have changed; a resume after a couple of minutes is a
  /// different matter.
  static const _retryWindow = Duration(seconds: 30);

  ConsentInformation get _information => ConsentInformation.instance;

  ConsentStatus _status = ConsentStatus.unknown;
  bool _canRequestAds = false;
  bool _privacyOptionsRequired = false;
  bool _formShown = false;
  DateTime? _lastAttempt;
  Future<AdConsentResult>? _inFlight;

  bool get canRequestAds => _canRequestAds;
  bool get privacyOptionsRequired => _privacyOptionsRequired;
  ConsentStatus get status => _status;

  AdConsentResult get _known => AdConsentResult(
        canRequestAds: _canRequestAds,
        status: _status,
        privacyOptionsRequired: _privacyOptionsRequired,
        formShown: _formShown,
      );

  /// Asks the consent SDK where this user stands, and puts the form in front of
  /// them when the answer is that one is required.
  ///
  /// Safe to call more than once — on a resume, say — because the second call
  /// inside [_retryWindow] returns what the first one found instead of asking
  /// again.
  Future<AdConsentResult> gather({ConsentDebugSettings? debugSettings, bool force = false}) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final lastAttempt = _lastAttempt;
    if (!force && lastAttempt != null && DateTime.now().difference(lastAttempt) < _retryWindow) {
      return Future.value(_known);
    }

    final future = _gather(debugSettings);
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<AdConsentResult> _gather(ConsentDebugSettings? debugSettings) async {
    _lastAttempt = DateTime.now();
    String? error;
    var formShown = false;

    try {
      final update = await _requestConsentInfoUpdate(
        ConsentRequestParameters(
          // The app is not directed at children and does not tag the user as
          // under the age of consent. Left explicit rather than defaulted, so
          // the claim is visible to whoever reviews the store listing.
          tagForUnderAgeOfConsent: false,
          consentDebugSettings: debugSettings,
        ),
      );
      error = update?.message;

      if (update == null) {
        final formAvailable = await _information.isConsentFormAvailable();
        // `required` is the only status that wants a form: `obtained` already
        // has an answer, and `notRequired` is a user outside every regime that
        // asks for one.
        if (formAvailable && await _information.getConsentStatus() == ConsentStatus.required) {
          formShown = await _showRequiredForm();
        }
      }
    } catch (e) {
      // No consent channel at all — a desktop build, or a device with no Play
      // services. There is nothing to ask and no ad to request either.
      error = '$e';
    }

    _formShown = _formShown || formShown;
    _canRequestAds = await _read(_information.canRequestAds, false);
    _status = await _read(_information.getConsentStatus, ConsentStatus.unknown);
    _privacyOptionsRequired = await _read(
      () async => await _information.getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required,
      false,
    );

    return AdConsentResult(
      canRequestAds: _canRequestAds,
      status: _status,
      privacyOptionsRequired: _privacyOptionsRequired,
      formShown: formShown,
      error: error,
    );
  }

  /// Opens the consent form again, from the Settings row.
  ///
  /// Returns whether the form was shown without an error. A user who is not in
  /// a region that asks for consent has no such row, so a failure here is a
  /// genuine failure rather than a missing form.
  Future<bool> showPrivacyOptions() async {
    if (!_privacyOptionsRequired) return false;
    try {
      final error = await _showPrivacyOptionsForm();
      return error == null;
    } catch (e) {
      debugPrint('[AdConsent] privacy options failed: $e');
      return false;
    }
  }

  Future<FormError?> _requestConsentInfoUpdate(ConsentRequestParameters parameters) {
    final completer = Completer<FormError?>();
    _information.requestConsentInfoUpdate(
      parameters,
      () {
        if (!completer.isCompleted) completer.complete(null);
      },
      (error) {
        debugPrint('[AdConsent] update failed: ${error.message}');
        if (!completer.isCompleted) completer.complete(error);
      },
    );
    return completer.future;
  }

  /// Shows the form the SDK says is required, and reports whether the user
  /// finished it rather than dismissing it.
  Future<bool> _showRequiredForm() {
    final completer = Completer<bool>();
    ConsentForm.loadConsentForm(
      (form) {
        form.show((error) {
          form.dispose();
          if (!completer.isCompleted) completer.complete(error == null);
        });
      },
      (loadError) {
        debugPrint('[AdConsent] form load failed: ${loadError.message}');
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    return completer.future;
  }

  Future<FormError?> _showPrivacyOptionsForm() {
    final completer = Completer<FormError?>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (!completer.isCompleted) completer.complete(error);
    });
    return completer.future;
  }

  Future<T> _read<T>(Future<T> Function() read, T fallback) async {
    try {
      return await read();
    } catch (_) {
      return fallback;
    }
  }
}
