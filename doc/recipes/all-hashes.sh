#!/bin/bash
grep -oP '[0-9]+: \K[a-fA-F0-9]{64}'
