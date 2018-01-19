#!/bin/bash

find $PWD/backup/ -type f -name '*.zip' -mtime 1 -exec rm -rf {} \;

find $PWD/postgres/ -type f -name '*.dump' -mtime 1 -exec rm -rf {} \;

find $PWD/redis/ -type f -name '*.json' -mtime 1 -exec rm -rf {} \;
