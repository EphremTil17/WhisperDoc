import logging
import os
import sys

from loguru import logger

# ---------------------------------------------------------------------------
# Third-party noise filter (general-purpose)
# ---------------------------------------------------------------------------
# Suppresses sub-ERROR stdlib log messages from noisy third-party libraries.
# The primary NeMo silencing is handled by the fd-level redirect in
# parakeet_engine._suppress_nemo_noise().  This filter acts as a safety net
# for any stdlib-routed messages that escape the fd redirect (e.g. during
# import time before the context manager is active).
#
# Installed on the ROOT logger so it survives logging.basicConfig(force=True)
# calls that NeMo's import chain makes (which replaces handlers but not filters).
SILENCED_PREFIXES = (
    "nemo",
    "nv_one_logger",
    "lhotse",
    "pytorch_lightning",
    "matplotlib",
)

SILENCED_MESSAGES = ("Initializing Lhotse CutSet",)


class _ThirdPartyNoiseFilter(logging.Filter):
    """Drop sub-ERROR messages from known noisy third-party namespaces."""

    def filter(self, record):
        if record.name.startswith(SILENCED_PREFIXES):
            return record.levelno >= logging.ERROR
        if record.levelno < logging.ERROR:
            msg = record.getMessage()
            if any(s in msg for s in SILENCED_MESSAGES):
                return False
        return True


logging.getLogger().addFilter(_ThirdPartyNoiseFilter())


def configure_logging():
    """Configures the Loguru logger for the application."""

    logger.remove()  # Remove default handler

    # Update colors for standard levels
    # We only pass 'color' because these levels already exist in loguru
    logger.level("TRACE", color="<cyan><dim>")
    logger.level("DEBUG", color="<magenta><dim>")
    logger.level("INFO", color="<light-blue>")
    logger.level("SUCCESS", color="<green>")
    logger.level("WARNING", color="<yellow>")
    logger.level("ERROR", color="<red>")
    logger.level("CRITICAL", color="<red><reverse>")
    # Custom Level for Incognito Mode
    logger.level("PRIVACY", no=25, color="<magenta>")

    # Get log level from environment variable, default to INFO
    log_level = os.getenv("LOG_LEVEL", "INFO").upper()

    # Determine if we should force colorization (useful for docker exec)
    # If COLORIZE_LOGS is not set, we let loguru decide based on TTY detection
    force_color = os.getenv("COLORIZE_LOGS", "true").lower() == "true"

    def formatter(record):
        # All timestamps are UTC regardless of host timezone
        # Concise format for INFO/SUCCESS/PRIVACY
        if record["level"].name in ["INFO", "SUCCESS", "PRIVACY"]:
            return "<white>{time:YYYY-MM-DD HH:mm:ss!UTC}</white> | <level>{level: <8}</level> | <white>{message}</white>\n"
        # Verbose format for ERROR/WARNING/DEBUG
        return "<white>{time:YYYY-MM-DD HH:mm:ss!UTC}</white> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> - <level>{message}</level>\n"

    # --- Intercept Standard Logging (Uvicorn/FastAPI) ---
    class InterceptHandler(logging.Handler):
        def emit(self, record):
            # Get corresponding Loguru level if it exists
            try:
                level = logger.level(record.levelname).name
            except ValueError:
                level = record.levelno

            # Find caller from where originated the logged message
            frame, depth = logging.currentframe(), 2
            while frame is not None and frame.f_code.co_filename == logging.__file__:
                frame = frame.f_back
                depth += 1

            logger.opt(depth=depth, exception=record.exc_info).log(
                level, record.getMessage()
            )

    # Set up global intercept for all standard library loggers
    logging.basicConfig(handlers=[InterceptHandler()], level=0, force=True)

    # Specifically target uvicorn and web framework loggers
    for logger_name in (
        "uvicorn",
        "uvicorn.access",
        "uvicorn.error",
        "fastapi",
        "starlette",
    ):
        mod_logger = logging.getLogger(logger_name)
        mod_logger.handlers = [InterceptHandler()]
        mod_logger.propagate = False

    # Console logger
    logger.add(sys.stderr, level=log_level, format=formatter, colorize=force_color)

    return logger


# Create a configured logger instance
log = configure_logging()
