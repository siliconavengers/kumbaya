#!/bin/bash

find $PWD/backup/ -type f -name '*.zip' -exec rm -rf {} \;

find $PWD/backup/ -type f -name '*.gpg' -exec rm -rf {} \;

find $PWD/backup/postgres/ -type f -name '*.dump' -exec rm -rf {} \;

find $PWD/backup/redis/ -type f -name '*.json' -exec rm -rf {} \;
