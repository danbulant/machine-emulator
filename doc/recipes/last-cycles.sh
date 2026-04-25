#!/bin/bash
grep -oP 'Cycles: \K[0-9]+' | tail -1
