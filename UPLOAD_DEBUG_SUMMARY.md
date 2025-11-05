# Upload Debug Summary

## Problem
- Uploaded recordings show up as 0 bytes on the server
- Files don't get processed (stuck in "not processing" state)
- Affects both recorded and file-uploaded audio

## Changes Made

### 1. Added Comprehensive Logging

**File: `server/src/api/uploads.py`**
- Added detailed logging to all three endpoints: `/upload-url`, `/upload`, `/ingest`
- Logs include:
  - User ID and asset ID for tracking
  - File details (filename, content_type, size)
  - Success/failure of each step
  - Any errors with stack traces

**File: `server/src/services/storage_service.py`**
- Added logging to `save_upload()` method
- Logs:
  - Path where file is being saved
  - Number of chunks read
  - Total bytes written
  - Verification of file on disk after write
  - Detection of size mismatches

### 2. Created Debugging Scripts

**File: `server/scripts/debug_uploads.py`**
- Checks database for recent audio assets
- Verifies files exist on disk
- Compares DB sizes vs actual file sizes
- Lists all zero-byte files
- Provides analysis and recommendations

**File: `server/scripts/test_upload.py`**
- Tests the upload flow with dummy data
- Verifies the storage service works correctly
- Can be run on the server to test in isolation

## Next Steps

### 1. Deploy Changes to Railway
```bash
# First, commit the changes
git add server/src/api/uploads.py server/src/services/storage_service.py
git commit -m "Add comprehensive logging for upload debugging"

# Push to trigger deployment
git push
```

### 2. Login to Railway and SSH into Server
```bash
# Login to Railway (this will open a browser)
railway login

# Once logged in, SSH into the server
railway ssh --project=24bd293f-fda2-4c53-8924-3e1cc7c313ba --environment= --service=9493f093-3e4c-49cf-a713-9604f08d23dd
```

### 3. Run Debugging Script
```bash
# Once SSH'd into the server
cd /app
python scripts/debug_uploads.py
```

### 4. Monitor Live Logs
```bash
# In a separate terminal on your local machine
railway logs --project=24bd293f-fda2-4c53-8924-3e1cc7c313ba --environment= --service=9493f093-3e4c-49cf-a713-9604f08d23dd --follow
```

### 5. Test Upload from App
- Try uploading a new recording
- Try uploading a file
- Watch the logs in real-time to see where the issue occurs

## Key Log Messages to Look For

### Upload URL Request
```
[upload-url] User {id} requesting upload URL for {filename} ({mime})
[upload-url] Created asset {id} at path: {path}
```

### File Upload
```
[upload] User {id} uploading file for asset {id}
[upload] File details - filename: {name}, content_type: {type}, size: {size}
[upload] Successfully saved {size} bytes to disk for asset {id}
```

### File Save
```
[save_upload] Saving asset {id} to {path}
[save_upload] First chunk size: {size} bytes
[save_upload] Wrote {size} bytes in {chunks} chunks to {path}
[save_upload] File exists on disk with size: {size} bytes
```

### Ingest
```
[ingest] User {id} requesting ingest for asset {id}
[ingest] Asset {id} has size: {size} bytes
```

## Potential Root Causes

### 1. Upload Endpoint Not Being Called
- Symptoms: You'll see upload-url logs but no upload logs
- Cause: Client might be failing to call /upload endpoint
- Solution: Check client-side error logs

### 2. Empty File Being Uploaded
- Symptoms: You'll see upload logs but size is 0 or chunks_read is 0
- Cause: File might not exist or be readable on client device
- Solution: Add file validation on client before upload

### 3. File Write Failure
- Symptoms: Chunks are read but file doesn't exist or is 0 bytes
- Cause: Disk space, permissions, or I/O errors
- Solution: Check disk space and permissions

### 4. Network/Timeout Issue
- Symptoms: Upload starts but doesn't complete
- Cause: Network interruption or timeout
- Solution: Check timeout settings and network stability

## File Path Investigation

The file upload uses `MultipartFile.fromFile()` in the Flutter client. Potential issues:

1. **File Path Access**: On Android 10+, files are stored in app-specific external storage. Make sure the path is accessible when reading.

2. **File URI vs Path**: The code uses `file.path` which should work, but verify the file exists before upload.

3. **Permissions**: Storage permissions might be needed to read the file for upload (separate from write permissions).

## Additional Checks

1. **File Exists Before Upload**: Add validation in client to check `File(path).existsSync()` before upload
2. **File Size Before Upload**: Log `File(path).lengthSync()` to ensure file has data
3. **Upload Progress**: Add upload progress callbacks to detect if upload is actually sending data
