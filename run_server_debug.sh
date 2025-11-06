#!/bin/bash
# Script to run debugging on Railway server

echo "=========================================="
echo "Running Debug Script on Railway Server"
echo "=========================================="
echo ""

# SSH into server and run debug script
railway ssh --project=24bd293f-fda2-4c53-8924-3e1cc7c313ba --environment= --service=9493f093-3e4c-49cf-a713-9604f08d23dd << 'ENDSSH'
cd /app
echo "Current directory: $(pwd)"
echo ""
python scripts/debug_uploads.py
ENDSSH

echo ""
echo "=========================================="
echo "Debug script completed"
echo "=========================================="
