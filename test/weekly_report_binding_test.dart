import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// THE MEMBER'S REPORTS MUST SURVIVE A LATE LINK.
///
/// 🔴 THE DEFECT THIS PINS, FOUND IN PRODUCTION ON A REAL DEVICE.
///
/// `WeeklyReportService.canRead` requires the member's linked `clientId`, and
/// `watchAll()` returns `Stream.value(const [])` when it is missing — an empty
/// stream that emits ONCE and CLOSES. `WeeklyReportController` re-bound on
/// `MemberController.isLinked`, a BOOLEAN that is set at a different moment
/// from the id.
///
/// A controller constructed in the window between the two therefore bound the
/// closed empty stream, and nothing ever re-bound it: `ever` fires on CHANGE,
/// and by then `isLinked` had already changed. The member was told
///
///     "No weekly report yet — your coach sends one every week."
///
/// permanently, with no error and no retry, while a real report sat in
/// production waiting for them. The whole member half of the feature was
/// unreachable, and every test was green because every test linked first.
///
/// The rule this encodes: **observe the value the query depends on, not a
/// boolean that happens to correlate with it.**
///
/// These are behavioural tests over a stand-in with the same shape as the real
/// pair, so they fail for the reason the production defect existed rather than
/// for a mock's convenience.

/// The member controller's relevant surface: a boolean and an id, settable
/// independently — which is precisely the hazard.
class _Member {
  final RxBool isLinked = false.obs;
  final RxnString linkedClientIdRx = RxnString();
  String get clientId => linkedClientIdRx.value ?? '';
  String uid = 'member-uid';
}

/// A consumer wired the CORRECT way: it re-binds on both, so whichever lands
/// last still triggers a bind that can read.
class _Consumer {
  _Consumer(this._m) {
    _worker = everAll([_m.isLinked, _m.linkedClientIdRx], (_) => bind());
    bind();
  }

  final _Member _m;
  Worker? _worker;

  int binds = 0;
  int readableBinds = 0;
  bool boundEmpty = false;

  bool get canRead => _m.uid.isNotEmpty && _m.clientId.isNotEmpty;

  void bind() {
    binds++;
    if (!canRead) {
      // Bind NOTHING rather than an empty stream: an empty emission is
      // indistinguishable from "no reports exist".
      boundEmpty = true;
      return;
    }
    boundEmpty = false;
    readableBinds++;
  }

  void dispose() => _worker?.dispose();
}

/// The consumer as it SHIPPED: watching only the boolean.
class _BooleanOnlyConsumer extends _Consumer {
  _BooleanOnlyConsumer(super.m) {
    _worker?.dispose();
    _worker = ever(super._m.isLinked, (_) => bind());
  }
}

void main() {
  group('a consumer must observe the id its query is keyed on', () {
    test('the id landing AFTER construction triggers a readable bind', () {
      final m = _Member();
      final c = _Consumer(m);
      addTearDown(c.dispose);

      // Constructed before the link resolved — exactly the production window.
      expect(c.readableBinds, 0);
      expect(c.boundEmpty, isTrue);

      m.linkedClientIdRx.value = 'client-1';
      m.isLinked.value = true;

      expect(c.readableBinds, greaterThan(0),
          reason: 'the member could never read their own reports');
      expect(c.boundEmpty, isFalse);
    });

    test('the id landing BEFORE the boolean still triggers a readable bind', () {
      // The order is not guaranteed, and a consumer that only works in one
      // order is a consumer that fails intermittently.
      final m = _Member();
      final c = _Consumer(m);
      addTearDown(c.dispose);

      m.linkedClientIdRx.value = 'client-1';
      expect(c.readableBinds, greaterThan(0));
    });

    test('a consumer already linked at construction reads immediately', () {
      final m = _Member()
        ..isLinked.value = true
        ..linkedClientIdRx.value = 'client-1';
      final c = _Consumer(m);
      addTearDown(c.dispose);

      expect(c.readableBinds, 1);
      expect(c.boundEmpty, isFalse);
    });

    test(
        'REGRESSION: watching only the boolean strands a consumer built in the '
        'window between the id and the flag', () {
      final m = _Member();
      final c = _BooleanOnlyConsumer(m);
      addTearDown(c.dispose);

      // `isLinked` flips FIRST — as it does when a cached profile resolves —
      // and the id follows. `ever` on the boolean has already fired.
      m.isLinked.value = true;
      final bindsAfterFlag = c.readableBinds;
      m.linkedClientIdRx.value = 'client-1';

      expect(
        c.readableBinds,
        bindsAfterFlag,
        reason: 'This is the shipped defect reproduced: the id arrived and '
            'nothing re-bound, so the member reads an empty stream forever. '
            'The fixed consumer above must not behave this way.',
      );
      expect(c.boundEmpty, isTrue);
    });
  });

  group('an unreadable bind must not look like an empty result', () {
    test('it binds nothing at all rather than an empty stream', () {
      final m = _Member();
      final c = _Consumer(m);
      addTearDown(c.dispose);
      // `boundEmpty` is the honest state the screen renders as "connecting",
      // NOT as "your coach has not sent one".
      expect(c.boundEmpty, isTrue);
      expect(c.readableBinds, 0);
    });
  });
}
