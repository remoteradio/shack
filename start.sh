#!/bin/sh
echo "stopping any running shacks"
killall beam.smp
sleep 1
echo "starting shack"
nohup /usr/bin/mix run --no-halt > log/shack.log &
