import 'package:bytequest/data/mission_content_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offline signup explains the device connection failure', () {
    const error = 'Exception: Sign up failed: ClientException with '
        'SocketException: Failed host lookup: project.supabase.co';

    expect(MissionContentData.signupFailureMessage(error),
        MissionContentData.signupNetworkUnavailableMessage);
  });

  test('signup feedback keeps account and server errors distinct', () {
    expect(
        MissionContentData.signupFailureMessage(
            'AuthException: User already registered'),
        MissionContentData.signupAlreadyRegisteredMessage);
    expect(
        MissionContentData.signupFailureMessage(
            'AuthException: email_address_invalid'),
        MissionContentData.signupInvalidEmailMessage);
    expect(
        MissionContentData.signupFailureMessage(
            'AuthException: Password is too weak'),
        MissionContentData.signupWeakPasswordMessage);
    expect(
        MissionContentData.signupFailureMessage(
            'Exception: Account provisioning is incomplete'),
        MissionContentData.signupProvisioningMessage);
    expect(
        MissionContentData.signupFailureMessage(
            'AuthException: signup_disabled'),
        MissionContentData.signupDisabledMessage);
    expect(MissionContentData.signupFailureMessage('unknown server failure'),
        MissionContentData.signupUnexpectedMessage);
  });
}
