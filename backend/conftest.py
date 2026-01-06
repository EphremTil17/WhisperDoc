import sys
import os

# This file tells pytest to treat the backend directory as a package root.
# It allows tests in the tests/ folder to find modules in the parent folder automatically.
backend_dir = os.path.abspath(os.path.dirname(__file__))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)
