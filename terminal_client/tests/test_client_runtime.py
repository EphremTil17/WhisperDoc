"""
Tests for DictationClient's runtime: the CLI entrypoint, first-run setup, the
event-loop lifecycle and shutdown.

The controller, hotkey listener and instance lock are faked; the asyncio event
loop is real, so start() and stop() run their actual scheduling and cleanup.
"""

import threading
import time
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from whisper_shell import client as client_module
from whisper_shell.client import DictationClient, _ensure_supported_platform, main
from whisper_shell.services.config_service import cfg

LOCK = "instance-lock-handle"


@pytest.fixture
def keys(monkeypatch) -> MagicMock:
    sec = MagicMock()
    sec.get_api_key.return_value = "stored-key"
    monkeypatch.setattr(client_module, "sec_cfg", sec)
    return sec


@pytest.fixture
def parts(keys):
    """A DictationClient whose collaborators are fakes; yields (client, fakes)."""
    with (
        patch.object(
            client_module, "acquire_single_instance_lock", return_value=LOCK
        ) as acquire,
        patch.object(client_module, "release_single_instance_lock") as release,
        patch.object(client_module, "RecordingController") as Controller,
        patch.object(client_module, "HotkeyService") as Hotkey,
    ):
        controller = Controller.return_value
        controller.transport.hostname = "dictation.example.com"
        controller.transport.connect = AsyncMock(return_value=True)
        controller.shutdown = AsyncMock()
        client = DictationClient()
        # Safety net: a regression that never stops the loop fails, not hangs.
        client.loop.call_later(5.0, _interrupt)
        fakes = SimpleNamespace(
            acquire=acquire,
            release=release,
            controller=controller,
            hotkey=Hotkey.return_value,
            Hotkey=Hotkey,
            keys=keys,
        )
        try:
            yield client, fakes
        finally:
            if not client.loop.is_closed():
                client.loop.close()


def _interrupt():
    raise KeyboardInterrupt


# ---------------------------------------------------------------------------
# Platform guard and console entrypoint
# ---------------------------------------------------------------------------


class TestPlatformGuard:
    def test_non_windows_exits_with_failure(self, monkeypatch):
        monkeypatch.setattr(client_module, "os", SimpleNamespace(name="posix"))

        with pytest.raises(SystemExit) as exc:
            _ensure_supported_platform()

        assert exc.value.code == 1

    def test_windows_is_allowed(self, monkeypatch):
        monkeypatch.setattr(client_module, "os", SimpleNamespace(name="nt"))

        assert _ensure_supported_platform() is None


class TestMain:
    def test_checks_platform_then_starts_the_client(self):
        calls = []
        with (
            patch.object(
                client_module,
                "_ensure_supported_platform",
                side_effect=lambda: calls.append("platform"),
            ),
            patch.object(client_module, "DictationClient") as Client,
        ):
            Client.return_value.start.side_effect = lambda: calls.append("start")
            main()

        assert calls == ["platform", "start"]

    def test_ctrl_c_exits_quietly(self):
        with (
            patch.object(client_module, "_ensure_supported_platform"),
            patch.object(client_module, "DictationClient") as Client,
        ):
            Client.return_value.start.side_effect = KeyboardInterrupt
            main()  # must not raise

    def test_unsupported_platform_never_builds_the_client(self, monkeypatch):
        monkeypatch.setattr(client_module, "os", SimpleNamespace(name="posix"))
        with patch.object(client_module, "DictationClient") as Client:
            with pytest.raises(SystemExit):
                main()

        Client.assert_not_called()


# ---------------------------------------------------------------------------
# Early CLI flags and first-run setup
# ---------------------------------------------------------------------------


@pytest.fixture
def setup_wizard():
    with patch.object(client_module, "setup_interactive") as wizard:
        yield wizard


class TestEarlyFlags:
    def test_first_run_without_env_file_runs_setup(self, monkeypatch, setup_wizard):
        monkeypatch.setattr(cfg, "ENV_PATH", MagicMock(exists=lambda: False))

        DictationClient._handle_early_flags()

        setup_wizard.assert_called_once_with()

    def test_setup_flag_reruns_setup_with_existing_env(self, monkeypatch, setup_wizard):
        monkeypatch.setattr(cfg.args, "setup", True)

        DictationClient._handle_early_flags()

        setup_wizard.assert_called_once_with()

    def test_configured_client_skips_setup(self, setup_wizard):
        DictationClient._handle_early_flags()

        setup_wizard.assert_not_called()

    def test_version_flag_exits_before_first_run_setup(self, monkeypatch, setup_wizard):
        monkeypatch.setattr(cfg.args, "version", True)
        monkeypatch.setattr(cfg, "ENV_PATH", MagicMock(exists=lambda: False))

        with pytest.raises(SystemExit) as exc:
            DictationClient._handle_early_flags()

        assert exc.value.code == 0
        setup_wizard.assert_not_called()

    def test_clear_key_targets_the_configured_server(self, monkeypatch, keys):
        monkeypatch.setattr(cfg.args, "clear_key", True)
        monkeypatch.setattr(cfg, "WS_URI", "wss://dictation.example.com:8443/ws")

        with pytest.raises(SystemExit) as exc:
            DictationClient._handle_early_flags()

        assert exc.value.code == 0
        keys.clear_key.assert_called_once_with("dictation.example.com")


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------


class TestStartLifecycle:
    def test_runs_until_ctrl_c_then_shuts_down_cleanly(self, parts):
        client, fakes = parts
        # The proactive connect runs on the loop; Ctrl+C arrives afterwards.
        fakes.controller.transport.connect.side_effect = lambda: client.loop.call_soon(
            _interrupt
        )

        client.start()

        fakes.keys.get_api_key.assert_called_once_with("dictation.example.com")
        fakes.controller.audio.start_stream.assert_called_once_with()
        fakes.controller.transport.connect.assert_awaited_once()
        fakes.hotkey.start.assert_called_once_with()
        fakes.hotkey.stop.assert_called_once_with()
        fakes.controller.shutdown.assert_awaited_once()
        fakes.release.assert_called_once_with(LOCK)
        assert client.loop.is_closed()
        assert client.is_running is False

    def test_hotkey_presses_toggle_on_the_loop_thread(self, parts):
        client, fakes = parts
        toggled_on = []
        fakes.controller.toggle_recording.side_effect = lambda: (
            toggled_on.append(threading.current_thread()),
            client.loop.call_soon(_interrupt),
        )
        on_hotkey = fakes.Hotkey.call_args.args[0]

        def press_from_listener_thread():
            listener = threading.Thread(target=on_hotkey)
            listener.start()
            listener.join()

        fakes.hotkey.start.side_effect = press_from_listener_thread

        client.start()

        assert toggled_on == [threading.main_thread()]

    def test_no_api_key_never_touches_audio_or_network(self, parts):
        client, fakes = parts
        fakes.keys.get_api_key.return_value = ""

        client.start()

        fakes.controller.audio.start_stream.assert_not_called()
        fakes.controller.transport.connect.assert_not_called()
        fakes.hotkey.start.assert_not_called()

    def test_audio_failure_aborts_before_connecting(self, parts):
        client, fakes = parts
        fakes.controller.audio.start_stream.side_effect = RuntimeError("no device")

        client.start()

        fakes.controller.transport.connect.assert_not_called()
        fakes.hotkey.start.assert_not_called()


PROMPT_STOP_SECONDS = 2.0


class TestStop:
    @pytest.mark.parametrize("shutdown_fails", [False, True])
    def test_stop_from_another_thread_shuts_down_on_the_running_loop(
        self, parts, shutdown_fails
    ):
        client, fakes = parts
        shutdown_on = []

        def shutdown():
            shutdown_on.append(threading.current_thread())
            if shutdown_fails:
                raise RuntimeError("transport wedged")

        fakes.controller.shutdown.side_effect = shutdown

        stopper = threading.Thread(target=client.stop)
        # Stop arrives once the loop is running (call_soon runs inside it).
        # Nothing else keeps the loop awake, so this also proves stop() wakes
        # an idle loop rather than leaving it blocked in its selector.
        fakes.hotkey.start.side_effect = lambda: client.loop.call_soon(stopper.start)

        began = time.monotonic()
        client.start()
        stopper.join(timeout=5)

        assert not stopper.is_alive()  # the loop stopped, so start() returned
        # Promptly: an unwoken loop would only stop at the fixture's 5 s guard.
        assert time.monotonic() - began < PROMPT_STOP_SECONDS
        assert shutdown_on == [threading.main_thread()]
        fakes.hotkey.stop.assert_called_once_with()
        fakes.release.assert_called_once_with(LOCK)

    def test_failed_shutdown_still_closes_loop_and_releases_lock(self, parts):
        client, fakes = parts
        fakes.controller.shutdown.side_effect = RuntimeError("socket stuck")

        client.stop()

        assert client.loop.is_closed()
        fakes.release.assert_called_once_with(LOCK)

    def test_stop_twice_releases_the_lock_once(self, parts):
        client, fakes = parts

        client.stop()
        client.stop()

        fakes.controller.shutdown.assert_awaited_once()
        fakes.release.assert_called_once_with(LOCK)
