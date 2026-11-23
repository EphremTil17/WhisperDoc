"""
Tests for HotkeyService's Win32 message loop.

user32 is replaced by a scripted fake that feeds window messages through the
real wintypes.MSG structure, so registration, dispatch and shutdown are
exercised without touching the desktop's global hotkey table.
"""

import ctypes
import threading
from types import SimpleNamespace

import pytest

from whisper_shell.services import hotkey_service
from whisper_shell.services.config_service import cfg
from whisper_shell.services.hotkey_service import HotkeyService

WM_HOTKEY = 0x0312
WM_KEYDOWN = 0x0100
WM_TIMER = 0x0113
MOD_CONTROL, MOD_SHIFT = 0x0002, 0x0004
VK_F9 = 0x78


class FakeUser32:
    """Scripted user32: GetMessageW yields queued messages, then WM_QUIT (0)."""

    def __init__(self, *messages: int, register_ok: bool = True, fails: bool = False):
        self.pending = list(messages)
        self.register_ok = register_ok
        self.fails = fails  # once the queue is empty, GetMessageW errors (-1)
        self.calls: list[tuple] = []

    def RegisterHotKey(self, hwnd, hotkey_id, mods, vk):
        self.calls.append(("register", hwnd, hotkey_id, mods, vk))
        return self.register_ok

    def UnregisterHotKey(self, hwnd, hotkey_id):
        self.calls.append(("unregister", hwnd, hotkey_id))
        return True

    def GetMessageW(self, msg_ref, hwnd, filter_min, filter_max):
        self.calls.append(("get",))
        if not self.pending:
            if self.fails:
                if len(self.named("get")) > 3:
                    raise AssertionError("loop kept calling GetMessageW after -1")
                return -1
            return 0  # WM_QUIT
        msg_ref._obj.message = self.pending.pop(0)
        return 1

    def TranslateMessage(self, msg_ref):
        self.calls.append(("translate", msg_ref._obj.message))

    def DispatchMessageW(self, msg_ref):
        self.calls.append(("dispatch", msg_ref._obj.message))

    def named(self, name: str) -> list[tuple]:
        return [call for call in self.calls if call[0] == name]


@pytest.fixture
def install_user32(monkeypatch):
    monkeypatch.setattr(cfg, "RECORD_HOTKEY", "ctrl+shift+f9")

    def install(fake: FakeUser32) -> FakeUser32:
        monkeypatch.setattr(
            hotkey_service,
            "ctypes",
            SimpleNamespace(windll=SimpleNamespace(user32=fake), byref=ctypes.byref),
        )
        return fake

    return install


class TestWindowsLoop:
    def test_a_getmessage_error_ends_the_loop_instead_of_spinning(self, install_user32):
        user32 = install_user32(FakeUser32(WM_HOTKEY, fails=True))

        HotkeyService(lambda: None)._windows_loop()

        # One message, then the -1 error: two calls, and the hotkey released.
        assert len(user32.named("get")) == 2
        assert user32.named("unregister")

    def test_registers_the_configured_hotkey(self, install_user32):
        user32 = install_user32(FakeUser32())

        HotkeyService(lambda: None)._windows_loop()

        assert user32.named("register") == [
            ("register", None, 1, MOD_CONTROL | MOD_SHIFT, VK_F9)
        ]

    def test_only_wm_hotkey_triggers_the_callback(self, install_user32):
        user32 = install_user32(FakeUser32(WM_HOTKEY, WM_KEYDOWN, WM_TIMER, WM_HOTKEY))
        presses = []

        HotkeyService(lambda: presses.append(1))._windows_loop()

        assert len(presses) == 2
        # Every message is still translated and dispatched, hotkey or not.
        assert [c[1] for c in user32.named("dispatch")] == [
            WM_HOTKEY,
            WM_KEYDOWN,
            WM_TIMER,
            WM_HOTKEY,
        ]
        assert len(user32.named("translate")) == 4

    def test_wm_quit_unregisters_the_hotkey(self, install_user32):
        user32 = install_user32(FakeUser32(WM_HOTKEY))

        HotkeyService(lambda: None)._windows_loop()

        assert user32.calls[-1] == ("unregister", None, 1)

    def test_register_failure_listens_to_nothing(self, install_user32):
        user32 = install_user32(FakeUser32(WM_HOTKEY, register_ok=False))
        presses = []

        HotkeyService(lambda: presses.append(1))._windows_loop()

        assert presses == []
        assert user32.named("get") == []
        assert user32.named("unregister") == []

    def test_stop_ends_the_loop_before_the_next_message(self, install_user32):
        user32 = install_user32(FakeUser32(WM_HOTKEY, WM_HOTKEY, WM_HOTKEY))
        presses = []

        def on_press():
            presses.append(1)
            svc.stop()

        svc = HotkeyService(on_press)
        svc._windows_loop()

        assert presses == [1]
        assert len(user32.pending) == 2  # never pulled after stop()
        assert user32.calls[-1] == ("unregister", None, 1)

    def test_win32_errors_do_not_escape_the_listener_thread(self, install_user32):
        user32 = install_user32(FakeUser32())

        def broken(*_args):
            raise OSError("access denied")

        user32.RegisterHotKey = broken

        HotkeyService(lambda: None)._windows_loop()  # must not raise


class TestStartStop:
    def test_start_runs_the_loop_on_a_daemon_thread(self, install_user32):
        install_user32(FakeUser32(WM_HOTKEY))
        pressed_on = []
        svc = HotkeyService(lambda: pressed_on.append(threading.current_thread()))

        svc.start()
        assert svc.thread is not None
        svc.thread.join(timeout=2)

        assert svc.thread.daemon is True
        assert not svc.thread.is_alive()
        assert pressed_on == [svc.thread]

    def test_stop_clears_the_running_flag(self):
        svc = HotkeyService(lambda: None)
        assert svc.running is True

        svc.stop()

        assert svc.running is False
