import sys
from pathlib import Path

# Make the example's handlers package importable so the registry gets populated
# before the generated tests run.
_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE))

from handlers import calculator_handlers  # noqa: F401, E402
