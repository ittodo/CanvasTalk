import "dart:io";

class FolderPicker {
  static bool get isSupported => Platform.isWindows;

  static Future<String?> pickDirectory() async {
    if (!Platform.isWindows) {
      return null;
    }

    const script = r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = "Select Project Folder"
$dialog.ShowNewFolderButton = $true
$result = $dialog.ShowDialog()
if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output $dialog.SelectedPath
}
''';

    final result = await Process.run(
      "powershell",
      <String>[
        "-NoProfile",
        "-Command",
        script,
      ],
    );
    if (result.exitCode != 0) {
      return null;
    }

    final raw = result.stdout?.toString() ?? "";
    final lines = raw
        .split(RegExp(r"\r?\n"))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    if (lines.isEmpty) {
      return null;
    }
    return lines.first;
  }
}
