# WindowStrider 

this is my [Hammerspoon](https://www.hammerspoon.org/) script that i use daily to switch between windows

the goal of my setup is to imprint the window switching into the muscle memory and make it effortless, **so i don't have to think about it**

<p align="center">
<video src="https://github.com/user-attachments/assets/412adec0-9031-4aa3-8add-d4568e633036"></video>
</p>

to achieve this, WindowStrider allows you to bind applications to specific hotkeys and switch between their windows instantly

```lua
hs.loadSpoon("WindowStrider")
    :bindHotkey({"option"}, "2", { "com.google.chrome" })
    :bindHotkey({"option"}, "3", { "com.microsoft.VSCode", "dev.zed.Zed", "com.jetbrains.rider" })
```

in such a setup, switching between the browser and code editor is as simple as pressing <kbd>option</kbd> + <kbd>2</kbd> and <kbd>option</kbd> + <kbd>3</kbd>

### cycling

if you have multiple instances of the same application, WindowStrider will cycle through them on repeated presses

it works the same way for groups of multiple apps. in the example above, <kbd>option</kbd> + <kbd>3</kbd> will cycle through the windows of VSCode, Zed, and Rider.
this way, the muscle memory stays even if you use multiple code editors

### dynamic pinning

sometimes you want to quickly access an app that's not in your usual bindings.
instead of editing your config, you can use dynamic pinning

```lua
hs.loadSpoon("WindowStrider")
    :bindPinHotkey({"option"}, "1", "shift")
```

with this setup:
- <kbd>option</kbd> + <kbd>shift</kbd> + <kbd>1</kbd> pins the currently focused app to the hotkey
- <kbd>option</kbd> + <kbd>1</kbd> cycles through windows of the pinned app

this is useful when you're temporarily working with an app you don't usually use

### delay

the thought of switching to another app should instantly translate to the action of switching to it.
for this, WindowStrider is made with the goal of having as little delay as possible.
in my experience, even with many windows open, the delay is less than 30ms

## installation

1. download the [latest release](https://github.com/Dubzer/WindowStrider/releases/latest/download/WindowStrider.spoon.zip)
2. extract the archive and open with Hammerspoon
3. open `~/.hammerspoon/init.lua` file and add the loading of the spoon and the hotkey bindings.
use the `:bindHotkey(modifiers, key, appBundleIDs)` method, where:
    - `modifiers` is a table of modifier keys (e.g., `{"option", "shift"}`)
    - `key` is the key to bind
    - `appBundleIDs` is a table of application bundle identifiers. if you have [Raycast](https://www.raycast.com/) installed, you can find it by searching for the app and selecting "Copy Bundle Identifier" from the context menu.

```lua
hs.loadSpoon("WindowStrider")
    :bindHotkey({"option"}, "1", { "com.mitchellh.ghostty" })
    :bindHotkey({"option", "shift"}, "2", { "com.google.chrome", "com.apple.Safari" })
```

## comparisons

### macOS workspaces

sometimes i just want a brief glance at another app.  and the worst thing about workspaces is having to sit and wait for the animation to finish.
generally, i don't use workspaces because of this flaw

also, i see having multiple workspaces as an overhead to window management reasoning

### [AltTab](https://alt-tab-macos.netlify.app/) (or cmd-tab)

AltTab allows instant switching between windows, but because the order in the list is constantly changing, that doesn't allow you to develop muscle memory, 
instead having to pay attention to the list when pressing the hotkey

### [AeroSpace](https://github.com/nikitabobko/AeroSpace)

this tiling manager allows you to achieve a similar experience. unfortunately, it's not ideal since some non-resizable windows behave incorrectly.
also, i don't really need window tiling, and it's ok for me to keep all the windows on a single workspace
