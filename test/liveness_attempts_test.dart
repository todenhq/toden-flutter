import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/liveness_attempts.dart';
import 'package:toden_flutter/src/config/session_declined.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/config/workflow_merge.dart';
import 'package:toden_flutter/src/providers/verification_provider.dart';
import 'package:toden_flutter/src/providers/verification_state.dart';
import 'package:toden_flutter/src/screens/liveness_attempts_left.dart';
import 'package:toden_flutter/src/services/api_service.dart';
import 'package:toden_flutter/src/services/verification_error_mapper.dart';
import 'package:toden_flutter/src/widgets/icons/icons.dart';

// A workflow's maxLivenessAttempts (1 to 3) has the SDK report each failed
// liveness check to POST /api/kyc/liveness/failed. The server answers how many
// attempts are left, or declines the session at the limit: 409
// session_declined with reasonCode liveness_attempts_exceeded. Anything else
// is ignored, so Try Again works as before.

const _title = "We couldn't verify your face";
const _body =
    'The face check did not succeed in the attempts allowed, so this verification has ended. Contact the organisation that sent it if you need help.';
const _serverMessage = 'You used all your attempts at the face check.';

VerificationApiException _declined(
        {String? reason = kLivenessAttemptsExceeded, String? message}) =>
    VerificationApiException(
      statusCode: 409,
      error: kSessionDeclinedCode,
      message: message,
      details: reason == null
          ? null
          : errorDetailsFrom(
              409, {'error': kSessionDeclinedCode, 'reasonCode': reason}),
    );

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body, {this.status = 200});
  final Object body;
  final int status;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

VerificationApiService _api(_Adapter adapter) => VerificationApiService(
      baseUrl: 'https://api.example',
      apiKey: 'pk_test_x',
      httpClientAdapter: adapter,
    );

class _StubApi extends VerificationApiService {
  _StubApi() : super(baseUrl: 'http://stub', apiKey: 'pk_test_stub');

  @override
  Future<SessionStartResponse> startSession({
    String? externalUserId,
    String? workflowId,
    String? deviceRef,
    Map<String, dynamic>? device,
  }) async =>
      const SessionStartResponse(sessionId: 'hs_test', resumed: false);

  @override
  Future<void> saveProgress(
      String sessionId, Map<String, dynamic> progress) async {}
}

void main() {
  group('the workflow setting', () {
    const base = VerificationConfig(apiKey: 'pk_test_x', country: 'NG');

    test('reads 1 to 3, caps a larger number, is off only for false', () {
      expect(maxLivenessAttemptsFrom(1), 1);
      expect(maxLivenessAttemptsFrom(3), 3);
      expect(maxLivenessAttemptsFrom(2.0), 2);
      expect(maxLivenessAttemptsFrom(5), 3);
      expect(maxLivenessAttemptsFrom(false), isNull);
      for (final raw in [null, 0, -1, 1.5, '2', true]) {
        expect(maxLivenessAttemptsFrom(raw), 3, reason: '$raw');
      }
    });

    test('reaches the config from the workflow; absent means 3', () {
      expect(base.maxLivenessAttempts, isNull);
      final limited = mergeWorkflowIntoConfig(
        base,
        const WorkflowFlowConfig(raw: {'maxLivenessAttempts': 2}),
      );
      expect(limited.maxLivenessAttempts, 2);
      final unset =
          mergeWorkflowIntoConfig(base, const WorkflowFlowConfig(raw: {}));
      expect(unset.maxLivenessAttempts, 3);
      final off = mergeWorkflowIntoConfig(
        base,
        const WorkflowFlowConfig(raw: {'maxLivenessAttempts': false}),
      );
      expect(off.maxLivenessAttempts, isNull);
    });
  });

  group('the answer', () {
    test('maps each body the server sends', () {
      expect(LivenessFailedResponse.fromJson({'limited': false}),
          LivenessFailedResponse.unlimited);
      expect(
        LivenessFailedResponse.fromJson({'limited': true, 'attemptsLeft': 2}),
        const LivenessFailedResponse(limited: true, attemptsLeft: 2),
      );
      expect(
        LivenessFailedResponse.fromJson({'limited': true, 'attemptsLeft': 0}),
        const LivenessFailedResponse(limited: true, attemptsLeft: 0),
      );
      expect(LivenessFailedResponse.fromJson(null),
          LivenessFailedResponse.unlimited);
      expect(LivenessFailedResponse.fromJson({}),
          LivenessFailedResponse.unlimited);
      expect(
        LivenessFailedResponse.fromJson({'limited': true, 'attemptsLeft': 'x'}),
        const LivenessFailedResponse(limited: true),
      );
    });

    test('posts the session and country to the liveness endpoint', () async {
      final adapter = _Adapter({'limited': true, 'attemptsLeft': 1});
      final res = await _api(adapter)
          .reportLivenessFailed(sessionId: 'hs_1', country: 'GH');
      expect(res, const LivenessFailedResponse(limited: true, attemptsLeft: 1));
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/api/kyc/liveness/failed');
      expect(req.data, {'sessionId': 'hs_1', 'country': 'GH'});
      expect(req.headers['Authorization'], 'Bearer pk_test_x');
    });

    test('leaves out what the flow does not have', () async {
      final adapter = _Adapter({'limited': false});
      await _api(adapter).reportLivenessFailed(country: '');
      expect(adapter.requests.single.data, <String, dynamic>{});
    });

    test('a 409 decline surfaces as session_declined with its reason',
        () async {
      final adapter = _Adapter({
        'error': kSessionDeclinedCode,
        'reasonCode': kLivenessAttemptsExceeded,
        'message': _serverMessage,
      }, status: 409);
      Object? thrown;
      try {
        await _api(adapter).reportLivenessFailed(sessionId: 'hs_1');
      } catch (e) {
        thrown = e;
      }
      expect(isSessionDeclinedError(thrown), isTrue);
      final words = sessionDeclinedFor(thrown)!;
      expect(words.title, _title);
      expect(words.message, _serverMessage);
      expect(words.reasonCode, kLivenessAttemptsExceeded);
    });
  });

  group('the attempts-left line', () {
    test('says how many are left, singular and plural', () {
      expect(
          livenessAttemptsLeftLine(
              const LivenessFailedResponse(limited: true, attemptsLeft: 1)),
          '1 attempt left.');
      expect(
          livenessAttemptsLeftLine(
              const LivenessFailedResponse(limited: true, attemptsLeft: 2)),
          '2 attempts left.');
    });

    test('says nothing with no limit, none left, or no answer', () {
      expect(
          livenessAttemptsLeftLine(LivenessFailedResponse.unlimited), isNull);
      expect(
          livenessAttemptsLeftLine(
              const LivenessFailedResponse(limited: true, attemptsLeft: 0)),
          isNull);
      expect(
          livenessAttemptsLeftLine(const LivenessFailedResponse(limited: true)),
          isNull);
      expect(livenessAttemptsLeftLine(null), isNull);
    });

    Future<void> pumpNotice(WidgetTester tester, UiColorScheme scheme) =>
        tester.pumpWidget(MaterialApp(
          theme: ThemeData(extensions: [scheme]),
          home: const Scaffold(
              body: LivenessAttemptsLeft(text: '2 attempts left.')),
        ));

    BoxDecoration pill(WidgetTester tester) => tester
        .widget<Container>(find.descendant(
            of: find.byType(LivenessAttemptsLeft),
            matching: find.byType(Container)))
        .decoration! as BoxDecoration;

    testWidgets('is a small warning: real text in the body colour, not red',
        (tester) async {
      await pumpNotice(tester, UiColorScheme.light);
      expect(find.text('2 attempts left.'), findsOneWidget);
      final words = tester.widget<Text>(find.text('2 attempts left.'));
      expect(words.style!.color, UiColorScheme.light.textDark);
      expect(words.style!.color, isNot(UiColors.error));
      expect(pill(tester).color, UiColorScheme.light.warningBg);
      final glyph = tester.widget<UiIcon>(find.byType(UiIcon));
      expect(glyph.icon, UiIcons.triangleAlert);
      expect(glyph.semanticLabel, isNull);
    });

    testWidgets('takes the dark warning tint in a dark theme', (tester) async {
      await pumpNotice(tester, UiColorScheme.dark);
      expect(pill(tester).color, UiColorScheme.dark.warningBg);
      final words = tester.widget<Text>(find.text('2 attempts left.'));
      expect(words.style!.color, UiColorScheme.dark.textDark);
      expect(tester.widget<UiIcon>(find.byType(UiIcon)).color,
          UiColors.warning);
    });
  });

  group('the report', () {
    test('with no limit, nothing is reported', () async {
      var calls = 0;
      final line = await reportFailedLivenessCheck(
        maxAttempts: null,
        report: () async {
          calls++;
          return LivenessFailedResponse.unlimited;
        },
        onDeclined: (_) => fail('no decline'),
      );
      expect(line, isNull);
      expect(calls, 0);
    });

    test('reports once and answers the line', () async {
      var calls = 0;
      final line = await reportFailedLivenessCheck(
        maxAttempts: 3,
        report: () async {
          calls++;
          return const LivenessFailedResponse(limited: true, attemptsLeft: 2);
        },
        onDeclined: (_) => fail('no decline'),
      );
      expect(line, '2 attempts left.');
      expect(calls, 1);
    });

    test('a decline ends the flow; it is not retried', () async {
      var calls = 0;
      final declines = <Object>[];
      final line = await reportFailedLivenessCheck(
        maxAttempts: 1,
        report: () async {
          calls++;
          throw _declined();
        },
        onDeclined: declines.add,
      );
      expect(line, isNull);
      expect(calls, 1);
      expect(declines.single, isA<VerificationApiException>());
    });

    test('any other failure is ignored, once', () async {
      for (final failure in <Object>[
        const VerificationApiException(statusCode: 0, error: 'network_error'),
        const VerificationApiException(
            statusCode: 500, error: 'internal_error'),
        const VerificationApiException(
            statusCode: 409, error: 'session_cancelled'),
        StateError('boom'),
      ]) {
        var calls = 0;
        final line = await reportFailedLivenessCheck(
          maxAttempts: 2,
          report: () async {
            calls++;
            throw failure;
          },
          onDeclined: (_) => fail('no decline for $failure'),
        );
        expect(line, isNull);
        expect(calls, 1);
      }
    });
  });

  group('the declined screen', () {
    test('names the face check, whatever channel is known', () {
      for (final channel in [null, 'email', 'phone']) {
        final words = sessionDeclinedFor(_declined(), channel: channel)!;
        expect(words.title, _title);
        expect(words.message, _body);
      }
    });

    test('the body is the server message when it sent one', () {
      expect(sessionDeclinedFor(_declined(message: _serverMessage))!.message,
          _serverMessage);
      expect(sessionDeclinedFor(_declined(message: '  '))!.message, _body);
    });

    test('the submission maps the decline to its own code and words', () {
      final e =
          mapToVerificationError(_declined(), context: ErrorContext.verify);
      expect(e.code, kSessionDeclinedCode);
      expect(e.message, _body);
    });

    test('the flow ends on it from the liveness step', () {
      final c = ProviderContainer(overrides: [
        verificationConfigProvider.overrideWithValue(
          const VerificationConfig(
              apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              country: 'NG',
              consentStep: false),
        ),
        verificationApiServiceProvider.overrideWithValue(_StubApi()),
        preloadedServerConfigProvider.overrideWithValue(
            const ServerSdkConfig(status: ServerConfigStatus.ready)),
        kYCNotifierProvider.overrideWith(VerificationNotifier.new),
      ]);
      addTearDown(c.dispose);
      expect(
          c.read(kYCNotifierProvider.notifier).endOnSessionRefusal(_declined()),
          isTrue);
      expect(
          c.read(kYCNotifierProvider).sessionDeclined,
          const SessionDeclined(
            title: _title,
            message: _body,
            reasonCode: kLivenessAttemptsExceeded,
          ));
    });

    test('no copy carries an em dash', () {
      for (final copy in [
        _title,
        _body,
        '1 attempt left.',
        '2 attempts left.'
      ]) {
        expect(copy.contains('—'), isFalse);
      }
    });
  });
}
