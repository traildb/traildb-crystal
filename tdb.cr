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
    timestamp, num_items : UInt64
    items : Pointer(TdbItem)
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

  fun tdb_lexicon_size(Tdb, TdbField) : TdbError

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
  fun tdb_cursor_free(Tdb)
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

# Crystal Library syntactic sugar
alias TrailDBEvent = Hash(String, String)

# def uuid_raw(uuid : String)
# end

class TrailDBException < Exception
end

class TrailDBEvents
  include Iterator(TrailDBEvent)

  def initialize(@cursor : TdbCursor)
  end

  def next
    event = LibTrailDB.tdb_cursor_next(@cursor)

    if !event
      stop
    end
  end
end

class TrailDBLexicon
  include Iterator(String)

  def initialize(@traildb : TrailDB, field : TdbField)
    @curr = 0
    @max = @traildb.lexicon_size(@field)
  end

  def next
    if val >= @max
      stop
    end

    val = @traildb.get_value(@field, i)
    @curr += 1
    val
  end
end

class TrailDB
  @num_trails : UInt64
  @num_events : UInt64
  @num_fields : UInt64
  @fields : Array(String)
  @field_map : Hash(String, TdbField)
  @buffer : Pointer(UInt64)

  getter num_trails
  getter num_events
  getter num_fields
  getter fields

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

    @num_fields.times.each do |field|
      fieldish = String.new(LibTrailDB.tdb_get_field_name(@db, field))
      @fields << fieldish
      # @field_map[fieldish] = field
    end

    @buffer = Pointer(UInt64).malloc(2)
  end

  def field(fieldish : String) : TdbField
    # Return a field ID given a field name.
    self.field_map[fieldish]
  end

  def get_item(fieldish : String, value : String) : TdbItem
    # Return the item corresponding to a field ID or a field name and a string value.
    field = self.field(fieldish)
    item = LibTrailDB.tdb_get_item(@db, field, value, value.size)
    if !item
      raise TrailDBException.new("No such value: #{value}")
    end
    item
  end

  def get_item_value(item : TdbItem) : String
    # Return the string value corresponding to an item.
    value = LibTrailDB.tdb_get_item_value(@db, item, @buffer)
    if !value
      raise TrailDBException.new("Error reading value, error: #{LibTrailDB.tdb_error(@db)}")
    end
    value[0, @buffer.value]
  end

  def get_value(fieldish : String, val : TdbVal) : String
    # Return the string value corresponding to a field ID or a field name and a value ID.
    field = self.field(fieldish)
    value = String.new(LibTrailDB.tdb_get_value(@db, field, val, @buffer))
    if !value
      raise TrailDBException.new("Error reading value, error: #{LibTrailDB.tdb_error(@db)}")
    end
    value[0, @buffer.value]
  end

  def get_uuid(trail_id : UInt64) : String
    # Return UUID given a Trail ID.
    uuid = LibTrailDB.tdb_get_uuid(@db, trail_id)
    if !uuid
      raise TrailDBException.new("Trail ID out of range")
    end
    String.new(uuid, 16)
  end

  def lexicon_size(fieldish : String) : Int32
    # Return the number of distinct values in the given field ID or field name.
    field = self.field(fieldish)
    value = LibTrailDB.tdb_lexicon_size(@db, field)
    if value == 0
      raise TrailDBException.new("Invalid field index")
    end
    value
  end

  def lexicon(fieldish : String)
    # Return an iterator over values of the given field ID or field name.
    field = self.field(fieldish)
    return TrailDBLexicon.new(self, field)
  end
end

t = TrailDB.new("/home/joey/Downloads/wikipedia-history-small.tdb")
puts t.num_trails
