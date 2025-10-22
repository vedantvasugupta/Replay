# Deployment Guide

## Critical: Database Migrations

**IMPORTANT FOR ALL AI ASSISTANTS AND DEVELOPERS:**

When deploying this application, database migrations MUST run before the application starts. This is not optional - the application will fail if the database schema doesn't match the code.

## How Migrations Work

### Development (Local)
```bash
# After creating a new migration
alembic upgrade head
```

### Production (Railway)
Migrations run automatically on each deployment via:
- `railway.toml` - startCommand runs migrations first (at runtime)
- `Procfile` - defines web process only (no release phase)
- `scripts/run_migrations.py` - handles migration execution

**Important:** Migrations MUST run at **runtime** (startCommand), NOT during build (release phase), because:
- DATABASE_URL environment variable is only available at runtime
- Database connections aren't accessible during Docker build phase
- Running migrations during build causes "Name or service not known" errors

## Migration Workflow

### Creating a New Migration
```bash
cd server
alembic revision -m "description of changes"
# Edit the generated file in alembic/versions/
alembic upgrade head  # Test locally
```

### What Happens on Railway Deployment
1. Code is pushed to master branch
2. Railway detects changes and builds Docker image
3. Container starts at runtime (DATABASE_URL now available)
4. **Migration script runs**: `python scripts/run_migrations.py`
5. If migrations succeed → uvicorn starts the app
6. If migrations fail → container exits (deployment fails)

## Why Migrations Must Run on Deployment

### The Problem We Solved
- Code added `speakers_json` column to Transcript model
- Migration file `0003_add_speakers_to_transcripts.py` was created
- Local SQLite database was migrated
- **Railway PostgreSQL database was NOT migrated**
- Result: `column transcripts.speakers_json does not exist` error

### The Solution
Automatic migrations on deployment ensure:
- Database schema always matches code
- No manual intervention needed
- Atomic updates (fail fast if issues)
- Consistent across all environments

## Deployment Checklist

When adding new database columns/tables:
- [ ] Create migration: `alembic revision -m "description"`
- [ ] Test migration locally: `alembic upgrade head`
- [ ] Commit migration file to git
- [ ] Push to master - migrations run automatically on Railway
- [ ] Verify deployment logs show successful migration
- [ ] Test app functionality

## Common Issues

### Migration Fails on Railway
**Check:**
1. Migration file syntax is correct
2. DATABASE_URL environment variable is set
3. PostgreSQL version compatibility
4. No conflicting migrations

**View logs:**
```bash
railway logs
```

### "Name or service not known" Error During Build
**Error:** `socket.gaierror: [Errno -2] Name or service not known`

**Cause:** Migrations trying to run during Docker build phase when DATABASE_URL isn't available.

**Solution:**
- Migrations MUST run in `railway.toml` startCommand (runtime)
- NOT in Procfile release phase (build time)
- Our configuration correctly runs migrations at runtime only

### Column Already Exists Error
If you manually added columns or ran migrations out of order:
```bash
# Mark migration as complete without running it
alembic stamp head
```

### Rolling Back Migrations
```bash
# Rollback one migration
alembic downgrade -1

# Rollback to specific version
alembic downgrade <revision_id>
```

## Database URLs

### Local Development
```
DATABASE_URL=sqlite+aiosqlite:///./replay.db
```

### Railway Production
```
DATABASE_URL=postgresql+asyncpg://user:pass@host:port/database
```

Alembic automatically reads from `DATABASE_URL` environment variable (see `alembic/env.py`).

## Files Involved

### Deployment Configuration
- `railway.toml` - Railway deployment config
- `Procfile` - Process definitions (release + web)
- `scripts/run_migrations.py` - Migration runner script

### Migration Files
- `alembic.ini` - Alembic configuration
- `alembic/env.py` - Alembic environment setup
- `alembic/versions/*.py` - Individual migration files

### Database Models
- `src/models/*.py` - SQLAlchemy ORM models
- `src/core/db.py` - Database connection setup
- `src/core/config.py` - Configuration (DATABASE_URL)

## Best Practices

1. **Always create migrations for schema changes** - Don't modify database manually
2. **Test migrations locally first** - Catch issues before production
3. **One migration per logical change** - Easier to debug and rollback
4. **Never edit existing migrations** - Create new ones to fix issues
5. **Keep migrations in version control** - Essential for team collaboration
6. **Review migration SQL** - Use `alembic upgrade head --sql` to preview

## For AI Models

When helping with database changes:
1. Always check if migration exists for new columns/tables
2. Remind developers to run migrations locally
3. Verify deployment config runs migrations automatically
4. Check Railway/deployment logs for migration errors
5. Don't assume manual database changes are acceptable

**Key principle:** Code and database schema must stay in sync through migrations, not manual SQL.
