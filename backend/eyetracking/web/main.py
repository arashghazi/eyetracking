"""Entry point for `uvicorn eyetracking.web.main:app --reload`."""
from .app import create_app

app = create_app()
