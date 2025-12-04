#!/bin/bash
# Replay CAN data from candump log to vcan0
# The log was captured from 'elmcan' interface, we map it to vcan0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

canplayer -I "$CONFIG_DIR/candump.log" vcan0=elmcan
