#!/bin/env bash

BENCHMARKS=(
    barnes_hut2
    barnes_hut
    boyer
    coresml
    count_graphs
    cpstak
    diviter
    divrec
    fft
    gcbench
    knuth_bendix
    lexgen
    life
    logic
    mandelbrot
    mlyacc
    smlyacc
    nucleic
    nqueen
    perm9
    puzzle
    ratio_regions
    ray
    simple
    tsp
    vliw)

#SUFFIX=v1.2.0
SUFFIX=v2.0.0

function toAbsolutePath () {
	echo $(cd $(dirname $1) && pwd)/$(basename $1)
}

function make_result_json () {
	local readonly name=$1
	local readonly  now=$2
	local readonly result=$3
	echo "{\"name\":\"$name\", \"date\":\"$now\", \"result\":$result}"
}

function run () {
	local readonly name=$(basename $1)
	local readonly now=$(date +"%Y-%m-%dT%H:%S:%M")
	local readonly format="{\"time\":{\"elapsed\":%e, \"kernal\":%S, \"user\":%U}, \"memory\":{\"max\":%M}}"
	local readonly log_dir=$(toAbsolutePath $2)
	local readonly temp=$(mktemp)
	trap "rm -rf $temp" EXIT
	cd $1
		/usr/bin/time -f "${format}" -o ${temp} ./doit${SUFFIX} > $log_dir
		local readonly error=$?
	cd ..
	if [ $error -eq 0 ]; then
		make_result_json $name $now "$(cat $temp)"
	else
		make_result_json $name $now "null"
	fi
	return $error
}

LOG_DIR=${LOG_DIR:-log}
mkdir -p ${LOG_DIR}

result=()
for (( i=0; i<${#BENCHMARKS[@]}; i++ ))
do
	echo "running ${BENCHMARKS[$i]} ..." >&2
	r=$(run benchmarks/${BENCHMARKS[$i]} ${LOG_DIR}/${BENCHMARKS[$i]}.log)
	result[$i]=$r
done

echo "["
for (( i=0; i<${#result[@]}; i++ ))
do
	echo -n "${result[$i]}"
	if [ $i -lt $((${#result[@]} - 1)) ]; then
		echo ", "
	else
		echo ""
	fi
done
echo "]"

