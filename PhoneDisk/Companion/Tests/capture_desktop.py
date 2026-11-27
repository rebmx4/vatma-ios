"""Capture the shipped desktop window with an isolated example catalog."""

from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import uuid4
import subprocess
import sys
import tkinter as tk

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from desktop import DesktopWindow, configure_window, server_for


def fill_demo(server, directory):
    for title in ("Фото и видео", "Документы", "Автокопии"):
        target = directory / title
        target.mkdir()
        server.admin({"action": "add", "path": str(target), "backup": title == "Автокопии"})
    server.admin({"action": "invite"})
    code, _ = server.access.invitation
    server.access.pair(
        {"code": code, "deviceId": uuid4().hex, "name": "iPhone · пример"},
        True, server.name,
    )


def capture_mac(root, path):
    from AppKit import NSApplication, NSBitmapImageFileTypePNG

    app = NSApplication.sharedApplication()
    app.activateIgnoringOtherApps_(True)
    root.update()
    windows = [window for window in app.windows() if window.title() == root.title()]
    if not windows:
        raise RuntimeError("The app window could not be located")
    window = windows[0]
    window.displayIfNeeded()
    result = subprocess.run(["/usr/sbin/screencapture", "-x", "-o", "-l",
                             str(window.windowNumber()), str(path)],
                            capture_output=True, timeout=15)
    if result.returncode == 0 and path.is_file() and path.stat().st_size > 12000:
        return
    view = window.contentView().superview()
    bounds = view.bounds()
    bitmap = view.bitmapImageRepForCachingDisplayInRect_(bounds)
    view.cacheDisplayInRect_toBitmapImageRep_(bounds, bitmap)
    data = bitmap.representationUsingType_properties_(NSBitmapImageFileTypePNG, {})
    if not data.writeToFile_atomically_(str(path), True):
        raise RuntimeError("Unable to save the Mac window snapshot")


def main():
    out = Path(sys.argv[1]).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix="disks-") as temporary:
        directory = Path(temporary).resolve()
        files = directory / "Демо"
        files.mkdir()
        with server_for(directory / "state", loopback=True) as server:
            fill_demo(server, files)
            root = tk.Tk()
            configure_window(root)
            icon = ROOT.parent / "Assets.xcassets" / "AppIcon.appiconset" / "icon.png"
            root.iconphoto(True, tk.PhotoImage(file=icon))
            DesktopWindow(root, server)
            root.geometry("+80+80")

            def finished():
                try:
                    root.update_idletasks()
                    if sys.platform == "darwin":
                        capture_mac(root, out)
                    else:
                        subprocess.run(["import", "-silent", "-window", root.wm_frame(), str(out)],
                                       check=True, timeout=15)
                finally:
                    root.quit()

            root.after(650, finished)
            root.mainloop()
            root.destroy()
    if not out.is_file() or out.stat().st_size < 11000:
        raise RuntimeError("The screenshot is missing or empty")


if __name__ == "__main__":
    main()
