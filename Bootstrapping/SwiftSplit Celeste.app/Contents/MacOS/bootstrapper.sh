#!/bin/bash
SWIFT_SPLIT_PATH="${0%/*/*}/Resources/SwiftSplit.app/Contents/MacOS/SwiftSplit"
BOOTSTRAP_SCRIPT="do shell script \"'$SWIFT_SPLIT_PATH'\" with prompt \"SwiftSplit wants to read process memory.\" with administrator privileges"
osascript -e "$BOOTSTRAP_SCRIPT" &
