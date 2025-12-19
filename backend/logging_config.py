
import sys
import os
from loguru import logger

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

    # Get log level from environment variable, default to INFO
    log_level = os.getenv("LOG_LEVEL", "INFO").upper()

    # Determine if we should force colorization (useful for docker exec)
    # If COLORIZE_LOGS is not set, we let loguru decide based on TTY detection
    force_color = os.getenv("COLORIZE_LOGS", "true").lower() == "true"

    # Console logger
    logger.add(
        sys.stderr,
        level=log_level,
        format="<white>{time:YYYY-MM-DD HH:mm:ss}</white> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> - <level>{message}</level>",
        colorize=force_color
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

