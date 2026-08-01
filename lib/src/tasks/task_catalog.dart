import '../projects/remote_project.dart';
import 'task_reducer.dart';

final class TaskCatalog {
  List<String> _projectTaskIds = const [];
  List<String> _unassignedTaskIds = const [];
  String? _projectNextCursor;
  String? _unassignedNextCursor;
  bool _unassignedExpanded = false;

  List<String> get projectTaskIds => _projectTaskIds;
  List<String> get unassignedTaskIds => _unassignedTaskIds;
  String? get projectNextCursor => _projectNextCursor;
  String? get unassignedNextCursor => _unassignedNextCursor;
  bool get unassignedExpanded => _unassignedExpanded;

  void replaceProjectPage(
    List<TaskSnapshot> tasks, {
    required String? nextCursor,
  }) {
    _projectTaskIds = _uniqueIds(tasks);
    _projectNextCursor = nextCursor;
  }

  void appendProjectPage(
    List<TaskSnapshot> tasks, {
    required String? nextCursor,
  }) {
    _projectTaskIds = _appendUnique(_projectTaskIds, tasks);
    _projectNextCursor = nextCursor;
  }

  void replaceUnassignedPage(
    List<TaskSnapshot> tasks, {
    required List<RemoteProject> projects,
    required String? nextCursor,
  }) {
    _unassignedTaskIds = _uniqueIds(_unassigned(tasks, projects));
    _unassignedNextCursor = nextCursor;
  }

  void appendUnassignedPage(
    List<TaskSnapshot> tasks, {
    required List<RemoteProject> projects,
    required String? nextCursor,
  }) {
    _unassignedTaskIds = _appendUnique(
      _unassignedTaskIds,
      _unassigned(tasks, projects),
    );
    _unassignedNextCursor = nextCursor;
  }

  void toggleUnassigned() {
    _unassignedExpanded = !_unassignedExpanded;
  }

  void clearProjectPage() {
    _projectTaskIds = const [];
    _projectNextCursor = null;
  }

  void clear() {
    clearProjectPage();
    _unassignedTaskIds = const [];
    _unassignedNextCursor = null;
    _unassignedExpanded = false;
  }
}

final class TaskDetailLoadState {
  var _generation = 0;
  String? _taskId;
  String? _loadingTaskId;
  String? _error;

  String? get taskId => _taskId;
  String? get loadingTaskId => _loadingTaskId;
  String? get error => _error;

  int begin(String taskId) {
    _generation++;
    _taskId = taskId;
    _loadingTaskId = taskId;
    _error = null;
    return _generation;
  }

  void complete(int generation) {
    if (generation != _generation) return;
    _loadingTaskId = null;
    _error = null;
  }

  void fail(int generation, String error) {
    if (generation != _generation) return;
    _loadingTaskId = null;
    _error = error;
  }

  void clear() {
    _generation++;
    _taskId = null;
    _loadingTaskId = null;
    _error = null;
  }
}

List<TaskSnapshot> _unassigned(
  List<TaskSnapshot> tasks,
  List<RemoteProject> projects,
) {
  final projectCwds =
      projects.map((project) => normalizeRemoteCwd(project.cwd)).toSet();
  return tasks
      .where((task) => !projectCwds.contains(normalizeRemoteCwd(task.cwd)))
      .toList(growable: false);
}

String normalizeRemoteCwd(String cwd) {
  final normalized = cwd.trim();
  if (normalized.length <= 1) return normalized;
  return normalized.replaceFirst(RegExp(r'/+$'), '');
}

List<String> _uniqueIds(Iterable<TaskSnapshot> tasks) =>
    List.unmodifiable(tasks.map((task) => task.id).toSet());

List<String> _appendUnique(
  List<String> existing,
  Iterable<TaskSnapshot> tasks,
) =>
    List.unmodifiable({...existing, ...tasks.map((task) => task.id)});
