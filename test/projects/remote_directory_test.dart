import 'package:android_ssh_codex/src/projects/remote_directory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('joins Linux and Windows remote paths', () {
    expect(remotePathChild('/srv', 'app'), '/srv/app');
    expect(remotePathChild('/', 'srv'), '/srv');
    expect(remotePathChild(r'C:\Users', 'owner'), r'C:\Users\owner');
    expect(remotePathChild('C:/Users', 'owner'), 'C:/Users/owner');
  });

  test('finds Linux and Windows parent directories', () {
    expect(remotePathParent('/srv/app'), '/srv');
    expect(remotePathParent('/srv'), '/');
    expect(remotePathParent('/'), isNull);
    expect(remotePathParent(r'C:\Users\owner'), 'C:/Users');
    expect(remotePathParent('C:/Users'), 'C:/');
    expect(remotePathParent('C:/'), isNull);
    expect(remotePathParent('relative'), '.');
  });
}
