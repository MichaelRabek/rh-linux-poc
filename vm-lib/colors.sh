#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2026 Michal Rábek <mrabek@redhat.com> All rights reserved.

# Only use colors if stdout is a terminal
if [ -t 1 ]; then
    RED="\e[31m"
    GREEN="\e[32m"
    YELLOW="\033[1;33m"
    BLUE="\e[34m"
    NC="\e[0m"  # No Color
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    NC=""
fi

# Common messaging functions

# Print error message and exit
error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Print info message
info() {
    echo -e "${GREEN}$1${NC}"
}

# Print warning message
warning() {
    echo -e "${YELLOW}$1${NC}"
}

# Print debug message
debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        echo -e "${BLUE}Debug: $1${NC}" >&2
    fi
}
