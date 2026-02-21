import "package:flutter/material.dart";

import "../model/ui_page.dart";
import "../services/folder_picker_service.dart";
import "../state/app_controller.dart";

class PageControlBar extends StatelessWidget {
  const PageControlBar({
    required this.controller,
    super.key,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final currentPath = controller.currentProjectPath;
    final hasCurrentPath = currentPath != null && currentPath.trim().isNotEmpty;
    final recents = controller.recentProjectPaths;
    final canSave = controller.projectStorageSupported &&
        (hasCurrentPath || FolderPicker.isSupported);
    final canSaveAs =
        controller.projectStorageSupported && FolderPicker.isSupported;
    final canLoad =
        controller.projectStorageSupported && FolderPicker.isSupported;
    final canLoadRecent =
        controller.projectStorageSupported && recents.isNotEmpty;
    final zoomPercent = (controller.canvasZoom * 100).round();
    final activePage = controller.activePage;
    final standalonePreviewMode = controller.standaloneOverlayPreviewMode;
    final baseCandidates =
        controller.pages.where((page) => page.id != activePage.id).toList();
    final overlayChildren = controller.pages
        .where(
          (page) =>
              page.mode == UiPageMode.overlay &&
              page.basePageId != null &&
              page.basePageId == activePage.id,
        )
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                FilledButton.icon(
                  onPressed: canSave ? () => _save(context) : null,
                  icon: const Icon(Icons.save),
                  label: Text(hasCurrentPath ? "Save" : "Save As"),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: canSaveAs ? () => _saveAs(context) : null,
                  icon: const Icon(Icons.save_as_outlined),
                  label: const Text("Save As"),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: canLoad ? () => _loadFromPicker(context) : null,
                  icon: const Icon(Icons.folder_open),
                  label: const Text("Load"),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  enabled: canLoadRecent,
                  tooltip: "Load Recent",
                  onSelected: (path) => _loadByPath(context, path),
                  itemBuilder: (context) {
                    if (recents.isEmpty) {
                      return const <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          enabled: false,
                          child: Text("No recent projects"),
                        ),
                      ];
                    }
                    return recents
                        .map(
                          (path) => PopupMenuItem<String>(
                            value: path,
                            child: SizedBox(
                              width: 420,
                              child: Text(
                                path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        )
                        .toList();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.history),
                        SizedBox(width: 4),
                        Text("Recent"),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const VerticalDivider(width: 1, thickness: 1),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: "Add Page",
                  onPressed: controller.addPage,
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  tooltip: "Delete Active Page",
                  onPressed: controller.pages.length <= 1
                      ? null
                      : controller.deleteActivePage,
                  icon: const Icon(Icons.delete_outline),
                ),
                IconButton(
                  tooltip: "Rename Active Page",
                  onPressed: () => _showRenamePageDialog(context),
                  icon: const Icon(Icons.drive_file_rename_outline),
                ),
                IconButton(
                  tooltip: "Edit Page LLM Comment",
                  onPressed: () => _showPageCommentDialog(context),
                  icon: const Icon(Icons.comment_outlined),
                ),
                const SizedBox(width: 12),
                const VerticalDivider(width: 1, thickness: 1),
                const SizedBox(width: 12),
                const Text("View Zoom"),
                IconButton(
                  tooltip: "Canvas Zoom Out (view only)",
                  onPressed: controller.zoomOutCanvasView,
                  icon: const Icon(Icons.zoom_out),
                ),
                OutlinedButton(
                  onPressed: controller.resetCanvasZoom,
                  child: Text("$zoomPercent%"),
                ),
                IconButton(
                  tooltip: "Canvas Zoom In (view only)",
                  onPressed: controller.zoomInCanvasView,
                  icon: const Icon(Icons.zoom_in),
                ),
                const SizedBox(width: 12),
                const VerticalDivider(width: 1, thickness: 1),
                const SizedBox(width: 12),
                Tooltip(
                  message: "Scale all UI +10% (canvas size included)",
                  child: FilledButton.tonalIcon(
                    onPressed: () => controller.scaleProject(1.1),
                    icon: const Icon(Icons.aspect_ratio),
                    label: const Text("Scale +10%"),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => controller.scaleProject(0.9),
                  icon: const Icon(Icons.compress),
                  label: const Text("Scale -10%"),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 420,
                  child: Text(
                    !controller.projectStorageSupported
                        ? "Project file I/O: disabled in web mode"
                        : hasCurrentPath
                            ? "Project: $currentPath"
                            : "Project: (unsaved)",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: controller.pages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final page = controller.pages[index];
                final selected = page.id == controller.activePageId;
                return _pageTab(
                  context,
                  page.id,
                  page.name,
                  selected,
                  isOverlay: page.mode == UiPageMode.overlay,
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                const Text("Page Mode"),
                const SizedBox(width: 8),
                DropdownButton<UiPageMode>(
                  value: activePage.mode,
                  onChanged: (mode) {
                    if (mode == null) {
                      return;
                    }
                    controller.setActivePageMode(mode);
                  },
                  items: UiPageMode.values
                      .map(
                        (mode) => DropdownMenuItem<UiPageMode>(
                          value: mode,
                          child: Text(mode.name),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(width: 12),
                if (activePage.mode == UiPageMode.overlay) ...<Widget>[
                  const Text("Base Page"),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: activePage.basePageId,
                    hint: const Text("Select base"),
                    onChanged: (value) =>
                        controller.setActivePageBasePage(value),
                    items: baseCandidates
                        .map(
                          (page) => DropdownMenuItem<String>(
                            value: page.id,
                            child: Text(page.name),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Overlay = parent page + current page layers",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else ...<Widget>[
                  Text(
                    "Standalone = independent page",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(width: 16),
                const Text("Standalone Preview"),
                const SizedBox(width: 8),
                DropdownButton<StandaloneOverlayPreviewMode>(
                  value: standalonePreviewMode,
                  onChanged: (mode) {
                    if (mode == null) {
                      return;
                    }
                    controller.setStandaloneOverlayPreviewMode(mode);
                  },
                  items: const <DropdownMenuItem<StandaloneOverlayPreviewMode>>[
                    DropdownMenuItem<StandaloneOverlayPreviewMode>(
                      value: StandaloneOverlayPreviewMode.oneLevel,
                      child: Text("1-level"),
                    ),
                    DropdownMenuItem<StandaloneOverlayPreviewMode>(
                      value: StandaloneOverlayPreviewMode.fullTree,
                      child: Text("Full tree"),
                    ),
                  ],
                ),
                Text(
                  "(global)",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                const Text("Overlay Pages On This Base"),
                const SizedBox(width: 8),
                if (overlayChildren.isEmpty)
                  Text(
                    "(none)",
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  ...overlayChildren.map((overlayPage) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: OutlinedButton(
                        onPressed: () =>
                            controller.setActivePage(overlayPage.id),
                        child: Text("↗ ${overlayPage.name}"),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageTab(
      BuildContext context, String pageId, String pageName, bool selected,
      {required bool isOverlay}) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => controller.setActivePage(pageId),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
          ),
        ),
        child: Text(
          isOverlay ? "◳ $pageName" : pageName,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? theme.colorScheme.onPrimaryContainer : null,
          ),
        ),
      ),
    );
  }

  Future<void> _loadFromPicker(BuildContext context) async {
    if (!controller.projectStorageSupported || !FolderPicker.isSupported) {
      await _showMessage(
        context,
        title: "Unavailable",
        message: "Folder picker/load is not supported on this platform.",
      );
      return;
    }
    final path = await FolderPicker.pickDirectory();
    if (!context.mounted || path == null || path.trim().isEmpty) {
      return;
    }
    await _loadByPath(context, path.trim());
  }

  Future<void> _loadByPath(BuildContext context, String path) async {
    final ok = await controller.loadProjectFromPath(path);
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      await _showMessage(
        context,
        title: "Load Failed",
        message: controller.statusMessage,
      );
      return;
    }
    await _showMessage(
      context,
      title: "Loaded",
      message: "Project loaded.\n$path",
    );
  }

  Future<void> _save(BuildContext context) async {
    final path = controller.currentProjectPath;
    if (path == null || path.trim().isEmpty) {
      await _saveAs(context);
      return;
    }
    final ok = await controller.saveProjectToPath(path);
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      await _showMessage(
        context,
        title: "Save Failed",
        message: controller.statusMessage,
      );
      return;
    }
    await _showMessage(
      context,
      title: "Saved",
      message: "Project saved successfully.\n$path",
    );
  }

  Future<void> _saveAs(BuildContext context) async {
    if (!controller.projectStorageSupported || !FolderPicker.isSupported) {
      await _showMessage(
        context,
        title: "Unavailable",
        message: "Save As via folder picker is not supported on this platform.",
      );
      return;
    }
    final path = await FolderPicker.pickDirectory();
    if (!context.mounted || path == null || path.trim().isEmpty) {
      return;
    }
    final ok = await controller.saveProjectToPath(path.trim());
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      await _showMessage(
        context,
        title: "Save Failed",
        message: controller.statusMessage,
      );
      return;
    }
    await _showMessage(
      context,
      title: "Saved",
      message: "Project saved successfully.\n$path",
    );
  }

  Future<void> _showRenamePageDialog(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return _TextInputDialog(
          title: "Rename Page",
          label: "Page Name",
          initialValue: controller.activePage.name,
          minLines: 1,
          maxLines: 1,
        );
      },
    );
    if (result == null) {
      return;
    }
    controller.renameActivePage(result);
  }

  Future<void> _showPageCommentDialog(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return _TextInputDialog(
          title: "Page LLM Comment",
          label: "Comment",
          initialValue: controller.activePage.llmComment,
          minLines: 3,
          maxLines: 8,
        );
      },
    );
    if (result == null) {
      return;
    }
    controller.setActivePageLlmComment(result);
  }

  Future<void> _showMessage(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.minLines,
    required this.maxLines,
  });

  final String title;
  final String label;
  final String initialValue;
  final int minLines;
  final int maxLines;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: widget.label,
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text("Apply"),
        ),
      ],
    );
  }
}
