import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "NotesModel.js" as Model

Panel {
  id: root
  moduleName: "burnz.notes"
  ipcTarget: "burnz.notes"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar tracks the widget mounted in its slot, not this nested panel.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property var settings: ({})

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    root.refresh()
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    renaming = false
    flushSave()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---- Notes state
  readonly property string notesDir: Quickshell.env("HOME") + "/Documents/Notes"

  property var notes: []              // filenames, mtime-descending
  property string selectedStem: ""    // filename without .md
  property string searchText: ""
  property string editorText: ""
  property bool editorDirty: false
  property bool deleteArmed: false
  property bool renaming: false
  property bool settingsOpen: false
  property string statusText: ""

  readonly property bool compactEditor: settings && settings.editorSize === "compact"
  readonly property real editorHeight: Style.space(compactEditor ? 130 : 200)

  readonly property var visibleNotes: Model.filterNotes(root.notes, root.searchText)
  readonly property bool showCreateRow: root.searchText.trim() !== "" && !Model.hasExactNote(root.notes, root.searchText)
  readonly property string selectedTitle: selectedStem === "" ? "" : Model.titleOf(selectedStem)
  readonly property string expectedPath: selectedStem === "" ? "" : Model.notePath(notesDir, selectedStem)

  function refresh() {
    if (!listProc.running) listProc.running = true
  }

  function loadIntoEditor(content) {
    root.editorText = content
    editor.text = content
  }

  function selectNote(stem) {
    if (stem === root.selectedStem) return
    flushSave()
    deleteArmed = false
    renaming = false
    root.selectedStem = stem
    if (stem === "") {
      noteFile.path = notesDir + "/__none__.md"
      loadIntoEditor("")
      root.editorDirty = false
      return
    }
    noteFile.path = Model.notePath(notesDir, stem)
    noteFile.reload()
  }

  function createNoteWithStem(stem) {
    flushSave()
    searchField.text = ""
    root.searchText = ""
    deleteArmed = false
    root.selectedStem = stem
    noteFile.path = Model.notePath(notesDir, stem)
    noteFile.setText("")
    loadIntoEditor("")
    root.editorDirty = false
    refresh()
    Qt.callLater(function() { editor.forceActiveFocus() })
  }

  function createNote() {
    createNoteWithStem(Model.fileNameFor(root.searchText))
  }

  function createBlankNote() {
    var existing = root.notes.slice()
    if (root.selectedStem !== "") existing.push(root.selectedStem + ".md")
    createNoteWithStem(Model.uniqueStem(existing, "Untitled"))
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function toggleEditorSize() {
    persistSettings({ editorSize: root.compactEditor ? "comfortable" : "compact" })
  }

  function markDirty() {
    root.editorDirty = true
    statusText = "Editing…"
    saveDebounce.restart()
  }

  function flushSave() {
    saveDebounce.stop()
    if (root.editorDirty && root.selectedStem !== "") saveNow()
  }

  function saveNow() {
    if (root.selectedStem === "") return
    root.editorDirty = false
    statusText = "Saving…"
    noteFile.setText(root.editorText)
    statusText = "Saved"
    flashTimer.restart()
  }

  function requestDelete() {
    if (root.selectedStem === "" || deleteProc.running || renameProc.running) return
    if (!deleteArmed) {
      deleteArmed = true
      deleteDisarm.restart()
      return
    }
    deleteArmed = false
    deleteDisarm.stop()
    deleteNote(root.selectedStem)
  }

  function deleteNote(stem) {
    if (stem === "" || deleteProc.running || renameProc.running) return
    // A pending debounced atomic write can recreate the file after rm.
    // Cancel it only when deleting the selected note.
    if (stem === root.selectedStem) {
      saveDebounce.stop()
      root.editorDirty = false
    }
    deleteProc.stemToDelete = stem
    deleteProc.command = Model.deleteCommand(notesDir, stem)
    root.statusText = "Deleting…"
    deleteProc.running = true
  }

  function renameNote(stem) {
    if (stem === "" || deleteProc.running || renameProc.running) return
    root.selectNote(stem)
    Qt.callLater(root.startRename)
  }

  function startRename() {
    if (root.selectedStem === "" || deleteProc.running || renameProc.running) return
    flushSave()
    deleteArmed = false
    root.renaming = true
    renameField.text = root.selectedTitle
    Qt.callLater(function() {
      renameField.selectAll()
      renameField.forceActiveFocus()
    })
  }

  function cancelRename() {
    root.renaming = false
    root.statusText = ""
    Qt.callLater(function() { editor.forceActiveFocus() })
  }

  function commitRename() {
    if (!root.renaming || renameProc.running) return
    var target = Model.renameTarget(root.notes, root.selectedStem, renameField.text)
    if (target.error !== "") {
      root.statusText = target.error
      return
    }
    if (target.stem === root.selectedStem) {
      cancelRename()
      return
    }
    renameProc.oldStem = root.selectedStem
    renameProc.newStem = target.stem
    renameProc.command = Model.renameCommand(notesDir, renameProc.oldStem, renameProc.newStem)
    root.statusText = "Renaming…"
    renameProc.running = true
  }

  IpcHandler {
    target: "burnz.notes"

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  Process {
    id: listProc
    command: ["python3", "-c",
      "import json,os;d=os.path.expanduser('" + root.notesDir + "');" +
      "print(json.dumps(sorted((f for f in os.listdir(d) if f.endswith('.md'))," +
      "key=lambda f:-os.path.getmtime(os.path.join(d,f)))))"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.notes = Model.parseListJson(text)
    }
  }

  Process {
    id: deleteProc
    property string stemToDelete: ""
    command: []
    stderr: StdioCollector {
      id: deleteStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var detail = String(deleteStderr.text || "").trim()
        root.statusText = detail === "" ? "Delete failed (" + exitCode + ")" : detail
        console.warn("burnz.notes delete failed:", exitCode, detail)
        return
      }
      if (root.selectedStem === stemToDelete) {
        root.selectedStem = ""
        noteFile.path = notesDir + "/__none__.md"
        loadIntoEditor("")
        root.editorDirty = false
      }
      root.statusText = "Deleted"
      flashTimer.restart()
      root.refresh()
    }
  }

  Process {
    id: renameProc
    property string oldStem: ""
    property string newStem: ""
    command: []
    stderr: StdioCollector {
      id: renameStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var detail = String(renameStderr.text || "").trim()
        root.statusText = detail === "" ? "Rename failed (" + exitCode + ")" : detail
        console.warn("burnz.notes rename failed:", exitCode, detail)
        return
      }
      root.renaming = false
      root.selectedStem = newStem
      noteFile.path = Model.notePath(notesDir, newStem)
      noteFile.reload()
      root.statusText = "Renamed"
      flashTimer.restart()
      root.refresh()
      Qt.callLater(function() { editor.forceActiveFocus() })
    }
  }

  Process {
    id: initProc
    command: ["mkdir", "-p", root.notesDir]
    onExited: function(exitCode) { root.refresh() }
  }

  Timer {
    id: initKick
    interval: 200
    running: true
    onTriggered: initProc.running = true
  }

  FileView {
    id: noteFile
    path: root.notesDir + "/__none__.md"
    watchChanges: true
    atomicWrites: true
    printErrors: false

    onLoaded: {
      // Ignore loads that no longer match the selected note.
      if (root.expectedPath !== "" && path !== root.expectedPath) return
      var content = String(text() || "").replace(/\n$/, "")
      // Our own autosave echo lands here too; only adopt genuinely new content.
      if (content === root.editorText) return
      loadIntoEditor(content)
      root.editorDirty = false
      root.statusText = ""
    }
    onLoadFailed: {
      if (path !== root.expectedPath) return
      loadIntoEditor("")
      root.editorDirty = false
    }
    onFileChanged: {
      // External edits land live while we're not mid-typing.
      if (!root.editorDirty && path === root.expectedPath) reload()
    }
  }

  Timer {
    id: saveDebounce
    interval: 600
    onTriggered: root.saveNow()
  }

  Timer {
    id: flashTimer
    interval: 1500
    onTriggered: root.statusText = ""
  }

  Timer {
    id: deleteDisarm
    interval: 2500
    onTriggered: root.deleteArmed = false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(notesColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || editor.activeFocus || newNoteButton.activeFocus
        || settingsButton.activeFocus || editorSizeButton.activeFocus || renameField.activeFocus
        || renameButton.activeFocus || deleteButton.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: notesColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // The toolbar is one bounded row. Its controls divide this exact
        // width, so none can inherit the full-screen layer surface width.
        Row {
          id: toolbar
          width: parent.width
          height: Style.space(30)
          spacing: Style.space(6)

          TextField {
            id: searchField
            width: Math.max(1, toolbar.width - newNoteButton.width - settingsButton.width - toolbar.spacing * 2)
            placeholderText: "Search or create a note…"
            foreground: root.bar.foreground
            font.family: root.bar.fontFamily

            onTextChanged: root.searchText = text

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.showCreateRow) root.createNote()
                else if (root.visibleNotes.length > 0) {
                  root.selectNote(Model.stemOf(root.visibleNotes[0]))
                  Qt.callLater(function() { editor.forceActiveFocus() })
                }
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
              }
            }
          }

          PanelActionButton {
            id: newNoteButton
            size: toolbar.height
            focusable: true
            bordered: true
            iconText: "+"
            tooltipText: "New note"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.createBlankNote()
          }

          PanelActionButton {
            id: settingsButton
            size: toolbar.height
            focusable: true
            bordered: true
            iconText: "\uf013"
            tooltipText: root.settingsOpen ? "Hide settings" : "Notes settings"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.settingsOpen = !root.settingsOpen
          }
        }

        Rectangle {
          visible: root.settingsOpen
          width: parent.width
          height: visible ? settingsRow.implicitHeight + Style.space(12) : 0
          radius: Style.cornerRadius
          color: Style.hoverFillFor(root.bar.foreground, Color.accent)

          Row {
            id: settingsRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              width: Math.max(1, settingsRow.width - editorSizeButton.width - settingsRow.spacing)
              anchors.verticalCenter: parent.verticalCenter
              text: "Editor size"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Button {
              id: editorSizeButton
              text: root.compactEditor ? "Compact" : "Comfortable"
              focusable: true
              bordered: true
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.toggleEditorSize()
            }
          }
        }

        Flickable {
          width: parent.width
          height: root.visibleNotes.length === 0 ? Style.space(34) : Math.min(Style.space(190), root.visibleNotes.length * Style.space(32))
          contentWidth: width
          contentHeight: listColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Column {
            id: listColumn
            width: parent.width - Style.space(16)
            x: Style.space(8)
            spacing: 0

            Repeater {
              model: root.visibleNotes

              Rectangle {
                required property var modelData
                required property int index
                readonly property bool isSelected: Model.stemOf(modelData) === root.selectedStem
                width: parent.width
                height: Style.space(32)
                radius: Style.cornerRadius
                color: isSelected || rowHover.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: Model.titleOf(modelData)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                MouseArea {
                  id: rowHover
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    var stem = Model.stemOf(modelData)
                    if (mouse.button === Qt.RightButton) {
                      noteContextMenu.noteStem = stem
                      noteContextMenu.popup()
                    } else {
                      root.selectNote(stem)
                      Qt.callLater(function() { editor.forceActiveFocus() })
                    }
                  }
                }
              }
            }

            Text {
              visible: root.visibleNotes.length === 0
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              topPadding: Style.space(8)
              text: root.notes.length === 0 ? "No notes yet — type above to create one" : "No matches"
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
            }
          }
        }

        Rectangle {
          visible: root.showCreateRow
          width: parent.width
          height: createRow.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          color: createHover.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

          Row {
            id: createRow
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Text {
              id: createIcon
              text: "+"
              color: Color.accent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: "Create \u201C" + root.searchText.trim() + "\u201D"
              width: Math.max(0, createRow.width - createIcon.implicitWidth - createRow.spacing)
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
            }
          }

          MouseArea {
            id: createHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.createNote()
          }
        }

        Rectangle {
          visible: root.selectedStem !== ""
          width: parent.width
          height: Style.spacing.hairline
          color: root.bar.foreground
          opacity: 0.12
        }

        Row {
          id: headerRow
          visible: root.selectedStem !== ""
          width: parent.width - Style.space(24)
          height: Style.space(30)
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)

          Item {
            width: Math.max(1, headerRow.width - renameButton.width - deleteButton.width
              - statusLabel.width - headerRow.spacing * 3)
            height: headerRow.height

            Text {
              anchors.fill: parent
              visible: !root.renaming
              verticalAlignment: Text.AlignVCenter
              text: root.selectedTitle
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }

            TextField {
              id: renameField
              anchors.fill: parent
              visible: root.renaming
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily
              horizontalPadding: Style.space(6)
              verticalPadding: Style.space(3)

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitRename()
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                  root.cancelRename()
                  event.accepted = true
                }
              }
            }
          }

          Text {
            id: statusLabel
            width: visible ? Math.min(implicitWidth, Style.space(110)) : 0
            height: headerRow.height
            verticalAlignment: Text.AlignVCenter
            text: root.statusText
            visible: root.statusText !== ""
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.italic: true
            elide: Text.ElideRight
          }

          Button {
            id: renameButton
            height: headerRow.height
            text: root.renaming ? "Save" : "Rename"
            focusable: true
            bordered: true
            enabled: !deleteProc.running && !renameProc.running
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.caption
            onClicked: root.renaming ? root.commitRename() : root.startRename()
          }

          Button {
            id: deleteButton
            height: headerRow.height
            text: root.deleteArmed ? "Confirm" : "Delete"
            focusable: true
            bordered: true
            enabled: !renameProc.running && !deleteProc.running
            foreground: root.deleteArmed ? "#ff8888" : root.bar.foreground
            accent: root.deleteArmed ? "#e05555" : Color.accent
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.caption
            onClicked: root.requestDelete()
          }
        }

        TextArea {
          id: editor
          visible: root.selectedStem !== ""
          width: parent.width - Style.space(24)
          height: root.editorHeight
          anchors.horizontalCenter: parent.horizontalCenter
          placeholderText: "Start writing…"
          wrapMode: TextArea.Wrap
          color: root.bar.foreground
          placeholderTextColor: Qt.darker(root.bar.foreground, 1.6)
          selectionColor: Style.selectionFillFor(root.bar.foreground, Color.accent)
          selectedTextColor: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          background: Rectangle {
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.bar.foreground, Color.accent)
            opacity: editor.activeFocus ? 0.35 : 0.18
          }

          onTextChanged: {
            if (text !== root.editorText) {
              root.editorText = text
              if (root.selectedStem !== "") root.markDirty()
            }
          }

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.flushSave()
              searchField.forceActiveFocus()
              event.accepted = true
            }
          }
        }
      }

      Menu {
        id: noteContextMenu
        property string noteStem: ""
        width: Style.space(150)
        padding: Style.space(4)

        background: Rectangle {
          color: Color.popups.background
          border.width: Style.spacing.hairline
          border.color: Color.popups.border
          radius: Style.cornerRadius
        }

        MenuItem {
          id: renameMenuItem
          text: "Rename"
          height: Style.space(32)
          contentItem: Text {
            text: renameMenuItem.text
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            verticalAlignment: Text.AlignVCenter
            leftPadding: Style.space(8)
          }
          background: Rectangle {
            color: renameMenuItem.highlighted
              ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
            radius: Style.cornerRadius
          }
          onTriggered: root.renameNote(noteContextMenu.noteStem)
        }

        MenuItem {
          id: deleteMenuItem
          text: "Delete"
          height: Style.space(32)
          contentItem: Text {
            text: deleteMenuItem.text
            color: "#ff8888"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            verticalAlignment: Text.AlignVCenter
            leftPadding: Style.space(8)
          }
          background: Rectangle {
            color: deleteMenuItem.highlighted
              ? Style.hoverFillFor(root.bar.foreground, "#e05555") : "transparent"
            radius: Style.cornerRadius
          }
          onTriggered: root.deleteNote(noteContextMenu.noteStem)
        }
      }
    }
  }

  Component.onCompleted: refresh()

  onOpenedChanged: if (opened) {
    refresh()
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }
}
