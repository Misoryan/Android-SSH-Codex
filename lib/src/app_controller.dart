import 'dart:async';

import 'package:flutter/foundation.dart';

import 'profiles/host_profile.dart';
import 'profiles/profile_store.dart';
import 'projects/remote_project.dart';
import 'protocol/codex_remote_api.dart';
import 'protocol/json_rpc_client.dart';
import 'protocol/websocket_rpc_transport.dart';
import 'tasks/task_catalog.dart';
import 'tasks/task_reducer.dart';
import 'transport/codex_daemon.dart';
import 'transport/ssh_connector.dart';
import 'transport/ssh_unix_tunnel.dart';

enum AppSection { hosts, tasks }

enum RemoteConnectionPhase { disconnected, connecting, connected, reconnecting }

enum ConnectionStage {
  profile,
  ssh,
  remoteAppServer,
  unixTunnel,
  rpcTunnel,
  initialize,
  refresh,
}

HostProfile? resolveAutoConnectProfile(
  List<HostProfile> profiles,
  String? profileId,
) {
  if (profileId == null) return null;
  return profiles.where((profile) => profile.id == profileId).firstOrNull;
}

Future<String> resolveCodexSocketForProfile(
  SshCommandRunner run,
  HostProfile profile,
) async {
  switch (profile.appServerMode) {
    case AppServerMode.shared:
      return CodexDaemon.startShared(
        run,
        environment: profile.environment,
      );
    case AppServerMode.custom:
      final configuredSocketPath = profile.customAppServerSocket;
      if (configuredSocketPath == null ||
          RegExp(r'[\x00-\x1F\x7F]').hasMatch(configuredSocketPath)) {
        throw const CodexBootstrapException(
          'Custom app-server socket must be an absolute Unix socket path.',
        );
      }
      final socketPath = configuredSocketPath.trim();
      if (socketPath.isEmpty || !socketPath.startsWith('/')) {
        throw const CodexBootstrapException(
          'Custom app-server socket must be an absolute Unix socket path.',
        );
      }
      return socketPath;
    case AppServerMode.isolated:
      return CodexDaemon.bootstrap(
        run,
        environment: profile.environment,
      );
  }
}

final class AppController extends ChangeNotifier {
  AppController({required ProfileStore store})
      : _store = store,
        _connector = SshConnector(store);

  factory AppController.memory() => AppController(store: MemoryProfileStore());

  final ProfileStore _store;
  final SshConnector _connector;
  final TaskReducer _taskReducer = TaskReducer();
  final TaskCatalog _taskCatalog = TaskCatalog();
  final TaskHistoryLoadState _historyLoadState = TaskHistoryLoadState();

  List<HostProfile> _profiles = const [];
  List<RemoteProject> _projects = const [];
  AppSection _section = AppSection.hosts;
  RemoteConnectionPhase _connectionPhase = RemoteConnectionPhase.disconnected;
  String? _selectedHostId;
  String? _selectedProjectId;
  String? _selectedTaskId;
  final Map<String, String> _activeTurnIds = {};
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
  Timer? _reconnectTimer;
  var _epoch = 0;
  var _connectionAttempt = 0;
  var _reconnectAttempt = 0;
  var _refreshing = false;
  var _refreshQueued = false;
  var _refreshQueuedResetPages = false;
  var _loadingProjectPage = false;
  var _loadingUnassignedPage = false;
  Future<void> _autoConnectIntentWrite = Future.value();

  List<HostProfile> get profiles => _profiles;
  List<RemoteProject> get projects => _projects;
  AppSection get section => _section;
  RemoteConnectionPhase get connectionPhase => _connectionPhase;
  String? get selectedHostId => _selectedHostId;
  String? get selectedProjectId => _selectedProjectId;
  String? get selectedTaskId => _selectedTaskId;
  String? get error => _error;
  HostKeyChallenge? get hostKeyChallenge => _hostKeyChallenge;
  List<PendingApproval> get approvals => _approvals;
  TaskState get taskState => _taskReducer.state;
  bool get unassignedExpanded => _taskCatalog.unassignedExpanded;
  bool get hasMoreProjectTasks => _taskCatalog.projectNextCursor != null;
  bool get hasMoreUnassignedTasks => _taskCatalog.unassignedNextCursor != null;
  bool get isLoadingProjectPage => _loadingProjectPage;
  bool get isLoadingUnassignedPage => _loadingUnassignedPage;
  bool get hasOlderTaskContext =>
      _historyLoadState.taskId == _selectedTaskId && _historyLoadState.hasOlder;
  bool get isLoadingOlderTaskContext =>
      _historyLoadState.taskId == _selectedTaskId &&
      _historyLoadState.isLoadingOlder;
  String? get olderTaskContextError =>
      _historyLoadState.taskId == _selectedTaskId
          ? _historyLoadState.olderError
          : null;

  HostProfile? get selectedHost =>
      _profiles.where((profile) => profile.id == _selectedHostId).firstOrNull;

  RemoteProject? get selectedProject => _selectedProjectId == null
      ? null
      : _projects
          .where((project) => project.id == _selectedProjectId)
          .firstOrNull;

  List<TaskRecord> get projectTasks =>
      _tasksForIds(_taskCatalog.projectTaskIds);

  List<TaskRecord> get unassignedTasks =>
      _tasksForIds(_taskCatalog.unassignedTaskIds);

  TaskRecord? get selectedTask => _selectedTaskId == null
      ? null
      : _taskReducer.state.tasks[_selectedTaskId];

  bool get isConnected => _connectionPhase == RemoteConnectionPhase.connected;

  bool isTaskDetailLoading(String taskId) =>
      _historyLoadState.taskId == taskId && _historyLoadState.isInitialLoading;

  String? taskDetailError(String taskId) => _historyLoadState.taskId == taskId
      ? _historyLoadState.initialError
      : null;

  Future<void> initialize() async {
    HostProfile? autoConnectProfile;
    try {
      _profiles = await _store.readProfiles();
      autoConnectProfile = resolveAutoConnectProfile(
        _profiles,
        await _store.readAutoConnectHostId(),
      );
    } catch (exception) {
      _profiles = const [];
      _error = 'Could not read secure storage: $exception';
    }
    notifyListeners();
    if (autoConnectProfile != null) {
      unawaited(connectHost(autoConnectProfile));
    }
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
    final attempt = ++_connectionAttempt;
    _cancelHostKeyPrompt();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    await _closeTransport();
    if (attempt != _connectionAttempt) return;
    _epoch = _taskReducer.beginConnection();
    await _openConnection(profile, attempt: attempt, reconnecting: false);
  }

  Future<void> _openConnection(
    HostProfile profile, {
    required int attempt,
    required bool reconnecting,
  }) async {
    _selectedHostId = profile.id;
    if (!reconnecting) _selectedTaskId = null;
    _connectionPhase = reconnecting
        ? RemoteConnectionPhase.reconnecting
        : RemoteConnectionPhase.connecting;
    _error = null;
    _section = AppSection.tasks;
    notifyListeners();

    SshConnection? ssh;
    SshUnixTunnel? tunnel;
    JsonRpcClient? rpc;
    StreamSubscription<RpcNotification>? notifications;
    StreamSubscription<RpcServerRequest>? requests;
    var published = false;
    var stage = ConnectionStage.profile;
    try {
      final secret = await _store.readSecret(profile.id);
      final ownedThreadIds = await _store.readOwnedThreads(profile.id);
      final projects =
          reconnecting ? _projects : await _store.readProjects(profile.id);
      if (attempt != _connectionAttempt) return;
      if (!reconnecting) {
        _projects = projects;
        _selectedProjectId = projects.firstOrNull?.id;
        _taskCatalog.clear();
        _historyLoadState.clear();
      }
      stage = ConnectionStage.ssh;
      ssh = await _connector.connect(
        profile,
        secret,
        prompt: _promptForHostKey,
      );
      stage = ConnectionStage.remoteAppServer;
      final client = ssh.client;
      final socketPath = await resolveCodexSocketForProfile(
        (command, {environment}) async {
          final result = await client.runWithResult(
            command,
            environment: environment,
          );
          return SshCommandResult(
            stdout: result.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            exitSignal: result.exitSignal?.signalName,
          );
        },
        profile,
      );
      if (attempt != _connectionAttempt) return;
      stage = ConnectionStage.unixTunnel;
      tunnel = await SshUnixTunnel.start(
        ssh.client,
        socketPath,
        environment: profile.environment,
      );
      stage = ConnectionStage.rpcTunnel;
      final tunnelFailure = tunnel.firstFailure.then<WebSocketRpcTransport>(
        (_) => throw StateError(
          'Remote Codex tunnel stopped without reporting a failure.',
        ),
      );
      final transport = await Future.any<WebSocketRpcTransport>([
        WebSocketRpcTransport.connect(
          Uri.parse('ws://127.0.0.1:${tunnel.localPort}/'),
        ),
        tunnelFailure,
      ]);
      rpc = JsonRpcClient(transport)..start();
      final api = CodexRemoteApi(rpc);
      notifications = api.notifications.listen(
        (notification) => _handleNotification(attempt, notification),
      );
      requests = api.serverRequests.listen(
        (request) => _handleServerRequest(attempt, request),
      );
      stage = ConnectionStage.initialize;
      await api.initialize();
      if (attempt != _connectionAttempt) return;

      _ssh = ssh;
      _tunnel = tunnel;
      _rpc = rpc;
      _api = api;
      _notificationSubscription = notifications;
      _requestSubscription = requests;
      _ownedThreadIds = ownedThreadIds;
      _loadedThreadIds = {};
      published = true;
      unawaited(rpc.done.then((_) => _handleTransportLoss(attempt, profile)));
      stage = ConnectionStage.refresh;
      await refreshTasks(throwOnError: true, resetPages: true);
      if (attempt != _connectionAttempt) return;
      _connectionPhase = RemoteConnectionPhase.connected;
      _reconnectAttempt = 0;
      await _rememberAutoConnectHost(profile.id);
      if (attempt != _connectionAttempt) return;
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => unawaited(refreshTasks()),
      );
    } catch (exception, stackTrace) {
      if (attempt != _connectionAttempt) return;
      debugPrint(
        'Connection failed during ${stage.name} for '
        '${profile.hostName}:${profile.port}: $exception',
      );
      debugPrintStack(stackTrace: stackTrace);
      _error = describeConnectionFailure(stage, exception, profile);
      if (published) await _closeTransport();
      if (reconnecting) {
        _connectionPhase = RemoteConnectionPhase.reconnecting;
        _scheduleReconnect(profile, attempt);
      } else {
        _connectionPhase = RemoteConnectionPhase.disconnected;
      }
    } finally {
      if (!published) {
        await notifications?.cancel();
        await requests?.cancel();
        await rpc?.close();
        await tunnel?.close();
        await ssh?.close();
      }
    }
    notifyListeners();
  }

  Future<void> _handleTransportLoss(int attempt, HostProfile profile) async {
    if (attempt != _connectionAttempt ||
        _connectionPhase != RemoteConnectionPhase.connected) {
      return;
    }
    _connectionPhase = RemoteConnectionPhase.reconnecting;
    _error = 'Remote connection lost. Reconnecting...';
    notifyListeners();
    await _closeTransport();
    if (attempt == _connectionAttempt) _scheduleReconnect(profile, attempt);
  }

  void _scheduleReconnect(HostProfile profile, int attempt) {
    if (attempt != _connectionAttempt || _reconnectTimer != null) return;
    const delays = [1, 2, 4, 8, 15];
    final delayIndex = _reconnectAttempt < delays.length
        ? _reconnectAttempt
        : delays.length - 1;
    final seconds = delays[delayIndex];
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      if (attempt != _connectionAttempt) return;
      final nextAttempt = ++_connectionAttempt;
      _epoch = _taskReducer.beginConnection(clearTasks: false);
      unawaited(_openConnection(
        profile,
        attempt: nextAttempt,
        reconnecting: true,
      ));
    });
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

  void _cancelHostKeyPrompt() {
    final completer = _hostKeyCompleter;
    _hostKeyCompleter = null;
    _hostKeyChallenge = null;
    if (completer != null && !completer.isCompleted) completer.complete(false);
  }

  Future<void> refreshTasks({
    bool throwOnError = false,
    bool resetPages = false,
  }) async {
    final api = _api;
    final epoch = _epoch;
    final connecting = _connectionPhase == RemoteConnectionPhase.connecting ||
        _connectionPhase == RemoteConnectionPhase.reconnecting;
    if (api == null || (!isConnected && !connecting)) return;
    if (_refreshing) {
      _refreshQueued = true;
      _refreshQueuedResetPages = _refreshQueuedResetPages || resetPages;
      return;
    }
    _refreshing = true;
    var resetNext = resetPages;
    try {
      do {
        final shouldResetPages = resetNext;
        resetNext = false;
        _refreshQueued = false;
        _refreshQueuedResetPages = false;
        final project = selectedProject;
        final selectedProjectId = project?.id;
        final token = _taskReducer.beginRefresh(epoch);
        final loadedFuture = api.readLoadedThreadIds();
        final unassignedFuture = api.readTaskPage();
        final projectFuture = project == null
            ? Future<RemoteTaskPage?>.value()
            : api.readTaskPage(cwd: project.cwd);
        final loadedThreadIds = await loadedFuture;
        final unassignedPage = await unassignedFuture;
        final projectPage = await projectFuture;
        if (api != _api || epoch != _epoch) return;
        if (selectedProjectId != _selectedProjectId) {
          resetNext = true;
          continue;
        }
        final snapshots = <String, TaskSnapshot>{
          for (final task in unassignedPage.tasks) task.id: task,
          if (projectPage != null)
            for (final task in projectPage.tasks) task.id: task,
        };
        final loadedByUs = loadedThreadIds.intersection(_ownedThreadIds);
        _loadedThreadIds = loadedThreadIds;
        _taskReducer.applyRefresh(
          token,
          snapshots.values.toList(growable: false),
          loadedByUs,
          retainExisting: !shouldResetPages,
        );
        if (projectPage == null) {
          _taskCatalog.clearProjectPage();
        } else if (shouldResetPages) {
          _taskCatalog.replaceProjectPage(
            projectPage.tasks,
            nextCursor: projectPage.nextCursor,
          );
        } else {
          _taskCatalog.mergeProjectHead(
            projectPage.tasks,
            nextCursor: projectPage.nextCursor,
          );
        }
        if (shouldResetPages) {
          _taskCatalog.replaceUnassignedPage(
            unassignedPage.tasks,
            projects: _projects,
            nextCursor: unassignedPage.nextCursor,
          );
        } else {
          _taskCatalog.mergeUnassignedHead(
            unassignedPage.tasks,
            projects: _projects,
            nextCursor: unassignedPage.nextCursor,
          );
        }
        notifyListeners();
        if (_refreshQueued) {
          resetNext = _refreshQueuedResetPages;
        }
      } while (_refreshQueued && isConnected);
    } catch (exception) {
      if (throwOnError) rethrow;
      _error = _friendlyError(exception);
      notifyListeners();
    } finally {
      _refreshing = false;
    }
  }

  Future<void> selectTask(String taskId) async {
    _selectedTaskId = taskId;
    _section = AppSection.tasks;
    _taskReducer.replaceItems(_epoch, taskId, const []);
    await _loadInitialTaskContext(taskId);
  }

  void clearSelectedTask() {
    _selectedTaskId = null;
    _historyLoadState.clear();
    notifyListeners();
  }

  Future<void> retrySelectedTaskDetails() async {
    final taskId = _selectedTaskId;
    if (taskId != null) await _loadInitialTaskContext(taskId);
  }

  Future<void> _loadInitialTaskContext(String taskId) async {
    final api = _api;
    final epoch = _epoch;
    if (api == null || !isConnected) return;
    final token = _historyLoadState.beginInitial(taskId);
    notifyListeners();
    try {
      final page = await api.readThreadTurnsPage(taskId);
      if (api != _api || epoch != _epoch) return;
      if (!_historyLoadState.complete(token, nextCursor: page.nextCursor)) {
        return;
      }
      _taskReducer.prependItems(epoch, taskId, page.items);
    } catch (exception) {
      if (api != _api || epoch != _epoch) return;
      _historyLoadState.fail(token, _friendlyError(exception));
    }
    notifyListeners();
  }

  Future<void> loadOlderSelectedTaskContext() async {
    final api = _api;
    final epoch = _epoch;
    if (api == null || !isConnected) return;
    final token = _historyLoadState.beginOlder();
    if (token == null) return;
    notifyListeners();
    try {
      final page = await api.readThreadTurnsPage(
        token.taskId,
        cursor: token.cursor,
      );
      if (api != _api || epoch != _epoch || token.taskId != _selectedTaskId) {
        return;
      }
      if (!_historyLoadState.complete(token, nextCursor: page.nextCursor)) {
        return;
      }
      _taskReducer.prependItems(epoch, token.taskId, page.items);
    } catch (exception) {
      if (api != _api || epoch != _epoch) return;
      _historyLoadState.fail(token, _friendlyError(exception));
    }
    notifyListeners();
  }

  Future<void> selectProject(String? projectId) async {
    if (projectId != null &&
        !_projects.any((project) => project.id == projectId)) {
      return;
    }
    if (_selectedProjectId == projectId) return;
    _selectedProjectId = projectId;
    _selectedTaskId = null;
    _historyLoadState.clear();
    _taskCatalog.clearProjectPage();
    notifyListeners();
    await refreshTasks(resetPages: true);
  }

  Future<void> saveProject({
    String? projectId,
    required String name,
    required String cwd,
  }) async {
    final hostId = _selectedHostId;
    if (hostId == null) throw StateError('Connect to a host first.');
    final normalizedName = name.trim();
    final normalizedCwd = normalizeRemoteCwd(cwd);
    if (normalizedName.isEmpty || normalizedCwd.isEmpty) {
      throw ArgumentError('Project name and remote directory are required.');
    }
    final matchingCwd = _projects
        .where((project) => normalizeRemoteCwd(project.cwd) == normalizedCwd)
        .firstOrNull;
    final id = projectId ??
        matchingCwd?.id ??
        '$hostId-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    await _store.writeProject(
      RemoteProject(
        id: id,
        hostId: hostId,
        name: normalizedName,
        cwd: normalizedCwd,
      ),
    );
    _projects = await _store.readProjects(hostId);
    _selectedProjectId = id;
    _selectedTaskId = null;
    _historyLoadState.clear();
    _taskCatalog.clearProjectPage();
    notifyListeners();
    await refreshTasks(resetPages: true);
  }

  Future<void> deleteProject(String projectId) async {
    final hostId = _selectedHostId;
    if (hostId == null) return;
    await _store.deleteProject(hostId, projectId);
    _projects = await _store.readProjects(hostId);
    if (_selectedProjectId == projectId) {
      _selectedProjectId = _projects.firstOrNull?.id;
      _selectedTaskId = null;
      _historyLoadState.clear();
      _taskCatalog.clearProjectPage();
    }
    notifyListeners();
    await refreshTasks(resetPages: true);
  }

  void toggleUnassigned() {
    _taskCatalog.toggleUnassigned();
    notifyListeners();
  }

  Future<void> loadMoreProjectTasks() async {
    final api = _api;
    final project = selectedProject;
    final cursor = _taskCatalog.projectNextCursor;
    final epoch = _epoch;
    if (api == null ||
        !isConnected ||
        project == null ||
        cursor == null ||
        _loadingProjectPage) {
      return;
    }
    _loadingProjectPage = true;
    notifyListeners();
    try {
      final page = await api.readTaskPage(cwd: project.cwd, cursor: cursor);
      if (api != _api || epoch != _epoch || project.id != _selectedProjectId) {
        return;
      }
      final token = _taskReducer.beginRefresh(epoch);
      _taskReducer.applyRefresh(
        token,
        page.tasks,
        _loadedThreadIds.intersection(_ownedThreadIds),
        retainExisting: true,
      );
      _taskCatalog.appendProjectPage(
        page.tasks,
        nextCursor: page.nextCursor,
      );
    } catch (exception) {
      _error = _friendlyError(exception);
    } finally {
      _loadingProjectPage = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreUnassignedTasks() async {
    final api = _api;
    final cursor = _taskCatalog.unassignedNextCursor;
    final epoch = _epoch;
    if (api == null ||
        !isConnected ||
        cursor == null ||
        _loadingUnassignedPage) {
      return;
    }
    _loadingUnassignedPage = true;
    notifyListeners();
    try {
      final page = await api.readTaskPage(cursor: cursor);
      if (api != _api || epoch != _epoch) return;
      final token = _taskReducer.beginRefresh(epoch);
      _taskReducer.applyRefresh(
        token,
        page.tasks,
        _loadedThreadIds.intersection(_ownedThreadIds),
        retainExisting: true,
      );
      _taskCatalog.appendUnassignedPage(
        page.tasks,
        projects: _projects,
        nextCursor: page.nextCursor,
      );
    } catch (exception) {
      _error = _friendlyError(exception);
    } finally {
      _loadingUnassignedPage = false;
      notifyListeners();
    }
  }

  Future<void> startNewTask(
      {required String cwd, required String prompt}) async {
    final api = _requireApi();
    final attempt = _connectionAttempt;
    final epoch = _epoch;
    final profileId = _selectedHostId!;
    final threadId = await api.startThread(cwd: cwd);
    if (!_isCurrentSession(api, attempt, epoch, profileId)) return;
    if (!await _claimThread(
      threadId,
      api: api,
      attempt: attempt,
      epoch: epoch,
      profileId: profileId,
    )) {
      return;
    }
    _loadedThreadIds = {..._loadedThreadIds, threadId};
    _selectedTaskId = threadId;
    _taskReducer.applyEvent(
      _epoch,
      TaskEvent.statusChanged(threadId, TaskStatus.running),
    );
    notifyListeners();
    await api.startTurn(threadId, prompt);
    if (!_isCurrentSession(api, attempt, epoch, profileId)) return;
    await refreshTasks();
  }

  Future<void> sendPrompt(String prompt, {RemoteSkill? skill}) async {
    final api = _requireApi();
    final attempt = _connectionAttempt;
    final epoch = _epoch;
    final profileId = _selectedHostId!;
    final task = selectedTask;
    if (task == null) throw StateError('Select or create a task first.');
    if (!task.canWrite) {
      throw StateError('This running task is owned by another Codex client.');
    }
    if (!_ownedThreadIds.contains(task.id) ||
        !_loadedThreadIds.contains(task.id)) {
      await api.resumeThread(task.id);
      if (!_isCurrentSession(api, attempt, epoch, profileId)) return;
      if (!await _claimThread(
        task.id,
        api: api,
        attempt: attempt,
        epoch: epoch,
        profileId: profileId,
      )) {
        return;
      }
      _loadedThreadIds = {..._loadedThreadIds, task.id};
    }
    final text = skill == null ? prompt : '\$${skill.name} $prompt';
    await api.startTurn(task.id, text, skill: skill);
    if (!_isCurrentSession(api, attempt, epoch, profileId)) return;
    _taskReducer.applyEvent(
      _epoch,
      TaskEvent.statusChanged(task.id, TaskStatus.running),
    );
    notifyListeners();
  }

  Future<List<RemoteSkill>> listSkillsForSelectedTask() async {
    final cwd = selectedTask?.cwd.isNotEmpty == true
        ? selectedTask!.cwd
        : selectedProject?.cwd;
    if (cwd == null || cwd.isEmpty) {
      throw StateError('The selected task has no working directory.');
    }
    return _requireApi().listSkills(cwd);
  }

  Future<RemoteThreadGoal?> readSelectedGoal() {
    final task = selectedTask;
    if (task == null) throw StateError('Select a task first.');
    return _requireApi().readThreadGoal(task.id);
  }

  Future<RemoteThreadGoal> setSelectedGoal({
    required String objective,
    int? tokenBudget,
  }) {
    final task = selectedTask;
    if (task == null) throw StateError('Select a task first.');
    final normalizedObjective = objective.trim();
    if (normalizedObjective.isEmpty) {
      throw ArgumentError('Goal objective is required.');
    }
    if (tokenBudget != null && tokenBudget <= 0) {
      throw ArgumentError('Token budget must be positive.');
    }
    return _requireApi().setThreadGoal(
      task.id,
      objective: normalizedObjective,
      tokenBudget: tokenBudget,
    );
  }

  Future<void> clearSelectedGoal() {
    final task = selectedTask;
    if (task == null) throw StateError('Select a task first.');
    return _requireApi().clearThreadGoal(task.id);
  }

  Future<void> compactSelectedTask() {
    final task = selectedTask;
    if (task == null) throw StateError('Select a task first.');
    if (!task.canWrite) {
      throw StateError('This running task is owned by another Codex client.');
    }
    return _requireApi().compactThread(task.id);
  }

  Future<void> interruptSelectedTask() async {
    final task = selectedTask;
    final turnId = task == null ? null : _activeTurnIds[task.id];
    if (task == null || !task.canWrite || turnId == null) return;
    await _requireApi().interruptTurn(task.id, turnId);
  }

  Future<void> guideExternalTask(String guidance) async {
    final task = selectedTask;
    if (task == null || task.ownership != TaskOwnership.external) {
      throw StateError('Select a task running in another client first.');
    }
    final normalized = guidance.trim();
    if (normalized.isEmpty) throw ArgumentError('Guidance is required.');
    final api = _requireApi();
    final turnId = await api.readActiveTurnId(task.id);
    if (turnId == null) {
      throw StateError('The other client no longer has an active turn.');
    }
    await api.steerTurn(task.id, turnId, normalized);
  }

  Future<void> takeOverExternalTask() async {
    final task = selectedTask;
    final profileId = _selectedHostId;
    if (task == null ||
        profileId == null ||
        task.ownership != TaskOwnership.external) {
      throw StateError('Select a task running in another client first.');
    }
    final api = _requireApi();
    final attempt = _connectionAttempt;
    final epoch = _epoch;
    final turnId = await api.readActiveTurnId(task.id);
    if (turnId != null) await api.interruptTurn(task.id, turnId);
    if (!_isCurrentSession(api, attempt, epoch, profileId)) return;
    await api.resumeThread(task.id);
    if (!_isCurrentSession(api, attempt, epoch, profileId)) return;
    if (!await _claimThread(
      task.id,
      api: api,
      attempt: attempt,
      epoch: epoch,
      profileId: profileId,
    )) {
      return;
    }
    _loadedThreadIds = {..._loadedThreadIds, task.id};
    _activeTurnIds.remove(task.id);
    _taskReducer.applyEvent(
      epoch,
      TaskEvent.statusChanged(task.id, TaskStatus.interrupted),
    );
    notifyListeners();
  }

  void answerApproval(PendingApproval approval, String decision) {
    if (!isConnected ||
        !_approvals.any((pending) => identical(pending, approval))) {
      return;
    }
    _api!.answerApproval(approval.requestId, decision);
    _approvals = _approvals
        .where((item) => item.requestId != approval.requestId)
        .toList(growable: false);
    notifyListeners();
  }

  Future<bool> _claimThread(
    String threadId, {
    required CodexRemoteApi api,
    required int attempt,
    required int epoch,
    required String profileId,
  }) async {
    if (!_isCurrentSession(api, attempt, epoch, profileId)) return false;
    final owned = {..._ownedThreadIds, threadId};
    await _store.writeOwnedThreads(profileId, owned);
    if (!_isCurrentSession(api, attempt, epoch, profileId)) return false;
    _ownedThreadIds = owned;
    return true;
  }

  bool _isCurrentSession(
    CodexRemoteApi api,
    int attempt,
    int epoch,
    String profileId,
  ) =>
      identical(api, _api) &&
      attempt == _connectionAttempt &&
      epoch == _epoch &&
      profileId == _selectedHostId;

  void _handleNotification(int attempt, RpcNotification notification) {
    if (attempt != _connectionAttempt) return;
    final event = CodexRemoteApi.parseNotification(
      notification.method,
      notification.params,
    );
    if (event != null) _taskReducer.applyEvent(_epoch, event);
    final threadId = notification.params['threadId'] as String? ??
        (notification.params['thread'] is Map
            ? (notification.params['thread'] as Map)['id'] as String?
            : null);
    if (notification.method == 'turn/started') {
      final turn = notification.params['turn'];
      final turnId = turn is Map ? turn['id'] as String? : null;
      if (threadId != null && turnId != null) {
        _activeTurnIds[threadId] = turnId;
      }
    } else if (notification.method == 'turn/completed' && threadId != null) {
      _activeTurnIds.remove(threadId);
      unawaited(refreshTasks());
    }
    notifyListeners();
  }

  void _handleServerRequest(int attempt, RpcServerRequest request) {
    if (attempt != _connectionAttempt) return;
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
    _connectionAttempt++;
    _cancelHostKeyPrompt();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectionPhase = RemoteConnectionPhase.disconnected;
    _selectedTaskId = null;
    _selectedProjectId = null;
    _projects = const [];
    _taskCatalog.clear();
    _historyLoadState.clear();
    _activeTurnIds.clear();
    _loadedThreadIds = {};
    _ownedThreadIds = {};
    _epoch = _taskReducer.beginConnection();
    _approvals = const [];
    await _closeTransport();
    try {
      await _writeAutoConnectIntent(null);
    } catch (exception) {
      _error = 'Disconnected, but could not clear auto-connect: $exception';
    }
    notifyListeners();
  }

  Future<void> _rememberAutoConnectHost(String profileId) async {
    try {
      await _writeAutoConnectIntent(profileId);
    } catch (exception) {
      debugPrint('Could not remember auto-connect host: $exception');
    }
  }

  Future<void> _writeAutoConnectIntent(String? profileId) {
    final operation = _autoConnectIntentWrite.then(
      (_) => _store.writeAutoConnectHostId(profileId),
    );
    _autoConnectIntentWrite = operation.catchError((Object exception) {
      debugPrint('Could not persist auto-connect intent: $exception');
    });
    return operation;
  }

  List<TaskRecord> _tasksForIds(List<String> ids) => ids
      .map((id) => _taskReducer.state.tasks[id])
      .whereType<TaskRecord>()
      .toList(growable: false);

  Future<void> _closeTransport() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _approvals = const [];
    final notificationSubscription = _notificationSubscription;
    final requestSubscription = _requestSubscription;
    final rpc = _rpc;
    final tunnel = _tunnel;
    final ssh = _ssh;
    _notificationSubscription = null;
    _requestSubscription = null;
    _rpc = null;
    _api = null;
    _tunnel = null;
    _ssh = null;
    await notificationSubscription?.cancel();
    await requestSubscription?.cancel();
    await rpc?.close();
    await tunnel?.close();
    await ssh?.close();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _connectionAttempt++;
    _cancelHostKeyPrompt();
    _reconnectTimer?.cancel();
    _refreshTimer?.cancel();
    unawaited(_closeTransport());
    super.dispose();
  }
}

String _friendlyError(Object exception) {
  if (exception is RpcRemoteException) return exception.message;
  final text = exception.toString();
  return text.replaceFirst(
      RegExp(r'^(Exception|StateError|ArgumentError):\s*'), '');
}

String describeConnectionFailure(
  ConnectionStage stage,
  Object exception,
  HostProfile profile,
) {
  final detail = _friendlyError(exception);
  final target = profile.proxyJump;
  final endpoint = target == null
      ? '${profile.hostName}:${profile.port}'
      : '${target.hostName}:${target.port}';
  return switch (stage) {
    ConnectionStage.profile => 'Could not read the SSH profile: $detail',
    ConnectionStage.ssh => 'SSH connection to $endpoint failed: $detail',
    ConnectionStage.remoteAppServer =>
      'SSH connected successfully, but the remote Codex app-server failed: '
          '$detail',
    ConnectionStage.unixTunnel =>
      'SSH connected successfully, but the remote Codex socket could not be '
          'forwarded: $detail',
    ConnectionStage.rpcTunnel =>
      'SSH connected successfully, but the Codex tunnel refused the local RPC '
          'connection: $detail',
    ConnectionStage.initialize =>
      'The Codex tunnel connected, but RPC initialization failed: $detail',
    ConnectionStage.refresh =>
      'Codex connected, but its task list could not be loaded: $detail',
  };
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
