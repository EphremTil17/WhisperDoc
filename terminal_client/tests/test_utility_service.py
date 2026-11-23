"""
Tests for utility_service: the single-instance mutex and the first-run setup wizard.

Only the OS edges are faked: kernel32 (via ctypes.windll), the keyboard
(builtins.input), PortAudio's device list (sounddevice) and the OS keyring.
The .env file is real, written to a temporary directory.
"""

import ctypes
from types import SimpleNamespace
from unittest.mock import MagicMock

import keyring
import pytest
from dotenv import dotenv_values

from whisper_shell.services import utility_service
from whisper_shell.services.config_service import SERVICE_NAME, cfg
from whisper_shell.services.utility_service import (
    _list_input_devices,
    _prompt_api_key_reset,
    _prompt_audio_api,
    _prompt_audio_device,
    _save_setup_config,
    acquire_single_instance_lock,
    release_single_instance_lock,
    setup_interactive,
)

MUTEX_NAME = "Global\\WhisperDocClientMutex"
ERROR_ALREADY_EXISTS = 183
API_MAP = {"1": "Windows WASAPI", "2": "Windows DirectSound", "3": "MME", "0": None}

# Colour codes are irrelevant to behaviour; plain strings keep output readable.
FORE = SimpleNamespace(RED="")
STYLE = SimpleNamespace(RESET_ALL="")


# ---------------------------------------------------------------------------
# Fakes
# ---------------------------------------------------------------------------


@pytest.fixture
def kernel32(monkeypatch) -> MagicMock:
    """A fake kernel32 behind ctypes.windll (imported lazily by the service)."""
    fake = MagicMock()
    fake.GetLastError.return_value = 0
    monkeypatch.setattr(ctypes, "windll", SimpleNamespace(kernel32=fake))
    return fake


class ScriptedInput:
    """Replaces builtins.input with a fixed script of answers."""

    def __init__(self, *answers: str):
        self.answers = list(answers)
        self.prompts: list[str] = []

    def __call__(self, prompt: str = "") -> str:
        self.prompts.append(prompt)
        if not self.answers:
            raise AssertionError(f"Unexpected extra prompt: {prompt!r}")
        return self.answers.pop(0)


@pytest.fixture
def answers(monkeypatch):
    """Install a scripted keyboard: answers("1", "") feeds two replies."""

    def install(*replies: str) -> ScriptedInput:
        scripted = ScriptedInput(*replies)
        monkeypatch.setattr("builtins.input", scripted)
        return scripted

    return install


# Device 0 is output-only, 2 is on another host API, 3 is the system default.
DEVICES = [
    {"name": "Speakers", "max_input_channels": 0, "hostapi": 0},
    {"name": "Desk Mic", "max_input_channels": 1, "hostapi": 0},
    {"name": "Legacy Mic", "max_input_channels": 2, "hostapi": 2},
    {"name": "Headset", "max_input_channels": 1, "hostapi": 0},
]
HOST_APIS = (
    {"name": "Windows WASAPI", "default_input": 3},
    {"name": "Windows DirectSound"},
    {"name": "MME"},
)


@pytest.fixture
def sound_devices(monkeypatch) -> MagicMock:
    fake_sd = MagicMock()
    fake_sd.query_devices.return_value = DEVICES
    fake_sd.query_hostapis.return_value = HOST_APIS
    monkeypatch.setattr(utility_service, "sd", fake_sd)
    return fake_sd


@pytest.fixture
def env_file(monkeypatch, tmp_path):
    """Point the config at a real, not-yet-existing .env in a temp dir."""
    path = tmp_path / ".env"
    monkeypatch.setattr(cfg, "ENV_PATH", path)
    monkeypatch.setattr(cfg, "_load_env", MagicMock(), raising=False)
    return path


@pytest.fixture
def stored_keys(monkeypatch) -> dict:
    """An in-memory OS keyring: {(service, host): key}."""
    store: dict = {}
    monkeypatch.setattr(
        keyring, "get_password", lambda service, host: store.get((service, host))
    )
    monkeypatch.setattr(
        keyring, "delete_password", lambda service, host: store.pop((service, host))
    )
    return store


# ---------------------------------------------------------------------------
# Single-instance lock
# ---------------------------------------------------------------------------


class TestAcquireSingleInstanceLock:
    def test_first_instance_owns_the_named_mutex(self, kernel32):
        kernel32.CreateMutexW.return_value = 1234

        assert acquire_single_instance_lock() == 1234
        kernel32.CreateMutexW.assert_called_once_with(None, True, MUTEX_NAME)
        kernel32.CloseHandle.assert_not_called()

    def test_second_instance_is_refused_and_closes_its_handle(self, kernel32):
        kernel32.CreateMutexW.return_value = 77
        kernel32.GetLastError.return_value = ERROR_ALREADY_EXISTS

        assert acquire_single_instance_lock() is None
        kernel32.CloseHandle.assert_called_once_with(77)

    def test_second_instance_without_handle_closes_nothing(self, kernel32):
        kernel32.CreateMutexW.return_value = 0
        kernel32.GetLastError.return_value = ERROR_ALREADY_EXISTS

        assert acquire_single_instance_lock() is None
        kernel32.CloseHandle.assert_not_called()

    def test_mutex_creation_failure_still_lets_the_client_run(self, kernel32):
        kernel32.CreateMutexW.return_value = 0
        kernel32.GetLastError.return_value = 5  # ERROR_ACCESS_DENIED

        assert acquire_single_instance_lock() is True

    def test_non_windows_skips_the_mutex(self, kernel32, monkeypatch):
        monkeypatch.setattr(utility_service, "os", SimpleNamespace(name="posix"))

        assert acquire_single_instance_lock() is True
        kernel32.CreateMutexW.assert_not_called()


class TestReleaseSingleInstanceLock:
    def test_releases_then_closes_the_owned_mutex(self, kernel32):
        release_single_instance_lock(1234)

        assert kernel32.mock_calls == [
            ("ReleaseMutex", (1234,), {}),
            ("CloseHandle", (1234,), {}),
        ]

    @pytest.mark.parametrize("handle", [None, True, 0])
    def test_nothing_to_release_without_an_owned_handle(self, kernel32, handle):
        release_single_instance_lock(handle)

        assert kernel32.mock_calls == []

    def test_non_windows_releases_nothing(self, kernel32, monkeypatch):
        monkeypatch.setattr(utility_service, "os", SimpleNamespace(name="posix"))

        release_single_instance_lock(1234)

        assert kernel32.mock_calls == []

    def test_acquired_handle_round_trips(self, kernel32):
        kernel32.CreateMutexW.return_value = 4321

        release_single_instance_lock(acquire_single_instance_lock())

        kernel32.ReleaseMutex.assert_called_once_with(4321)
        kernel32.CloseHandle.assert_called_once_with(4321)


# ---------------------------------------------------------------------------
# Setup wizard: audio API and device selection
# ---------------------------------------------------------------------------


class TestPromptAudioApi:
    def test_enter_selects_wasapi(self, answers):
        answers("")
        assert _prompt_audio_api(API_MAP, FORE, STYLE) == "Windows WASAPI"

    @pytest.mark.parametrize(
        ("choice", "api"),
        [("2", "Windows DirectSound"), ("3", "MME"), (" 1 ", "Windows WASAPI")],
    )
    def test_numbered_choice_selects_api(self, answers, choice, api):
        answers(choice)
        assert _prompt_audio_api(API_MAP, FORE, STYLE) == api

    def test_zero_means_all_apis(self, answers):
        answers("0")
        assert _prompt_audio_api(API_MAP, FORE, STYLE) is None

    def test_invalid_choice_asks_again(self, answers, capsys):
        scripted = answers("7", "wasapi", "3")

        assert _prompt_audio_api(API_MAP, FORE, STYLE) == "MME"
        assert len(scripted.prompts) == 3
        assert capsys.readouterr().out.count("Invalid choice") == 2


class TestListInputDevices:
    def test_lists_only_input_devices_of_the_chosen_api(self, capsys):
        ids = _list_input_devices("Windows WASAPI", DEVICES, HOST_APIS, 3)

        out = capsys.readouterr().out
        assert ids == [1, 3]
        assert " [1] Desk Mic | Windows WASAPI\n" in out
        assert " [3] Headset | Windows WASAPI (DEFAULT)" in out
        assert "Speakers" not in out
        assert "Legacy Mic" not in out

    def test_all_apis_lists_every_input_device(self, capsys):
        ids = _list_input_devices(None, DEVICES, HOST_APIS, None)

        out = capsys.readouterr().out
        assert ids == [1, 2, 3]
        assert "(All)" in out
        assert " [2] Legacy Mic | MME" in out
        assert "(DEFAULT)" not in out


class TestPromptAudioDevice:
    def test_enter_picks_the_first_listed_device(self, answers, sound_devices):
        answers("")
        assert _prompt_audio_device("Windows WASAPI", API_MAP, FORE, STYLE) == 1

    def test_rejects_non_numeric_and_unlisted_ids(self, answers, sound_devices, capsys):
        # 2 is a real input device, but not on the chosen API; 0 has no input.
        answers("mic", "2", "0", "3")

        assert _prompt_audio_device("Windows WASAPI", API_MAP, FORE, STYLE) == 3
        out = capsys.readouterr().out
        assert "Please enter a numeric Device ID." in out
        assert "Invalid Device ID 2." in out
        assert "Invalid Device ID 0." in out

    def test_api_without_devices_asks_for_another_api(
        self, answers, sound_devices, capsys
    ):
        scripted = answers("3", "")

        assert _prompt_audio_device("Windows DirectSound", API_MAP, FORE, STYLE) == 2
        assert "No devices found for the selected API" in capsys.readouterr().out
        assert scripted.prompts[0] == "Choice [1]: "
        assert "[2]" in scripted.prompts[1]  # default offered from the MME list


# ---------------------------------------------------------------------------
# Setup wizard: persistence and key reset
# ---------------------------------------------------------------------------


class TestSaveSetupConfig:
    def test_creates_env_with_defaults_and_reloads(self, env_file):
        _save_setup_config("wss://dictation.example.com/ws", 3)

        assert dotenv_values(env_file) == {
            "WHISPER_WS_URI": "wss://dictation.example.com/ws",
            "AUDIO_DEVICE_ID": "3",
            "RECORD_HOTKEY": "ctrl+alt+w",
            "LOG_LEVEL": "INFO",
            "IDLE_TIMEOUT": "300",
        }
        cfg._load_env.assert_called_once()

    def test_updates_existing_env_and_keeps_other_settings(self, env_file):
        env_file.write_text("CUSTOM_FLAG=on\nAUDIO_DEVICE_ID=9\n", encoding="utf-8")

        _save_setup_config("ws://localhost:9989/ws", 4)

        values = dotenv_values(env_file)
        assert values["CUSTOM_FLAG"] == "on"
        assert values["AUDIO_DEVICE_ID"] == "4"
        assert values["WHISPER_WS_URI"] == "ws://localhost:9989/ws"


class TestPromptApiKeyReset:
    def test_no_stored_key_asks_nothing(self, answers, stored_keys):
        scripted = answers()

        _prompt_api_key_reset("dictation.example.com")

        assert scripted.prompts == []

    def test_yes_clears_the_key_for_that_host_only(self, answers, stored_keys):
        stored_keys[(SERVICE_NAME, "dictation.example.com")] = "old-key"
        stored_keys[(SERVICE_NAME, "other.example.com")] = "keep-me"
        answers(" Y ")

        _prompt_api_key_reset("dictation.example.com")

        assert stored_keys == {(SERVICE_NAME, "other.example.com"): "keep-me"}

    @pytest.mark.parametrize("reply", ["", "n", "yes please"])
    def test_anything_but_y_keeps_the_key(self, answers, stored_keys, reply):
        stored_keys[(SERVICE_NAME, "dictation.example.com")] = "old-key"
        answers(reply)

        _prompt_api_key_reset("dictation.example.com")

        assert stored_keys == {(SERVICE_NAME, "dictation.example.com"): "old-key"}


class TestSetupInteractive:
    def test_full_wizard_writes_config_and_resets_key(
        self, answers, sound_devices, env_file, stored_keys
    ):
        stored_keys[(SERVICE_NAME, "dictation.example.com")] = "old-key"
        answers("wss://dictation.example.com/ws", "", "3", "y")

        setup_interactive()

        values = dotenv_values(env_file)
        assert values["WHISPER_WS_URI"] == "wss://dictation.example.com/ws"
        assert values["AUDIO_DEVICE_ID"] == "3"
        assert stored_keys == {}

    def test_blank_answers_keep_the_current_server(
        self, answers, sound_devices, env_file, stored_keys, monkeypatch
    ):
        monkeypatch.setattr(cfg, "WS_URI", "ws://localhost:9989/ws")
        scripted = answers("", "0", "")

        setup_interactive()

        values = dotenv_values(env_file)
        assert values["WHISPER_WS_URI"] == "ws://localhost:9989/ws"
        assert values["AUDIO_DEVICE_ID"] == "1"
        assert len(scripted.prompts) == 3  # no key stored: no reset prompt
