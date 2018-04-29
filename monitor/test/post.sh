#!/bin/bash

post() {
    cat $1.txt | curl -X POST --data-binary @- http://localhost:4838/feed/gpu1/$1
}

post mpstat
post sensors
post free
post nvidia
post df
post iostat
post ps
