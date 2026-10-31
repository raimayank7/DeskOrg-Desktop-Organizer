<p align="center">
  <img src="DeskOrgLogo.png" alt="DeskOrg logo" width="128" height="128">
</p>

<h1 align="center">DeskOrg — Desktop Organizer</h1>

<p align="center">
  <strong>Your desktop, sorted.</strong> Organize files, automate the cleanup, keep your flow.
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Windows%2010%20%2F%2011-0078D6">
  <img alt="Built with PowerShell" src="https://img.shields.io/badge/built%20with-PowerShell%20%2B%20WPF-5391FE">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-2FE6C8">
  <img alt="Code-signed" src="https://img.shields.io/badge/code-signed-8C7BFF">
</p>

<p align="center">
  Built by <a href="https://niveshsahayak.in"><strong>Nivesh Sahayak</strong></a> ·
  <a href="https://niveshsahayak.in/p/deskorg.html">Online guide</a>
</p>

---

## What is DeskOrg?

**DeskOrg** is a lightweight Windows app that keeps your desktop tidy — automatically. It sorts
the files cluttering your desktop into neat category folders (Documents, Images, Installers, and
more) using rules **you** control. Run it on demand with one click, or let it run quietly in the
background so new files get filed the moment they land.

Everything runs **locally on your PC** — nothing is uploaded anywhere.

| | |
|---|---|
| 🧹 **One-click cleanup** | Sort a messy desktop into folders instantly with **Organize Now**. |
| 🤖 **Smart automation** | A background watcher files new items for you, hands-free. |
| 🛡️ **Safe & yours** | Code-signed, local-only, with rules and protected file types you set. |
| ⚙️ **Fully configurable** | Edit which file types go where; protect files that should never move. |

---

## Download & install

1. Go to the [**Releases**](../../releases) page and download **`DeskOrgSetup.exe`** (latest).
2. Run it. DeskOrg is signed with a **self-made certificate**, so the first time Windows may show
   a blue **“Windows protected your PC”** box — click **More info → Run anyway**.
3. If a **Yes / No** security prompt (UAC) appears, click **Yes**.
4. When setup finishes, the guide opens automatically and DeskOrg is ready in your Start Menu and
   (optionally) on your desktop.

> The installer also trusts DeskOrg's certificate on your machine, so after the first install
> Windows recognizes it as a verified publisher (**Nivesh Sahayak**). Uninstalling removes it again.

Having trouble? See **[Troubleshooting](#troubleshooting)** below, or open the **Setup Help** shortcut
that ships in your Start Menu.

---

## How to use it

Open DeskOrg (desktop icon or Start Menu). A short splash appears, then the **Control Center** opens.
Five tabs run down the left side:

| Tab | What it does |
|-----|--------------|
| **01 · Overview** | Home dashboard — a quick welcome and the current status of your setup (rules, automation, logs). |
| **02 · Organize** | **Organize Now** runs the cleanup. Also opens your Windows Desktop folder or the DeskOrg app folder. |
| **03 · Smart Automation** | Install / enable the background watcher, check its status, disable it, or uninstall automation. |
| **04 · Rules & Settings** | Edit your rules (which file types go into which folder), open the app folder, refresh status. |
| **05 · Activity & Logs** | Open the DeskOrg log to see what was moved; confirm the organizer and automation scripts are present. |

**Three steps to get going:**

1. **Open DeskOrg.**
2. **Go to Organize → Organize Now** — this sorts your desktop into category folders. That's the core.
3. **(Optional) Turn on automation** under *Smart Automation* so new files are filed automatically.

👉 Full illustrated guide: **<https://niveshsahayak.in/p/deskorg.html>**

---

## How it works

DeskOrg is a set of **PowerShell + WPF** scripts wrapped in a small signed launcher. There is no
background service you don't control and no network access.

```
DeskOrg.exe  (signed launcher, built from DeskOrgLauncher.ps1 via PS2EXE)
      │
      ├─▶ DeskOrgSplash.ps1          5-second branded splash (WPF)
      │
      └─▶ DeskOrgControlCenter.ps1   the main window (WPF UI, 5 tabs)
                 │
                 ├─▶ DeskOrgOrganizer.ps1   the sorting engine (reads your rules, moves files)
                 │
                 └─▶ DeskOrgAutomation.ps1  installs / manages the background watcher
                            │
                            └─▶ DeskOrgWatcher.ps1   watches the desktop, files new items live
```

**The sorting engine.** `DeskOrgOrganizer.ps1` finds your real Desktop folder (via the registry,
so it works even with a relocated or OneDrive desktop), reads your rules, and moves each loose file
into a category subfolder — `Documents`, `Images`, `Spreadsheets`, `Videos`, `Audio`, `Archives`,
`PDFs`, `Presentations`, and `Other Files` for anything unrecognized. Every move is written to a
log at `%TEMP%\DeskOrg.log`.

**Protected file types stay put.** Executables and scripts (`.exe`, `.msi`, `.bat`, `.ps1`, `.lnk`,
`.dll`, …) are listed as *protected* and are never moved, so shortcuts and installers on your
desktop keep working.

**Your rules live with you.** The shipped `DeskOrgRules.json` is only a default seed. On first run
it is copied to **`%LOCALAPPDATA%\DeskOrg\DeskOrgRules.json`**, and that per-user copy is what you
edit from *Rules & Settings*. Because it lives in your profile, your rules **survive updates and
reinstalls**, and DeskOrg can run from a read-only location like `C:\Program Files`.

**Automation (optional).** Enabling Smart Automation registers `DeskOrgWatcher.ps1` to run in the
background and file new desktop items as they appear. You can disable or fully uninstall it anytime
from the same tab.

**Signed & verified.** All scripts and the launcher are Authenticode-signed with the project's
code-signing certificate (`CN=DeskOrg Code Signing (Nivesh Sahayak)`). The Control Center is even
launched with `-ExecutionPolicy AllSigned`, so Windows will refuse to run any file that has been
tampered with. Only the **public** certificate (`DeskOrg-CodeSigning.cer`) is included here — the
private key is never published.

---

## Rules & configuration

Rules are a simple JSON file. The default looks like this (abridged):

```jsonc
{
  "SourceFolder": "Desktop",
  "UnknownFileBehavior": "Other Files",
  "ProtectedExtensions": [ ".lnk", ".url", ".exe", ".msi", ".bat", ".ps1", "..." ],
  "Extensions": {
    ".pdf":  "PDFs",
    ".docx": "Documents",
    ".xlsx": "Spreadsheets",
    ".pptx": "Presentations",
    ".png":  "Images",
    ".mp4":  "Videos",
    ".mp3":  "Audio",
    ".zip":  "Archives"
  }
}
```

- **`Extensions`** — maps a file extension to the folder it should go into. Add your own anytime.
- **`ProtectedExtensions`** — file types DeskOrg will never move.
- **`UnknownFileBehavior`** — where unrecognized files go (default: `Other Files`).

Edit the copy at `%LOCALAPPDATA%\DeskOrg\DeskOrgRules.json` (easiest via **Rules & Settings** in the
app), then run **Organize Now** again.

---

## Building from source

You only need this if you want to compile the installer yourself. Requirements: Windows,
PowerShell 5.1+, the [`PS2EXE`](https://github.com/MScholtes/PS2EXE) module, and
[Inno Setup 6](https://jrsoftware.org/isinfo.php).

```powershell
# From the project folder — builds the launcher, signs everything,
# then compiles DeskOrgSetup.exe into .\Installer\
.\Build-Installer.ps1
```

The build chain is: **PS2EXE** (compile `DeskOrgLauncher.ps1` → `DeskOrg.exe`) → **sign** all
`*.ps1` and `*.exe` with the code-signing certificate → **Inno Setup** (`DeskOrg.iss`) compiles the
installer → the installer itself is signed. To re-sign after an edit without a full rebuild, use
`.\Resign-DeskOrg.ps1`.

> Building with your **own** certificate? Swap in your `.pfx` (keep it out of the repo — it's
> already git-ignored) and update the subject name in `DeskOrg.iss` and the resign scripts.

---

## Project structure

| File / folder | Purpose |
|---|---|
| `DeskOrgLauncher.ps1` → `DeskOrg.exe` | Small signed launcher that starts the splash + Control Center. |
| `DeskOrgSplash.ps1` | 5-second branded splash screen (WPF). |
| `DeskOrgControlCenter.ps1` | Main window — the 5-tab UI. |
| `DeskOrgOrganizer.ps1` | The file-sorting engine. |
| `DeskOrgWatcher.ps1` | Background watcher for Smart Automation. |
| `DeskOrgAutomation.ps1` | Installs / enables / removes the watcher. |
| `DeskOrgRules.json` | Default rules (seed; your editable copy lives in `%LOCALAPPDATA%\DeskOrg`). |
| `DeskOrg.iss` | Inno Setup script that builds `DeskOrgSetup.exe`. |
| `Build-Installer.ps1` / `Resign-DeskOrg.ps1` | Build & code-signing automation. |
| `Install-DeskOrg.ps1` | Script-based installer (alternative to the setup exe). |
| `DeskOrg-Guide.html` / `DeskOrg-Setup-Help.html` | Offline onboarding guide & troubleshooting pages. |
| `DeskOrgLogo.png` / `DeskOrg.ico` | App artwork. |
| `Unbounded.ttf` | Display font (see credits). |
| `DeskOrg-CodeSigning.cer` | **Public** code-signing certificate (safe to share). |

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Blue **“Windows protected your PC”** box | Click **More info → Run anyway**. It appears because the app is self-signed, not malicious. |
| A **Yes / No** prompt and setup didn't finish | Run the installer again and click **Yes** (it needs admin to install for all users). |
| Antivirus flagged it | New self-signed apps are sometimes flagged by heuristics. Allow it, or build from source yourself. |
| Nothing moved after *Organize Now* | Your desktop may already be sorted, or files match **protected** types. Check `%TEMP%\DeskOrg.log`. |

More detail ships in the **Setup Help** page (Start Menu → DeskOrg → Setup Help).

---

## Privacy & safety

- **100% local.** DeskOrg never sends your files or any data over the network.
- **Non-destructive.** It *moves* files into folders on the same desktop — it doesn't delete them.
- **Tamper-evident.** Code-signing lets Windows verify the scripts haven't been altered.

---

## Credits

Built with care by **[Nivesh Sahayak](https://niveshsahayak.in)**.

- 🌐 Website: <https://niveshsahayak.in>
- 📖 Guide: <https://niveshsahayak.in/p/deskorg.html>
- 📞 Contact: 8054009300

If you use, fork, or build on DeskOrg, please keep the **Nivesh Sahayak** credit as required by the
license below. A link back to the guide or website is always appreciated. 🙏

### Third-party

- **Unbounded** typeface — © The Unbounded Project Authors, licensed under the
  [SIL Open Font License 1.1](https://openfontlicense.org/). Bundled as `Unbounded.ttf`.

---

## License

Released under the **[MIT License](LICENSE)** — © 2026 Nivesh Sahayak. You may use, modify, and
distribute it freely, **provided the copyright and credit notice are kept** in all copies.
