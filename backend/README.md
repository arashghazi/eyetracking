# Backend (FastAPI)

Accounts, roles, invitations, information sheet and consent, profile and demographics for build step 1.

```
cd backend
pip install -e ".[test]"
cp .env.example .env            # set the admin bootstrap values and a JWT secret
uvicorn eyetracking.web.main:app --reload --port 8000
python -m pytest -q
```

Layers: `eyetracking/domain` (rules, no framework) -> `application` (use cases, ports, authorization) -> `infrastructure` (SQLAlchemy, argon2, JWT) -> `web` (FastAPI). The SQLite file `eyetracking_dev.db` is local only; set `EYETRACKING_DATABASE_URL` to a PostgreSQL URL for a shared environment.
