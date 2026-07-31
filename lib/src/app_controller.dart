import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'profiles/host_profile.dart';
import 'profiles/profile_store.dart';
import 'protocol/codex_remote_api.dart';
import 'protocol/json_rpc_client.dart';
import 'protocol/websocket_rpc_transport.dart';
import 'tasks/task_reducer.dart';
import 'transport/codex_daemon.dart';
import 'transport/ssh_connector.dart';
import 'transport/ssh_unix_tunnel.dart';

enum AppSection { hosts, tasks }

enum RemoteConnectionPhase { disconnected, connecting, connected, reconnecting }

final class AppController extends ChangeNotifier {
  AppController({required ProfileStore store})
      : _store = store,
        _connector = SshConnector(store);

  factory AppController.memory() => AppController(store: MemoryProfileStore());

  final ProfileStore _store;
  final SshConnector _connector;
  final TaskReducer _taskReducer = TaskReducer();

  List<HostProfile> _profiles = const [];
  AppSection _section = AppSection.hosts;
  RemoteConnectionPhase _connectionPhase = RemoteConnectionPhase.disconnected;
  String? _selectedHostId;
  String? _selectedTaskId;
  String? _activeTurnId;
  String? _error;
  HostKeyChallenge? _hostKeyChallenge;
  Completer<bool>? _hostKeyCompleter;
  List<PendingApproval> _approvals = const [];
  Set<String> _ownedThreadIds = {};
  Set<String> _loadedThreadIds = {};
  SshConnection? _ssh;
  SshUnixTunnel? _tunnel;
  JsonRpcClient? _rpc;
  CodexRemoteApi? _api;
  StreamSubscription<RpcNotification>? _notificationSubscription;
  StreamSubscription<RpcServerRequest>? _requestSubscription;
  Timer? _refreshTimer;
  var _epoch = 0;
  var _refreshing = false;
  var _refreshQueued = false;

  List<HostProfile> get profiles => _profiles;
  AppSection get section => _section;
  RemoteConnectionPhase get connectionPhase => _connectionPhase;
  String? get selectedHostId => _selectedHostId;
  String? get selectedTaskId => _selectedTaskId;
  String? get error => _error;
  HostKeyChallenge? get hostKeyChallenge => _hostKeyChallenge;
  List<PendingApproval> get approvals => _approvals;
  TaskState get taskState => _taskReducer.state;

  HostProfile? get selectedHost =>
      _profiles.where((profile) => profile.id == _selectedHostId).firstOrNull;

  TaskRecord? get selectedTask => _selectedTaskId == null
      ? null
      : _taskReducer.state.tasks[_selectedTaskId];

  bool get isConnected => _connectionPhase == RemoteConnectionPhase.connected;

  Future<void> initialize() async {
    _profiles = await _store.readProfiles();
    notifyListeners();
  }

  void selectSection(AppSection section) {
    if (_section == section) return;
    _section = section;
    notifyListeners();
  }

  Future<void> saveProfile(HostProfile profile, HostSecret secret) async {
    await _store.writeProfile(profile, secret);
    _profiles = await _store.readProfiles();
    _selectedHostId = profile.id;
    notifyListeners();
  }

  Future<void> deleteProfile(String id) async {
    if (_selectedHostId == id) await disconnect();
    await _store.deleteProfile(id);
    _profiles = await _store.readProfiles();
    notifyListeners();
  }

  Future<HostSecret> readSecret(String id) => _store.readSecret(id);

  Future<void> connectHost(HostProfile profile) async {
    await disconnect();
    _selectedHostId = profile.id;
    _connectionPhase = RemoteConnectionPhase.connecting;
    _error = null;
    _section = AppSection.tasks;
    notifyListeners();

    try {
      final secret = await _store.readSecret(profile.id);
      _ownedThreadIds = await _store.readOwnedThreads(profile.id);
      _ssh = await _connector.connect(
        profile,
        secret,
        prompt: _promptForHostKey,
      );
      final output = utf8.decode(
        await _ssh!.client.run(CodexDaemon.bootstrapScript),
        allowMalformed: true,
      );
      final socketPath = output
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.endsWith('app-server.sock'))
          .lastOrNull;
      if (socketPath == null) {
        throw StateError('Remote Codex app-server did not report its socket.');
      }
      _tunnel = await SshUnixTunnel.start(_ssh!.client, socketPath);
      final transport = await WebSocketRpcTransport.connect(
        Uri.parse('ws://127.0.0.1:${_tunnel!.localPort}/'),
      );
      _rpc = JsonRpcClient(transport)..start();
      _api = CodexRemoteApi(_rpc!);
      _notificationSubscription =
          _api!.notifications.listen(_handleNotification);
      _requestSubscription = _api!.serverRequests.listen(_handleServerRequest);
      await _api!.initialize();
      _epoch = _taskReducer.beginConnection();
      _connectionPhase = RemoteConnectionPhase.connected;
      await refreshTasks();
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(refreshTasks()),
      );
    } catch (exception) {
      _error = _friendlyError(exception);
      _connectionPhase = RemoteConnectionPhase.disconnected;
      await _closeTransport();
    }
    notifyListeners();
  }

  Future<bool> _promptForHostKey(HostKeyChallenge challenge) async {
    _hostKeyCompleter?.complete(false);
    final completer = Completer<bool>();
    _hostKeyCompleter = completer;
    _hostKeyChallenge = challenge;
    notifyListeners();
    return completer.future;
  }

  void answerHostKey(bool accepted) {
    final completer = _hostKeyCompleter;
    _hostKeyCompleter = null;
    _hostKeyChallenge = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(accepted);
    }
    notifyListeners();
  }

  Future<void> refreshTasks() async {
    if (_api == null || !isConnected) return;
    if (_refreshing) {
      _refreshQueued = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshQueued = false;
        final token = _taskReducer.beginRefresh(_epoch);
        final batch = await _api!.readTaskBatch();
        _loadedThreadIds = batch.loadedThreadIds;
        final ownedAndLoaded =
            batch.loadedThreadIds.intersection(_ownedThreadIds);
        _taskReducer.applyRefresh(token, batch.tasks, ownedAndLoaded);
        notifyListeners();
      } while (_refreshQueued && isConnected);
    } catch (exception) {
      _error = _friendlyError(exception);
      notifyListeners();
    } finally {
      _refreshing = false;
    }
  }

  Future<void> selectTask(String taskId) async {
    _selectedTaskId = taskId;
    _section = AppSection.tasks;
    notifyListeners();
    if (_api == null) return;
    try {
      final detail = await _api!.readThread(taskId);
      final snapshots = _taskReducer.state.tasks.values
          .map(_snapshotFromRecord)
          .where((task) => task.id != taskId)
          .followedBy([detail]).toList(growable: false);
      final token = _taskReducer.beginRefresh(_epoch);
      _taskReducer.applyRefresh(
        token,
        snapshots,
        _loadedThreadIds.intersection(_ownedThreadIds),
      );
      notifyListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      notifyListeners();
    }
  }

  void clearSelectedTask() {
    _selectedTaskId = null;
    notifyListeners();
  }

  Future<void> startNewTask(
      {required String cwd, required String prompt}) async {
    final api = _requireApi();
    final threadId = await api.startThread(cwd: cwd);
    await _claimThread(threadId);
    _selectedTaskId = threadId;
    _taskReducer.applyEvent(
      _epoch,
      TaskEvent.statusChanged(threadId, TaskStatus.running),
    );
    notifyListeners();
    await api.startTurn(threadId, prompt);
    await refreshTasks();
  }

  Future<void> sendPrompt(String prompt) async {
    final api = _requireApi();
    final task = selectedTask;
    if (task == null) throw StateError('Select or create a task first.');
    if (!task.canWrite) {
      throw StateError('This running task is owned by another Codex client.');
    }
    if (!_ownedThreadIds.contains(task.id)) {
      await api.resumeThread(task.id);
      await _claimThread(task.id);
    }
    await api.startTurn(task.id, prompt);
    _taskReducer.applyEvent(
      _epoch,
      TaskEvent.statusChanged(task.id, TaskStatus.running),
    );
    notifyListeners();
  }

  Future<void> interruptSelectedTask() async {
    final task = selectedTask;
    if (task == null || !task.canWrite || _activeTurnId == null) return;
    await _requireApi().interruptTurn(task.id, _activeTurnId!);
  }

  void answerApproval(PendingApproval approval, String decision) {
    _api?.answerApproval(approval.requestId, decision);
    _approvals = _approvals
        .where((item) => item.requestId != approval.requestId)
        .toList(growable: false);
    notifyListeners();
  }

  Future<void> _claimThread(String threadId) async {
    _ownedThreadIds = {..._ownedThreadIds, threadId};
    final hostId = _selectedHostId;
    if (hostId != null) {
      await _store.writeOwnedThreads(hostId, _ownedThreadIds);
    }
  }

  void _handleNotification(RpcNotification notification) {
    final event = CodexRemoteApi.parseNotification(
      notification.method,
      notification.params,
    );
    if (event != null) _taskReducer.applyEvent(_epoch, event);
    if (notification.method == 'turn/started') {
      final turn = notification.params['turn'];
      if (turn is Map) _activeTurnId = turn['id'] as String?;
    } else if (notification.method == 'turn/completed') {
      _activeTurnId = null;
      unawaited(refreshTasks());
    }
    notifyListeners();
  }

  void _handleServerRequest(RpcServerRequest request) {
    if (!request.method.contains('requestApproval')) {
      _rpc?.respondError(request.id, -32601, 'Unsupported server request');
      return;
    }
    final approval = CodexRemoteApi.parseApproval(request);
    _approvals = [..._approvals, approval];
    notifyListeners();
  }

  CodexRemoteApi _requireApi() {
    final api = _api;
    if (api == null || !isConnected) {
      throw StateError('Connect to a host first.');
    }
    return api;
  }

  Future<void> disconnect() async {
    _connectionPhase = RemoteConnectionPhase.disconnected;
    _selectedTaskId = null;
    _activeTurnId = null;
    _approvals = const [];
    _hostKeyCompleter?.complete(false);
    _hostKeyCompleter = null;
    _hostKeyChallenge = null;
    await _closeTransport();
    notifyListeners();
  }

  Future<void> _closeTransport() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _notificationSubscription?.cancel();
    await _requestSubscription?.cancel();
    _notificationSubscription = null;
    _requestSubscription = null;
    await _rpc?.close();
    _rpc = null;
    _api = null;
    await _tunnel?.close();
    _tunnel = null;
    await _ssh?.close();
    _ssh = null;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    unawaited(_closeTransport());
    super.dispose();
  }
}

TaskSnapshot _snapshotFromRecord(TaskRecord record) => TaskSnapshot(
      id: record.id,
      title: record.title,
      status: record.status,
      cwd: record.cwd,
      updatedAt: record.updatedAt,
      items: record.items,
    );

String _friendlyError(Object exception) {
  if (exception is RpcRemoteException) return exception.message;
  final text = exception.toString();
  return text.replaceFirst(
      RegExp(r'^(Exception|StateError|ArgumentError):\s*'), '');
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }

  T? get lastOrNull {
    T? result;
    var found = false;
    for (final item in this) {
      result = item;
      found = true;
    }
    return found ? result : null;
  }
}
