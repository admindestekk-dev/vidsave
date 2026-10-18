import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/user_identity_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('identity is a stable UUID per installation', () async {
    final first = await UserIdentityService.getOrCreateUserId();
    final second = await UserIdentityService.getOrCreateUserId();

    expect(
      first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(second, first);
  });

  test(
    'clearing identity causes a new installation id to be generated',
    () async {
      final first = await UserIdentityService.getOrCreateUserId();
      await UserIdentityService.clearUserId();

      final next = await UserIdentityService.getOrCreateUserId();

      expect(next, isNot(first));
    },
  );
}
