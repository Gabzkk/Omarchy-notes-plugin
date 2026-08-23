const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawnSync } = require("node:child_process")
const Model = require("./NotesModel.js")

assert.equal(Model.stemOf("Daily.md"), "Daily")
assert.equal(Model.stemOf("release.md.notes.md"), "release.md.notes")
assert.equal(Model.uniqueStem([], "Untitled"), "Untitled")
assert.equal(Model.uniqueStem(["Untitled.md"], "Untitled"), "Untitled 2")
assert.equal(
  Model.uniqueStem(["Untitled.md", "Untitled 2.md", "Untitled 3.md"], "Untitled"),
  "Untitled 4"
)

assert.deepEqual(Model.renameTarget(["Daily.md"], "Daily", "  Weekly  "), {
  stem: "Weekly",
  error: ""
})
assert.deepEqual(Model.renameTarget(["Daily.md", "Weekly.md"], "Daily", "Weekly"), {
  stem: "",
  error: "A note named “Weekly” already exists"
})
assert.deepEqual(Model.renameTarget(["Daily.md"], "Daily", "Daily"), {
  stem: "Daily",
  error: ""
})
assert.deepEqual(Model.deleteCommand("/tmp/Notes", "Daily"), [
  "/usr/bin/rm", "-f", "--", "/tmp/Notes/Daily.md"
])
assert.deepEqual(Model.deleteCommand("/tmp/Notes", Model.stemOf("Daily.md")), [
  "/usr/bin/rm", "-f", "--", "/tmp/Notes/Daily.md"
])
assert.deepEqual(Model.renameCommand("/tmp/Notes", "Daily", "Weekly"), [
  "/usr/bin/mv", "--", "/tmp/Notes/Daily.md", "/tmp/Notes/Weekly.md"
])

const testDir = fs.mkdtempSync(path.join(os.tmpdir(), "burnz-notes-test-"))
try {
  fs.writeFileSync(path.join(testDir, "Daily.md"), "test")
  let command = Model.renameCommand(testDir, "Daily", "Weekly")
  assert.equal(spawnSync(command[0], command.slice(1)).status, 0)
  assert.equal(fs.existsSync(path.join(testDir, "Daily.md")), false)
  assert.equal(fs.readFileSync(path.join(testDir, "Weekly.md"), "utf8"), "test")

  command = Model.deleteCommand(testDir, "Weekly")
  assert.equal(spawnSync(command[0], command.slice(1)).status, 0)
  assert.equal(fs.existsSync(path.join(testDir, "Weekly.md")), false)
  assert.equal(spawnSync(command[0], command.slice(1)).status, 0)
} finally {
  fs.rmSync(testDir, { recursive: true, force: true })
}

console.log("NotesModel tests passed")
