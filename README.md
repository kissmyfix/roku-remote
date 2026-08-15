# roku-remote
Quick and dirty bash script for interacting with a Roku device from your Linux workstation.

This project is built with a minimalist vision: it relies strictly on standard built-in Linux utilities (bash, curl, sed). It features an automated setup wizard that auto-discovers your Roku over the local network using a transient Python SSDP probe—falling back to manual IP assignment gracefully if Python is missing.

## Features

* Zero Overhead: No heavy language runtimes or third-party packages required.
* Auto-Discovery: Scans your local network for active Roku devices automatically.
* App Synchronization: Pulls your actual channel list directly from your device, allowing you to map up to 10 favorite channels to instant-launch hotkeys.
* Headless Integration: Tailored specifically to run inside an overlay dialog window via system-wide hotkeys.
* Dual Interface Modes: Features a direct directional input mode and a dynamic grid layout to navigate synced channels and media keys.

---

## Installation and First Run

1. Clone the repository and navigate into the directory:
   ```bash
   git clone https://github.com/kissmyfix/roku-remote.git
   cd roku-remote
   ```

2. Make the script executable:
   ```bash
   chmod +x roku.sh
   ```

3. Launch the script. Because the configuration blocks are blank by default, the script will automatically launch the Setup Wizard:
   ```bash
   ./roku.sh
   ```

### Reconfiguration and Resetting

* To overwrite your current settings and change devices or apps, run the script with the setup flag:
  ```bash
  ./roku.sh --setup
  ```

* To completely wipe your IP and app choices back to a clean template state before sharing your code, execute:
  ```bash
  bash -c 'source ./roku.sh && reset_config'
  ```

---

## Keyboard Control Conventions

Once the remote interface is open, control your television using your physical keyboard. The script processes commands via the following layouts:

| Key | Roku Command | Description |
| :--- | :--- | :--- |
| Spacebar | Play / Pause | Toggles playback state |
| Enter | Select | Clicks the active item or OK |
| Backspace | Back | Returns to the previous screen |
| Page Up / Page Down | Cycle Apps | Cycle through your chosen top 10 channels |
| Arrows (Up/Down/Left/Right) | Directional Pad | Navigates menus natively |
| Tab | Toggle Layout | Switches between the direct remote and the app grid |

---

## Headless CLI Automation (No GUI)

You can bypass the interactive terminal interface entirely by passing direct command arguments to the script. This is useful for mapping specific actions to specialized multimedia keys or automated cron jobs:

```bash
./roku.sh play    # Toggles play/pause instantly
./roku.sh home    # Returns to the Roku home screen
./roku.sh select  # Sends an 'OK' / 'Select' click
```

### Available CLI Commands:
up, down, left, right, select, back, home, info, play, fwd, rev

---

## GNOME Desktop Integration (Ctrl+Alt+K Workflow)

For a seamless experience, you can bind this script to a global desktop environment hotkey. This allows you to press Ctrl+Alt+K anywhere on your computer to drop down a compact control window instantly.

### Setting up the GNOME Shortcut:

1. Open your system Settings and navigate to Keyboard, then Keyboard Shortcuts, and select View and Customize Shortcuts.
2. Scroll to the bottom and select Custom Shortcuts, then click Add Shortcut (+).
3. Configure the fields exactly as follows:
   * Name: Roku Remote
   * Command: gnome-terminal --class="roku-popup" --geometry=44x24 -- ./path/to/roku.sh
   * Shortcut: Press Ctrl + Alt + K
4. Click Add.

Now, pressing Ctrl+Alt+K spawns a dedicated mini-terminal overlay allowing you to control your television completely mouse-free.

---

## License

This project is dedicated to the public domain under the Unlicense. Feel free to copy, modify, publish, use, compile, sell, or distribute this software in any form, for any purpose, commercial or non-commercial. See the LICENSE file for more details.
