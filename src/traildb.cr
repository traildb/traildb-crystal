# C Library type aliases
alias Tdb = Pointer(Void)
alias TdbCons = Pointer(Void)
alias TdbField = UInt32
alias TdbVal = UInt64
alias TdbItem = UInt64
alias TdbCursor = Pointer(Void)
alias TdbError = Int32
alias TdbEventFilter = Pointer(Void)
alias TdbChar = UInt8

@[Link("traildb")]
lib LibTrailDB
  struct TdbEvent
    timestamp : UInt64
    num_items : UInt64
    items : TdbItem
  end

  union TdbOptValue
    ptr : Pointer(Void)
    value : UInt64
  end

  fun tdb_cons_init : TdbCons
  fun tdb_cons_open(TdbCons, Pointer(TdbChar), Pointer(Pointer(TdbChar)), UInt64) : TdbError
  fun tdb_cons_close(TdbCons)
  fun tdb_cons_add(TdbCons, Pointer(UInt8), UInt64, Pointer(Pointer(TdbChar)), Pointer(UInt64)) : TdbError
  fun tdb_cons_append(TdbCons, Tdb) : TdbError
  fun tdb_cons_finalize(TdbCons) : TdbError

  fun tdb_init : Tdb
  fun tdb_open(Tdb, Pointer(TdbChar)) : TdbError
  fun tdb_close(Tdb)

  fun tdb_lexicon_size(Tdb, TdbField) : TdbVal

  fun tdb_get_field(Tdb, Pointer(TdbChar)) : TdbError
  fun tdb_get_field_name(Tdb, TdbField) : Pointer(TdbChar)

  fun tdb_get_item(Tdb, TdbField, Pointer(TdbChar), UInt64) : TdbItem
  fun tdb_get_value(Tdb, TdbField, TdbVal, Pointer(UInt64)) : Pointer(TdbChar)
  fun tdb_get_item_value(Tdb, TdbItem, Pointer(UInt64)) : Pointer(TdbChar)

  fun tdb_get_uuid(Tdb, UInt64) : Pointer(UInt8)
  fun tdb_get_trail_id(Tdb, Pointer(UInt8), Pointer(UInt64)) : TdbError

  fun tdb_error_str(TdbError) : Pointer(TdbChar)

  fun tdb_num_trails(Tdb) : UInt64
  fun tdb_num_events(Tdb) : UInt64
  fun tdb_num_fields(Tdb) : UInt64
  fun tdb_min_timestamp(Tdb) : UInt64
  fun tdb_max_timestamp(Tdb) : UInt64

  fun tdb_version(Tdb) : UInt64

  fun tdb_cursor_new(Tdb) : TdbCursor
  fun tdb_cursor_free(TdbCursor)
  fun tdb_cursor_next(TdbCursor) : Pointer(TdbEvent)
  fun tdb_get_trail(TdbCursor, UInt64) : TdbError
  fun tdb_get_trail_length(TdbCursor) : UInt64
  fun tdb_cursor_set_event_filter(TdbCursor, TdbEventFilter) : TdbError

  fun tdb_event_filter_new : TdbEventFilter
  fun tdb_event_filter_add_term(TdbEventFilter, TdbItem, Int32) : TdbError
  fun tdb_event_filter_add_time_range(UInt64, UInt64) : TdbError
  fun tdb_event_filter_new_clause(TdbEventFilter) : TdbError
  fun tdb_event_filter_new_match_none : TdbEventFilter
  fun tdb_event_filter_new_match_all : TdbEventFilter
  fun tdb_event_filter_free(TdbEventFilter)

  fun tdb_set_opt(Tdb, UInt32, TdbOptValue) : TdbError
  fun tdb_set_trail_opt(Tdb, UInt64, UInt32, TdbOptValue) : TdbError
end

# Because Crystal's `pointerof` doesn't inspect external libraries
# Use a C wrapper function to get the pointer to the TrailDB Event items
# https://github.com/crystal-lang/crystal/issues/4845
@[Link(ldflags: "-ltraildb_wrapper -L#{__DIR__}/../build")]
lib LibTrailDBWrapper
  fun tdb_event_item_pointer(LibTrailDB::TdbEvent) : TdbItem*
end

# Crystal Library syntactic sugar

# TrailDB Event, mapping field => value
alias TrailDBEventHash = Hash(String, String | Time | UInt64)

# Returned when iterating over all trails
# uuid can be accessed by destructuring in the loop
# e.g. `traildb.trails.each { |(uuid, trail)| }`
alias TrailDBEventIteratorWithUUID = Tuple(String, TrailDBEventIterator)

# Generic field for all field-like objects. Translated into TdbField by TrailDB#field
alias TrailDBField = String | UInt32 | Int32

# Generic TrailDB exception, used all the place
class TrailDBException < Exception
end

class TrailDBEvent
  def initialize(@traildb : TrailDB, @event : LibTrailDB::TdbEvent*, @item : TdbItem*, @parse_timestamp : Bool = true)
  end

  def time
    @parse_timestamp ? Time.epoch(@event.value.timestamp) : @event.value.timestamp
  end

  # Return item value for a particular field
  def [](fieldish : TrailDBField) : String
    item_slice = Slice.new(@item, @event.value.num_items)
    field = @traildb.field(fieldish)
    @traildb.get_item_value(item_slice[field - 1])
  end

  # Return the full event as a hash
  def to_h : TrailDBEventHash
    item_slice = Slice.new(@item, @event.value.num_items)
    items = TrailDBEventHash.new
    @traildb.fields.each_with_index do |field, idx|
      items[field] = @traildb.get_item_value(item_slice[idx])
    end

    items["time"] = self.time
    items
  end
end

class TrailDBEventIterator
  include Iterator(TrailDBEvent)

  @traildb : TrailDB
  @trail_id : UInt64
  @event_filter : TrailDBEventFilter | Nil
  @parse_timestamp : Bool
  @cursor : TdbCursor

  def initialize(@traildb : TrailDB, @trail_id : UInt64, @event_filter : TrailDBEventFilter | Nil = nil, @parse_timestamp : Bool = true)
    @cursor = LibTrailDB.tdb_cursor_new(@traildb.db)
    if LibTrailDB.tdb_get_trail(@cursor, @trail_id) != 0
      raise TrailDBException.new("Error getting trail #{@trail_id}")
    end

    self.apply_filter
  end

  def finalize
    LibTrailDB.tdb_cursor_free(@cursor)
  end

  def next
    event = LibTrailDB.tdb_cursor_next(@cursor)

    if event.null?
      stop
    else
      item = LibTrailDBWrapper.tdb_event_item_pointer(event.value)
      TrailDBEvent.new(@traildb, event, item, @parse_timestamp)
    end
  end

  def rewind
    @cursor = LibTrailDB.tdb_cursor_new(@traildb.db)
    if LibTrailDB.tdb_get_trail(@cursor, @trail_id) != 0
      raise TrailDBException.new("Error getting trail #{@trail_id}")
    end

    self.apply_filter
  end

  protected def apply_filter
    # Use local variable to get around Nil guard
    # https://github.com/crystal-lang/crystal/issues/477
    event_filter = @event_filter

    if event_filter
      ret = LibTrailDB.tdb_cursor_set_event_filter(@cursor, event_filter.flt)
      if ret != 0
        raise TrailDBException.new("cursor_set_event_filter failed")
      end
    end
  end
end

class TrailDBTrailIterator
  include Iterator(TrailDBEventIteratorWithUUID)

  @traildb : TrailDB
  @curr : UInt64
  @parse_timestamp : Bool

  def initialize(@traildb : TrailDB, @event_filter : TrailDBEventFilter | Nil = nil, @parse_timestamp : Bool = true)
    @curr = 0_u64
  end

  def next
    if @curr >= @traildb.num_trails
      stop
    else
      val = TrailDBEventIterator.new(@traildb, @curr, @event_filter, @parse_timestamp)
      uuid = @traildb.get_uuid(@curr)
      @curr += 1
      {uuid, val}
    end
  end
end

class TrailDBLexiconIterator
  include Iterator(String)

  @traildb : TrailDB
  @fieldish : TrailDBField
  @curr : TdbVal
  @max : TdbVal

  def initialize(@traildb : TrailDB, @fieldish : TrailDBField)
    @curr = 1_u64
    @max = @traildb.lexicon_size(@fieldish)
  end

  def next
    if @curr >= @max
      stop
    else
      val = @traildb.get_value(@fieldish, @curr)
      @curr += 1
      val
    end
  end
end

# Single term of an event filter.
alias TrailDBEventFilterTermWithoutNegation = Tuple(String, String)

# Single term of an event filter. The final parameter is negation
alias TrailDBEventFilterTermWithNegation = Tuple(String, String, Bool)

# Combined single term of an event filter.
alias TrailDBEventFilterTerm = TrailDBEventFilterTermWithoutNegation | TrailDBEventFilterTermWithNegation

# Clause in an event filter
alias TrailDBEventFilterClause = Array(TrailDBEventFilterTerm)

# Full event filter, to be parsed into TrailDBEventFilter
alias TrailDBEventFilterQuery = Array(TrailDBEventFilterClause)

# Create a TrailDB filter from a series of clauses
class TrailDBEventFilter
  @traildb : TrailDB
  @flt : TdbEventFilter
  getter flt

  def initialize(@traildb : TrailDB, query : TrailDBEventFilterQuery)
    @flt = LibTrailDB.tdb_event_filter_new

    query.each_with_index do |clause, i|
      if i > 0
        err = LibTrailDB.tdb_event_filter_new_clause(@flt)
        if err != 0
          raise TrailDBException.new("Out of memory in _create_filter")
        end
      end

      clause.each do |term|
        if term.is_a?(TrailDBEventFilterTermWithNegation)
          field, value, is_negative = term
        else
          field, value = term
          is_negative = false
        end

        begin
          item = @traildb.get_item(field, value)
        rescue TrailDBException
          item = 0
        end

        err = LibTrailDB.tdb_event_filter_add_term(@flt, item, is_negative ? 1 : 0)
        if err != 0
          raise TrailDBException.new("Out of memory in _create_filter")
        end
      end
    end
  end

  def finalize
    LibTrailDB.tdb_event_filter_free(@flt)
  end
end

# Construct a new TrailDB.
class TrailDBConstructor
  # Initialize a new TrailDB constructor.
  # path -- TrailDB output path (the `.tdb` extension is optional).
  # ofields -- List of field (names) in this TrailDB.
  def initialize(@path : String, @ofields : Array(String) = [] of String)
    if !path
      raise TrailDBException.new("Path is required")
    end

    n = @ofields.size
    ofield_names = @ofields.map { |ofield| ofield.bytes.to_unsafe }
    @cons = LibTrailDB.tdb_cons_init

    if LibTrailDB.tdb_cons_open(@cons, path, ofield_names, n) != 0
      raise TrailDBException.new("Cannot open constructor")
    end
  end

  def finalize
    LibTrailDB.tdb_cons_close(@cons)
  end

  # Add an event in TrailDB.
  #
  # uuid -- UUID of this event.
  # tstamp -- Timestamp of this event (datetime or integer).
  # values -- value of each field.
  def add(uuid : String, tstamp : Time | UInt64 | Int32, values : Array(String))
    tstamp = tstamp.is_a?(Time) ? tstamp.epoch.to_u64 : tstamp.to_u64
    value_array = values.map { |v| v.bytes.to_unsafe }
    value_lengths = values.map { |v| v.size.to_u64 }
    f = LibTrailDB.tdb_cons_add(@cons, uuid.hexbytes, tstamp, value_array, value_lengths)
    if f != 0
      raise TrailDBException.new("Too many values: #{values[f]}")
    end
  end

  # Merge an existing TrailDB in this TrailDB.
  #
  # traildb -- an existing TrailDB
  def append(traildb : TrailDB)
    f = LibTrailDB.tdb_cons_append(@cons, traildb.db)
    if f < 0
      raise TrailDBException.new("Wrong number of fields: #{traildb.num_fields}")
    end
    if f > 0
      raise TrailDBException.new("Too many values")
    end
  end

  # Finalize this TrailDB. You cannot add new events in this TrailDB
  # after calling this function.
  #
  # Returns a new TrailDB handle.
  def close
    r = LibTrailDB.tdb_cons_finalize(@cons)
    if r != 0
      raise TrailDBException.new("Could not finalize (#{r})")
    end
    TrailDB.new(@path)
  end
end

# Load a TrailDB, including metadata and a trails iterator
class TrailDB
  @db : Tdb
  @num_trails : UInt64
  @num_events : UInt64
  @num_fields : UInt64
  @fields : Array(String)
  @field_map : Hash(String, TdbField)
  @event_filter : TrailDBEventFilter | Nil
  @buffer : Pointer(UInt64)
  @parse_timestamp : Bool

  # Raw TrailDB pointer.
  getter db

  # Number of trails.
  getter num_trails

  # Number of events.
  getter num_events

  # Number of fields.
  getter num_fields

  # Field strings.
  getter fields

  # The current event filter. Set to nil to remove.
  property event_filter

  # Whether to parse timestamp as a Time, or leave as UInt64
  property parse_timestamp

  # Load a TrailDB at path (the `.tdb` extension is optional).
  def initialize(path : String)
    @db = LibTrailDB.tdb_init
    res = LibTrailDB.tdb_open(@db, path)

    if res != 0
      raise TrailDBException.new("Could not open #{path}, error code #{res}")
    end

    @num_trails = LibTrailDB.tdb_num_trails(@db)
    @num_events = LibTrailDB.tdb_num_events(@db)
    @num_fields = LibTrailDB.tdb_num_fields(@db)
    @fields = [] of String
    @field_map = {} of String => TdbField

    # Exclude `time` from field mapping
    1.upto(@num_fields - 1).each do |field|
      fieldish = String.new(LibTrailDB.tdb_get_field_name(@db, field))
      @fields << fieldish
      @field_map[fieldish] = field.to_u32
    end

    @buffer = Pointer(UInt64).malloc(2)
    @event_filter = nil
    @parse_timestamp = true
  end

  def finalize
    LibTrailDB.tdb_close(@db)
  end

  # Return true if UUID or Trail ID exists in this TrailDB.
  def includes?(uuidish)
    begin
      self[uuidish]
      true
    rescue TrailDBException
      false
    end
  end

  # Return a iterator for all trails.
  def trails
    TrailDBTrailIterator.new(self, @event_filter, @parse_timestamp)
  end

  # Return a iterator for the given UUID.
  def [](uuidish : String | UInt64 | Int32)
    trail_id = uuidish.is_a?(String) ? self.get_trail_id(uuidish) : uuidish.to_u64
    TrailDBEventIterator.new(self, trail_id, @event_filter, @parse_timestamp)
  end

  # Return a field ID for given a field name or field ID.
  def field(fieldish : TrailDBField) : TdbField
    fieldish.is_a?(String) ? @field_map[fieldish] : fieldish.to_u32
  end

  # Return the item corresponding to a field ID or a field name and a string value.
  def get_item(fieldish : String, value : String) : TdbItem
    field = self.field(fieldish)
    item = LibTrailDB.tdb_get_item(@db, field, value, value.size)
    if !item
      raise TrailDBException.new("No such value: #{value}")
    end
    item
  end

  # Return the string value corresponding to an item.
  def get_item_value(item : TdbItem) : String
    value = LibTrailDB.tdb_get_item_value(@db, item, @buffer)
    if !value
      raise TrailDBException.new("Error reading value")
    end
    String.new(value, @buffer.value)
  end

  # Return the string value corresponding to a field ID or a field name and a value ID.
  def get_value(fieldish : TrailDBField, val : TdbVal) : String
    field = self.field(fieldish)
    value = String.new(LibTrailDB.tdb_get_value(@db, field, val, @buffer))
    if !value
      raise TrailDBException.new("Error reading value")
    end
    value[0, @buffer.value]
  end

  # Return UUID given a Trail ID.
  def get_uuid(trail_id : UInt64 | Int32, raw = false) : String
    uuid = LibTrailDB.tdb_get_uuid(@db, trail_id.to_u64)
    if !uuid
      raise TrailDBException.new("Trail ID out of range")
    end

    raw ? String.new(uuid, 16) : Slice.new(uuid, 16).hexstring
  end

  # Return the number of distinct values in the given field ID or field name.
  def lexicon_size(fieldish : TrailDBField) : TdbVal
    field = self.field(fieldish)
    value = LibTrailDB.tdb_lexicon_size(@db, field)
    if value == 0
      raise TrailDBException.new("Invalid field index")
    end
    value
  end

  # Return an iterator over values of the given field ID or field name.
  def lexicon(fieldish : TrailDBField)
    return TrailDBLexiconIterator.new(self, fieldish)
  end

  # Return Trail ID given a UUID.
  def get_trail_id(uuid : String)
    ret = LibTrailDB.tdb_get_trail_id(@db, uuid.hexbytes, @buffer)
    if ret != 0
      raise TrailDBException.new("UUID '#{uuid}' not found")
    end
    @buffer.value
  end

  # Return the time range covered by this TrailDB.
  def time_range
    tmin = Time.epoch(self.min_timestamp)
    tmax = Time.epoch(self.max_timestamp)
    {tmin, tmax}
  end

  # Return the minimum time stamp of this TrailDB.
  def min_timestamp
    LibTrailDB.tdb_min_timestamp(@db)
  end

  # Return the maximum time stamp of this TrailDB.
  def max_timestamp
    LibTrailDB.tdb_max_timestamp(@db)
  end

  # Create TrailDB filter
  def create_filter(query : TrailDBEventFilterQuery, set_filter : Bool = false)
    event_filter = TrailDBEventFilter.new(self, query)
    if set_filter
      @event_filter = event_filter
    end
    event_filter
  end
end
