#!/bin/bash
# Run's Build.PL

perl Build.PL
./Build test  # make sure everything passes
./Build manifest  # ensure all files are listed
./Build distcheck  # catch any MANIFEST inconsistencies
./Build disttest  # final sanity check
./Build dist  # Build dist
