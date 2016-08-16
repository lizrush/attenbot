#!/bin/sh

start_time=$3
duration=$4

palette="/tmp/palette.png"

filters="fps=15,scale=320:-1:flags=lanczos"

ffmpeg -v warning -ss $start_time -t $duration -i $1 -vf "$filters,palettegen" -y $palette
ffmpeg -v warning -ss $start_time -t $duration -i $1 -i $palette -lavfi "$filters [x]; [x][1:v] paletteuse" -y $2



# $ ./make_gif.sh input.mkv output.gif start_time duration
