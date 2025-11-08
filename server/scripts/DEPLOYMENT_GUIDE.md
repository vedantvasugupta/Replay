# Summary Generation Fix - Deployment Guide

## Problem Summary

**Issue 1: Missing Summaries**
- Some recordings have transcripts but no summaries
- Sessions are stuck in "processing" status instead of "ready"
- Root cause: Silent errors during summary save operations

**Issue 2: Chat Not Working**
- Chat requires sessions to be in "ready" status
- Sessions without summaries remain in "processing" status
- Users cannot chat with recordings that are stuck in processing

## Solution Overview

1. **Improved Error Handling** - Better logging and validation in `transcription_service.py`
2. **Diagnostic Script** - Identify affected sessions
3. **Fix Script** - Regenerate summaries from existing transcripts

## Deployment Steps

### Step 1: Deploy Code Changes

The code has been committed and pushed. Deploy the updated code to production:

```bash
# On Railway or your deployment platform:
# 1. Merge the branch or deploy from claude/railway-ssh-connection-011CUv7gU9arS6sTtjsCNFAf
# 2. Wait for deployment to complete
# 3. Verify the application is running
```

### Step 2: Run Diagnostic Script

First, assess the scope of the problem:

```bash
# SSH into your production server
railway ssh --project=24bd293f-fda2-4c53-8924-3e1cc7c313ba \
  --environment=8489a056-0f9c-4baa-aae0-43d93f66dc4a \
  --service=9493f093-3e4c-49cf-a713-9604f08d23dd

# Once connected, run:
cd /app
python -m scripts.diagnose_sessions
```

**Expected Output:**
```
📊 OVERALL STATISTICS
Total sessions: XX
Sessions by status:
  ready       : XX
  processing  : XX  <-- These are potentially stuck
  failed      : XX

🚨 SESSIONS WITH TRANSCRIPTS BUT NO SUMMARIES
Found X sessions with transcripts but no summaries:
  Session XXX: Title... | Status: processing | Transcript: XXXX chars

📋 LAST 15 SESSIONS (DETAILED VIEW)
ID  | Title | Status | T | S | Chat | Created
...
```

### Step 3: Run Fix Script (Dry Run First)

Test the fix script in dry-run mode to see what would happen:

```bash
# Still in the SSH session
python scripts/regenerate_summaries.py --dry-run --limit=10
```

This will show which sessions would be fixed without making any changes.

### Step 4: Run Fix Script (Production)

If the dry run looks good, run it for real:

```bash
# Fix the most recent 10 sessions without summaries
python scripts/regenerate_summaries.py --limit=10
```

**Expected Output:**
```
🔍 Searching for sessions with transcripts but no summaries (limit=10)...
📋 Found X sessions without summaries:

ID    | Title                    | Status     | Transcript | Created
12345 | Team Meeting...          | processing | 15234 ch  | 2025-11-07 14:23:45

🚀 Ready to regenerate summaries for X sessions

[1/X] Processing session 12345: Team Meeting...
🔄 Starting summary regeneration...
📝 Transcript length: 15234 characters
🤖 Calling Gemini to generate summary...
📊 Summary generated: 456 chars, 3 actions, 5 timeline items, 2 decisions
✅ Summary saved to database
✅ Status updated to 'ready'
🎉 Summary regeneration complete!

REGENERATION COMPLETE
✅ Successful: X
❌ Failed: 0
```

### Step 5: Verify Chat Works

After fixing sessions:

1. Go to a recording that was previously stuck in "processing"
2. Verify it now shows as "ready"
3. Try using the chat feature
4. It should now work!

### Step 6: Process Remaining Sessions (if any)

If there are more than 10 affected sessions, run the script again with a higher limit:

```bash
# Fix up to 50 sessions
python scripts/regenerate_summaries.py --limit=50
```

Or run multiple times with smaller batches to avoid rate limiting.

## Monitoring

After deployment, monitor the logs for:

1. **Successful summary saves:**
```
✅ [SESSION XXX] Summary saved successfully
```

2. **Detailed error information (if issues occur):**
```
❌ [SESSION XXX] Failed to save summary: <error details>
❌ [SESSION XXX] Error details:
<full stack trace>
❌ [SESSION XXX] Summary data that failed: ...
```

3. **Data validation warnings:**
```
⚠️ [SESSION XXX] Summary text is not a string, converting: <type>
```

## Troubleshooting

### Issue: Script fails with "DATABASE_URL not set"

**Solution:**
```bash
# Make sure you're running in the production environment
# Or set DATABASE_URL manually:
export DATABASE_URL="your-database-url"
python scripts/regenerate_summaries.py
```

### Issue: Script fails with "GEMINI_API_KEY not set"

**Solution:**
The script will use fallback mode if no API key is set, but this won't generate real summaries.
Make sure GEMINI_API_KEY is set in your environment.

### Issue: Rate limiting errors

**Solution:**
The script includes 3-second delays between sessions. If you still hit rate limits:
- Reduce the `--limit` parameter
- Run in smaller batches
- Wait a few minutes between runs

### Issue: Sessions still showing as "processing"

**Possible causes:**
1. Summary failed to save (check logs for error details)
2. Gemini API error (check logs)
3. Database transaction failed (check database logs)

**Solution:**
Run the diagnostic script again to see current state:
```bash
python -m scripts.diagnose_sessions
```

## Rollback

If issues occur, you can rollback the code deployment. The database changes (new summaries) are safe and won't cause issues.

To manually revert a session status:
```sql
-- Connect to database
UPDATE sessions SET status = 'processing' WHERE id = XXX;
```

## Scripts Reference

### diagnose_sessions.py
**Purpose:** Diagnose issues with sessions, transcripts, summaries, and chat
**Usage:** `python -m scripts.diagnose_sessions`
**Output:** Comprehensive report of session states

### regenerate_summaries.py
**Purpose:** Fix sessions with transcripts but no summaries
**Usage:**
- Dry run: `python scripts/regenerate_summaries.py --dry-run --limit=N`
- Production: `python scripts/regenerate_summaries.py --limit=N`
**Output:** Regenerates summaries and updates session status

### fix_missing_summaries.py
**Purpose:** Alternative implementation of summary regeneration
**Usage:** Similar to regenerate_summaries.py
**Note:** Use regenerate_summaries.py as it's more production-ready

## Success Criteria

After deployment and running the fix scripts:

✅ All sessions with transcripts should have summaries
✅ Sessions should be in "ready" status (not stuck in "processing")
✅ Chat functionality should work on all ready sessions
✅ New recordings should generate summaries successfully
✅ Detailed error logs available for any future issues

## Contact

If issues persist after following this guide, check:
1. Application logs for detailed error messages
2. Database logs for constraint violations
3. Gemini API status and rate limits
