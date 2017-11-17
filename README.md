[![Build Status](https://travis-ci.org/traildb/traildb-crystal.svg?branch=master)](https://travis-ci.org/traildb/traildb-crystal)

# TrailDB Crystal Bindings

![TrailDB Logo](http://traildb.io/images/traildb_logo_512.png)

Official Crystal bindings for [TrailDB](http://traildb.io/), an efficient tool for storing and querying series of events. 
This library is heavily inspired by the [official Python bindings](https://github.com/traildb/traildb-python).
Crystal is an excellent language for TrailDB due to its simplicity and blazing fast performance. Crystal + TrailDB = ❤️.

## Install

1. Install [`traildb`](https://github.com/traildb/traildb) to your system. You can install the binaries for your system or compile it from source. [Detailed instructions here.](https://github.com/traildb/traildb#installing-binaries)
2. Add this to your `shard.yml`
```yaml
dependencies:
  traildb:
    github: traildb/traildb-crystal
```
3. Install using `crystal deps`

## Examples

### Constructing a TrailDB

#### Code
```crystal
require "traildb"

cons = TrailDBConstructor.new("testtrail.tdb", ["field1", "field2"])

uuid = "12345678123456781234567812345678"
cons.add(uuid, Time.new(2017, 11, 12, 1, 1), ["a", "1"])
cons.add(uuid, Time.new(2017, 11, 13, 1, 1), ["b", "2"])
cons.add(uuid, Time.new(2017, 11, 14, 1, 1), ["c", "3"])
cons.close
```

### Loading all trails

#### Code

```crystal
require "traildb"

traildb = TrailDB.new("testtrail.tdb")

puts "Number of trails: #{traildb.num_trails}"
puts "Number of fields: #{traildb.num_fields}"

traildb.trails.each do |(uuid, trail)|
  puts "Events for trail #{uuid}"
  trail.each do |event|
    puts event
  end
end
```

#### Output
```
Number of trails: 1
Number of fields: 3
Events for trail 12345678123456781234567812345678
{"field1" => "a", "field2" => "1", "time" => 2017-11-12 06:01:00 UTC}
{"field1" => "b", "field2" => "2", "time" => 2017-11-13 06:01:00 UTC}
{"field1" => "c", "field2" => "3", "time" => 2017-11-14 06:01:00 UTC}
```

### Loading all events in a trail

#### Code

```crystal
events = traildb[0].to_a
# or
events = traildb["12345678123456781234567812345678"].to_a
```

### Applying an Event Filter

#### Code

```crystal
require "traildb"

event_filter = traildb.create_filter([[{"field1", "a"}]])
traildb.event_filter = event_filter

traildb.trails.each do |(uuid, trail)|
  puts "Events for trail #{uuid}"
  trail.each do |event|
    puts event
  end
end
```

#### Output
```
Events for trail 12345678123456781234567812345678
{"field1" => "a", "field2" => "1", "time" => 2017-11-12 06:01:00 UTC}
```

For more examples, check out the specs for the library at `spec/traildb_spec.cr`.

## License

These bindings are licensed under the MIT license.
