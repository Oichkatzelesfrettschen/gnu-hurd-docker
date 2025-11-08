#!/bin/bash
# Master installation script
echo "Running all Hurd installations..."
bash install-essentials-hurd.sh
bash install-nodejs-hurd.sh
bash install-claude-code-hurd.sh
