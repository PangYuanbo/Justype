# JustType

> LLM-powered fuzzy keyboard input for macOS. No IME, no autocorrect — just
> type the way it sounds and let the model figure out what you meant.

[![Release](https://img.shields.io/github/v/release/PangYuanbo/Justype?display_name=tag)](https://github.com/PangYuanbo/Justype/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

JustType replaces the IME mental model with a single floating box. Tap a
trigger key, type whatever you want — Chinese, Japanese, Korean, mixed
languages, casual English, code identifiers, anything — and an LLM turns
your raw keystrokes into the text you actually meant. It then pastes the
final text into whatever app was focused.

```
wo yao chi fan       →  我要吃饭
hello sekai          →  hello 世界
ni hao i am bob      →  你好，I'm Bob
xie yi ge python script  →  写一个 Python script
```

---

## Table of contents

- [Why](#why)
- [Demo](#demo)
- [How it works](#how-it-works)
- [Install](#install)
- [First-run setup](#first-run-setup)
- [Configuration](#configuration)
- [Keyboard reference](#keyboard-reference)
- [Privacy & data](#privacy--data)
- [Build from source](#build-from-source)
- [Architecture](#architecture)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)
- [中文说明](#中文说明)

---

## Why

Traditional IMEs assume one language at a time and a fixed phonetic
scheme. JustType assumes you have a model that can read context. That
gives you:

- **No mode-switching.** Drop English words into Chinese sentences (or
  vice versa) without toggling input source.
- **Tolerant input.** Typos, missing tones, no spaces, run-on syllables
  — the model handles it.
- **Screen context (optional).** When enabled, JustType attaches a small
  screenshot so the model knows which app you're in and which language
  the surrounding text is in. Useful when typing into a Chinese chat in
  one window and English code in another.
- **Bring your own key.** Works with any OpenAI-compatible endpoint —
  OpenRouter, OpenAI, Together, vLLM, LiteLLM, your own server.

---

## Demo

Drop a screen recording / GIF here once you've captured one:
`docs/demo.gif`. Suggested flow: open Notes, tap Right Option, type
`wo yao gei mama da ge dianhua`, pause, ↩ to accept, ↩ again to submit.

---

## How it works

1. **Tap the trigger key** (default: Right Option `⌥`; alternatives: Fn,
   Caps Lock). A floating box appears at the bottom of the screen.
2. **Type freely** in raw keyboard form. Letters, numbers, basic
   punctuation, and spaces are captured into a "pending" segment.
3. **Pause briefly** (≈ 0.5 s). JustType sends the pending segment plus
   any already-committed text and an optional screenshot to your model;
   a candidate appears under the input as an IME-style suggestion.
4. **Press `↩`** to accept the candidate. It locks in as committed text.
   Keep typing more — each new pause produces another candidate that
   continues from what's already locked in.
5. **Press `↩` again when everything is converted** — JustType pastes
   the full result into the focused app and dismisses the box.
   *(Tapping the trigger key a second time also works.)*

`Esc` aborts the session without pasting anything. `Backspace` edits.

The "magic box" is non-activating — your previous app keeps its focus,
so the final paste lands exactly where you were typing before.

---

## Install

1. Download `JustType.zip` from the
   [latest release](https://github.com/PangYuanbo/Justype/releases/latest).
2. Double-click the zip to extract `JustType.app`.
3. Drag `JustType.app` into `/Applications`.

### First launch — Gatekeeper workaround

JustType ships signed with an Apple Development certificate but is **not
notarized** (notarization needs a paid $99/yr Apple Developer Program
membership). On first launch macOS will block it with one of these:

> "JustType" can't be opened because Apple cannot check it for malicious
> software.

> Apple could not verify "JustType" is free of malware…

This is a one-time workaround:

1. Open `/Applications` in Finder.
2. **Right-click** `JustType.app` → **Open**.
3. In the dialog that appears, click **Open** again.

Or, if you've already double-clicked it once and got the warning:

1. Open **System Settings → Privacy & Security**.
2. Scroll down — you'll see "JustType was blocked from use because it
   is not from an identified developer." Click **Open Anyway** beside it.
3. Confirm in the next dialog.

After this one-time approval, JustType launches normally — no more
warnings.

---

## First-run setup

1. **Launch JustType.** A keyboard icon appears in the menu bar
   (top-right of the screen). The app has no Dock icon by design.
2. **Grant Accessibility.** macOS will prompt the first time it sees
   JustType try to read keyboard events. The path is:
   *System Settings → Privacy & Security → Accessibility*. Enable the
   **JustType** switch.
3. **Fully quit and relaunch** (right-click the menu-bar icon → Quit,
   then reopen). macOS only honors the Accessibility grant for the
   process running at the moment of the toggle.
4. **Open Settings** (menu-bar icon → *LLM Settings…*).
5. **Paste your API key.** Get a free one at
   [openrouter.ai/keys](https://openrouter.ai/keys) — JustType
   auto-fetches the model list as soon as the key is valid.
6. **Pick a model.** Vision-capable models (📷) bubble to the top,
   because JustType uses screen context by default. A solid default is
   `google/gemini-2.5-flash`.
7. **Hit *Test current config*** to verify everything is wired up.

That's it. Tap the trigger key in any text field and start typing.

---

## Configuration

Everything is in the menu-bar menu and the Settings window.

### Menu bar

| Item                    | What it does                                         |
| ----------------------- | ---------------------------------------------------- |
| Enable / Disable        | Master switch; the event tap stops when disabled.    |
| Trigger Key             | Right Option · Fn · Caps Lock.                       |
| Language                | English · 中文. Switches the entire UI live.         |
| Use Screenshot as Context | Attach a low-detail screenshot to each LLM request. |
| LLM Settings…           | Open the settings window.                            |
| History                 | Last 50 sessions; click to copy the result.          |
| Quit                    | ⌘Q.                                                  |

### Settings window

- **Appearance → Language** — toggle between English and 中文.
- **Endpoint → Base URL** — any OpenAI-compatible host. Default
  `https://openrouter.ai/api/v1`. Use `https://api.openai.com/v1` for
  OpenAI, your own URL for self-hosted gateways.
- **Endpoint → API Key** — saved to `UserDefaults`. The settings UI
  treats it as a secure field. Editing the key triggers a debounced
  re-fetch of the model list.
- **Model** — searchable list of every model your key can call. Models
  marked with a 📷 accept image input (recommended when *Use
  Screenshot as Context* is on). The "Vision-capable only" filter
  trims the list.
- **Test current config** — runs a small `ni hao` round-trip and
  reports the result.

### Triggers — which to choose?

| Trigger        | Pros                                                | Cons                                                                  |
| -------------- | --------------------------------------------------- | --------------------------------------------------------------------- |
| Right Option ⌥ | Default. Doesn't conflict with anything common.     | If you remap your right-Option (e.g. Karabiner), pick a different one. |
| Fn (🌐)        | Quick to reach; not used by most apps.              | macOS may still intercept Fn for "Show Emoji & Symbols" — check System Settings → Keyboard → "Press 🌐 key to". |
| Caps Lock      | Big, easy to find by feel.                          | Pressing it physically toggles the system Caps Lock LED, which is jarring. |

---

## Keyboard reference

Inside an active session (after the first trigger tap):

| Key                                  | Effect                                              |
| ------------------------------------ | --------------------------------------------------- |
| Letters / numbers / `,.?!'-` / Space | Inserted into the raw segment **at the caret position**. |
| `←` / `→`                            | Move the caret inside the raw segment.              |
| `Home` / `End` (or Fn+←/→)           | Jump caret to start / end of raw segment.           |
| `⌫` Backspace                        | Delete the character to the left of the caret. With raw empty, pulls the last character off the committed text. |
| `Fn`+`⌫` (Forward Delete)            | Delete the character to the right of the caret.    |
| `↩` (raw non-empty)                  | Convert the raw segment now (force-commit). Does **not** submit. |
| `↩` (everything converted)           | Submit — paste the full text into the focused app. |
| Trigger key (second tap)             | Same as "submit" above.                             |
| `Esc`                                | Abort. Nothing is pasted.                           |

Outside a session, JustType doesn't intercept any keys.

### What if pasting fails?

After ↩-submit, JustType verifies via Accessibility that the converted
text actually appeared in the focused field. If it's clearly missing
(e.g. nothing was focused, or a sandboxed app silently dropped the
Cmd+V), JustType **leaves the converted text on your clipboard** and
shows a quick amber HUD that says *"Couldn't paste — press ⌘V to
insert."* Just press ⌘V wherever you want it to go.

If JustType *can't* verify the paste either way (some Electron apps
and a few web fields hide AXValue), the previous clipboard contents
are restored optimistically.

---

## Privacy & data

JustType is local-first by design, but the LLM call is by definition
remote. Specifically:

- **Keystrokes during a session.** The raw letters you typed in the
  magic box are sent to the endpoint you configured. Nothing is sent
  outside an active session — JustType doesn't keylog.
- **Screen context (optional).** When *Use Screenshot as Context* is on,
  a single low-resolution JPEG of your primary display is captured at
  the moment of conversion and attached to the request. The screenshot
  is never written to disk. Toggle the option off in the menu bar to
  send text only.
- **History.** The 50 most recent input/output pairs are saved to
  `~/Library/Application Support/JustType/history.json`. Use *History
  → Clear History* to wipe it.
- **Learned corrections.** When you manually edit a chunk of text right
  after JustType pastes it, JustType reads the new content via the
  Accessibility API and stores `(raw, what-we-produced, what-you-changed-it-to)`
  in `~/Library/Application Support/JustType/corrections.json` (capped
  at 50 entries). The most recent ~8 are appended to the system prompt
  on every subsequent request, so the model picks up your preferences
  over time. Inspect / clear from menu bar → *Learned Corrections*.
- **API key.** Stored in `UserDefaults`. JustType ships with no key;
  the value is whatever you paste in.
- **Telemetry.** None. There is no analytics, crash reporter, or
  phone-home from JustType itself. Your provider (OpenRouter / OpenAI /
  etc.) sees its usual request logs.

---

## Build from source

### Requirements

- macOS 14 (Sonoma) or later.
- Swift 5.9+ toolchain (`swift --version`).
- Optional: an Apple Developer signing identity. Without one, the
  Makefile generates a local self-signed cert so the Accessibility
  grant survives rebuilds.

### Quick start

```bash
git clone https://github.com/PangYuanbo/Justype.git
cd Justype
make run
```

That builds the release binary, wraps it in `JustType.app`, signs it,
and launches it.

### Make targets

```bash
make build      # swift build -c release
make bundle     # build + assemble the .app + sign it (default for `make`)
make run        # bundle then `open` it
make install    # copy the .app to /Applications
make sign       # re-sign the existing bundle in build/
make identity   # print the signing identity that will be used
make reset-tcc  # one-time: wipe stale Accessibility TCC entries
make clean      # rm -rf .build build
```

### Project layout

```
Sources/JustType/
  main.swift                  # entry point
  AppDelegate.swift           # lifecycle, main menu, session orchestration
  AppState.swift              # @Published settings, persisted to UserDefaults
  EventTap.swift              # CGEventTap → trigger detection + key routing
  TriggerKey.swift            # Fn / Right Option / Caps Lock detection
  MagicSession.swift          # state machine: committed / raw / candidate
  HUDController.swift         # floating panel + SwiftUI HUD view
  MenuBarController.swift     # status item + menu
  SettingsWindow.swift        # SwiftUI settings UI with model picker
  LLMClient.swift             # OpenAI-compatible chat completions client
  ModelCatalog.swift          # /models discovery + vision detection
  Screenshotter.swift         # ScreenCaptureKit-based screen context
  TextInjector.swift          # Cmd+V paste with input-source juggling
  InputSourceManager.swift    # Carbon TIS helpers
  HistoryStore.swift          # last-50 history JSON
  CorrectionStore.swift       # learned `(raw → bad → good)` triples
  EditWatcher.swift           # AX-reads focused field after paste, detects edits
  AccessibilityHelper.swift   # AXIsProcessTrusted + system settings deep-link
  L10n.swift                  # English/Chinese string table
Resources/
  Info.plist                  # bundle metadata, permission strings, LSUIElement
scripts/
  ensure-cert.sh              # create a local self-signed cert if needed
  get-sign-identity.sh        # pick the most stable available identity
Makefile
Package.swift
```

---

## Architecture

```
┌──────────────┐  flagsChanged    ┌────────────────┐
│ EventTap     │ ───────────────► │ AppDelegate    │
│ (CGEventTap) │  keyDown         │  (orchestrator)│
└──────────────┘ ───────────────► └─────┬──────────┘
                                        │
        commands (append/back/enter)    │       publishes
                ▼                       ▼
          ┌──────────────┐    ┌──────────────────┐
          │ MagicSession │    │ HUDController    │
          │ committed    │    │ (NSPanel +       │
          │ raw          │    │  SwiftUI capsule)│
          │ candidate    │    └──────────────────┘
          │ + debounced  │
          │   LLM call   │
          └──────┬───────┘
                 │ /chat/completions
                 ▼
          ┌──────────────┐
          │ LLMClient    │── any OpenAI-compatible API
          └──────────────┘
```

**Trigger detection.** A `CGEventTap` listens for `flagsChanged` and
`keyDown`. When the user presses the configured trigger, we toggle a
boolean and either start a session (begin consuming key events) or
finalize one (paste). When `consumingKeys = false`, every keystroke
passes through normally — the rest of macOS is unaware.

**Debounced conversion.** Every accepted keystroke schedules a 500 ms
debounce. If nothing happens during that window, the current `raw`
segment is sent to the LLM. Once a response comes back, the result is
shown as a candidate but not auto-committed. ↩ commits.

**Continuation context.** When a session already has committed text,
the prompt is structured so the model sees the previous segment as
`ALREADY_WRITTEN:` context and only translates the new `TO_CONVERT:`
segment, then continues naturally.

**Learned corrections.** After a paste, `EditWatcher` reads the focused
text field via Accessibility, locates our injected text using
prefix/suffix anchors from the baseline, and waits ~8 seconds. If the
content of that region has changed, the difference is recorded in
`CorrectionStore` as a `(raw → bad → good)` triple. The most recent
~8 triples are appended to the system prompt on every future request
as authoritative user preferences — so a habit like "I always write
*Beijing* not *北京*" gets respected after the first correction.

**Pasting back.** Final injection goes through the system clipboard
(Cmd+V). Before pasting, JustType:
1. Snapshots the current pasteboard items so they can be restored.
2. If a CJK input source is active, briefly switches to ABC so the
   paste characters aren't reinterpreted.
3. Posts a synthetic Cmd+V via `cgAnnotatedSessionEventTap`.
4. Restores both the pasteboard and the input source.

---

## Troubleshooting

### I tap the trigger key and nothing happens

Most likely Accessibility hasn't been granted to the *current* binary.
A re-signed build invalidates the previous TCC grant.

1. System Settings → Privacy & Security → Accessibility.
2. Find **JustType**, switch it **OFF**, then **ON** again.
3. Right-click the menu-bar keyboard icon → Quit. Reopen the app.

### The trigger key isn't doing anything (still)

Check which trigger you have selected. The default is Right Option `⌥`
(the one to the *right* of the spacebar). Left Option doesn't count.

If you remap your right-Option in Karabiner-Elements or
hidutil, switch JustType to a different trigger from the menu.

If you picked Fn, make sure System Settings → Keyboard → "Press 🌐 key
to" is set to *Do Nothing* (otherwise macOS swallows it).

### I can't paste my API key into the Settings field

Fixed in v0.2.1+. Make sure you're on the latest release.

### "HTTP 401" when fetching models

Bad / revoked API key, or your endpoint expects a different
authentication header. Verify the key works in `curl`:

```bash
curl https://openrouter.ai/api/v1/models \
  -H "Authorization: Bearer YOUR_KEY"
```

### "HTTP 402" / "insufficient credits"

OpenRouter free models have a daily request cap. Pick a different model
or top up your account.

### The conversion is wrong

- Make sure the model you picked is multilingual *and* preferably
  vision-capable (📷). Tiny models like `tiny-llama` will produce
  nonsense.
- Try toggling *Use Screenshot as Context* on — for short ambiguous
  inputs the screen context can be the difference between a good
  guess and a bad one.
- Provide more keystrokes; very short inputs (`a`, `wo`) are
  inherently ambiguous.

### The pasted text replaces my selection / pastes the wrong thing

JustType uses Cmd+V. If you had something selected in the focused app,
that selection is overwritten — same as a normal paste. JustType
restores your previous clipboard automatically after pasting.

---

## FAQ

**Is this an input method?**
No. JustType doesn't register as a TIS (Text Input Source) — it's a
floating, opt-in transformation. Your normal keyboard layout and IMEs
still work everywhere outside the magic box.

**Does it work offline?**
Only if you point it at a local OpenAI-compatible server (LM Studio,
Ollama with the `/v1` shim, vLLM, etc.). Set the Base URL to
`http://localhost:PORT/v1` and pick whatever model your server is
serving.

**Can I use it with OpenAI / Together / Anthropic / xxx?**
- OpenAI: yes — `https://api.openai.com/v1`, your `sk-…` key.
- Together / Fireworks / DeepSeek / LiteLLM proxies: yes, all OpenAI
  compatible.
- Anthropic native: not directly — use OpenRouter or LiteLLM as a
  bridge.

**Does it support languages other than Chinese?**
Yes. The system prompt is multilingual and works with Japanese,
Korean, Vietnamese, mixed-language, and casual English. Whatever your
chosen model supports.

**Does it cost money?**
Only what you pay your model provider. JustType itself is free.
Several OpenRouter models are free up to a daily quota; the default
`google/gemini-2.5-flash` is cheap.

**How do I uninstall?**
Quit the app, drag `/Applications/JustType.app` to the trash. To also
remove settings and history:
```bash
defaults delete com.justype.app
rm -rf ~/Library/Application\ Support/JustType
```

---

## Roadmap

- [ ] Notarization so first launch doesn't show a Gatekeeper dialog.
- [ ] Auto-update via Sparkle.
- [ ] More languages in the UI (PRs welcome — see `Sources/JustType/L10n.swift`).
- [ ] Custom system prompt per session / per app.
- [ ] Streaming candidates as the model produces them.
- [ ] Per-app "always on" mode that converts every keystroke.
- [ ] Optional inline preview overlay (instead of the bottom HUD).

---

## Contributing

Bug reports, feature requests, and PRs are welcome. The codebase is
small and intentionally readable — about 1,800 lines of Swift across
the files listed above. A few notes:

- One file = one responsibility. Don't dump everything into AppDelegate.
- The HUD reads from `MagicSession` via a `HUDSnapshot` struct so the
  view layer is dumb. Keep state changes in the session.
- New user-facing strings go in `L10n.swift` with both `en` and `zh`
  variants.
- Run `swift build -c release` before opening a PR to make sure the
  release configuration compiles (the SDK occasionally complains
  about things `swift build` alone misses).

---

## License

MIT. See [LICENSE](LICENSE).

---

## 中文说明

> 给 macOS 的 LLM 模糊键盘输入工具。不用切输入法,直接按裸键盘的形式打字,
> 由模型推断你想表达的最终文字 — 中文、日文、韩文、大小写、标点,都行。

### 怎么用

1. 按一下触发键(默认右 Option `⌥`,可改 Fn / Caps Lock)。屏幕底部弹出
   一个浮动输入框。
2. 用裸键盘形式打字,例如 `wo yao chi fan`。
3. 停顿 ~0.5 秒,候选 `我要吃饭` 出现在下方。
4. 按 `↩` 接受候选 — 候选变成已确认部分;可继续打更多。
5. 全部转换完毕后再按 `↩`,完整内容自动粘贴到当前输入框。
   (再按一次触发键也能提交。)

`Esc` 取消,`Backspace` 删字。

### 安装

去 [Releases](https://github.com/PangYuanbo/Justype/releases/latest) 下载
`JustType.dmg`,拖进 Applications。第一次打开会被 Gatekeeper 拦,**右键
点 App → 打开** 即可。

首次启动:
1. 系统设置 → 隐私与安全性 → 辅助功能,把 **JustType** 打开。
2. 完全退出 App 再重启(辅助功能授权要重启才生效)。
3. 菜单栏 ⌨️ → **LLM Settings…**,粘贴 OpenRouter API key
   ([openrouter.ai/keys](https://openrouter.ai/keys) 免费注册)。
4. 模型列表会自动加载,选一个支持图片输入的(📷),例如
   `google/gemini-2.5-flash`。

### 切换语言

菜单栏 ⌨️ → **Language**,或设置面板的 **Appearance** 区,在 English 和
中文之间切换。整个 UI 即时更新。

更多细节(快捷键、隐私、源码构建、故障排查、FAQ)请翻上面的英文版,
内容是一致的。
