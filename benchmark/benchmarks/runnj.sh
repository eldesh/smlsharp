#!/bin/sh

ARCH=x86-linux
OS=linux
(* sml/nj *)
SML=sml

# build
function build_nj () {
	local readonly bench=$1
	ml-build $bench/sources.cm Test.main $bench/sources.${ARCH}-${OS}
}

function run_nj () {
	local readonly bench=$1
	cd $bench
		${SML} @SMLload=sources.${ARCH}-${OS}
	cd ..
}

# skip
#   using smlyacc-lib (SML# specific)
#     smlyacc
#   using FFI
#     mlyacc nqeen realtime
#   using toplevel open
#     vliw
#   Array2 is dupricated
#     simple simple2
BENCHMARKS='boyer count_graphs cpstak diviter divrec fft gcbench knuth_bendix lexgen life logic mandelbrot
			nucleic perm9 puzzle ratio_regions ray tsp'
for bench in $BENCHMARKS
do
	build_nj $bench
	if [ $? -eq 0 ]; then
		echo "build success [$bench]" >&2
	else
		echo "build failure [$bench]" >&2
	fi
done


# run
${SML} < coresml/fibonacci.sml

for bench in $BENCHMARKS
do
	run_nj $bench >/dev/null
	if [ $? -eq 0 ]; then
		echo "run success [$bench]" >&2
	else
		echo "run failure [$bench]" >&2
	fi
done



