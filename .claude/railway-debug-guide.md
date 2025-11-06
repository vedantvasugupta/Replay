# Railway Database Debugging Guide

## Querying the Database via SSH

When you need to query the Railway production database, the best approach is to use a Python script rather than inline SQL commands.

### Why Use a Script File?

- Avoids shell quoting/escaping issues with complex SQL
- Can install required packages (sqlalchemy, psycopg2)
- Provides formatted, readable output
- Can be reused and version controlled

### Approach

1. **Local script exists:** `server/check_db.py`
   - Queries session status, job status, stuck jobs, missing data
   - Uses SQLAlchemy for robust database access

2. **To run on Railway:**

```bash
# Option 1: Upload and run the existing script
railway run python server/check_db.py

# Option 2: Copy script to server and run via SSH
# First, create the script on the server
railway ssh --project=<PROJECT_ID> --environment=<ENV_ID> --service=<SERVICE_ID> << 'EOF'
cat > /tmp/check_db.py << 'PYEOF'
[paste the check_db.py contents here]
PYEOF
/opt/venv/bin/python /tmp/check_db.py
EOF
```

3. **Important Notes:**
   - The Railway environment already has sqlalchemy and psycopg2 installed
   - Database URL is available as `DATABASE_URL` environment variable
   - Script automatically converts async URL to sync for simple queries
   - Virtual env is at `/opt/venv/bin/python`

### Common Queries

**Check specific session:**
```sql
SELECT id, status, created_at FROM sessions WHERE id = X;
```

**Find stuck jobs:**
```sql
SELECT id, job_type, status, session_id, attempts,
       EXTRACT(EPOCH FROM (NOW() - updated_at))/60 as minutes_stuck
FROM jobs
WHERE status = 'processing'
  AND updated_at < NOW() - INTERVAL '10 minutes';
```

**Session with missing data:**
```sql
SELECT s.id, s.status,
       CASE WHEN a.id IS NOT NULL THEN 'Yes' ELSE 'No' END as has_audio,
       CASE WHEN t.id IS NOT NULL THEN 'Yes' ELSE 'No' END as has_transcript,
       CASE WHEN su.id IS NOT NULL THEN 'Yes' ELSE 'No' END as has_summary
FROM sessions s
LEFT JOIN audio_assets a ON s.id = a.session_id
LEFT JOIN transcripts t ON s.id = t.session_id
LEFT JOIN summaries su ON s.id = su.session_id
WHERE s.id = X;
```

### Debugging Workflow

1. Use `check_db.py` to get overview of recent sessions/jobs
2. Identify stuck sessions (status='processing' but no active job)
3. Check if session has audio/transcript/summary
4. Look for failed jobs with error messages
5. Use `/requeue/{session_id}` endpoint to retry if needed
