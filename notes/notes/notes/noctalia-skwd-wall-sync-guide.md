# Syncing Noctalia's Wallpaper State with skwd-wall (Without Breaking skwd-paper Transitions)

**Goal:** Let skwd-wall (using skwd-paper as the renderer, with shader transitions) tell Noctalia what the current wallpaper is — for Noctalia's own theming/color sync — without Noctalia trying to render the wallpaper itself, and without losing skwd-paper's animated transitions.

**Stack assumed:** Niri compositor, skwd-wall + skwd-daemon (skwd-paper as the wallpaper engine), Noctalia shell.

---

## 1. Find Noctalia's real IPC command

Don't guess the syntax — pull it from Noctalia's own IPC registry:

```bash
qs -c noctalia-shell ipc show
```

Look for the `wallpaper` target. The working call is:

```bash
qs -c noctalia-shell ipc call wallpaper set /absolute/path/to/image.webp all
```

Notes:
- Use `qs -c noctalia-shell`, not `noctalia msg ...` (that's a v5-only binary and won't work on current installs).
- Use an **absolute path**, not `~` — tilde expansion isn't guaranteed to happen inside the IPC call context.
- Check the actual file extension. skwd-wall auto-converts imported wallpapers to `.webp` in the background, so a stale `.png` reference will fail silently (IPC call returns exit 0 but does nothing).
- `all` as the last argument applies to every monitor.

Verify it worked:
```bash
qs -c noctalia-shell ipc call wallpaper get all
```
This should echo back the path you just set.

---

## 2. Disable Noctalia's own wallpaper rendering

Noctalia has its own background-drawing layer (`noctalia-background-eDP-1`). If both Noctalia and skwd-paper try to render a background, they'll fight over the same layer and one will get hidden or override the other.

Check Noctalia's config:
```bash
grep -i "wallpaper" ~/.config/noctalia/settings.json
```

Find the wallpaper module's enable key (e.g. `wallpaper.enabled`) and set it to `false` — safely, via `jq`, with a backup first:

```bash
cp ~/.config/noctalia/settings.json ~/.config/noctalia/settings.json.bak
jq '.wallpaper.enabled = false' ~/.config/noctalia/settings.json > /tmp/settings.json.new \
  && mv /tmp/settings.json.new ~/.config/noctalia/settings.json
```

This stops Noctalia from *painting* a wallpaper layer. It can still *receive* the IPC call and use it for theming — it just won't compete visually.

---

## 3. Add the niri layer-rule for skwd-paper

Find your active niri config (it may not be the default `config.kdl` — check any file with `spawn-at-startup` or `include`):

```bash
grep -rln "spawn-at-startup\|include" ~/.config/niri/
```

Add this block to that file:

```kdl
layer-rule {
    match namespace="^skwd-paper-backdrop$"
    place-within-backdrop true
}
```

Restart niri (or reload config) after saving.

---

## 4. ⚠️ The trap: don't use `externalWallpaperCommand`

skwd-wall's config has a field called `externalWallpaperCommand`. It looks like the right place to put the Noctalia sync command — **it isn't**, if you want to keep transitions.

Setting `externalWallpaperCommand` tells skwd-daemon to treat that external tool as the **sole renderer** for wallpaper changes. It **skips its own shader transition step entirely** (confirmed via daemon logs — no `wall::apply::paper` log line fires when this field is set). You'll get correct wallpapers and correct Noctalia sync, but every change will be an instant hard cut, no animation.

If you already set this, clear it:
```bash
jq '.externalWallpaperCommand = ""' ~/.config/skwd-wall/config.json > /tmp/config.json.new \
  && mv /tmp/config.json.new ~/.config/skwd-wall/config.json
```

---

## 5. The actual fix: use `postProcessing` instead

`postProcessing` runs a command *after* skwd-paper has already rendered the wallpaper (transition included) — it doesn't take over rendering. This is the correct hook for "also notify Noctalia."

Set it like this:

```bash
jq '.postProcessing = [{"command": "qs -c noctalia-shell ipc call wallpaper set %path% all"}]' \
  ~/.config/skwd-wall/config.json > /tmp/config.json.new \
  && mv /tmp/config.json.new ~/.config/skwd-wall/config.json
```

Notes on syntax:
- Use skwd-wall's real placeholder tokens: `%path%`, `%type%`, `%name%` (percent-wrapped — check the README/`--help` for your version rather than assuming curly-brace `{path}` style).
- `postProcessing` expects an **array of entries**, and each entry can be a plain string or an object with a `command` key (an "untagged enum" internally — skwd-daemon tries each shape until one parses). If the object-with-`command` form throws a parse error in the logs, try adding `"enabled": true` alongside it.
- If you're ever unsure of a config field's exact shape and it's undocumented, you can pull it straight from the compiled binary:
  ```bash
  strings "$(which skwd-daemon)" | grep -i "postprocess" -A2 -B2
  ```
  Look for `struct`/`enum` names near the field — that's the real serde schema, more reliable than docs or guessing.

---

## 6. Restart and verify

```bash
systemctl --user restart skwd-daemon.service
journalctl --user -u skwd-daemon.service -n 20 --no-pager
```

No "did not match any variant" error here means the config parsed cleanly.

Then apply a wallpaper and tail the log live:
```bash
journalctl --user -u skwd-daemon.service -f
```

Pick a new wallpaper through skwd-wall's picker and confirm you see:
- A `skwd_daemon::wall::apply::paper` entry (transition actually ran), **and**
- The external command line for the Noctalia IPC call firing on the same apply

Then sanity-check the layer stack and Noctalia's state:
```bash
niri msg layers
qs -c noctalia-shell ipc call wallpaper get all
```

Expect: `skwd-paper` / `skwd-paper-backdrop` present, no competing Noctalia wallpaper layer, and `wallpaper get` returning the path you just picked.

---

## End result

- skwd-paper renders the wallpaper with full shader transitions (bounce, random, etc.)
- Noctalia is disabled as a renderer but still gets told the current wallpaper path via `postProcessing`, so its own color/theme sync stays working
- `externalWallpaperCommand` stays empty — it's a full-renderer-handoff switch, not a "run this too" hook
