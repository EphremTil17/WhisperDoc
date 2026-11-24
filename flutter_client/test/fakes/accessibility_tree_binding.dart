// A shared test library, not a test: its public classes are the point.
// ignore_for_file: avoid-top-level-members-in-tests
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A test binding that keeps the accessibility tree the way the Windows
/// engine does, and records every update the engine would reject.
///
/// Windows logs a rejection as "Failed to update ui::AXTree, error: N will
/// not be in the tree and is not the new root", and from then on drops every
/// update that touches that node, so screen readers see a stale tree.
/// Create it before the first test (`final binding = AccessibilityTreeBinding();`)
/// and turn semantics on with `tester.ensureSemantics()`.
class AccessibilityTreeBinding extends AutomatedTestWidgetsFlutterBinding {
  final EngineAccessibilityTree tree = EngineAccessibilityTree();

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _RecordingUpdateBuilder(tree.apply);
}

/// One node of a semantics update, as the engine reads it.
typedef SentNode = ({int id, List<int> children});

/// The engine's tree, updated the way the shared accessibility bridge does
/// it (`shell/platform/common/accessibility_bridge.cc`): a node that moved is
/// first removed from its old parent (deleting its subtree), then the update
/// is applied parents first, and a node the tree doesn't hold must be listed
/// as a child by a node earlier in the same update.
class EngineAccessibilityTree {
  final Map<int, List<int>> _children = {};
  final Map<int, int> _parent = {};

  /// Each node the engine would have rejected, as `update N: node M`.
  final List<String> rejections = [];
  int _updates = 0;

  void apply(List<SentNode> nodes) {
    _updates++;
    _detachMovedChildren(nodes);
    final introduced = <int>{};
    for (final node in _parentsFirst(nodes)) {
      final known = _children.containsKey(node.id) || node.id == 0;
      if (!known && !introduced.contains(node.id)) {
        rejections.add('update $_updates: node ${node.id}');
        continue;
      }
      for (final child in node.children) {
        if (!_children.containsKey(child)) introduced.add(child);
      }
      _setChildren(node.id, node.children);
    }
  }

  void _detachMovedChildren(List<SentNode> nodes) {
    for (final node in nodes) {
      for (final child in node.children) {
        final oldParent = _parent[child];
        if (oldParent == null || oldParent == node.id) continue;
        _setChildren(oldParent, [
          for (final sibling in _children[oldParent] ?? const <int>[])
            if (sibling != child) sibling,
        ]);
      }
    }
  }

  /// The bridge's order: each node with the pending part of its subtree,
  /// groups taken in reverse, so a parent comes before its children.
  static Iterable<SentNode> _parentsFirst(List<SentNode> nodes) {
    final pending = {for (final node in nodes) node.id: node};
    final groups = <List<SentNode>>[];
    void collect(SentNode node, List<SentNode> into) {
      into.add(node);
      for (final child in node.children) {
        final next = pending.remove(child);
        if (next != null) collect(next, into);
      }
    }

    while (pending.isNotEmpty) {
      final first = pending.keys.first;
      final group = <SentNode>[];
      final node = pending.remove(first);
      if (node != null) collect(node, group);
      groups.add(group);
    }

    return groups.reversed.expand((group) => group);
  }

  void _setChildren(int id, List<int> children) {
    for (final old in _children[id] ?? const <int>[]) {
      if (!children.contains(old) && _parent[old] == id) _delete(old);
    }
    _children[id] = children;
    for (final child in children) {
      _parent[child] = id;
    }
  }

  void _delete(int id) {
    for (final child in _children[id] ?? const <int>[]) {
      _delete(child);
    }
    _children.remove(id);
    _parent.remove(id);
  }
}

/// Builds the real update and hands each batch of nodes to [_onBuild].
class _RecordingUpdateBuilder implements ui.SemanticsUpdateBuilder {
  _RecordingUpdateBuilder(this._onBuild);

  final void Function(List<SentNode>) _onBuild;
  final ui.SemanticsUpdateBuilder _real = ui.SemanticsUpdateBuilder();
  final List<SentNode> _nodes = [];

  // Forwards the builder's three methods to the real one; their long
  // parameter lists change between Flutter versions, so they are forwarded
  // as they come rather than restated here. noSuchMethod returns dynamic.
  @override
  // ignore: avoid-dynamic, noSuchMethod must return dynamic
  dynamic noSuchMethod(Invocation invocation) {
    final named = invocation.namedArguments;
    switch (invocation.memberName) {
      case #updateNode:
        final children = named[#childrenInTraversalOrder] as Int32List;
        _nodes.add((id: named[#id] as int, children: children.toList()));

        return Function.apply(_real.updateNode, const [], named);
      case #updateCustomAction:
        return Function.apply(_real.updateCustomAction, const [], named);
      case #build:
        _onBuild(List.of(_nodes));

        return _real.build();
    }

    return super.noSuchMethod(invocation);
  }
}
