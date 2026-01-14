
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
    # Custom Level for Incognito Mode
    logger.level("PRIVACY", no=25, color="<magenta>")

    # Get log level from environment variable, default to INFO
    log_level = os.getenv("LOG_LEVEL", "INFO").upper()

    # Determine if we should force colorization (useful for docker exec)
    # If COLORIZE_LOGS is not set, we let loguru decide based on TTY detection
    force_color = os.getenv("COLORIZE_LOGS", "true").lower() == "true"

    def formatter(record):
        # Concise format for INFO/SUCCESS/PRIVACY
        if record["level"].name in ["INFO", "SUCCESS", "PRIVACY"]:
            return "<white>{time:YYYY-MM-DD HH:mm:ss}</white> | <level>{level: <8}</level> | <white>{message}</white>\n"
        # Verbose format for ERROR/WARNING/DEBUG
        return "<white>{time:YYYY-MM-DD HH:mm:ss}</white> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> - <level>{message}</level>\n"

    # Console logger
    logger.add(
        sys.stderr,
        level=log_level,
        format=formatter,
        colorize=force_color
    )

    return logger

# Create a configured logger instance
log = configure_logging()

