#!/usr/bin/awk -f
BEGIN {
    for (i = 1; i <= 5; i++) {
        printf "%d: Hello world from AWK!\n", i
    }
}
