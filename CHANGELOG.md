# Changelog

## [0.1.3](https://github.com/traildb/traildb-crystal/releases/tag/v0.1.3) - 2017-11-24

- Added TrailDB#reuse_cursor bool for a speed boost when iterating

## [0.1.2](https://github.com/traildb/traildb-crystal/releases/tag/v0.1.2) - 2017-11-24

- Works in crystal --release mode

## [0.1.1](https://github.com/traildb/traildb-crystal/releases/tag/v0.1.1) - 2017-11-24

- Use a struct for TrailDBEvent

## [0.1.0](https://github.com/traildb/traildb-crystal/releases/tag/v0.1.0) - 2017-11-23

- Optionally parse timestamps into `Time` objects with `parse_timestamps`. Set to false to return a `UInt64`. (Fixes #3)
- Introduce the `TrailDBEvent` class, a wrapper for items in the event. Instead of returning a `Hash`, we return something that can be evaluated more lazily.  (Fixes #2)

## [0.0.1](https://github.com/traildb/traildb-crystal/releases/tag/v0.0.1) - 2017-11-19

- Initial release
