#!/bin/bash

find $PWD/backup/ -type f -name '*.zip' -mtime +1 -exec rm -rf {} \;

find $PWD/backup/postgres/ -type f -name '*.dump' -mtime +1 -exec rm -rf {} \;

find $PWD/backup/redis/ -type f -name '*.json' -mtime +1 -exec rm -rf {} \;
