.PHONY: default docs

default: build build/libtraildb_wrapper.a

build/libtraildb_wrapper.a:
	gcc -Wall -g -O3 -c -o build/traildb_wrapper.o ext/traildb_wrapper.c
	ar -rsc build/libtraildb_wrapper.a build/traildb_wrapper.o
	ranlib build/libtraildb_wrapper.a

build:
	mkdir build

clean:
	rm -rf build
	rm -rf docs

docs:
	rm -rf docs
	crystal docs
	mv doc docs
