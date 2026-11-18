# Zed Setup — Run C & C++ Files Without Compiling Manually

**Date:** 2026-10-13
**Machine:** `flickowens` (Linux, Wayland, zsh)
**Zed version:** 1.23.3 (`/usr/lib/zed/zed-editor`)
**Goal:** Press one key in Zed to compile and run the current C/C++ file, instead of manually running `gcc`/`g++` and then the output binary.

---

## TL;DR

- Open your **project folder** in Zed (`File → Open Folder`), *not* a loose `.c` file.
- With the project open, open your `.c`/`.cpp` file, click in the code, press **`F5`**.
- Zed compiles with `gcc`/`g++` (auto-detected by extension) and runs the binary from `/tmp`.
- This only works when a **project folder is open as a visible worktree** — that was the whole problem originally.

---

## Files changed / created

| File | What was done |
|---|---|
| `~/.config/zed/tasks.json` | Replaced the old/broken task with a working `Run C/C++ file` task |
| `~/.config/zed/keymap.json` | **Created** it (didn't exist) with `F5` / `Shift-F5` bindings |

Nothing else was modified. `~/.config/zed/settings.json` was left untouched.

---

## 1. `~/.config/zed/tasks.json`

Final contents:

```json
[
  {
    "label": "Run C/C++ file",
    "command": "case \"$ZED_FILE\" in *.c) gcc -Wall -g \"$ZED_FILE\" -o \"/tmp/$ZED_STEM\" -lm ;; *.cpp|*.cc|*.cxx|*.C) g++ -std=c++20 -Wall -g \"$ZED_FILE\" -o \"/tmp/$ZED_STEM\" ;; *) echo \"Not a C/C++ file: $ZED_FILE\" >&2; exit 1 ;; esac && \"/tmp/$ZED_STEM\"",
    "cwd": "$ZED_DIRNAME",
    "use_new_terminal": false,
    "allow_concurrent_runs": false,
    "reveal": "always",
    "save": "current"
  }
]
```

### What each field does

- **`label`** — name shown in the task picker (`task: spawn`).
- **`command`** — a shell `case` statement:
  - `.c` → `gcc -Wall -g file.c -o /tmp/name -lm`
  - `.cpp` / `.cc` / `.cxx` / `.C` → `g++ -std=c++20 -Wall -g file.cpp -o /tmp/name`
  - anything else → error message and stop
  - `&& "/tmp/$ZED_STEM"` — runs the binary **only if compilation succeeded**.
- **`cwd: "$ZED_DIRNAME"`** — run from the file's own folder (so relative `#include`s / data files work).
- **`save: "current"`** — auto-saves the active buffer before compiling (so it builds what you see, not a stale copy).
- **`use_new_terminal: false`** — reuse the same terminal tab for repeated runs.
- **`reveal: "always"`** — always show the terminal pane so you can see output and type input.

### Zed variables used

| Variable | Meaning |
|---|---|
| `$ZED_FILE` | absolute path of the currently focused file |
| `$ZED_STEM` | filename without extension (used for the `/tmp` output name) |
| `$ZED_DIRNAME` | folder containing the file |

The binary is written to `/tmp/$ZED_STEM`, so your source folder stays clean.

---

## 2. `~/.config/zed/keymap.json`

Final contents:

```json
[
  {
    "context": "Workspace",
    "bindings": {
      "f5": ["task::Spawn", { "task_name": "Run C/C++ file" }],
      "shift-f5": "task::Rerun"
    }
  }
]
```

- **`F5`** — runs the `Run C/C++ file` task.
- **`Shift-F5`** — re-runs the last task.

> If `F5` ever shows a *task picker/menu* instead of running directly, it means the named task could not be resolved (see the gotcha below).

---

## 3. How to use

1. `File → Open Folder` and choose your project folder (e.g. `~/Projects/practice`).
2. Open the `.c` / `.cpp` file from the project panel.
3. **Click inside the code** so the editor (not the terminal) has focus.
4. Press **`F5`**.

No keybinding? Use `Ctrl+Shift+P` → `task: spawn` → **Run C/C++ file**.

Interactive programs (`scanf` / `cin`) work — type into the terminal pane that opens.

---

## 4. The big gotcha — the actual root cause

This cost most of the debugging time, so it is written down carefully.

### Symptom
Only tasks that used **no variables** appeared in the task picker (`task: spawn`). Any task using `$ZED_FILE`, `$ZED_STEM`, `$ZED_DIRNAME`, or `$ZED_WORKTREE_ROOT` silently disappeared. Even after fixing the JSON, only `Example task` appeared — then, after adding probe tasks, only `ZZ1 no variables` showed.

### Why
Zed's task system resolves templates against a **`TaskContext`** built from your **focused file inside an open project (folder)**. From Zed's own source (`crates/task/src/task_template.rs`):

```rust
// If a referenced $ZED_* variable is not present in the context,
// substitution bails and the task is DROPPED from the list:
} else if variable_name.starts_with(ZED_VARIABLE_NAME_PREFIX) {
    if !default.is_empty() { ... } else {
        bail!("Unknown variable name: {variable_name}");   // -> task filtered out
    }
}
```

The files were being opened as **loose files**, not via an opened folder. So the workspace had:
- `workspaces.paths = ''` (no folder)
- worktree diagnostics: `visible 0` (no *visible* / root worktree)

With no visible worktree, no file/context variables existed, so every variable-based task was filtered out. Only variable-free tasks survived.

### Proof
Zed's log (`~/.local/share/zed/logs/Zed.log`) before the fix:

```
worktree diagnostics: projects 1, ... visible 0, ... largest /home/flickowens/Projects/practice/sequence.c (1 entries, 1 visible)
```

After opening the folder (`/usr/bin/zeditor /home/flickowens/Projects/practice`):

```
worktree diagnostics: projects 1, ... visible 1, strong 1, ... largest /home/flickowens/Projects/practice (20 entries, 20 visible)
```

`visible 1` + the folder as the largest entry = a real project worktree = variables resolve.

### Fix
Open the **folder** as a project. It was opened via the CLI:
```sh
/usr/bin/zeditor /home/flickowens/Projects/practice
```
(You can also use `File → Open Folder` in the UI.)

---

## 5. Golden rules going forward

1. **Always open the folder**, not an individual file:
   `File → Open Folder → ~/Projects/practice`.
2. Before pressing `F5`, make sure the **code editor has focus**, not the terminal panel.
3. Trust the project if Zed asks (`Trust`), so language servers and tooling work fully.

---

## 6. Troubleshooting checklist

| Symptom | Likely cause / fix |
|---|---|
| `F5` opens a task picker instead of running | The task didn't resolve → folder not open, or no file focused. Open the folder and click into the code. |
| `task: spawn` shows no tasks / only "Example task" | Same as above: no visible worktree / no focused file. |
| Task appears but compile errors | Expected — errors show in the terminal; the binary is not run on failure. |
| `"Not a C/C++ file"` | The focused file isn't `.c`/`.cpp`/`.cc`/`.cxx`/`.C`. |
| Nothing seems to update after editing `tasks.json` | `Ctrl+Shift+P` → `workspace: reload`, or restart Zed. |
| F5 does something unrelated | Check `~/.config/zed/keymap.json` is valid JSON and the `label` matches exactly. |

---

## 7. Caveats / tips

- **Single-file programs only.** For multi-file projects, add a second task, e.g.:
  `cmake --build build && ./build/app` or `make && ./app`.
- **`/tmp` name collisions:** two different files with the same stem (e.g. `~/a/main.c` and `~/b/main.c`) map to the same `/tmp/main`. If that bothers you, change the output to something like `"/tmp/${ZED_STEM}_$$"`.
- **Prefer clang?** Swap `gcc`→`clang` and `g++`→`clang++`.
- **Learning/debugging tip:** add `-fsanitize=address,undefined` to the flags to catch memory bugs.
- **Environment note:** Zed on this machine sometimes hangs on quit (`timed out waiting on app_will_quit`) and logs Wayland warnings. This is unrelated to tasks; it just makes "restart Zed" an unreliable step — prefer `workspace: reload`.

---

## 8. Optional fallback (if tasks ever misbehave again)

A shell function that always works, independent of Zed's task context. Add to `~/.zshrc`:

```zsh
run() {
  local f="${1:?usage: run <file.c|file.cpp>}"
  local out="/tmp/${f:t:r}"
  case "$f" in
    *.c)                        gcc -Wall -g "$f" -o "$out" -lm && "$out" ;;
    *.cpp|*.cc|*.cxx|*.C)       g++ -std=c++20 -Wall -g "$f" -o "$out" && "$out" ;;
    *) echo "not a C/C++ file: $f" >&2; return 1 ;;
  esac
}
```

Then in Zed's terminal: `run sequence.c`.
