import os
import sys


def _set_bundled_java_home():
    candidates = []
    if hasattr(sys, "_MEIPASS"):
        candidates.append(os.path.join(sys._MEIPASS, "jvm"))
    candidates.append(
        os.path.abspath(os.path.join(os.path.dirname(sys.executable), "..", "Resources", "Home"))
    )
    candidates.append(os.path.abspath(os.path.join(sys.prefix, "..", "Resources", "Home")))

    for bundled_jvm in candidates:
        if os.path.isdir(bundled_jvm):
            os.environ.setdefault("JAVA_HOME", bundled_jvm)
            os.environ.setdefault("CP_JAVA_HOME", bundled_jvm)
            bin_path = os.path.join(bundled_jvm, "bin")
            existing_path = os.environ.get("PATH", "")
            if bin_path not in existing_path.split(os.pathsep):
                os.environ["PATH"] = bin_path + os.pathsep + existing_path
            break


if hasattr(sys, "_MEIPASS"):
    _set_bundled_java_home()

# Disable typeguard at runtime to avoid source inspection failures in bundled apps.
os.environ.setdefault("TYPEGUARD_DISABLE", "1")

# Ensure ARGVZERO is set for worker spawning in frozen macOS apps.
os.environ.setdefault("ARGVZERO", sys.executable)
