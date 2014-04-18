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

function toAbsolutePath () {
	echo $(cd $(dirname $1) && pwd)/$(basename $1)
}

function run () {
	local readonly name=$(basename $1)
	local readonly now=$(date +"%Y-%m-%dT%H:%S:%M")
	local readonly format="{\"name\":\"$name\", \"date\":\"$now\", \"time\":{\"elapsed\":%e, \"kernal\":%S, \"user\":%U}, \"memory\":{\"max\":%M}}"
	local readonly log_dir=$(toAbsolutePath $2)
	local readonly temp=$(mktemp)
	trap "rm -rf $temp" EXIT
	cd $1
		/usr/bin/time -f "${format}" -o ${temp} ./doit > $log_dir
		local readonly result=$?
	cd ..
	if [ $result -eq 0 ]; then
		cat $temp
	fi
	return $result
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

echo "{"
for (( i=0; i<${#result[@]}; i++ ))
do
	echo -n "${result[$i]}"
	if [ $i -lt $((${#result[@]} - 1)) ]; then
		echo ", "
	else
		echo ""
	fi
done
echo "}"

