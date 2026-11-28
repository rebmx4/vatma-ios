"""Local desktop controls for the macOS and Linux companion."""

import argparse
import math
import os
import shutil
import sys
import threading
import time
import tkinter as tk
from pathlib import Path
from tempfile import TemporaryDirectory
from tkinter import filedialog, messagebox, ttk

from desktop_theme import DesktopAppearance
from phonedisk.service import CompanionServer, PORT
from phonedisk.storage import TransferError, file_info


APP_NAME = "Мой диск"
ROOT = Path(__file__).resolve().parent
PERMISSIONS = {
    "view": "Просмотр",
    "download": "Скачивание",
    "create": "Загрузка на компьютер",
    "delete": "Удаление",
}
ERROR_MESSAGES = {
    "folder-needed": "Сначала добавьте папку.",
    "wifi-unavailable": "Подключите компьютер и iPhone к одной домашней сети.",
    "invalid-folder": "Выберите доступную папку.",
    "invalid-permissions": "Список папок изменился. Откройте права доступа ещё раз.",
}


def configure_window(root):
    root.disk_appearance = DesktopAppearance(root)
    icon = ROOT / "icon.png"
    if icon.is_file():
        root.iconphoto(True, tk.PhotoImage(file=icon))


class DesktopWindow:
    def __init__(self, root, server):
        self.root = root
        self.server = server
        self.folders = None
        self.phones = None
        self.network = tk.StringVar()
        self.note = tk.StringVar()
        root.title(APP_NAME)
        root.minsize(640, 470)
        root.geometry("790x545")
        root.columnconfigure(0, weight=1)
        root.rowconfigure(0, weight=1)

        content = ttk.Frame(root, padding=(24, 18, 24, 12))
        content.grid(sticky="nsew")
        content.columnconfigure(0, weight=1)
        content.rowconfigure(1, weight=6)
        content.rowconfigure(2, weight=4)
        header = ttk.Frame(content)
        header.grid(row=0, sticky="ew", pady=(0, 16))
        ttk.Label(header, text=APP_NAME, style="Title.TLabel").pack(side="left")
        signal = ttk.Frame(header, style="Network.TFrame", padding=(10, 6))
        signal.pack(side="right")
        self.signal = ttk.Label(signal, textvariable=self.network, style="Network.TLabel")
        self.signal.pack()
        self.folder_list = self.section(
            content, 1, "Общие папки", (("name", "Папка", 175), ("path", "Путь", 350),
                                        ("purpose", "Назначение", 118)), 3,
            ("Добавить папку", lambda: self.add_folder(False)),
            ("Папка для автокопий", lambda: self.add_folder(True), "Soft"),
            ("Убрать из списка", self.remove_folder, "Remove"))
        self.phone_list = self.section(
            content, 2, "Подключённые устройства", (("name", "Имя", 210), ("folders", "Доступные папки", 400)), 2,
            ("Подключить телефон", self.open_invitation),
            ("Права доступа", self.open_permissions, "Soft"),
            ("Отключить телефон", self.disconnect_phone, "Remove"))
        ttk.Label(content, textvariable=self.note, style="Note.TLabel", wraplength=580).grid(row=3, sticky="w")
        self.poll()

    def section(self, parent, row, title, columns, height, primary, *actions):
        card = ttk.Frame(parent, style="Card.TFrame", padding=(16, 12))
        card.grid(row=row, sticky="nsew", pady=(0, 12))
        card.columnconfigure(0, weight=1)
        card.rowconfigure(1, weight=1)
        ttk.Label(card, text=title, style="Section.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 7))
        self.button(card, *primary, kind="Mint").grid(row=0, column=1, sticky="e", pady=(0, 7))
        view = self.table(card, columns, height)
        buttons = ttk.Frame(card, style="Inset.TFrame")
        buttons.grid(row=2, column=0, columnspan=2, sticky="e", pady=(7, 0))
        for label, handler, kind in actions:
            self.button(buttons, label, handler, kind).pack(side="left", padx=(7, 0))
        return view

    @staticmethod
    def table(parent, columns, height):
        frame = ttk.Frame(parent, style="Inset.TFrame")
        frame.grid(row=1, column=0, columnspan=2, sticky="nsew")
        frame.columnconfigure(0, weight=1)
        frame.rowconfigure(0, weight=1)
        view = ttk.Treeview(frame, columns=[key for key, _, _ in columns], show="headings",
                            selectmode="browse", height=height)
        for index, (key, heading, width) in enumerate(columns):
            view.heading(key, text=heading, anchor="w")
            view.column(key, width=width, minwidth=76, anchor="w", stretch=index == 1)
        scroll = ttk.Scrollbar(frame, orient="vertical", style="Disk.Vertical.TScrollbar", command=view.yview)

        def update_scroll(first, last):
            scroll.set(first, last)
            overflow = float(first) > 0 or float(last) < 1
            mapped = bool(scroll.winfo_manager())
            if overflow and not mapped:
                scroll.grid()
            if not overflow and mapped:
                scroll.grid_remove()

        view.configure(yscrollcommand=update_scroll)
        view.grid(row=0, column=0, sticky="nsew")
        scroll.grid(row=0, column=1, sticky="ns", padx=(5, 0))
        return view

    def button(self, parent, label, handler, kind="Soft", dialog=None):
        return ttk.Button(parent, text=label, style=f"{kind}.TButton",
                          command=lambda: self.perform(handler, dialog))

    @staticmethod
    def replace_rows(view, rows):
        selected = view.selection()
        view.delete(*view.get_children())
        for key, values in rows:
            view.insert("", "end", iid=key, values=values)
        if selected and view.exists(selected[0]):
            view.selection_set(selected[0])

    def perform(self, action, parent=None):
        try:
            return action()
        except TransferError as error:
            messagebox.showwarning(APP_NAME, ERROR_MESSAGES.get(error.code, "Не удалось выполнить действие."),
                                   parent=parent or self.root)
        except OSError:
            messagebox.showwarning(APP_NAME, "Не удалось открыть папку или сохранить настройки.",
                                   parent=parent or self.root)
        return None

    def poll(self):
        self.refresh()
        self.root.after(1500, self.poll)

    def refresh(self):
        snapshot = self.server.admin({"action": "state"})
        folders = snapshot["folders"]
        phones = snapshot["phones"]
        if folders != self.folders:
            self.replace_rows(self.folder_list, (
                (key, (record["name"], record["path"], "Автокопии" if record["backup"] else "Файлы"))
                for key, record in folders.items()))
        if phones != self.phones or folders != self.folders:
            self.replace_rows(self.phone_list, (
                (phone["id"], (phone["name"], ", ".join(
                    folders[key]["name"] for key, scopes in phone["scopes"].items() if key in folders and scopes)))
                for phone in phones))
        self.folders, self.phones = folders, phones
        routes = []
        if snapshot["hasNetwork"]:
            routes.append("Домашняя сеть")
        if snapshot["hasTailnet"]:
            routes.append("Tailscale")
        self.signal.configure(style="Network.TLabel" if routes else "Offline.Network.TLabel")
        self.network.set("●  " + " · ".join(routes) if routes else "○  Нет сети")
        if not folders:
            self.note.set("Добавьте папку, чтобы подключить iPhone.")
        elif not snapshot["hasNetwork"]:
            self.note.set("Подключите компьютер к домашней сети, чтобы создать QR-код.")
        elif not phones:
            self.note.set("Папка готова. Нажмите «Подключить телефон».")
        else:
            self.note.set("Окно можно свернуть.")

    def add_folder(self, backup):
        path = filedialog.askdirectory(title="Папка для автокопий" if backup else "Добавить папку",
                                       parent=self.root, mustexist=True)
        if path:
            selected = Path(path).resolve(strict=True)
            self.server.admin({"action": "add", "path": str(selected), "backup": backup})
            self.refresh()

    def remove_folder(self):
        selected = self.folder_list.selection()
        if selected and messagebox.askyesno(APP_NAME, "Закрыть доступ к выбранной папке?", parent=self.root):
            self.server.admin({"action": "remove", "source": selected[0]})
            self.refresh()

    def selected_phone(self):
        selected = self.phone_list.selection()
        return next((phone for phone in self.phones if selected and phone["id"] == selected[0]), None)

    def disconnect_phone(self):
        phone = self.selected_phone()
        if phone and messagebox.askyesno(APP_NAME, "Отключить выбранный телефон?", parent=self.root):
            self.server.admin({"action": "revoke", "device": phone["id"]})
            self.refresh()

    def open_invitation(self):
        first = self.server.admin({"action": "invite"})
        dialog = tk.Toplevel(self.root)
        dialog.title("Подключить телефон")
        dialog.transient(self.root)
        self.root.disk_appearance.color_classic_widgets(dialog)
        dialog.resizable(False, False)
        content = ttk.Frame(dialog, style="Card.TFrame", padding=18)
        content.pack(fill="both", expand=True, padx=12, pady=12)
        ttk.Label(content, text="Подключите iPhone к той же сети, что и компьютер. Наведите камеру на QR-код и нажмите на ссылку. "
                  "Код также можно отсканировать через «Добавить компьютер» в «Моём диске».",
                  style="Inset.TLabel", wraplength=310, justify="center").pack(pady=(0, 12))
        canvas = tk.Canvas(content, width=310, height=310, bg="white", highlightthickness=0)
        canvas.pack()
        clock = ttk.Label(content, style="Inset.TLabel")
        clock.pack(pady=(10, 3))
        expires = 0.0
        timer = None

        def draw(invitation):
            nonlocal expires
            matrix = invitation["matrix"]
            cell = 310 // len(matrix)
            origin = (310 - cell * len(matrix)) // 2
            canvas.delete("all")
            for row, line in enumerate(matrix):
                for column, bit in enumerate(line):
                    if bit == "1":
                        x, y = origin + cell * column, origin + cell * row
                        canvas.create_rectangle(x, y, x + cell, y + cell, fill="black", outline="")
            expires = time.monotonic() + invitation["expiresIn"]

        def close():
            if timer is not None:
                dialog.after_cancel(timer)
            self.server.admin({"action": "cancel"})
            dialog.destroy()
            self.refresh()

        def tick():
            nonlocal timer
            timer = None
            remaining = max(0, math.ceil(expires - time.monotonic()))
            if remaining and not self.server.admin({"action": "state"})["inviting"]:
                close()
                return
            if remaining:
                minutes, seconds = divmod(remaining, 60)
                clock.configure(text=f"Код действует {minutes}:{seconds:02d}")
            else:
                canvas.delete("all")
                canvas.create_text(155, 155, text="Код истёк", fill="black")
                clock.configure(text="Нажмите «Новый код».")
            timer = dialog.after(1000, tick)

        controls = ttk.Frame(content, style="Inset.TFrame")
        controls.pack(pady=(5, 0))
        self.button(controls, "Новый код", lambda: draw(self.server.admin({"action": "invite"})),
                    "Mint", dialog).pack(side="left", padx=4)
        self.button(controls, "Закрыть", close, dialog=dialog).pack(side="left", padx=4)
        dialog.protocol("WM_DELETE_WINDOW", close)
        dialog.bind("<Escape>", lambda event: close())
        dialog.grab_set()
        draw(first)
        tick()

    def open_permissions(self):
        phone = self.selected_phone()
        if not phone or not self.folders:
            return
        dialog = tk.Toplevel(self.root)
        dialog.title("Права доступа")
        dialog.transient(self.root)
        self.root.disk_appearance.color_classic_widgets(dialog)
        content = ttk.Frame(dialog, style="Card.TFrame", padding=18)
        content.pack(fill="both", expand=True, padx=12, pady=12)
        content.rowconfigure(1, weight=1)
        content.columnconfigure(0, weight=1)
        ttk.Label(content, text=phone["name"], style="Section.TLabel").grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 8))
        folder_list = tk.Listbox(content, width=28, height=10, exportselection=False,
                                relief="flat", borderwidth=0)
        self.root.disk_appearance.color_classic_widgets(folder_list)
        folder_list.grid(row=1, column=0, sticky="nsew")
        rights = ttk.Frame(content, style="Inset.TFrame", padding=(15, 0, 0, 0))
        rights.grid(row=1, column=1, sticky="nw")
        folders = list(self.folders.items())
        choices = {}
        for key, record in folders:
            folder_list.insert("end", record["name"])
            allowed = ("create",) if record["backup"] else PERMISSIONS
            choices[key] = {right: tk.BooleanVar(dialog, value=right in phone["scopes"].get(key, []))
                            for right in allowed}

        def show_choices(event=None):
            indices = folder_list.curselection()
            if not indices:
                return
            for child in rights.winfo_children():
                child.destroy()
            selected = folders[indices[0]][0]
            for right, value in choices[selected].items():
                ttk.Checkbutton(rights, text=PERMISSIONS[right], variable=value).pack(anchor="w", pady=3)

        def save():
            grants = {key: [right for right, value in options.items() if value.get()]
                      for key, options in choices.items()}
            self.server.admin({"action": "grant", "device": phone["id"], "scopes": grants})
            dialog.destroy()
            self.refresh()

        folder_list.bind("<<ListboxSelect>>", show_choices)
        folder_list.selection_set(0)
        show_choices()
        self.button(content, "Сохранить", save, "Mint", dialog).grid(row=2, column=0, sticky="w", pady=(12, 0))
        self.button(content, "Отмена", dialog.destroy, dialog=dialog).grid(row=2, column=1, sticky="e", pady=(12, 0))
        dialog.bind("<Escape>", lambda event: dialog.destroy())
        dialog.grab_set()


def state_directory():
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "PhoneDisk"
    base = Path(os.environ.get("XDG_STATE_HOME", ""))
    return (base if base.is_absolute() else Path.home() / ".local" / "state") / "phonedisk"


def server_for(state, loopback=False):
    ffmpeg = None if sys.platform == "darwin" else shutil.which("ffmpeg")
    thumbnailer = ROOT / "media" / "phonedisk-thumbnail"
    return CompanionServer(state, ROOT / "web", ffmpeg, loopback=loopback,
                           port=0 if loopback else PORT,
                           thumbnailer=thumbnailer if thumbnailer.is_file() else None)


def verify(root, video):
    with TemporaryDirectory(prefix="phonedisk-desktop-") as temporary:
        temporary = Path(temporary).resolve()
        folder = temporary / "Videos"
        folder.mkdir()
        with server_for(temporary / "state", loopback=True) as server:
            app = DesktopWindow(root, server)
            server.admin({"action": "add", "path": str(folder), "backup": False})
            app.refresh()
            root.update_idletasks()
            assert app.folder_list.get_children(), "Folder controls are unavailable"
            app.open_invitation()
            root.update_idletasks()
            assert server.admin({"action": "state"})["inviting"], "Unable to create a pairing QR code"
            server.admin({"action": "cancel"})
            if sys.platform == "darwin":
                assert server.thumbnailer and server.thumbnailer.is_file(), "The native thumbnail tool is missing"
            if video:
                video = video.resolve(strict=True)
                cover = server.cover(video, file_info(video))
                assert cover.read_bytes().startswith(b"\xff\xd8"), "Unable to create a JPEG video cover"
            root.destroy()


def main():
    import fcntl
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--verify-video", type=Path)
    args = parser.parse_args()
    root = tk.Tk()
    configure_window(root)
    if args.verify:
        verify(root, args.verify_video)
        return 0

    try:
        state = state_directory().resolve()
        state.mkdir(parents=True, exist_ok=True, mode=0o700)
        with (state / "instance.lock").open("a+b") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                messagebox.showinfo(APP_NAME, "Приложение уже открыто.", parent=root)
                return 0
            with server_for(state) as server:
                worker = threading.Thread(target=server.serve_forever, daemon=True)
                worker.start()
                try:
                    DesktopWindow(root, server)
                    root.mainloop()
                finally:
                    server.shutdown()
                    worker.join()
    except OSError:
        messagebox.showerror(APP_NAME, "Не удалось запустить «Мой диск». Проверьте доступ к папке приложения и повторите запуск.",
                             parent=root)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
