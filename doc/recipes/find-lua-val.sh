#!/bin/bash
grep -oP "\"*$1\"* = \"*\K(0x[0-9a-fA-F]+|-?[0-9]+)" | head -1
