"""Capture the shipped desktop window with an isolated example catalog."""

from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import uuid4
import faulthandler
import os
import subprocess
import sys
import tkinter as tk
from tkinter import ttk

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from desktop import DesktopWindow, configure_window, server_for
from desktop_theme import DARK, LIGHT


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
    root.update_idletasks()
    windows = [window for window in app.windows() if window.title() == root.title()]
    if not windows:
        raise RuntimeError("The app window could not be located")
    window = windows[0]
    window.makeKeyAndOrderFront_(None)
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


def find_button(widget, title):
    for child in widget.winfo_children():
        if isinstance(child, ttk.Button) and child.cget("text") == title:
            return child
        button = find_button(child, title)
        if button is not None:
            return button
    return None


def verify_controls(root, window, server):
    root.geometry("640x470+80+80")
    root.update()
    assert len(window.folder_list.get_children()) == 3, "The catalog did not render"
    permissions = find_button(root, "Права доступа")
    assert permissions is not None and permissions.winfo_viewable(), "Controls must fit at the minimum width"
    phone = window.phone_list.get_children()[0]
    window.phone_list.selection_set(phone)
    permissions.invoke()
    root.update()
    assert root.grab_current() is not None, "Permissions dialog did not open"
    find_button(root.grab_current(), "Отмена").invoke()
    window.phone_list.selection_remove(phone)
    find_button(root, "Подключить телефон").invoke()
    root.update()
    assert server.admin({"action": "state"})["inviting"], "Pairing QR did not open"
    find_button(root.grab_current(), "Новый код").invoke()
    assert server.admin({"action": "state"})["inviting"], "Pairing QR did not renew"
    find_button(root.grab_current(), "Закрыть").invoke()
    assert not server.admin({"action": "state"})["inviting"], "Closed QR remained active"
    root.geometry("790x545+80+80")
    root.update()
    tree = window.folder_list
    assert all(tree.bbox(key) for key in tree.get_children()), "The three demo folders must fit in the default window"
    extras = [tree.insert("", "end", values=(f"Папка {index}", "/tmp", "Файлы")) for index in range(20)]
    root.update()
    assert tree.yview()[1] < 1, "The catalog must scroll when it has more folders"
    tree.yview_moveto(1)
    root.update()
    assert tree.bbox(extras[-1]), "Scrolling did not reach the last folder"
    tree.delete(*extras)
    tree.yview_moveto(0)
    root.update()


def test_portal():
    from gi.repository import Gio, GLib

    namespace = "org.freedesktop.appearance"
    interface = "org.freedesktop.portal.Settings"
    path = "/org/freedesktop/portal/desktop"
    connection = Gio.DBusConnection.new_for_address_sync(
        os.environ["DBUS_SESSION_BUS_ADDRESS"],
        Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
        None, None,
    )
    schema = Gio.DBusNodeInfo.new_for_xml("""
        <node><interface name="org.freedesktop.portal.Settings">
          <method name="ReadAll">
            <arg type="as" direction="in"/><arg type="a{sa{sv}}" direction="out"/>
          </method>
          <signal name="SettingChanged"><arg type="s"/><arg type="s"/><arg type="v"/></signal>
        </interface></node>
    """)
    choice = 2

    def read(_connection, _sender, _path, _interface, _method, _parameters, invocation):
        values = {namespace: {"color-scheme": GLib.Variant("u", choice)}}
        invocation.return_value(GLib.Variant("(a{sa{sv}})", (values,)))

    registration = connection.register_object(path, schema.interfaces[0], read, None, None)
    assert registration != 0
    name = connection.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                "RequestName", GLib.Variant("(su)", ("org.freedesktop.portal.Desktop", 4)),
                                None, Gio.DBusCallFlags.NONE, 1000, None)
    assert name.unpack() == (1,)

    def change(dark):
        nonlocal choice
        choice = 0 if dark is None else 1 if dark else 2
        data = GLib.Variant("(ssv)", (namespace, "color-scheme", GLib.Variant("u", choice)))
        connection.emit_signal(None, path, interface, "SettingChanged", data)

    return change


def main():
    out = Path(sys.argv[1]).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix="disks-", dir="/tmp") as temporary:
        directory = Path(temporary).resolve()
        files = directory / "Демо"
        files.mkdir()
        with server_for(directory / "state", loopback=True) as server:
            fill_demo(server, files)
            root = tk.Tk()
            macos = sys.platform == "darwin"
            if macos:
                def change(dark):
                    root.tk.call("::tk::unsupported::MacWindowStyle", "appearance", root._w,
                                 "darkaqua" if dark else "aqua")
            else:
                os.environ["XDG_CONFIG_HOME"] = str(directory / "settings")
                gtk = Path(os.environ["XDG_CONFIG_HOME"]) / "gtk-3.0" / "settings.ini"
                gtk.parent.mkdir(parents=True)
                gtk.write_text("[Settings]\ngtk-application-prefer-dark-theme=true\n", encoding="utf-8")
                change = test_portal()
            configure_window(root)
            icon = ROOT.parent / "Assets.xcassets" / "AppIcon.appiconset" / "icon.png"
            root.iconphoto(True, tk.PhotoImage(file=icon))
            window = DesktopWindow(root, server)
            if macos:
                root.geometry("+80+80")
            else:
                verify_controls(root, window, server)

            selected = window.folder_list.get_children()[0]
            window.folder_list.selection_set(selected)
            errors = []

            def capture(dark):
                try:
                    root.update_idletasks()
                    palette = DARK if dark else LIGHT
                    appearance = root.disk_appearance
                    portal = appearance.linux.portal if not macos else None
                    assert appearance.palette is palette, (
                        f"Expected {'dark' if dark else 'light'}, actual {appearance.style.theme_use()}, "
                        f"portal owner {bool(portal and portal.get_name_owner())}, "
                        f"portal mode {appearance.linux.portal_dark if appearance.linux else None}"
                    )
                    assert window.folder_list.selection() == (selected,), "Changing theme lost the selection"
                    assert len(window.folder_list.get_children()) == 3, "Changing theme lost the catalog"
                    style = root.disk_appearance.style
                    assert style.lookup("Treeview", "background") == palette.surface
                    assert root.cget("background") == palette.background
                    if not macos:
                        assert root.disk_appearance.linux.portal_dark is dark, "Portal preference was not applied"
                    theme = "dark" if dark else "light"
                    image = out.with_name(f"{out.name}-{theme}.png")
                    if macos:
                        capture_mac(root, image)
                    else:
                        subprocess.run(["import", "-silent", "-window", root.wm_frame(), str(image)],
                                       check=True, timeout=15)
                    assert image.is_file() and image.stat().st_size > 11000, "Window capture is missing"
                    if dark:
                        change(False)
                        root.after(1400, verify_return)
                    else:
                        change(True)
                        root.after(1400, capture, True)
                except Exception as error:
                    errors.append(error)
                    root.quit()

            def verify_return():
                if root.disk_appearance.palette is not LIGHT:
                    errors.append(AssertionError("The window did not return to the light scheme"))
                if macos:
                    root.quit()
                else:
                    change(None)
                    root.after(1400, verify_fallback)

            def verify_fallback():
                appearance = root.disk_appearance
                if appearance.linux.portal_dark is not None or appearance.palette is not DARK:
                    errors.append(AssertionError("No preference did not fall back to the local GTK theme"))
                root.quit()

            def start():
                if macos:
                    change(False)
                root.after(1900, capture, False)

            root.after(450, start)
            root.mainloop()
            root.destroy()
    if errors:
        raise errors[0]


if __name__ == "__main__":
    faulthandler.dump_traceback_later(45, exit=True)
    main()
