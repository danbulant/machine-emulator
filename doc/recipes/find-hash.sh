#!/bin/bash
grep -oP "\"*$1\"*: \"*\K[a-fA-F0-9]{64}" | head -1
