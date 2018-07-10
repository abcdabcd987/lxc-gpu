#!/bin/bash

export SERVER_NAME="$(hostname)"
export WEB_URL="$1"

run_df() {
    df -h | curl -s -X POST --data-binary @- "$WEB_URL/feed/$SERVER_NAME/df" > /dev/null 2>&1
    sleep 5
}

run_free() {
    free | curl -s -X POST --data-binary @- "$WEB_URL/feed/$SERVER_NAME/free" > /dev/null 2>&1
    sleep 5
}

run_iostat() {
    iostat -dxy 3 1 | curl -s -X POST --data-binary @- "$WEB_URL/feed/$SERVER_NAME/iostat" > /dev/null 2>&1
    sleep 2
}

run_mpstat() {
    mpstat -P ALL 3 1 | curl -s -X POST --data-binary @- "$WEB_URL/feed/$SERVER_NAME/mpstat" > /dev/null 2>&1
    sleep 2
}

run_nvidia() {
    nvidia-smi -q | curl -s -X POST --data-binary @- "$WEB_URL/feed/$SERVER_NAME/nvidia" > /dev/null 2>&1
    sleep 5
}

run_ps() {
    ps auxww | curl -s -X POST --data-binary @- "$WEB_URL/feed/$SERVER_NAME/ps" > /dev/null 2>&1
    sleep 5
}

run_sensors() {
    sensors | curl -s -X POST --data-binary @- "$WEB_URL/feed/$SERVER_NAME/sensors" > /dev/null 2>&1
    sleep 5
}

forever() {
    while true; do $1; done
}

kill_all() {
    trap '' INT TERM
    echo Exiting...
    kill -TERM 0
    wait
    echo DONE
}

trap 'kill_all' INT TERM

forever run_df &
forever run_free &
forever run_iostat &
forever run_mpstat &
forever run_nvidia &
forever run_ps &
forever run_sensors &
wait
