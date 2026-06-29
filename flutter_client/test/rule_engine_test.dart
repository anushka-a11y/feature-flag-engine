import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/flag_service.dart';

void main() {
  group('Feature Flag Rule Evaluation Tests', () {
    late FlagSnapshot snapshot;

    setUp(() {
      snapshot = FlagSnapshot(
        flags: [
          const FeatureFlag(
            id: 'new_checkout_flow',
            enabled: true,
            rule: 'Beta Users Only',
            rolloutPercentage: 100,
          ),
          const FeatureFlag(
            id: 'dark_mode_beta',
            enabled: true,
            rule: 'Everyone',
            rolloutPercentage: 100,
          ),
          const FeatureFlag(
            id: 'ai_recommendations',
            enabled: true,
            rule: 'Everyone',
            rolloutPercentage: 10,
          ),
          const FeatureFlag(
            id: 'disabled_flag',
            enabled: false,
            rule: 'Everyone',
            rolloutPercentage: 100,
          ),
        ],
        configs: [],
        fetchedAt: DateTime.now(),
      );
    });

    test('Disabled flag is always disabled', () {
      final user = const UserContext(userId: 'alice', isBeta: true);
      expect(snapshot.isEnabled('disabled_flag', user), isFalse);
    });

    test('Rule: Everyone is enabled for everyone', () {
      final alice = const UserContext(userId: 'alice', isBeta: true);
      final bob = const UserContext(userId: 'bob', isBeta: false);
      expect(snapshot.isEnabled('dark_mode_beta', alice), isTrue);
      expect(snapshot.isEnabled('dark_mode_beta', bob), isTrue);
    });

    test('Rule: Beta Users Only is only enabled for beta users', () {
      final alice = const UserContext(userId: 'alice', isBeta: true);
      final bob = const UserContext(userId: 'bob', isBeta: false);
      expect(snapshot.isEnabled('new_checkout_flow', alice), isTrue);
      expect(snapshot.isEnabled('new_checkout_flow', bob), isFalse);
    });

    test('Rollout: 10% is deterministic based on hash', () {
      // 'alice' has hash 0 for 'ai_recommendations' -> enabled (< 10)
      final alice = const UserContext(userId: 'alice', isBeta: false);
      // 'bob' has hash 25 for 'ai_recommendations' -> disabled (>= 10)
      final bob = const UserContext(userId: 'bob', isBeta: false);

      expect(snapshot.isEnabled('ai_recommendations', alice), isTrue);
      expect(snapshot.isEnabled('ai_recommendations', bob), isFalse);
    });

    test('Default user context fallback (anonymous, non-beta)', () {
      // No context provided:
      // new_checkout_flow (Beta Users Only) -> should be false
      expect(snapshot.isEnabled('new_checkout_flow'), isFalse);
      
      // dark_mode_beta (Everyone) -> should be true
      expect(snapshot.isEnabled('dark_mode_beta'), isTrue);
    });
  });
}
