// Pure helpers for the Notes plugin. No Quickshell imports so this stays
// trivially inspectable.
function stemOf(name) {
  return String(name || "").replace(/\.md$/, "")
}

function titleOf(name) {
  return stemOf(name)
}

// Sanitize a user-typed title into a safe filename stem.
function fileNameFor(title) {
  var t = String(title || "").trim().replace(/[/\\:*?"<>|]/g, "").replace(/\s+/g, " ").slice(0, 80).trim()
  return t || "Untitled"
}

function notePath(dir, stem) {
  return dir + "/" + stem + ".md"
}

function hasExactNote(names, title) {
  var wanted = fileNameFor(title) + ".md"
  for (var i = 0; i < names.length; i++)
    if (names[i] === wanted) return true
  return false
}

function uniqueStem(names, baseTitle) {
  var base = fileNameFor(baseTitle)
  var used = {}
  for (var i = 0; i < names.length; i++) used[String(names[i])] = true
  if (!used[base + ".md"]) return base
  var suffix = 2
  while (used[base + " " + suffix + ".md"]) suffix++
  return base + " " + suffix
}

function renameTarget(names, currentStem, title) {
  var stem = fileNameFor(title)
  if (stem !== currentStem && hasExactNote(names, stem))
    return { stem: "", error: "A note named “" + stem + "” already exists" }
  return { stem: stem, error: "" }
}

function deleteCommand(dir, stem) {
  return ["/usr/bin/rm", "-f", "--", notePath(dir, stem)]
}

function renameCommand(dir, oldStem, newStem) {
  return ["/usr/bin/mv", "--", notePath(dir, oldStem), notePath(dir, newStem)]
}

function filterNotes(names, query) {
  var q = String(query || "").toLowerCase()
  if (!q) return names.slice()
  var out = []
  for (var i = 0; i < names.length; i++)
    if (titleOf(names[i]).toLowerCase().indexOf(q) !== -1) out.push(names[i])
  return out
}

function parseListJson(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    return Array.isArray(parsed) ? parsed.filter(function(n) { return typeof n === "string" }) : []
  } catch (e) {
    return []
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    stemOf: stemOf,
    titleOf: titleOf,
    fileNameFor: fileNameFor,
    notePath: notePath,
    hasExactNote: hasExactNote,
    uniqueStem: uniqueStem,
    renameTarget: renameTarget,
    deleteCommand: deleteCommand,
    renameCommand: renameCommand,
    filterNotes: filterNotes,
    parseListJson: parseListJson
  }
}
