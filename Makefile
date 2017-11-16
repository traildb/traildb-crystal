.PHONY: default

default: build build/libtraildb_wrapper.so build/traildb

build/libtraildb_wrapper.so:
	gcc -shared -o build/libtraildb_wrapper.so -fPIC src/traildb_wrapper.c

build/traildb:
	crystal build src/traildb.cr -o build/traildb

build:
	mkdir build

clean:
	rm -rf build
