"""Run Alembic database migrations."""
import subprocess
import sys
from pathlib import Path

def run_migrations():
    """Run Alembic migrations to upgrade database to latest version."""
    # Get the server directory (parent of scripts)
    server_dir = Path(__file__).parent.parent

    # Change to server directory where alembic.ini is located
    original_dir = Path.cwd()
    try:
        import os
        os.chdir(server_dir)

        print("Running database migrations...")
        result = subprocess.run(
            ["alembic", "upgrade", "head"],
            capture_output=True,
            text=True
        )

        if result.returncode == 0:
            print("✓ Migrations completed successfully!")
            print(result.stdout)
        else:
            print("✗ Migration failed!")
            print(result.stderr)
            sys.exit(1)

    finally:
        os.chdir(original_dir)

if __name__ == "__main__":
    run_migrations()
