
import sys
from logging_config import log

def run_log_tests():
    """Generates a log message for each level to test configuration."""
    log.info("--- Starting Log Test ---")
    
    log.debug("This is a test DEBUG message. It should only appear in the log file, not the console.")
    log.info("This is a test INFO message. It should appear in both the console and log file.")
    log.success("This is a test SUCCESS message. It should be green and have an icon in the console.")
    log.warning("This is a test WARNING message. It should be yellow in the console.")
    log.error("This is a test ERROR message. It should be red in the console.")
    log.critical("This is a test CRITICAL message. It should be bold and red in the console.")
    
    try:
        1 / 0
    except ZeroDivisionError:
        log.exception("This is a test EXCEPTION message. A traceback should be automatically included.")

    log.info("--- Log Test Complete ---")

if __name__ == "__main__":
    run_log_tests()
    print("\n\nLog test script finished.")
    print("--------------------------------------------------")
    print("Verification Steps:")
    print("1. Check the console output above for formatted, colored log messages from INFO level and up.")
    print("2. Check the log file inside the container for all messages, including DEBUG and the full exception traceback.")
    print("   Run this command to see the log file:")
    print("   sudo docker compose exec whisper-backend cat /app/logs/backend.log")
    print("--------------------------------------------------")

