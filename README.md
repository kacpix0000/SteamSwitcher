
# **SteamSwitcher**

A lightweight utility designed to automatically switch Steam accounts and launch specific games directly from your desktop. Works well with launchers like **Playnite.**

**SteamSwitcher** lets you switch Steam accounts and open games automatically. You just type the game's name and its App ID, and the program creates a `.vbs` file. When you click this file, it closes Steam, switches to the right account, and starts the game for you.

This tool is useful for people who have multiple Steam accounts and want to use Steam Family Library Sharing but cannot due to regional locks or the $5 minimum store spend restriction.

## Installation

1. Download the latest `STEAMSWITCHERINSTALLER.exe` from the Releases section.
2. Run the executable and proceed through the installation wizard.
3. Use the `SteamSwitcher.exe` shortcut created on your system to launch the main program interface.

## How to Use

Upon execution, SteamSwitcher initializes a Text User Interface (TUI) main menu. Navigate the application by entering the numerical value corresponding to the required action.

### First-Time Configuration
* **Setup paths [3]:** Select option `3` to define the system directory paths for your Steam installation. This step is mandatory before executing any profile operations.

### Generating Game Shortcuts
* **Create game profile [1]:** Select option `1` to generate a new game configuration. You will be prompted to provide the target Steam account, the game name, the Steam App ID, and the output directory. The application will compile a `.vbs` script at that location. Running this script will silently close Steam, update the registry for the target account, and launch the game.

### Profile Management
* **Manage game profiles [2]:** Select option `2` to display, modify, or execute previously configured Steam profiles stored in the local database.
* **Software Info [4]:** Displays current version compilation metadata, build statistics, and licensing overviews.
* **Exit Application [5]:** Safely terminates the PowerShell console session and unloads runtime variables.

---

![Logo](https://raw.githubusercontent.com/kacpix0000/SteamSwitcher/refs/heads/main/STSWlogo.ico)

## Feedback

For bug reports or feature requests, please use the GitHub Issues tab or reach out to us at [kacpixworks@gmail.com](mailto:kacpixworks@gmail.com?subject=Feedback%5D%20SteamSwitcher%20App).


## Authors

* [Kcpx_](https://github.com/kacpix0000)

*Note: AI assistance was utilized during the coding and documentation phases of this project.*
