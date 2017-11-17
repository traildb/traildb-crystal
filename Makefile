.PHONY: default

default: build build/libtraildb_wrapper.a

build/libtraildb_wrapper.a:
	gcc -Wall -g -O2 -c -o build/traildb_wrapper.o ext/traildb_wrapper.c
	ar -rsc build/libtraildb_wrapper.a build/traildb_wrapper.o
	ranlib build/libtraildb_wrapper.a

build:
	mkdir build

clean:
	rm -rf build
