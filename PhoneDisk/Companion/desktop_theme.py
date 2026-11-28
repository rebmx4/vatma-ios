"""Apply the desktop's preferred color scheme to the companion window."""

import configparser
from dataclasses import dataclass
import math
import os
from pathlib import Path
import sys
import tkinter as tk
from tkinter import font, ttk


@dataclass(frozen=True)
class Palette:
    background: str
    surface: str
    outline: str
    text: str
    muted: str
    accent: str
    selected: str
    danger: str
    control: str
    control_outline: str
    primary: str
    primary_outline: str
    hover: str
    pressed: str
    signal: str
    signal_outline: str
    scrollbar: str


LIGHT = Palette(
    background="#f4f5f3", surface="#ffffff", outline="#dce3de",
    text="#1b211e", muted="#54605a", accent="#315a42", selected="#e2ede6", danger="#963b37",
    control="#f1f3f1", control_outline="#dce1dd", primary="#e7f0e9", primary_outline="#cbded2",
    hover="#e9eeea", pressed="#e1eae3", signal="#edf3ee", signal_outline="#d8e5dc", scrollbar="#858d87",
)
DARK = Palette(
    background="#000000", surface="#161616", outline="#313131",
    text="#f4f4f4", muted="#b4b4b4", accent="#a4c8ae", selected="#293a30", danger="#efa8a5",
    control="#252525", control_outline="#373737", primary="#26362c", primary_outline="#40574a",
    hover="#343834", pressed="#303c34", signal="#1b221e", signal_outline="#343c37", scrollbar="#565c58",
)


def mac_prefers_dark(root):
    try:
        return root.tk.getboolean(root.tk.call("::tk::unsupported::MacWindowStyle", "isdark", root._w))
    except tk.TclError:
        return sum(root.winfo_rgb("systemWindowBackgroundColor")) < 3 * 32768


class LinuxAppearance:
    NAMESPACE = "org.freedesktop.appearance"
    KEY = "color-scheme"

    def __init__(self):
        self.portal = None
        self.portal_dark = None
        self.revision = 0
        self.settings = None
        self.schema = None
        self.context = None
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", ""))
        self.config_home = config_home if config_home.is_absolute() else Path.home() / ".config"
        try:
            from gi.repository import Gio, GLib
        except (ImportError, ValueError):
            return
        self.gio, self.glib = Gio, GLib
        self.context = GLib.MainContext.default()
        schemas = Gio.SettingsSchemaSource.get_default()
        if schemas:
            self.schema = schemas.lookup("org.gnome.desktop.interface", True)
        if self.schema:
            self.settings = Gio.Settings.new_full(self.schema, None, None)
        Gio.DBusProxy.new_for_bus(
            Gio.BusType.SESSION, Gio.DBusProxyFlags.DO_NOT_LOAD_PROPERTIES, None,
            "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.Settings", None, self.portal_ready, None,
        )

    def portal_ready(self, source, result, _data):
        try:
            self.portal = self.gio.DBusProxy.new_for_bus_finish(result)
        except self.glib.Error:
            return
        self.portal.connect("g-signal", self.setting_changed)
        self.portal.connect("notify::g-name-owner", self.read_portal)
        self.read_portal(self.portal)

    def read_portal(self, proxy, _property=None):
        self.portal_dark = None
        self.revision += 1
        if proxy.get_name_owner():
            proxy.call("ReadAll", self.glib.Variant("(as)", ([self.NAMESPACE],)),
                       self.gio.DBusCallFlags.NONE, 1500, None, self.read_finished, self.revision)

    def read_finished(self, proxy, result, revision):
        try:
            values = proxy.call_finish(result).unpack()[0]
        except self.glib.Error:
            return
        if revision == self.revision:
            self.portal_dark = {1: True, 2: False}.get(values.get(self.NAMESPACE, {}).get(self.KEY))

    def setting_changed(self, proxy, sender, signal, parameters):
        if signal == "SettingChanged":
            namespace, key, value = parameters.unpack()
            if (namespace, key) == (self.NAMESPACE, self.KEY):
                self.revision += 1
                self.portal_dark = {1: True, 2: False}.get(value)

    def read_config(self, file):
        config = configparser.ConfigParser(interpolation=None, strict=False)
        try:
            config.read(self.config_home / file, encoding="utf-8")
        except (configparser.Error, UnicodeError):
            return configparser.ConfigParser()
        return config

    def prefers_dark(self):
        if self.context:
            for _ in range(16):
                if not self.context.iteration(False):
                    break
        if self.portal_dark is not None:
            return self.portal_dark

        gtk_override = os.environ.get("GTK_THEME")
        if gtk_override:
            return "dark" in gtk_override.casefold()
        if "kde" in os.environ.get("XDG_CURRENT_DESKTOP", "").casefold():
            kde = self.read_config("kdeglobals")
            background = kde.get("Colors:Window", "BackgroundNormal", fallback="")
            channels = background.split(",")
            if len(channels) == 3 and all(channel.strip().isdigit() for channel in channels):
                return sum(int(channel) for channel in channels) < 3 * 128
        if self.schema and self.schema.has_key(self.KEY):
            preference = self.settings.get_string(self.KEY)
            if preference in ("prefer-dark", "prefer-light"):
                return preference == "prefer-dark"
        for toolkit in ("gtk-4.0", "gtk-3.0"):
            gtk = self.read_config(f"{toolkit}/settings.ini")
            try:
                preference = gtk.getboolean("Settings", "gtk-application-prefer-dark-theme", fallback=None)
            except ValueError:
                preference = None
            if preference is not None:
                return preference
            theme = gtk.get("Settings", "gtk-theme-name", fallback="")
            if theme:
                return "dark" in theme.casefold()
        if self.schema and self.schema.has_key("gtk-theme"):
            return "dark" in self.settings.get_string("gtk-theme").casefold()
        return False


def rounded_image(root, radius, background, outline, surface, tile):
    size = 2 * (radius + 1) + tile
    center = (size - 1) / 2
    straight = (tile + 1) / 2
    colors = [root.winfo_rgb(color) for color in (background, outline, surface)]
    pixels = bytearray()
    for y in range(size):
        for x in range(size):
            dx = max(0, abs(x - center) - straight)
            dy = max(0, abs(y - center) - straight)
            distance = math.hypot(dx, dy)
            edge = min(1, max(0, radius + 0.5 - distance))
            fill = min(1, max(0, radius - 0.5 - distance))
            for outside, border, inside in zip(*colors):
                pixels.append(round((outside * (1 - edge) + border * (edge - fill) + inside * fill) / 257))
    header = f"P6\n{size} {size}\n255\n".encode("ascii")
    return tk.PhotoImage(master=root, data=header + pixels, format="ppm")


def configure_styles(root, style, palette):
    images = []

    def element(name, radius, background, outline, surface, padding, states=(), tile=16):
        image = rounded_image(root, radius, background, outline, surface, tile)
        variants = [(state, rounded_image(root, radius, background, border, fill, tile))
                    for state, border, fill in states]
        images.extend([image, *(variant for _, variant in variants)])
        minimum = 2 * radius + 3
        style.element_create(name, "image", image, *variants, border=radius + 1, padding=padding,
                             width=minimum, height=minimum, sticky="nsew")

    # Large center tiles keep Tk from painting each pixel of a panel separately on macOS.
    element("Disk.Card", 22, palette.background, palette.outline, palette.surface, (16, 12), tile=64)
    style.layout("Card.TFrame", [("Disk.Card", {"sticky": "nsew"})])
    element("Disk.Network", 15, palette.background, palette.signal_outline, palette.signal, (10, 6))
    style.layout("Network.TFrame", [("Disk.Network", {"sticky": "nsew"})])
    for name, fill, border, color in (
        ("Soft", palette.control, palette.control_outline, palette.text),
        ("Mint", palette.primary, palette.primary_outline, palette.accent),
        ("Remove", palette.control, palette.control_outline, palette.danger),
    ):
        face = f"Disk.{name}"
        element(face, 11, palette.surface, border, fill, (12, 7), (
            ("disabled", palette.control_outline, palette.control),
            ("focus", palette.accent, fill),
            ("pressed", border, palette.pressed),
            ("active", border, palette.hover),
        ))
        variant = f"{name}.TButton"
        style.layout(variant, [(face, {"sticky": "nsew", "children": [("Button.label", {"sticky": "nsew"})]})])
        style.configure(variant, background=palette.surface, foreground=color)
        style.map(variant, foreground=[("disabled", palette.muted)])

    default_font = font.nametofont("TkDefaultFont", root=root)
    family = default_font.actual("family")
    style.configure(".", background=palette.background, foreground=palette.text)
    style.configure("Title.TLabel", font=(family, 25, "bold"))
    style.configure("Section.TLabel", background=palette.surface, font=(family, 13, "bold"))
    style.configure("Note.TLabel", foreground=palette.muted)
    style.configure("Inset.TFrame", background=palette.surface)
    style.configure("Inset.TLabel", background=palette.surface)
    style.configure("Network.TLabel", background=palette.signal, foreground=palette.accent)
    style.configure("Offline.Network.TLabel", foreground=palette.muted)
    style.configure("TCheckbutton", background=palette.surface)
    style.map("TCheckbutton", background=[("active", palette.surface)])
    style.layout("Treeview", [("Treeview.treearea", {"sticky": "nsew"})])
    style.configure("Treeview", background=palette.surface, fieldbackground=palette.surface,
                    foreground=palette.text, rowheight=max(26, default_font.metrics("linespace") + 6),
                    borderwidth=0)
    style.map("Treeview", background=[("selected", palette.selected)], foreground=[("selected", palette.text)])
    style.configure("Treeview.Heading", background=palette.surface, foreground=palette.muted,
                    font=default_font, padding=(0, 4), relief="flat", borderwidth=0,
                    bordercolor=palette.surface, separable=False)
    style.map("Treeview.Heading", background=[("active", palette.surface), ("pressed", palette.surface)])
    element("Disk.thumb", 3, palette.surface, palette.scrollbar, palette.scrollbar, 0)
    style.layout("Disk.Vertical.TScrollbar", [("Vertical.Scrollbar.trough", {"sticky": "ns", "children": [
        ("Disk.thumb", {"expand": True, "sticky": "nswe"}),
    ]})])
    style.configure("Disk.Vertical.TScrollbar", troughcolor=palette.surface, background=palette.scrollbar,
                    bordercolor=palette.surface, lightcolor=palette.surface, darkcolor=palette.surface,
                    width=7, relief="flat")
    return images


class DesktopAppearance:
    def __init__(self, root):
        self.root = root
        self.style = ttk.Style(root)
        self.linux = LinuxAppearance() if sys.platform.startswith("linux") else None
        self.palette = None
        self.images = {}
        self.update()

    def update(self):
        if sys.platform == "darwin":
            dark = mac_prefers_dark(self.root)
        else:
            dark = self.linux is not None and self.linux.prefers_dark()
        palette = DARK if dark else LIGHT
        if palette is not self.palette:
            name = "PhoneDiskDark" if dark else "PhoneDiskLight"
            if name not in self.images:
                self.style.theme_create(name, parent="clam")
                self.style.theme_use(name)
                self.images[name] = configure_styles(self.root, self.style, palette)
            else:
                self.style.theme_use(name)
            self.palette = palette
            self.color_classic_widgets(self.root)
        self.root.after(700, self.update)

    def color_classic_widgets(self, widget):
        palette = self.palette
        if isinstance(widget, (tk.Tk, tk.Toplevel)):
            widget.configure(background=palette.background)
        elif isinstance(widget, tk.Listbox):
            widget.configure(bg=palette.surface, fg=palette.text, selectbackground=palette.selected,
                             selectforeground=palette.text, highlightbackground=palette.outline,
                             highlightcolor=palette.accent)
        for child in widget.winfo_children():
            self.color_classic_widgets(child)
