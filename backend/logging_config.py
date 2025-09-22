
import sys
import os
from loguru import logger

def configure_logging():
    """Configures the Loguru logger for the application."""
    
    logger.remove()  # Remove default handler

    # Add a new level for SUCCESS, but don't fail if it already exists
    try:
        logger.level("SUCCESS", no=25, color="<green><bold>", icon="✅")
    except ValueError:
        pass  # Level already exists

    # Get log level from environment variable, default to INFO
    log_level = os.getenv("LOG_LEVEL", "INFO").upper()

    # Console logger
    logger.add(
        sys.stderr,
        level=log_level,
        format="<white>{time:YYYY-MM-DD HH:mm:ss}</white> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> - <level>{message}</level>",
        colorize=True
    )

    # File logger (always logs from DEBUG level up)
    logger.add(
        "/app/logs/backend.log",
        level="DEBUG",
        rotation="10 MB",  # Rotate log file when it reaches 10 MB
        retention="7 days", # Keep logs for 7 days
        format="{time:YYYY-MM-DD HH:mm:ss} | {level: <8} | {name}:{function}:{line} - {message}",
        enqueue=True,      # Make file logging non-blocking
        backtrace=True,
        diagnose=True
    )

    return logger

# Create a configured logger instance
log = configure_logging()

